#!/usr/bin/env node
// pwx.js — Chrome Beta CDP targetId 고정 실행기
//
// 조회(list/title/eval)는 raw CDP, 조작은 connectOverCDP로 붙는다. 이유:
//   1) `playwright-cli open`은 공유 프로필의 기존 탭 하나를 about:blank로 덮어쓴다 (실측 2회 재현)
//   2) `run-code`는 입력 스크립트 전체를 응답에 에코백해 출력 토큰이 두 배가 된다
//   3) targetId 해석 보일러플레이트(약 20줄)를 매 호출 반복하지 않아도 된다
//
// 사용법:
//   pwx.js list                        열린 탭을 "targetId<TAB>url<TAB>title"로 출력
//   pwx.js new <url>                   새 탭 생성 → "targetId<TAB>title | url"
//   pwx.js <targetId> title            "title | url" (탭 확정 직후 검증용)
//   pwx.js <targetId> eval '<expr>'    대상 탭에서 읽기 전용 Runtime.evaluate
//   pwx.js <targetId> '<code>'         해당 탭에서 code 실행 → 결과 1줄
//
// code 규칙: `page`(대상 탭), `ctx`(BrowserContext)가 바인딩된다.
//   `return`이 있으면 함수 본문으로, 없으면 단일 표현식으로 취급한다.
//   예) pwx.js $ID 'page.title()'
//       pwx.js $ID 'await page.fill("[name=q]","아이폰"); return page.url()'
//
// 주의: `./e2e.sh run`이 그 탭에서 실행 중일 때는 붙이지 않는다. 같은 탭에 두 프로세스가
//   동시에 attach되면 그 탭의 fetch가 완료되지 않을 수 있다(connect.js 실측 주석).
//   실행이 끝난 뒤의 순차 사용은 안전하다 — 재attach 3회 후에도 fetch status 200 정상.
//
// 출력은 PWX_MAX(기본 2000)자에서 잘린다. 페이지 텍스트를 통째로 흘려보내
// 컨텍스트를 태우는 사고를 도구 레벨에서 막기 위한 것이다.
// PWX_MAX를 올리기 전에: eval 코드 안에서 querySelector로 필요한 조각만 반환하도록
// 좁히는 게 먼저다(예: document.querySelector('.p-panel_head').outerHTML).
// 그래도 부족하면 값을 올린다.

const path = require('path');

const PORT = process.env.E2E_CDP_PORT || '9333';
const MAX = Number(process.env.PWX_MAX || 2000);
const CONNECT_TIMEOUT_MS = Number(process.env.E2E_ATTACH_TIMEOUT_MS || 10000);
const TOTAL_TIMEOUT_MS = Number(process.env.PWX_TIMEOUT_MS || 60000);
const CDP_URL = `http://127.0.0.1:${PORT}`;

function loadPlaywright() {
  const globalRoots = [
    path.join(path.dirname(process.execPath), '..', 'lib', 'node_modules'),
    '/usr/local/lib/node_modules',
    '/opt/homebrew/lib/node_modules',
    // Windows: npm 전역 루트는 %APPDATA%\npm\node_modules (POSIX의 ../lib/node_modules 아님)
    ...(process.env.APPDATA ? [path.join(process.env.APPDATA, 'npm', 'node_modules')] : []),
  ];
  const searchPaths = [
    ...globalRoots,
    ...globalRoots.map((root) => path.join(root, '@playwright/cli', 'node_modules')),
  ];
  for (const name of ['playwright', 'playwright-core']) {
    try {
      return require(require.resolve(name, { paths: searchPaths }));
    } catch (error) {
      /* 다음 후보로 */
    }
  }
  throw new Error('playwright-core를 찾지 못했습니다. 설치: npm i -g playwright-core');
}

async function targetIdOf(ctx, page) {
  const session = await ctx.newCDPSession(page);
  try {
    const info = await session.send('Target.getTargetInfo');
    return info.targetInfo.targetId;
  } finally {
    await session.detach().catch(() => {});
  }
}

// 긴 추적 파라미터(Google gs_lp/sxsrf는 700B를 넘는다)는 판단에 기여하지 않으므로 줄인다.
// 다만 쿼리를 통째로 버리면 안 된다 — 백오피스 SPA는 `?page=2&status=active`처럼
// 화면 상태를 쿼리에 담고, 그게 사라지면 같은 origin 탭 구분과 검증이 흐려진다.
// 그래서 쿼리는 QUERY_MAX(80자)까지 보존하고 넘치는 부분만 자른다.
// 전체 URL이 필요하면 코드 모드에서 page.url()을 직접 반환한다.
const QUERY_MAX = 80;

function shortUrl(url) {
  try {
    const parsed = new URL(url);
    // about:blank·chrome://·file: 등은 origin이 "null"이라 조립하면 값이 망가진다
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return url;
    const base = parsed.origin + parsed.pathname;
    const query = parsed.search.replace(/^\?/, '');
    if (!query) return base;
    if (query.length <= QUERY_MAX) return `${base}?${query}`;
    return `${base}?${query.slice(0, QUERY_MAX)}…(+${query.length - QUERY_MAX}자)`;
  } catch (error) {
    return url;
  }
}

function render(value) {
  if (value === undefined || value === null) return 'ok';
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return text.length > MAX ? `${text.slice(0, MAX)}…[truncated ${text.length}자, PWX_MAX=${MAX}]` : text;
}

async function fetchTargets() {
  const response = await fetch(`${CDP_URL}/json/list`, {
    signal: AbortSignal.timeout(Math.min(TOTAL_TIMEOUT_MS, 5000)),
  });
  if (!response.ok) throw new Error(`CDP 탭 목록 실패: HTTP ${response.status}`);
  return (await response.json()).filter((target) => target.type === 'page');
}

async function findTarget(targetId) {
  const target = (await fetchTargets()).find((item) => item.id === targetId);
  if (!target) throw new Error(`targetId 미발견: ${targetId} (pwx.js list로 재확인)`);
  return target;
}

async function evaluateTarget(targetId, expression) {
  if (!expression) throw new Error("eval '<expression>' 형식으로 표현식을 지정합니다");
  if (typeof WebSocket === 'undefined') throw new Error('raw CDP eval은 Node.js 22 이상이 필요합니다');

  const target = await findTarget(targetId);
  if (!target.webSocketDebuggerUrl) throw new Error(`탭 WebSocket 미발견: ${targetId}`);

  return new Promise((resolve, reject) => {
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error(`CDP eval timeout (${TOTAL_TIMEOUT_MS}ms)`));
    }, TOTAL_TIMEOUT_MS);
    const finish = (callback, value) => {
      clearTimeout(timer);
      ws.close();
      callback(value);
    };

    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Runtime.evaluate',
        params: { expression, awaitPromise: true, returnByValue: true },
      }));
    });
    ws.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id !== 1) return;
      if (message.error) return finish(reject, new Error(message.error.message));
      if (message.result.exceptionDetails) {
        return finish(reject, new Error(message.result.exceptionDetails.text || 'Runtime.evaluate 실패'));
      }
      const remote = message.result.result;
      finish(resolve, Object.prototype.hasOwnProperty.call(remote, 'value') ? remote.value : remote.description);
    });
    ws.addEventListener('error', () => finish(reject, new Error('탭 WebSocket 연결 실패')));
  });
}

async function main() {
  const [command, arg, extra] = process.argv.slice(2);
  if (!command) throw new Error("사용법: pwx.js list | new <url> | <targetId> title | <targetId> eval '<expr>' | <targetId> <code>");

  if (command === 'list') {
    return (await fetchTargets())
      .map((target) => [target.id, shortUrl(target.url), target.title].join('\t'))
      .join('\n');
  }

  if (command !== 'new') {
    const target = await findTarget(command);
    if (!arg || arg === 'title') return `${target.title} | ${shortUrl(target.url)}`;
    if (arg === 'eval') return render(await evaluateTarget(command, extra));
  }

  const { chromium } = loadPlaywright();
  let browser;
  try {
    browser = await chromium.connectOverCDP(CDP_URL, { timeout: CONNECT_TIMEOUT_MS });
  } catch (error) {
    if (/timeout/i.test(error.message)) {
      throw new Error(`PLAYWRIGHT_ATTACH_TIMEOUT (${CONNECT_TIMEOUT_MS}ms): Chrome Beta 상태 확인 후 재시작 승인 필요`);
    }
    throw error;
  }
  const contexts = browser.contexts();
  if (contexts.length === 0) throw new Error('CDP에 context가 없습니다 (Chrome Beta 실행 확인)');
  // context가 여러 개인 프로필도 있다. [0]만 보면 탭이 조용히 누락되므로 전부 순회한다.
  const ctx = contexts[0];
  const allPages = contexts.flatMap((c) => c.pages().map((p) => ({ ctx: c, page: p })));

  try {
    if (command === 'new') {
      if (!arg) throw new Error('new <url> 형식으로 URL을 지정합니다');
      const page = await ctx.newPage();
      await page.goto(arg, { waitUntil: 'domcontentloaded' });
      // 새 탭 생성과 title+href 검증을 한 왕복으로 끝낸다 (탭 확정 게이트 대응)
      return `${await targetIdOf(ctx, page)}\t${await page.title()} | ${page.url()}`;
    }

    let page = null;
    let pageCtx = ctx;
    for (const entry of allPages) {
      if ((await targetIdOf(entry.ctx, entry.page)) === command) {
        page = entry.page;
        pageCtx = entry.ctx;
        break;
      }
    }
    if (!page) throw new Error(`Playwright targetId 미발견: ${command}`);

    const body = /(^|[^.\w])return[\s(]/.test(arg) ? arg : `return (${arg});`;
    const run = new Function('page', 'ctx', `return (async () => { ${body} })();`);
    return render(await run(page, pageCtx));
  } finally {
    // connectOverCDP의 close는 CDP 연결만 끊는다. 브라우저와 탭은 유지된다.
    await browser.close().catch(() => {});
  }
}

const watchdog = setTimeout(() => {
  process.stderr.write(`ERR PWX_TIMEOUT (${TOTAL_TIMEOUT_MS}ms): 연결 프로세스를 종료합니다\n`);
  process.exit(124);
}, TOTAL_TIMEOUT_MS);

main()
  .then((output) => {
    process.stdout.write(`${output}\n`);
  })
  .catch((error) => {
    process.stderr.write(`ERR ${error.message.split('\n')[0]}\n`);
    process.exit(1);
  })
  .finally(() => clearTimeout(watchdog));
