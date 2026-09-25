# playwright-cli 명령어 레퍼런스

Chrome Beta CDP 포트(기본 9333)에 붙어 실제 로그인 세션을 사용하는 브라우저 확인 도구다.
`snapshot`/`click ref` 같은 접근성 트리 기반 조작에는 이 CLI가 필요하다.

> **먼저 읽을 것**: `playwright-cli open`은 공유 프로필의 기존 탭 하나를 `about:blank`로 덮어쓴다(실측 2회 재현). 사용자 탭이 열려 있는 고정 프로필에서 `open`을 먼저 실행하면 남의 작업이 날아간다. 세션 생성 없이 targetId만으로 조작하는 `references/infra/tools/pwx.js`를 기본 경로로 쓰고, 이 CLI는 `snapshot` 계열이 필요할 때만 쓴다.

> 전역 옵션은 명령 **뒤**에 붙인다(`run-code '<code>' --raw`). 명령 앞의 `--config`는 0.1.13에서 실패할 수 있다.
> CDP 직접 연결: `PLAYWRIGHT_MCP_CDP_ENDPOINT=http://127.0.0.1:${E2E_CDP_PORT:-9333}`, `PLAYWRIGHT_MCP_ISOLATED=false`, `-s=<session>`으로 `open` 후 같은 세션에서 실행. 유용한 전역 옵션: `--raw`(결과값만), `--json`.

## 환경 설정

```bash
# 프로젝트 E2E 인프라가 있을 때
cd e2e && ./e2e.sh setup

# 직접 확인
command -v playwright-cli || echo "playwright-cli 미설치: npm i -g @playwright/cli"
curl -s http://127.0.0.1:${E2E_CDP_PORT:-9333}/json/version
```

## 세션 관리

```bash
./e2e/tools/pwc.sh open
./e2e/tools/pwc.sh list
./e2e/tools/pwc.sh close
```

래퍼 없이 직접 실행:

```bash
PLAYWRIGHT_MCP_CDP_ENDPOINT=http://127.0.0.1:${E2E_CDP_PORT:-9333} \
PLAYWRIGHT_MCP_ISOLATED=false \
playwright-cli -s=e2e-cdp open
```

## targetId 확인

반복 실행과 병렬 조작은 tab index가 아니라 CDP `targetId`로 고정한다.

```bash
<스킬경로>/references/infra/tools/pwx.js list      # 권장 — 브라우저 세션 생성 없음
curl -s http://127.0.0.1:${E2E_CDP_PORT:-9333}/json/list \
  | jq -r '.[] | select(.type=="page") | [.id,.title,.url] | @tsv'   # node 없을 때
```

목록은 한 번 조회해 targetId를 기억하고 재조회하지 않는다. 같은 작업 중 3회 조회하면 그만큼 출력 토큰이 중복된다.

시나리오 실행:

```bash
cd e2e && E2E_TAB_ID=<targetId> ./e2e.sh run '시나리오/대상.js'
```

## 탐색

```bash
./e2e/tools/pwc.sh goto "https://URL"
./e2e/tools/pwc.sh back
./e2e/tools/pwc.sh forward
```

## 스냅샷과 요소 확인

```bash
./e2e/tools/pwc.sh snapshot
./e2e/tools/pwc.sh screenshot
```

snapshot 출력을 AI가 통째로 읽으면 토큰이 급증한다. snapshot 실행 후 필요한 ref만 필터링한다.

```bash
./e2e/tools/pwc.sh snapshot && grep -i "찾을요소" e2e/.playwright-cli/page-*.yml | grep "ref=" | tail -5
```

## 요소 조작

```bash
./e2e/tools/pwc.sh click e10
./e2e/tools/pwc.sh fill e37 "텍스트"
./e2e/tools/pwc.sh select e20 "옵션값"
./e2e/tools/pwc.sh check e15
./e2e/tools/pwc.sh uncheck e15
./e2e/tools/pwc.sh press Enter
./e2e/tools/pwc.sh press Escape
```

## JavaScript 실행

```bash
./e2e/tools/pwc.sh eval "document.title"
./e2e/tools/pwc.sh eval "document.querySelector('#id').value"
./e2e/tools/pwc.sh eval "document.querySelectorAll('tr').length"
./e2e/tools/pwc.sh eval "document.querySelector('.cls') ? document.querySelector('.cls').innerText.trim() : '없음'"
```

IIFE `(function(){...})()`는 직렬화 오류가 날 수 있다. 여러 동작이 필요하면 각각 별도 eval로 나눈다.

## targetId 고정 실행은 pwx.js를 쓴다 (run-code보다 우선)

iframe, targetId page 고정, 여러 단계 조작에는 `references/infra/tools/pwx.js`를 사용한다. `playwright-cli run-code`는 아래 세 가지 실측 문제가 있어 fallback으로만 남긴다.

```bash
PWX=<스킬경로>/references/infra/tools/pwx.js

$PWX list                      # targetId<TAB>url<TAB>title
$PWX new "https://URL"         # 새 탭 생성 + title 검증을 한 왕복으로
$PWX "$ID" title               # "title | url" (쿼리는 80자까지 보존, 초과분만 절삭) — 게이트 4 검증용
$PWX "$ID" 'page.title()'      # 단일 표현식
$PWX "$ID" 'await page.fill("[name=q]","검색어"); return page.url()'   # return 있으면 함수 본문
```

`page`(대상 탭)와 `ctx`(BrowserContext)가 바인딩된다. 출력은 `PWX_MAX`(기본 2000)자에서 잘려 페이지 텍스트를 통째로 흘려 컨텍스트를 태우는 사고를 도구 레벨에서 막는다.

### playwright-cli run-code를 기본으로 쓰지 않는 이유 (요약)

`open`의 기존 탭 파괴(2회 재현) + 입력 스크립트 에코백(출력 14배) + targetId 보일러플레이트 반복. 수치 전문은 `토큰-최적화-실측데이터.md` "도구 오버헤드 실측". `attach`는 CDP endpoint에 붙지 않아(무음 실패) 탭 파괴를 우회할 방법이 없다 — `pwx.js`의 `connectOverCDP`는 기존 탭을 건드리지 않는다(diff 0).

### fallback으로 run-code를 쓸 때의 계약

`playwright-cli 0.1.13 --help`: *"a javascript function containing playwright code... invoked with a single argument, page"*. 실제 계약은 다음과 같다. 톱레벨 문장으로 쓰면 `SyntaxError`다.

```bash
playwright-cli -s=e2e-cdp run-code 'async (page) => {
  const ctx = page.context();          // context 전역은 없다 — page.context()로 얻는다
  return (await page.title());         // 반환값이 "### Result"로 출력된다
}' --raw                               # --raw로 status/에코 일부를 줄인다
```

- `process`는 스코프에 없다 — `process.env.E2E_TAB_ID`는 `ReferenceError`. targetId는 문자열 리터럴로 주입한다.
- `console.log`는 출력에 나타나지 않는다. 결과 회수는 `return`만 사용한다.

## iframe 처리

```js
await page.frameLocator('#same-frame').locator('#keyword').fill('검색어');

const frame = page.frames().find((candidate) => candidate.url().includes('/iframe-path'));
if (!frame) throw new Error('iframe not found');
await frame.locator('#keyword').fill('검색어');
```

same-origin 단순 확인은 `eval`로도 가능하지만, nested/cross-origin iframe은 Playwright `frameLocator` 또는 `page.frames()`를 기본으로 한다.

## 탭 관리

```bash
./e2e/tools/pwc.sh tab-list
./e2e/tools/pwc.sh tab-select 1
./e2e/tools/pwc.sh tab-new "https://URL"
./e2e/tools/pwc.sh tab-close
```

`tab-select N`은 단발 확인용이다. suite, QA 재현, 자동수정 루프에서는 `E2E_TAB_ID`를 사용한다.

## 주의사항

- ref는 DOM 변경 시 무효화된다.
- snapshot 결과는 필요한 줄만 필터링한다.
- `./e2e/tools/pwc.sh close`는 CDP 연결만 끊고 Chrome Beta 브라우저는 유지한다.
- 병렬 조작은 tab index가 아니라 코드 내부에서 CDP `targetId`로 page를 다시 찾아 실행한다.
- 민감 세션과 운영 데이터 변경은 사용자 확인 후 진행한다.

## 출력 절삭

`run-code`는 응답 **앞부분**에 결과를, 뒷부분에 입력 스크립트 에코를 붙인다. `tail`로 자르면 에코가 그대로 남으므로 방향이 틀렸다.

```bash
... run-code '<code>' --raw 2>&1 | grep -E '^(###|ERR|[^`])' | head -5   # 화이트리스트
```

다만 필터가 너무 좁으면 에러 메시지까지 지워져 원인을 못 보고 재시도하게 된다 — 실패 왕복이 절약분보다 비싸다. 에러 형식은 `### Error` + 다음 줄이므로 최소 2줄은 남긴다.

긴 URL(Google `gs_lp`·`sxsrf` 등은 700B를 넘긴다)은 판단에 기여하지 않는다. 다만 쿼리를 통째로 버리면 안 된다 — 백오피스 SPA는 `?page=2&status=active`처럼 화면 상태를 쿼리에 담으므로 그게 사라지면 탭 구분·검증이 흐려진다. `pwx.js`는 쿼리를 80자까지 보존하고 초과분만 `…(+N자)`로 표시한다.

## pwx.js 동시 attach 주의

`connect.js` 실측 주석: **같은 탭에 두 번째 프로세스가 `connectOverCDP`로 재attach된 상태에서는 그 탭의 fetch가 완료되지 않을 수 있다**(요청은 추적되나 응답 이벤트가 안 옴). 따라서 `./e2e.sh run`이 그 탭에서 **실행 중일 때** `pwx.js`를 붙이지 않는다. 실행이 끝난 뒤 확인하는 순차 사용은 안전하다 — 재attach 3회 후에도 fetch가 정상 완료됐다(2026-07-30 실측, status 200 / 1,483ms→16ms→22ms).
