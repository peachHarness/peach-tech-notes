#!/usr/bin/env node
// pwt.js — Chrome Beta CDP 무응답(freeze) 탭 진단 및 복구
//
// connectOverCDP가 PLAYWRIGHT_ATTACH_TIMEOUT으로 hang할 때, 어느 page 타깃이
// 무응답인지 특정하고(--fix면 되살리기까지) 한다. connectOverCDP 자체가 막힌
// 상황에서 쓰는 도구이므로 playwright-core에 의존하지 않고 Node 22+ 내장
// WebSocket만으로 raw CDP를 사용한다.
//
// 사용법:
//   node e2e/tools/pwt.js          # 진단만 (읽기 전용 — 탭을 닫거나 activate하지 않는다)
//   node e2e/tools/pwt.js --fix    # 무응답 탭을 Target.activateTarget으로 복구 시도
//
// 환경변수: E2E_CDP_PORT (기본 9333), PWT_PROBE_MS (기본 5000)
//
// --fix 의 성질:
//   - 비파괴다. 탭을 닫지 않고 데이터를 잃지 않는다. 바뀌는 것은 탭 포커스뿐이며,
//     원래 보이던 탭을 기억해 마지막에 되돌린다.
//   - 만능이 아니다. Chrome이 스스로 강등한 백그라운드 렌더러는 activateTarget으로
//     되살아나지만(2026-08-17 Chrome Beta 152.0.7977.42, page 타깃 10개 중 5개 freeze → 5/5 복구),
//     렌더러가 실제로 멈춘 경우(무한 루프·커널 정지)는 풀리지 않는다.
//     풀리지 않으면 남은 탭을 보고하고 exit 1 — 거짓 성공으로 넘기지 않는다.
//   - Page.setWebLifecycleState{state:'active'}는 호출은 성공하지만 복구되지 않는다
//     (같은 날 실측 0/5, 격리 재현에서도 동일). 대안으로 시도하지 않는다.
//
// 종료 코드: 무응답 탭이 남으면 1, 전부 정상이면 0.

const PORT = process.env.E2E_CDP_PORT || '9333';
const BASE = `http://127.0.0.1:${PORT}`;
const PROBE_TIMEOUT_MS = Number(process.env.PWT_PROBE_MS || 5000);
const FIX = process.argv.includes('--fix');

function truncate(str, max) {
  return str.length > max ? str.slice(0, max) + '…' : str;
}

// 타깃별 WebSocket 1회 왕복. 브라우저 세션 하나에 몰지 않으므로 병렬로 쓸 수 있다.
function cdp(wsUrl, method, params = {}, timeoutMs = PROBE_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    let ws;
    const done = (r) => {
      try { ws && ws.close(); } catch { /* ignore */ }
      resolve({ ...r, ms: Date.now() - t0 });
    };
    const timer = setTimeout(() => done({ ok: false, err: 'TIMEOUT' }), timeoutMs);
    try { ws = new WebSocket(wsUrl); } catch (err) { clearTimeout(timer); return done({ ok: false, err: err.message }); }
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method, params }));
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.id !== 1) return;
      clearTimeout(timer);
      done(data.error ? { ok: false, err: data.error.message } : { ok: true, result: data.result });
    };
    ws.onerror = () => { clearTimeout(timer); done({ ok: false, err: 'ws error' }); };
  });
}

// 응답 여부를 한 왕복으로 확인한다.
// document.visibilityState 는 쓰지 않는다 — freeze 방지 플래그(--disable-backgrounding-*)
// 하에서는 모든 탭이 visible 을 보고한다(2026-08-19 실측: 같은 창 3탭 전부 visible+hasFocus).
const probe = (t) => cdp(t.webSocketDebuggerUrl, 'Runtime.evaluate',
  { expression: '1', returnByValue: true });

async function main() {
  let pageTargets;
  try {
    const res = await fetch(`${BASE}/json/list`);
    pageTargets = (await res.json()).filter((t) => t.type === 'page');
  } catch (err) {
    console.error(`❌ CDP HTTP(${BASE}) 연결 실패: ${err.message}`);
    process.exit(1);
  }

  // 진단은 병렬이다. 직렬이면 무응답 개수 × timeout 만큼 걸려
  // 무응답 5개에 25초가 든다(실측). 병렬이면 timeout 1회로 끝난다.
  const startedAt = Date.now();
  const probes = await Promise.all(pageTargets.map(async (t) => {
    const r = await probe(t);
    return { target: t, alive: r.ok, ms: r.ms };
  }));
  const probeMs = Date.now() - startedAt;

  console.log(`${'상태'.padEnd(6)} ${'응답시간'.padEnd(10)} targetId${' '.repeat(24)} URL`);
  for (const p of probes) {
    const url = truncate(p.target.url || '', 60);
    const mark = p.target.id === pageTargets[0]?.id ? '[보임] ' : '';
    console.log(`${p.alive ? '✅ OK  ' : '❌ 무응답'} ${(p.ms + 'ms').padEnd(10)} ${p.target.id} ${mark}${url}`);
  }

  const frozen = probes.filter((p) => !p.alive);
  console.log(`\n요약: page 타깃 ${pageTargets.length}개 중 ${frozen.length}개 무응답 (진단 ${probeMs}ms, 병렬)`);

  if (!frozen.length) {
    process.exit(0);
  }
  if (!FIX) {
    console.log('connectOverCDP hang의 원인일 가능성이 높다. `--fix`로 복구를 시도하거나 실행환경-공통게이트.md §5-1 절차를 따른다.');
    process.exit(1);
  }

  // ── --fix: 무응답 탭만 activateTarget ────────────────────
  let browserWs;
  try {
    browserWs = (await (await fetch(`${BASE}/json/version`)).json()).webSocketDebuggerUrl;
  } catch (err) {
    console.error(`❌ 브라우저 엔드포인트 조회 실패: ${err.message}`);
    process.exit(1);
  }

  // /json/list 는 최근 활성화(MRU) 순이라 첫 page 항목이 사용자가 보던 탭이다
  // (2026-08-19 실측: activateTarget 3회 모두 첫 항목과 일치, AppleScript active tab 교차 확인).
  // Target.getTargets 순서는 MRU 가 아니어서 쓸 수 없다.
  const wasVisible = pageTargets[0];
  console.log('');
  for (const p of frozen) {
    const r = await cdp(browserWs, 'Target.activateTarget', { targetId: p.target.id }, 3000);
    console.log(`  activate ${r.ok ? 'OK  ' : 'FAIL'} ${(r.ms + 'ms').padEnd(8)} ${truncate(p.target.url || '', 60)}`);
  }

  // activateTarget은 탭을 전면으로 올린다. 사용자가 보던 탭으로 되돌린다.
  if (wasVisible) {
    await cdp(browserWs, 'Target.activateTarget', { targetId: wasVisible.id }, 3000);
    console.log(`  포커스 복귀 → ${truncate(wasVisible.url || '', 60)}`);
  }

  const recheck = await Promise.all(frozen.map((p) => probe(p.target)));
  const still = recheck.filter((r) => !r.ok).length;
  if (still) {
    console.log(`\n⚠️ ${still}개가 여전히 무응답 — activateTarget으로 풀리지 않는 정지다.`);
    console.log('실행환경-공통게이트.md §5-1의 나머지 절차(CDP 클라이언트 정리 → 사용자 승인 후 탭 종료/재시작)로 넘어간다.');
    process.exit(1);
  }
  console.log(`\n✅ ${frozen.length}개 전부 복구 — connectOverCDP를 다시 시도한다.`);
  process.exit(0);
}

main().catch((err) => {
  console.error(`❌ 진단 실패: ${err.message}`);
  process.exit(1);
});
