// run-scenario.test.js — 시나리오 실행 watchdog 회귀 테스트
//
// 실행: cd e2e && ./e2e.sh test  (검증 대상 스크립트와 같은 폴더에 둔다)
//
// 이 파일이 지키는 것:
//   watchdog은 "시나리오가 영영 안 끝나는" 사고의 마지막 방어선이다. 실제로 무한 대기를
//   겪고 나서 도입됐고, 이게 조용히 망가지면 증상이 "테스트가 안 끝남"으로만 나타나
//   원인을 찾는 데 오래 걸린다. 그런데 정작 이 로직 자체는 Chrome이 전혀 필요 없다 —
//   자식 node 프로세스를 죽이는 것뿐이라 여기서 온전히 검증할 수 있다.
//
// 가짜 시나리오로 `node -e '<코드>'`를 쓴다. run-scenario.js가 인자를 그대로
// process.execPath에 넘기므로 fixture 파일을 만들 필요가 없다.

const { test } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('child_process');
const path = require('path');

const RUNNER = path.resolve(__dirname, 'run-scenario.js');

// run-scenario.js를 실행하고 종료코드와 stderr를 돌려준다.
function runRunner(args, env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [RUNNER, ...args], {
      env: { ...process.env, ...env },
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let stderr = '';
    child.stderr.on('data', (c) => (stderr += c));
    child.on('exit', (code) => resolve({ code, stderr }));
  });
}

test('정상 종료: 시나리오의 exit code를 그대로 전달한다', async () => {
  // 시나리오 실패(1)와 watchdog 타임아웃(124)이 섞이면 자동수정 판단이 어긋난다.
  const { code } = await runRunner(['-e', 'process.exit(3)']);
  assert.strictEqual(code, 3);
});

test('성공 시 타이머가 해제되어 즉시 끝난다', async () => {
  // 타이머를 안 지우면 시나리오가 끝나도 부모가 300초를 붙들고 있게 된다.
  const started = process.hrtime.bigint();
  const { code } = await runRunner(['-e', 'process.exit(0)'], { E2E_SCENARIO_TIMEOUT_SEC: '30' });
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;

  assert.strictEqual(code, 0);
  assert.ok(elapsedMs < 5000, `타이머 미해제 의심 — ${Math.round(elapsedMs)}ms 소요`);
});

test('무한 대기 시나리오를 타임아웃으로 끊고 124로 보고한다', async () => {
  // 이번 결함 계열(freeze 탭에서 렌더러 응답이 영영 안 옴)의 최종 방어선.
  const { code, stderr } = await runRunner(
    ['-e', 'setInterval(() => {}, 1000)'],   // 스스로는 절대 끝나지 않는다
    { E2E_SCENARIO_TIMEOUT_SEC: '1' }
  );

  assert.strictEqual(code, 124, 'SCENARIO_PROCESS_TIMEOUT은 124여야 한다');
  assert.match(stderr, /SCENARIO_PROCESS_TIMEOUT/);
});

test('잘못된 입력은 실행 전에 2로 거절한다', async () => {
  const noArgs = await runRunner([]);
  assert.strictEqual(noArgs.code, 2);

  const badTimeout = await runRunner(['-e', 'process.exit(0)'], { E2E_SCENARIO_TIMEOUT_SEC: '0' });
  assert.strictEqual(badTimeout.code, 2);
});
