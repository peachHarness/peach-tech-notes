---
name: peach-e2e-browse
description: Chrome CDP+Playwright로 브라우저를 탐색·조작한다.
---

# AI 브라우저 탐색

Chrome Beta 고정 프로필의 CDP 포트(기본 9333)를 raw CDP 조회와 Playwright 조작(`connectOverCDP` + `targetId` 고정)으로 제어한다. 다른 스킬(design·e2e·team-e2e)이 브라우저 제어를 위임하는 행위 SoT다.

Chrome 실행 불변 규칙·인프라 버전 게이트·탭 확정·주소 정책의 상세와 명령 전문은 `references/실행환경-공통게이트.md`가 SoT다. 아래 강제 게이트는 그 요약이며, 충돌 시 SoT를 따른다.

## 강제 게이트 (권장이 아니라 강제)

0. CDP는 `127.0.0.1:${E2E_CDP_PORT:-9333}` 사용. 연결 확인: `curl -s http://127.0.0.1:${E2E_CDP_PORT:-9333}/json/version`
1. Chrome Beta 실행은 `cd e2e && ./e2e.sh chrome` 우선. 직접 실행은 고정 프로필 옵션 필수 (명령 전문: 공통게이트 §1)
2. `e2e/e2e.sh`가 있으면 작업 전 `./e2e.sh status` 확인. `E2E_INFRA_VERSION`이 최신 계약 버전 `1.2.9`와 다르거나, 포트가 `9222`, `E2E_BROWSER_STATE=stale`, 또는 `E2E_BROWSER_FLAGS=missing`(freeze 방지 플래그 없이 기동됨 — attach hang 재발 위험)이면 중단한다. 버전 불일치는 `references/셋업-배포.md`로 최신 인프라를 갱신하고, stale(실행본/설치본 불일치)은 탭 영향 보고와 사용자 승인 후 Chrome Beta를 재시작한다
3. URL/base_url이 있으면 CDP `/json/list`에서 같은 origin 탭을 먼저 찾는다 — 1개면 재사용, 0개면 새 탭 생성 후 `targetId` 기록, 2개+면 사용자에게 선택 확인. URL 없이 탭 미확정이면 목록·상태만 보고하고 대기
4. 작업 탭 확정 후 `document.title + ' | ' + location.href`로 검증하고, 이후 실행 컨텍스트는 `targetId`/`E2E_TAB_ID`로 고정 — 검증 전에는 조작하지 않는다
5. Google 로그인·OAuth·관리자 콘솔·결제·프로필 세션 유지 작업은 상태 확인까지만 자율 수행. 입력/제출/설정 변경/운영 데이터 변경은 사용자 확인 후
6. 인증/2차 인증은 AI가 직접 시도하지 않는다 — 사용자가 고정 프로필에서 완료한 세션을 이어받는다
7. 도구가 비정상이어도 OS 레벨 우회(`open -a`, 다른 브라우저, 다른 프로필 경로)를 하지 않는다. 상태 보고 후 중단
8. `playwright-cli open`을 고정 프로필에 실행하지 않는다 — 기존 탭 1개를 `about:blank`로 덮어써 사용자 작업이 사라진다(실측 2회 재현). `snapshot`/`click ref`가 꼭 필요할 때만, 손실 가능성을 사전 보고하고 사용

## 부트스트랩 (이 3줄로 게이트 0·3·4를 통과한다)

```bash
PWX=<이 스킬 경로>/references/infra/tools/pwx.js         # node + 전역 playwright-core 필요
curl -s http://127.0.0.1:${E2E_CDP_PORT:-9333}/json/version | head -2   # 게이트 0
$PWX list                                          # 게이트 3 — targetId<TAB>url<TAB>title
$PWX new "https://URL"                             # 같은 origin 탭이 없을 때: 생성+검증 1왕복
$PWX "$ID" title                                   # 게이트 4 — "title | url" (쿼리는 80자까지 보존, 초과분만 절삭)
$PWX "$ID" eval "({title:document.title,href:location.href})" # raw CDP 읽기
$PWX "$ID" eval "(() => { const el=document.querySelector('.p-panel'); const cs=getComputedStyle(el); return {radius:cs.borderRadius, border:cs.border, h:el.getBoundingClientRect().height}; })()"  # CSS 판정 — 속성을 묶어 1회, screenshot 대신
```

`list`·`title`·`eval`은 Playwright를 attach하지 않는 raw CDP 조회다. `$PWX list` 결과는 한 번만 조회해 targetId를 기억한다. 클릭·입력 등 실제 조작은 `$PWX "$ID" '<code>'`로 하고, `page`·`ctx`가 바인딩된다. 조작 코드는 브라우저 JS가 아니라 **node 컨텍스트(Playwright API)**다 — `document`를 직접 쓰면 `not defined`이고, DOM 읽기만 필요하면 `eval`, 조작은 `page.locator()` 또는 `page.evaluate(() => ...)`를 사용한다. 출력은 2000자에서 잘린다(`PWX_MAX`).

독립적인 DOM 확인은 `eval`에서 객체 하나로 묶고, 실제 조작은 Playwright attach 한 번에 묶는다. 단, 앞 결과를 보고 판단이 갈리는 지점(탭 2개+ 확인, 민감 세션 승인)에서는 끊는다.

CDP 미연결이면 `cd e2e && ./e2e.sh chrome`(없으면 공통게이트 §1 직접 실행) 후 재확인하고, 그래도 실패면 사용자에게 수동 실행을 안내한다. `PLAYWRIGHT_ATTACH_TIMEOUT`은 같은 명령을 반복하지 않고 **먼저 `node e2e/tools/pwt.js --fix`를 실행한다** — freeze된 탭을 `Target.activateTarget`으로 되살리며 비파괴여서 사용자 승인이 필요 없다. 복구되면 그대로 진행하고, exit 1로 남으면 공통게이트 §5-1의 나머지 절차(정확한 CDP 클라이언트 정리 → 필요 시 사용자 승인 후 Chrome Beta 재시작)로 넘어간다. DOM 확인은 가능하면 코드·테스트 구현을 먼저 읽고 실제 확인은 필요한 범위만(미니파이·벤더 파일은 grep 대상에서 제외). 반복 가치가 있으면 peach-e2e-scenario로 시나리오화한다.

**`screenshot` + `Read` 조합을 판정 도구로 반복 사용하지 않는다.** 값으로 판정 가능한 항목(테두리 모양, 배경색, 높이, 표시 여부)은 `eval`의 `getComputedStyle()`/`getBoundingClientRect()`로 확인한다 — 필요한 속성을 객체 하나로 묶어 한 번에 받으면 수백 바이트로 끝난다. `screenshot`은 사람이 최종적으로 눈으로 확인해야 하는 시점(수정 완료 후, 결과 보고용)에만 쓰고 수정 1건마다 찍지 않는다. 찍어야 하면 전체 화면 대신 `page.locator('.대상').screenshot()`이나 `clip`으로 관심 영역만 좁힌다 — 이미지 토큰은 넓이×높이에 비례해 실측 13배까지 갈린다. `PWX_MAX`를 올리기 전에 `querySelector`로 반환 범위를 먼저 좁힌다. 실측 비교는 `references/토큰-최적화-실측데이터.md`.

## 도구 역할 분담

| 용도 | 기본 도구 | 기준 |
|------|----------|------|
| 탭 목록·확정·검증·DOM 읽기 | **`references/infra/tools/pwx.js`의 `list`/`title`/`eval`** | raw CDP라 Playwright attach 없음 |
| 클릭·입력·새 탭 등 실제 조작 | **`references/infra/tools/pwx.js`의 Playwright 코드** | targetId 고정, 10초 attach/60초 전체 timeout |
| 접근성 트리 기반 조작(`snapshot`/`click ref`) | `playwright-cli` / `./e2e/tools/pwc.sh` | isTrusted 이벤트가 필요할 때만. `open` 탭 파괴 주의(게이트 8) |
| attach hang 진단·복구 | **`references/infra/tools/pwt.js`** (`--fix`) | `PLAYWRIGHT_ATTACH_TIMEOUT` 시 최우선. 비파괴·승인 불필요, 안 풀리면 exit 1 |
| 시나리오 실행·반복·QA 재현 | `E2E_TAB_ID=<targetId> ./e2e.sh run` | 실행별 기본 300초 제한, `--tab N` 반복 루프 금지 |
| 값으로 판정 가능한 CSS·레이아웃 확인(테두리·색상·높이·간격) | `eval`의 `getComputedStyle()`/`getBoundingClientRect()` | 스크린샷보다 1~2자릿수 저렴. 판정에 필요한 속성을 객체로 묶어 1회 반환 |
| 사람이 최종적으로 눈으로 봐야 하는 시점 | `screenshot file.png`(경로만, 80B) — `Read`는 결과 보고 시 1회로, **반드시 `clip`/요소 screenshot으로 좁혀서** | `screenshot`+`Read` 반복 = 회당 이미지 토큰. 뷰포트 전체 ~1,850 vs 요소 clip ~130(실측 13배차). 수정 1건마다 찍지 않는다 |
| iframe/nested/cross-origin | `pwx.js`에서 `page.frameLocator()` / `page.frames()` | 브라우저 JS `contentDocument`는 cross-origin에서 막힘 — quick check로만 |
| agent-browser | 명시 opt-in 한정 (아래) | current tab 공유 위험 |

## agent-browser 명시 opt-in

기본 도구가 아니다. 사용자 명시 요청 + 단일 AI 세션 + 읽기 전용 DOM 확인(click/fill/submit/운영 변경 없음) + 간섭 가능성 사전 보고를 모두 만족할 때만 사용하고, 병렬·장시간 suite·QA 재현·자동수정 루프에서는 금지한다. 근거는 병렬 탭 격리 실측 cross-tab 50/100(`references/토큰-최적화-실측데이터.md`), 명령은 `references/agent-browser-명령어.md`.

## 참조 문서

참조 문서는 조건이 걸렸을 때만 로드한다. 위 부트스트랩 3줄로 끝나는 단순 조회에서 8KB SoT를 통째로 읽으면 그 작업에서 쓰이지 않는 절이 절반이다. 로드할 때도 필요한 절만(`grep`, `Read offset/limit`) 읽는다.

| 문서 | 용도 | 로드 조건 |
|------|------|-----------|
| `references/실행환경-공통게이트.md` | Chrome 실행·버전 게이트·탭 확정·주소 정책 (SoT, 명령 전문) | Chrome 미실행, URL 미확정, 인프라 버전 게이트 판정, 민감 세션, 업로드 — 즉 부트스트랩이 막힐 때 |
| `references/셋업-배포.md` | E2E 인프라 설치/갱신 절차 (인프라 코드 SoT: `references/infra/`) | 초기 설치, 버전 게이트 불일치 시 |
| `references/playwright-cli-명령어.md` | playwright-cli(pwc.sh)·snapshot·run-code fallback | `snapshot`/`click ref`(isTrusted) 필요 시, pwx.js 불가 환경 — 일반 DOM 확인·조작은 부트스트랩의 pwx.js로 충분, 이 문서 불필요 |
| `references/탭-선택-패턴.md` | `targetId` 선택·`E2E_TAB_ID` 고정 상세 | 탭 확정 시 |
| `references/iframe-모달-패턴.md` | iframe/모달 접근 | iframe 대상 시 |
| `references/SPA-프레임워크-입력패턴.md` | Angular/React controlled input·file input | `fill` 값이 반영 안 되거나 validation이 계속 막을 때, 파일 업로드 시 — 일반 입력은 pwx.js `locator().fill()`로 충분 |
| `references/native-dialog-주의사항.md` | CDP 상주 세션의 dialog 자동 dismiss | dialog 개입 시 |
| `references/Flutter-웹앱-패턴.md` | Flutter 웹앱 판별/accessibility | Flutter 감지 시 |
| `references/외부서비스-링크전환-패턴.md` | 외부 서비스 링크 전환 fallback | 외부 전환 시 |
| `references/고정프로필-강제게이트-패턴.md` | 민감 세션 중단 조건·우회 금지 | 민감 세션 시 |
| `references/agent-browser-명령어.md` | agent-browser 명령 | opt-in 시 |
| `references/토큰-최적화-실측데이터.md` | 속도·병렬 격리 실측 | 도구 선택 판단 시 |
