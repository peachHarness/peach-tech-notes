/**
 * Chrome CDP 연결 공통 모듈
 * 이미 열린 Chrome에 연결하여 대상 탭의 page 객체를 반환한다.
 *
 * HARNESS_E2E_VERSION: e2e 인프라(e2e.sh + lib/connect.js + lib/run-scenario.js) 계약 버전.
 * e2e.sh 상단의 같은 상수와 항상 같은 값으로 함께 올린다(인프라가 의미 있게 바뀔 때만).
 * suite/scenario 실행 게이트가 e2e.sh status의 E2E_INFRA_VERSION으로 이 버전을 확인한다.
 *
 * 탭 식별: CDP targetId (탭별 고유 해시) — 동일 URL 탭도 정확히 구분.
 *
 * 탭 선택 방식:
 *   1. targetId (가장 정확 — selector.js TUI에서 사용)
 *      E2E_TAB_ID=ABC123... node 시나리오.js
 *
 *   2. 탭 인덱스 (--tab N 직접 지정, 하위 호환 편의 입력)
 *      E2E_TAB=3 node 시나리오.js
 *      → 내부적으로 CDP /json 조회 후 targetId로 즉시 변환
 *
 *   3. 인자 없음 → 첫 번째 비-chrome 페이지 탭 자동 선택
 *
 * origin은 선택된 탭의 URL에서 동적 추출.
 * 환경(local/test/prod) 구분 없이, 사용자가 로그인한 탭을 그대로 사용.
 */
// playwright-core: API만 포함 (브라우저 바이너리 없음). CDP 모드에서는 Chrome Beta를 직접 사용하므로 충분.
const { chromium } = require('playwright-core');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CDP_PORT = process.env.E2E_CDP_PORT || '9333';
const CDP_URL = `http://127.0.0.1:${CDP_PORT}`;
const CONNECT_TIMEOUT_MS = Number(process.env.E2E_ATTACH_TIMEOUT_MS || 10000);
// 라이트 모드 보정처럼 검증과 무관한 렌더러 호출의 상한. freeze 탭에서 무한 대기하는 것을 막는다.
const LIGHT_MODE_TIMEOUT_MS = 5000;

// e2e 인프라 계약 버전 — e2e.sh 상단 HARNESS_E2E_VERSION과 항상 같은 값으로 함께 갱신한다.
const HARNESS_E2E_VERSION = '1.2.9';

// ─── 실패 evidence 수집 ────────────────────────────────────
// 계약 SoT: peach-e2e-scenario/references/실패-evidence.md
// 원칙: 성공은 요약만, 실패 순간만 구조화해 1회 저장. 시나리오 .js는 손대지 않는다.
// connect()가 page 반환 시 console/network 리스너를 자동 구독해 버퍼에 쌓고,
// 프로세스가 비정상 종료(uncaughtException/unhandledRejection/exit!=0)하면 자동 flush 한다.

const _evidence = {
  page: null,
  consoleLogs: [],   // { type, text } — error/warning 및 pageerror
  network: [],       // { method, url, status, requestBody, responseStatus }
  flushed: false,
  scenarioFile: process.argv[1] || 'unknown',
};

// 자격증명 마스킹 (필수 게이트) — 못 가리면 값 자체를 ***로
// api[-_]?key: 실제 헤더는 x-api-key처럼 하이픈을 쓴다. apikey/api_key만 보면 하이픈 형태가 새어나간다(테스트로 확인).
const SENSITIVE_KEY = /(authorization|password|passwd|pwd|token|secret|api[-_]?key|cookie|set-cookie|credential)/i;

function maskValue() {
  return '***';
}

function maskHeaders(headers) {
  const out = {};
  for (const [k, v] of Object.entries(headers || {})) {
    out[k] = SENSITIVE_KEY.test(k) ? maskValue() : v;
  }
  return out;
}

const BODY_CAP = 4000; // 본문 저장 상한(분석엔 충분하고, 평문 누적·용량 폭주를 막는다)

function maskBody(body) {
  if (body == null) return body;
  let text = typeof body === 'string' ? body : String(body);
  // JSON이면 키 기준 마스킹, 아니면 길이만 보존(평문 노출 방지)
  try {
    const obj = JSON.parse(text);
    const walk = (o) => {
      if (Array.isArray(o)) return o.map(walk);
      if (o && typeof o === 'object') {
        const r = {};
        for (const [k, val] of Object.entries(o)) {
          r[k] = SENSITIVE_KEY.test(k) ? maskValue() : walk(val);
        }
        return r;
      }
      return o;
    };
    const masked = JSON.stringify(walk(obj));
    // 키 기반 마스킹은 data/value 같은 일반 키 토큰을 못 가린다(알려진 한계). 크기 캡으로 노출·용량을 줄인다.
    return masked.length > BODY_CAP ? masked.slice(0, BODY_CAP) + `…[truncated, total=${masked.length}]` : masked;
  } catch {
    // JSON 아님 — 자격증명이 섞였을 수 있으므로 전문 저장 대신 길이만 남긴다
    return `[non-json body, length=${text.length}]`;
  }
}

function _pushNetwork(entry) {
  _evidence.network.push(entry);
  if (_evidence.network.length > 50) _evidence.network.shift(); // 최근 50건만
}

// page에 console/network 리스너를 건다 (실행 시작 시점에 구독해야 실패 직전까지 모인다)
// network는 Playwright page.on('response')로 구독한다.
//
// 주의(실측): 같은 탭에 두 번째 프로세스가 connectOverCDP로 재attach하면, 그 탭의 fetch가 안정적으로
// 완료되지 않을 수 있다(요청은 추적되나 응답 이벤트가 오지 않음). CDP 세션으로 Network.enable을
// 직접 거는 보강도 같은 환경에서는 오히려 fetch 진행을 방해해 도움이 되지 않았다. 따라서 별도 CDP
// Network 구독은 두지 않고 Playwright 기본 경로만 쓴다. 네트워크 검증이 핵심인 시나리오는 첫 attach
// 탭에서 실행하는 것이 안전하다(화면 검증 위주의 같은 탭 재사용과 분리).
function _attachListeners(page) {
  page.on('console', (msg) => {
    const type = msg.type();
    if (type === 'error' || type === 'warning') {
      _evidence.consoleLogs.push({ type, text: msg.text() });
    }
  });
  page.on('pageerror', (err) => {
    _evidence.consoleLogs.push({ type: 'pageerror', text: err.message });
  });

  // entry를 즉시(동기로) push 한다. 비동기 await로 채우면 dumpEvidence가 그 사이 실행돼
  // 응답을 놓칠 수 있다(실패 직후 evidence 수집은 매우 빠르게 일어난다).
  page.on('response', (res) => {
    const req = res.request();
    const entry = {
      ts: new Date().toISOString(),  // 요청/응답 순서·타이밍 분석용
      method: req.method(),
      url: res.url(),
      status: res.status(),
      requestHeaders: maskHeaders(req.headers()),
      requestBody: maskBody(req.postData()),
    };
    _pushNetwork(entry);
    // 응답 본문은 비동기로 뒤늦게 채운다(못 채워도 entry는 이미 남는다).
    // 실패 원인 분석을 돕기 위해 4xx/5xx뿐 아니라 성공 응답 본문도 남긴다 — 실패 직전 API가 무엇을
    // 돌려줬는지가 단서가 되기 때문이다. 단 JSON(API 응답)만 받는다. HTML/이미지/스크립트 등 큰 정적
    // 리소스는 노이즈·용량만 키우므로 제외하고, maskBody의 크기 캡(BODY_CAP)으로 본문도 제한한다.
    const ct = (res.headers()['content-type'] || '');
    if (res.status() >= 400 || /application\/json/i.test(ct)) {
      res.text().then((text) => { entry.responseBody = maskBody(text); }).catch(() => {});
    }
  });
}

function _tsDir() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  const stamp = `${String(d.getFullYear()).slice(2)}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  const base = path.basename(_evidence.scenarioFile).replace(/\.js$/, '');
  // e2e.sh가 시나리오 실행 전 e2e 폴더로 cd 하므로 process.cwd()=e2e.
  // 실패 evidence는 휘발성 .tmp 안의 별도 폴더(evidence/)에 시나리오별로 둔다.
  // run 초기화 rm은 `e2e_*_state.json`만 지우므로 evidence/는 보존된다.
  return { dir: `.tmp/evidence/${base}-${stamp}` };
}

// state.json 후보(.tmp/*.json) 사본 수집
function _collectState() {
  try {
    const tmpDir = path.join(path.dirname(_evidence.scenarioFile), '..', '..', '.tmp');
    const altTmp = path.join(process.cwd(), '.tmp');
    const dir = fs.existsSync(tmpDir) ? tmpDir : (fs.existsSync(altTmp) ? altTmp : null);
    if (!dir) return null;
    const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
    const merged = {};
    for (const f of files) {
      try { merged[f] = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { /* skip */ }
    }
    return merged;
  } catch {
    return null;
  }
}

// page가 멈춰도(evidence 수집 중 페이지 불안정) 영영 기다리지 않도록 타임아웃을 건다
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error("evidence 수집 타임아웃")), ms)),
  ]);
}

// 실패 evidence를 디스크에 1회 저장 (성공 시 호출되지 않음)
async function dumpEvidence(meta = {}) {
  if (_evidence.flushed) return null; // 최초 1회만
  _evidence.flushed = true;

  const page = _evidence.page;
  const { dir } = _tsDir();
  const repoRoot = process.cwd();
  const outDir = path.join(repoRoot, dir);

  try {
    fs.mkdirSync(outDir, { recursive: true });
  } catch {
    return null; // evidence 저장 실패는 시나리오 결과에 영향 주지 않는다
  }

  const write = (name, content) => {
    try { fs.writeFileSync(path.join(outDir, name), content); } catch { /* best-effort */ }
  };

  const errText = meta.error
    ? (meta.error.stack || meta.error.message || String(meta.error))
    : '(no error object captured)';
  let url = '';
  try { url = page ? page.url() : ''; } catch { /* page closed */ }

  // 인메모리 데이터(page 무관)를 먼저 저장한다.
  // page가 불안정해 dom/screenshot 수집이 멈춰도 핵심 evidence는 이미 디스크에 남는다.
  write('error.txt', errText);
  write('console.json', JSON.stringify(_evidence.consoleLogs, null, 2));
  write('network.json', JSON.stringify(_evidence.network, null, 2));
  const state = _collectState();
  write('state.json', JSON.stringify(state || {}, null, 2));

  // dom.html + screenshot.png — page 의존. hang 방지를 위해 타임아웃으로 감싼다.
  if (page) {
    try { write('dom.html', await withTimeout(page.content(), 3000)); } catch { /* page closed/hang */ }
    try { await withTimeout(page.screenshot({ path: path.join(outDir, 'screenshot.png'), fullPage: false }), 5000); } catch { /* page closed/hang */ }
  }

  // summary.md — 원인 후보 자동 분류
  const lastApi = [..._evidence.network].reverse().find((n) => n.status >= 400);
  const hasConsoleErr = _evidence.consoleLogs.some((c) => c.type === 'error' || c.type === 'pageerror');
  const causes = [];
  if (/timeout|locator|selector|waiting for/i.test(errText) && lastApi) {
    causes.push('화면 대기 실패는 증상 — API 실패가 원인 후보 (' + lastApi.status + ' ' + lastApi.url + ')');
  } else if (/timeout|locator|selector|waiting for/i.test(errText)) {
    causes.push('프론트 렌더링 / selector 문제 후보');
  }
  if (hasConsoleErr) causes.push('프론트 런타임 / store 오류 후보 (console error)');
  if (!state || Object.keys(state).length === 0) causes.push('state 전달 데이터 없음 — suite 데이터 전달 문제 가능');
  // network가 0건이면 두 가지 가능성이 있다: ① 실제로 요청이 없었다 ② 수집이 실패했다.
  // ②의 대표 원인은 같은 CDP 포트에 붙은 다른 CDP 클라이언트가 request interception(Fetch 도메인)을 점유해
  // 이 프로세스의 fetch가 Fetch.requestPaused로 멈춘 경우다(서버 도달·응답 모두 차단 → network.json 빈 배열).
  // 어떤 클라이언트가 Fetch를 점유했는지는 외부에서 확정하기 어려우므로, 단정하지 않고 후보로만 안내한다.
  const networkEmpty = _evidence.network.length === 0;
  if (networkEmpty) {
    causes.push(`network.json 0건 — 실제 무요청이거나, CDP ${CDP_PORT}의 다른 CDP 클라이언트가 Fetch 도메인을 점유해 수집이 누락됐을 수 있음(후자면 다른 CDP 클라이언트 종료 후 재실행 시 잡힘)`);
  }
  if (causes.length === 0) causes.push('(자동 분류 불가 — error.txt/network.json 직접 확인)');

  const summary = [
    `# FAIL_EVIDENCE — ${path.basename(_evidence.scenarioFile)}`,
    '',
    `- 수집 시각: ${new Date().toISOString()}`,
    `- 시나리오 파일: ${_evidence.scenarioFile}`,
    `- 실패 URL: ${url}`,
    '',
    '## 에러 (요약)',
    '```',
    errText.split('\n').slice(0, 5).join('\n'),
    '```',
    '',
    '## 원인 후보',
    ...causes.map((c) => `- ${c}`),
    '',
    '## 근거',
    `- console: error/warning ${_evidence.consoleLogs.length}건`,
    `- network: 총 ${_evidence.network.length}건` + (lastApi ? `, 마지막 4xx/5xx = ${lastApi.method} ${lastApi.status} ${lastApi.url}` : ', 4xx/5xx 없음') + (networkEmpty ? ' (0건 = 무요청 또는 CDP Fetch 점유로 수집 누락 가능)' : ''),
    `- state: ${state ? Object.keys(state).join(', ') || '(빈 객체)' : '(없음)'}`,
    '',
    '> 자격증명은 마스킹(***)됨. 실패 evidence는 진단용 흔적이며 검증 통과 근거가 아니다.',
  ].join('\n');
  write('summary.md', summary);

  process.stderr.write(`\n🩺 실패 evidence 저장: ${dir}\n`);
  return dir;
}

// 비정상 종료 시 자동 flush 등록 (1회)
let _hooksInstalled = false;
function _installAutoFlush() {
  if (_hooksInstalled) return;
  _hooksInstalled = true;

  process.on('uncaughtException', async (err) => {
    await dumpEvidence({ error: err });
    process.stderr.write(String(err && err.stack ? err.stack : err) + '\n');
    process.exit(1);
  });
  process.on('unhandledRejection', async (reason) => {
    await dumpEvidence({ error: reason instanceof Error ? reason : new Error(String(reason)) });
    process.exit(1);
  });
  // try/catch 후 process.exitCode=1로 끝나는 표준 패턴 대응 (동기 flush 불가 → beforeExit 사용)
  process.on('beforeExit', async (code) => {
    if (code !== 0 && !_evidence.flushed) {
      await dumpEvidence({ error: new Error(`시나리오 비정상 종료 (exitCode=${code})`) });
    }
  });
}

/**
 * CDP HTTP API로 탭 목록 가져오기
 */
function fetchCdpTabs() {
  return new Promise((resolve) => {
    http.get(`${CDP_URL}/json`, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve([]);
        }
      });
    }).on('error', () => resolve([]));
  });
}

/**
 * CDP 탭 목록에서 비-chrome 페이지 탭만 필터 (status/selector와 동일 기준)
 */
function filterPageTabs(cdpTabs) {
  return cdpTabs.filter(
    (t) => t.type === 'page' && !t.url.startsWith('chrome')
  );
}

/**
 * Playwright page에서 CDP targetId를 추출
 */
async function getTargetId(page) {
  const session = await page.context().newCDPSession(page);
  try {
    const { targetInfo } = await session.send('Target.getTargetInfo');
    return targetInfo.targetId;
  } finally {
    // 세션을 남기면 탭마다 CDP 세션이 쌓인다(tools/pwx.js의 targetIdOf와 같은 처리).
    await session.detach().catch(() => {});
  }
}

/**
 * allPages에서 targetId가 일치하는 page를 찾아 반환
 */
async function findPageByTargetId(allPages, targetId) {
  for (const p of allPages) {
    const id = await getTargetId(p);
    if (id === targetId) return p;
  }
  return null;
}

/**
 * CDP로 Chrome에 연결하고 대상 탭의 page 객체를 반환
 *
 * ── 정리(teardown) 계약 ──
 * connect()는 일부러 browser.close()를 호출하지 않고, 해제 책임을 호출자에게 넘기지도 않는다.
 * 시나리오는 표준 패턴대로 `finally { process.exit(exitCode) }`로 끝내고, 프로세스가 죽으면
 * CDP WebSocket이 닫히면서 Chrome이 attach된 세션을 스스로 정리한다. 이것이 가장 단순하고
 * 확실한 해제 경로다 — 시나리오마다 close를 강제하면 빠뜨렸을 때 조용히 새기 시작한다.
 *
 * 그래서 아래 두 가지는 "정리하지 않는 것이 의도"이며 누수가 아니다.
 *   - _attachListeners가 건 page.on 리스너를 제거하지 않는다 (프로세스와 함께 사라진다)
 *   - 반환된 browser를 닫지 않는다
 *
 * 단, 이 계약은 **한 프로세스에서 connect()를 한 번만 호출하는 일회성 실행**을 전제한다.
 * 한 프로세스가 connect()를 반복 호출하면 리스너와 CDP 연결이 쌓인다. 반복 조작이 필요하면
 * connect()가 아니라 tools/pwx.js를 쓴다 — 그쪽은 매 호출 finally에서 browser.close()로 끊는다
 * (연결 모드의 close는 CDP 연결만 끊고 사용자 브라우저·탭은 유지된다).
 *
 * @param {object} [options] - { tab: number, tabId: string }
 * @returns {{ browser, context, page, origin, defaultDialogHandler }}
 */
async function connect(options) {
  const envTabId = process.env.E2E_TAB_ID;
  const envTab = process.env.E2E_TAB;

  let tabId = null;
  let tabIndex = null;

  // 인자 파싱
  if (options && typeof options === 'object') {
    if (options.tabId) tabId = options.tabId;
    if (options.tab != null) tabIndex = options.tab;
  }

  // 환경변수 우선 (CLI에서 전달)
  if (envTabId && !tabId) tabId = envTabId;
  if (envTab != null && tabIndex == null && !tabId) tabIndex = parseInt(envTab, 10);

  let browser;
  try {
    browser = await chromium.connectOverCDP(CDP_URL, { timeout: CONNECT_TIMEOUT_MS });
  } catch (error) {
    if (/timeout/i.test(error.message)) {
      throw new Error(
        `PLAYWRIGHT_ATTACH_TIMEOUT (${CONNECT_TIMEOUT_MS}ms): 시나리오 수정 없이 Chrome Beta 상태를 복구해야 합니다.\n` +
        `원인: connectOverCDP는 모든 page 타깃에 자동 attach하는데, 백그라운드 탭의 렌더러가 freeze되면 그 탭 하나가 전체 attach를 막는다(실측: 무응답 탭 1개로도 hang).\n` +
        `타임아웃을 늘려도 해결되지 않는다(실측: 60초에도 hang).\n` +
        `복구(1순위): \`node e2e/tools/pwt.js --fix\` — 무응답 탭을 activateTarget으로 되살린다. 비파괴이며 사용자 승인이 필요 없다.\n` +
        `진단만 하려면 \`node e2e/tools/pwt.js\`(읽기 전용, 탭을 닫거나 activate하지 않음).\n` +
        `--fix 로도 무응답이 남으면(exit 1) 실행환경-공통게이트.md §5-1의 나머지 절차를 따른다(사용자 승인 하에 탭 종료 또는 Chrome 재시작).`
      );
    }
    throw error;
  }
  const context = browser.contexts()[0];
  const allPages = context.pages();

  let page = null;

  if (tabId) {
    // targetId 매칭 — 동일 URL이어도 정확히 구분
    page = await findPageByTargetId(allPages, tabId);

    if (!page) {
      const tabList = allPages.map((p, i) => `  ${i}: ${p.url()}`).join('\n');
      throw new Error(
        `탭을 찾을 수 없습니다 (id: ${tabId})\n` +
          `열린 탭:\n${tabList}`
      );
    }
    console.log(`📍 탭 선택: ${page.url()}`);
  } else if (tabIndex != null) {
    // 탭 인덱스 → CDP /json 조회 후 targetId로 변환
    const cdpTabs = await fetchCdpTabs();
    const pageTabs = filterPageTabs(cdpTabs);

    if (tabIndex < 0 || tabIndex >= pageTabs.length) {
      const tabList = pageTabs
        .map((t, i) => `  ${i}: ${t.url}`)
        .join('\n');
      throw new Error(
        `${tabIndex}번 탭이 없습니다. (0~${pageTabs.length - 1}번 사용 가능)\n` +
          `열린 탭:\n${tabList}`
      );
    }

    const targetId = pageTabs[tabIndex].id;
    page = await findPageByTargetId(allPages, targetId);

    if (!page) {
      const tabList = allPages.map((p, i) => `  ${i}: ${p.url()}`).join('\n');
      throw new Error(
        `${tabIndex}번 탭을 Playwright에서 찾을 수 없습니다.\n` +
          `Playwright 탭:\n${tabList}`
      );
    }
    console.log(`📍 ${tabIndex}번 탭 선택: ${page.url()}`);
  } else {
    // 기본: 첫 번째 비-chrome 페이지 탭
    const cdpTabs = await fetchCdpTabs();
    const pageTabs = filterPageTabs(cdpTabs);

    if (pageTabs.length > 0) {
      const targetId = pageTabs[0].id;
      page = await findPageByTargetId(allPages, targetId);
    }

    if (!page) {
      page = allPages.find((p) => !p.url().startsWith('chrome'));
    }

    if (!page) {
      const tabList = allPages.map((p, i) => `  ${i}: ${p.url()}`).join('\n');
      throw new Error(
        `사용 가능한 탭을 찾을 수 없습니다.\n` +
          `브라우저에서 페이지를 열어주세요.\n` +
          `열린 탭:\n${tabList}`
      );
    }
    console.log(`📍 자동 선택: ${page.url()}`);
  }

  // 라이트 모드 강제 (reload 없이 즉시 적용)
  // 1. CSS 미디어 쿼리 오버라이드
  // 2. localStorage + html class 강제 변경 (vueuse/Nuxt 앱의 JS 다크모드 대응)
  //
  // page.evaluate에는 timeout 옵션이 없다(Playwright API). 렌더러가 freeze된 탭에서는 이 호출이
  // 영영 돌아오지 않아 connect()가 무한 대기에 빠진다 — attach는 성공한 뒤라 ATTACH_TIMEOUT도
  // 걸리지 않고, 시나리오 프로세스 watchdog(300초)까지 가야 끊긴다.
  // 라이트 모드는 스크린샷 가독성용 보정이지 검증 대상이 아니므로, 시간 제한을 걸고 실패해도
  // 경고만 남기고 진행한다. 보정 때문에 시나리오가 멈추는 것이 훨씬 나쁘다.
  try {
    await withTimeout((async () => {
      await page.emulateMedia({ colorScheme: 'light' });
      await page.evaluate(() => {
        localStorage.setItem('vueuse-color-scheme', 'light');
        localStorage.setItem('theme', 'light');
        document.documentElement.classList.remove('dark');
        document.documentElement.classList.add('light');
        document.documentElement.style.colorScheme = 'light';
      });
    })(), LIGHT_MODE_TIMEOUT_MS);
  } catch (error) {
    console.warn(`⚠️ 라이트 모드 강제 실패(무시하고 진행): ${error.message}`);
  }

  // 실패 evidence 자동 수집: page 확정 직후 리스너를 달고(실행 시작 시점 구독) 자동 flush 훅을 설치한다.
  // 시나리오 .js는 connect()만 호출하면 되고, 실패 시 evidence가 자동 저장된다.
  _evidence.page = page;
  _attachListeners(page);
  _installAutoFlush();

  // origin은 현재 탭 URL에서 동적 추출
  const origin = new URL(page.url()).origin;

  // 기본 dialog handler 등록
  // - handler가 없으면 Playwright DialogManager가 자동으로 dismiss(false)를 호출한다.
  // - 기본값은 accept(true). 시나리오에서 다른 동작이 필요하면 setDialogHandler()로 교체.
  //   (page.on('dialog')를 직접 추가하면 두 handler가 모두 실행되어 충돌한다.)
  const defaultDialogHandler = async (dialog) => {
    try {
      await dialog.accept();
    } catch (error) {
      if (!String(error?.message).includes('No dialog is showing')) throw error;
    }
  };
  page.on('dialog', defaultDialogHandler);

  return { browser, context, page, origin, defaultDialogHandler };
}

/**
 * dialog handler 교체 유틸리티
 * connect()가 등록한 기본 handler를 제거하고 새 handler로 교체한다.
 *
 * 사용 예:
 *   const { page, defaultDialogHandler } = await connect();
 *   const newHandler = setDialogHandler(page, defaultDialogHandler, async (dialog) => {
 *     logs.push({ type: dialog.type(), message: dialog.message() });
 *     await dialog.accept();
 *   });
 *   // 사용 후 복원
 *   setDialogHandler(page, newHandler, defaultDialogHandler);
 *
 * @param {import('playwright-core').Page} page
 * @param {Function} prevHandler - 제거할 이전 handler (defaultDialogHandler 또는 이전 교체 handler)
 * @param {Function} newHandler  - 등록할 새 handler (null이면 제거만)
 * @returns {Function} newHandler (다음 교체 시 prevHandler로 전달)
 */
function setDialogHandler(page, prevHandler, newHandler) {
  if (prevHandler) page.removeListener('dialog', prevHandler);

  if (newHandler) {
    // dialog가 다른 경로(자동 dismiss·페이지 전환)로 먼저 닫히면 accept가
    // 'No dialog is showing'으로 거부된다. 시나리오 핸들러마다 방어를 요구하지 않고
    // 여기서 한 번 감싼다 — 삼키지 않으면 unhandled rejection으로 프로세스가 죽는다.
    const guarded = async (dialog) => {
      try {
        await newHandler(dialog);
      } catch (error) {
        if (!String(error?.message).includes('No dialog is showing')) throw error;
      }
    };

    page.on('dialog', guarded);
    return guarded;
  }

  return newHandler;
}

// maskHeaders/maskBody는 자격증명 마스킹 게이트 함수다. 검증(e2e-verify)과 재사용을 위해 export한다.
module.exports = { connect, setDialogHandler, dumpEvidence, maskHeaders, maskBody, CDP_URL, HARNESS_E2E_VERSION };
