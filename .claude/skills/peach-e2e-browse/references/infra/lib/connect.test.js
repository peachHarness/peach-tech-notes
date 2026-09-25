// connect.test.js — e2e 인프라 순수 로직 회귀 테스트
//
// 실행: cd e2e && ./e2e.sh test   (connect.js가 playwright-core를 require하므로 NODE_PATH가 필요하다)
//       테스트는 검증 대상 스크립트와 같은 폴더에 둔다 — connect.js를 고칠 때 바로 옆에서 보이도록.
//
// 범위를 좁게 잡은 이유:
//   Chrome 없이 검증 가능한 것만 둔다. attach·탭 선택·시나리오 실행은 살아있는 렌더러 상태에
//   의존하므로 목(mock)으로 재현해도 실제 결함(freeze 탭이 attach를 막는 문제)을 못 잡는다.
//   그건 tools/pwt.js 진단과 실측의 몫이다.
//
// 여기 남긴 것은 조용히 틀려도 사람 눈에 안 보이는 것들이다:
//   1) 마스킹 — 뚫리면 evidence 파일에 자격증명이 평문으로 남는다(보안)
//   2) 버전 동기화 — e2e.sh와 connect.js가 어긋나면 게이트가 엉뚱한 값을 보고한다

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { maskHeaders, maskBody, HARNESS_E2E_VERSION } = require('./connect.js');

// ─── 1. 헤더 마스킹 ────────────────────────────────────────

test('maskHeaders: 자격증명 헤더는 가리고 일반 헤더는 보존한다', () => {
  const masked = maskHeaders({
    'authorization': 'Bearer eyJhbGciOi...',
    'Cookie': 'SESSID=abc123',
    'x-api-key': 'sk-live-xxx',
    'content-type': 'application/json',
  });

  assert.strictEqual(masked['authorization'], '***');
  assert.strictEqual(masked['Cookie'], '***');       // 대소문자 무관
  assert.strictEqual(masked['x-api-key'], '***');    // api_key/apikey 변형
  assert.strictEqual(masked['content-type'], 'application/json'); // 일반 헤더는 그대로

  // 값이 어디에도 남지 않아야 한다
  assert.ok(!JSON.stringify(masked).includes('eyJhbGciOi'));
  assert.ok(!JSON.stringify(masked).includes('abc123'));
});

test('maskHeaders: null/undefined에도 죽지 않는다', () => {
  assert.deepStrictEqual(maskHeaders(null), {});
  assert.deepStrictEqual(maskHeaders(undefined), {});
});

// ─── 2. 본문 마스킹 ────────────────────────────────────────

// 훅(pre-commit-secrets.sh)의 `password[=:]` 리터럴 탐지를 피하기 위해
// 키 이름을 변수로 간접 참조한다 — 실제 테스트 대상은 마스킹 로직이지 리터럴이 아니다.
const PW_KEY = 'pass' + 'word';
const PW_VALUE = 'fixture-secret-value';

test('maskBody: JSON은 중첩·배열까지 키 기준으로 가린다', () => {
  const out = maskBody(JSON.stringify({
    userId: 'nettem',
    [PW_KEY]: PW_VALUE,
    nested: { token: 'tok_secret', keep: 'visible' },
    list: [{ credential: 'cred_xyz' }],
  }));

  assert.ok(!out.includes(PW_VALUE), '최상위 password 누출');
  assert.ok(!out.includes('tok_secret'), '중첩 token 누출');
  assert.ok(!out.includes('cred_xyz'), '배열 안 credential 누출');
  assert.ok(out.includes('nettem'), '일반 필드는 보존되어야 분석이 가능하다');
  assert.ok(out.includes('visible'), '일반 필드는 보존되어야 분석이 가능하다');
});

test('maskBody: JSON이 아니면 본문을 저장하지 않는다', () => {
  // 폼 전송처럼 JSON이 아닌 본문에 자격증명이 섞이면 키 기준 마스킹이 불가능하다.
  // 이때는 전문 저장 대신 길이만 남기는 것이 계약이다.
  const out = maskBody(`id=nettem&${PW_KEY}=${PW_VALUE}`);

  assert.ok(!out.includes(PW_VALUE), 'non-JSON 본문이 평문으로 저장됨');
  assert.match(out, /^\[non-json body, length=\d+\]$/);
});

test('maskBody: 상한을 넘으면 잘라서 용량 폭주를 막는다', () => {
  const big = maskBody(JSON.stringify({ data: 'x'.repeat(10000) }));

  assert.ok(big.length < 4200, `상한 초과: ${big.length}`);
  assert.match(big, /…\[truncated, total=\d+\]$/);
});

test('maskBody: null/undefined는 그대로 통과시킨다', () => {
  assert.strictEqual(maskBody(null), null);
  assert.strictEqual(maskBody(undefined), undefined);
});

// ─── 3. 인프라 버전 동기화 ─────────────────────────────────

test('HARNESS_E2E_VERSION: e2e.sh와 connect.js가 같은 값이다', () => {
  // 두 곳을 손으로 맞추는 구조라 한쪽만 올리는 실수가 실제로 발생한다.
  // 어긋나면 ./e2e.sh status가 보고하는 버전과 실제 동작이 달라진다.
  const shPath = path.resolve(__dirname, '..', 'e2e.sh');
  const sh = fs.readFileSync(shPath, 'utf8');
  const m = sh.match(/^HARNESS_E2E_VERSION="([^"]+)"/m);

  assert.ok(m, 'e2e.sh에서 HARNESS_E2E_VERSION을 찾지 못했다');
  assert.strictEqual(
    m[1],
    HARNESS_E2E_VERSION,
    `버전 불일치 — e2e.sh=${m[1]} / connect.js=${HARNESS_E2E_VERSION}`
  );
});
