#!/usr/bin/env node
// 각 시나리오의 최대 실행시간만 제한한다. 정상 종료 시 타이머도 즉시 해제된다.

const { spawn } = require('child_process');
const path = require('path');

const args = process.argv.slice(2);
const timeoutSeconds = Number(process.env.E2E_SCENARIO_TIMEOUT_SEC || 300);

if (args.length === 0) {
  console.error('❌ 실행할 시나리오를 지정하세요.');
  process.exit(2);
}
if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
  console.error('❌ E2E_SCENARIO_TIMEOUT_SEC는 0보다 큰 숫자여야 합니다.');
  process.exit(2);
}

// ponytail: 시나리오는 별도 자식 프로세스를 만들지 않는 계약이다. 필요해지면 프로세스 그룹 종료로 확장한다.
const child = spawn(process.execPath, args, {
  cwd: path.resolve(__dirname, '..'),
  env: process.env,
  stdio: 'inherit',
});

let timedOut = false;
let forceTimer = null;
const timeoutTimer = setTimeout(() => {
  timedOut = true;
  console.error(`❌ SCENARIO_PROCESS_TIMEOUT (${timeoutSeconds}s): 시나리오 프로세스를 종료합니다.`);
  child.kill('SIGTERM');
  forceTimer = setTimeout(() => child.kill('SIGKILL'), 2000);
}, timeoutSeconds * 1000);

// 부모가 종료 신호를 받으면 자식도 함께 정리한다.
// 터미널 Ctrl-C는 프로세스 그룹 전체에 SIGINT를 보내 자식도 같이 죽지만, 그룹이 아닌 단일 PID로
// kill 되면(상위 러너·IDE·다른 세션이 이 프로세스만 종료) 자식만 살아남아 CDP 연결을 붙든
// 고아 node 프로세스가 된다. 그 고아는 다음 실행의 attach를 방해한다.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    child.kill(sig);
    // 자식이 신호를 무시해도 부모가 영영 남지 않도록 강제 종료로 승격한다.
    // unref: 이 타이머 때문에 이벤트 루프가 살아있지 않도록 한다.
    setTimeout(() => child.kill('SIGKILL'), 2000).unref();
  });
}

child.once('error', (error) => {
  clearTimeout(timeoutTimer);
  if (forceTimer) clearTimeout(forceTimer);
  console.error(`❌ 시나리오 실행 실패: ${error.message}`);
  process.exit(1);
});

child.once('exit', (code, signal) => {
  clearTimeout(timeoutTimer);
  if (forceTimer) clearTimeout(forceTimer);
  if (timedOut) return process.exit(124);
  if (code !== null) return process.exit(code);
  const signalExitCode = { SIGINT: 130, SIGTERM: 143, SIGKILL: 137 }[signal] || 1;
  process.exit(signalExitCode);
});
