# agent-browser 명령어 레퍼런스

Chrome Beta CDP에 연결된 상태에서 사용하는 명령어.
탐색/검증/확인의 기본 도구. eval 우선 전략.

## CDP 연결

```bash
# 최초 1회 -- 이후 세션 유지
agent-browser connect ${E2E_CDP_PORT:-9333}
```

> `connect` 없이 명령 실행하면 headless 새 브라우저가 열린다 (보이지 않음!).
> 반드시 Chrome Beta CDP에 먼저 connect 해야 한다.
> `connect` 또는 `tab list`가 비정상이면 `open -a`, 다른 브라우저, 다른 프로필 경로로 우회하지 말고 상태를 보고한다.

## 탭 관리

```bash
agent-browser tab list --json                   # 탭 목록 (tabId/label 확인)
agent-browser tab new --label app "https://URL" # label 있는 새 탭 생성 + 이동
agent-browser tab t3                            # t3 탭으로 전환
agent-browser tab app                           # app label 탭으로 전환
agent-browser tab close                         # 현재 탭 닫기
agent-browser tab close t3                      # t3 탭 닫기
```

> **`open URL --new-tab` 사용 금지!** 기존 탭을 덮어쓴다.
> 새 탭은 가능하면 `tab new --label <name> "URL"` 사용.

탭 목록 출력 예:
```
  t1  Daum - https://www.daum.net/
  t2  NAVER - https://www.naver.com/
```

> `→` 표시는 agent-browser 내부 포커스. Chrome UI 포커스가 아님.
> agent-browser 0.27.0+에서는 `tabId`(`t1` 등) 또는 label로 전환한다.
> `tab list`는 하드 게이트다. 단, 사용자가 URL/base_url/접속 주소를 명시한 경우에는 **먼저 같은 origin 탭을 찾아 재사용**하고, 없을 때만 `tab new --label <name> "URL"`로 새 탭을 만든다(title+href 검증 후 진행). 동일 origin 탭이 여러 개면 멈추고 사용자에게 확인한다. (탭-선택-패턴.md "동일 origin 탭 재사용 우선")
> 반복/시간차 실행(suite 루프, QA 재현)은 CDP `targetId` 고정(`E2E_TAB_ID`)을 쓴다. (탭-선택-패턴.md)
> URL도 작업 탭도 확정되지 않았으면 `open`, `tab`, `click`, `fill`, `press`, `eval` 실행 금지.
> Google 로그인, OAuth, 관리자 콘솔, 결제, 기존 세션 유지 작업은 새 탭 생성과 상태 확인까지만 자율 수행하고 실제 조작은 사용자 실행 승인 후 진행한다.

## 페이지 이동

```bash
agent-browser tab new "https://URL" # 새 탭 생성 + 이동 (URL 지정 시 기본)
agent-browser open "https://URL"    # 이미 확정된 현재 탭에서 이동할 때만
```

## JavaScript 실행 (핵심 조작)

```bash
# 값 읽기
agent-browser eval "document.title"
agent-browser eval "document.querySelector('#id').value"
agent-browser eval "document.querySelectorAll('tr').length"

# 조건부 읽기
agent-browser eval "document.querySelector('.cls') ? document.querySelector('.cls').innerText.trim() : '없음'"

# 목록 추출 (JSON.stringify 패턴)
agent-browser eval "JSON.stringify(Array.from(document.querySelectorAll('li')).map(function(el){return el.innerText}))"

# 클릭
agent-browser eval "document.querySelector('a.link').click()"

# 값 입력
agent-browser eval "document.querySelector('#input').value = '값'"

# 이벤트 발생 (Vue/React 반응형)
agent-browser eval "document.querySelector('#input').dispatchEvent(new Event('input', {bubbles:true}))"
```

> **단순 표현식만.** IIFE `(function(){...})()` 사용 금지 -- 직렬화 오류.

## iframe

```bash
agent-browser frame "#same-frame"
agent-browser snapshot -i -c
agent-browser fill @e1 "값"
agent-browser click @e2
agent-browser frame main
```

검증 기준:

- same-origin iframe은 `frame` 후 snapshot ref 기반 `fill/click`이 가능하다.
- `frame` 후 `eval`은 부모 document 기준으로 실행될 수 있으므로 iframe 내부 검증에는 신뢰하지 않는다.
- CSS selector 직접 조작(`click "#button"`)도 실패할 수 있어 snapshot ref를 우선한다.
- nested iframe, cross-origin iframe, 내부 ref 미노출은 Playwright fallback으로 전환한다.
> 여러 동작은 각각 별도 eval로 분리.

### eval 출력 특성

- **결과값만 반환** (playwright-cli와 달리 부가 정보 없음)
- 문자열: `"값"` (따옴표 포함)
- 숫자: `89`
- undefined: `✓ Done` 표시
- 에러: `✗ 에러 메시지`

## 스냅샷 (부득이할 때만)

```bash
# 인터랙티브 요소만 + 컴팩트 (필수 옵션)
agent-browser snapshot -i -c

# CSS 범위 제한 (더 절약)
agent-browser snapshot -i -c -s "table"

# DOM 깊이 제한
agent-browser snapshot -i -c -d 3
```

| 옵션 | 설명 |
|------|------|
| `-i` | 인터랙티브 요소만 (버튼, 링크, 입력창) |
| `-c` | 컴팩트 출력 |
| `-d N` | DOM 깊이 제한 |
| `-s "selector"` | CSS 범위 제한 |

> **전체 snapshot 금지.** 토큰 비교:
> - 전체: ~65,700 토큰
> - `-i -c`: ~9,800 토큰
> - eval: ~1~460 토큰

## ref 기반 요소 조작

snapshot 후 ref로 조작:

```bash
agent-browser click e10             # 클릭
agent-browser fill e37 "텍스트"      # 입력
agent-browser press Enter           # 키보드
agent-browser hover e5              # 호버
agent-browser focus e12             # 포커스
agent-browser select e20 "옵션"      # 드롭다운 선택
agent-browser check e15             # 체크박스 체크
agent-browser uncheck e15           # 체크박스 해제
```

> ref는 DOM 변경 시 무효. 클릭/이동 후 반드시 다시 snapshot.

## 스크린샷

```bash
agent-browser screenshot            # 터미널 출력
agent-browser screenshot result.png # 파일 저장 (토큰 미소비)
```

## 대기

```bash
agent-browser wait 2000             # 2초 대기
agent-browser wait ".selector"      # 요소 등장 대기
```

## 스크롤

```bash
agent-browser scroll down           # 아래로
agent-browser scroll up             # 위로
agent-browser scroll down 500       # 500px 아래로
agent-browser scrollintoview ".el"  # 요소 위치로 스크롤
```

## 텍스트 추출

```bash
agent-browser get text e1           # ref의 텍스트
```

## 요소 탐색 (snapshot 없이)

```bash
agent-browser find role button --name "Submit"
agent-browser find role link --name "자세히"
```

> snapshot 없이 특정 역할/이름의 요소를 직접 탐색. ref도 반환됨.

## SPA 대기

```bash
agent-browser wait --load networkidle     # 네트워크 안정 대기
agent-browser wait ".target-element"      # 요소 등장 대기
```

> SPA(React/Vue)에서 `document.readyState === 'complete'`는 hydration 미보장.
> `wait --load networkidle` 또는 특정 요소 대기가 안전.

## 시각적 피드백

```bash
# 요소 하이라이트 (Chrome에서 시각적으로 표시)
agent-browser highlight ".selector"
agent-browser highlight e5

# 세션 녹화
agent-browser record start ./session.webm
# ... 작업 수행 ...
agent-browser record stop

# 트레이스 (디버깅용)
agent-browser trace start
# ... 작업 수행 ...
agent-browser trace stop ./trace.zip

# 스냅샷/스크린샷 변경 비교
agent-browser diff snapshot
agent-browser diff screenshot --baseline
```

> ref 하이라이트는 `@e5`가 아니라 `e5` 형식을 사용한다.
> `agent-browser highlight @e5`는 CSS selector로 해석되어 실패할 수 있다.

> `record start ./파일명`을 줘도 일부 환경에서는 요청 경로가 아닌 기본 저장 폴더에 기록될 수 있다.
> `record stop` 출력 경로를 먼저 확인하고, 필요하면 `find ~ -maxdepth 4 -name "파일명"`으로 실제 위치를 찾는다.

## 한계

- iframe은 `agent-browser frame <selector>`를 먼저 시도한다.
- same-origin iframe은 snapshot ref 기반 `fill/click`까지 가능했다.
- `frame` 후 `eval`과 CSS selector 직접 조작은 부모 document 기준으로 실행될 수 있다.
- nested/cross-origin iframe, 내부 ref 미노출, 파일 업로드/네이티브 다이얼로그 조합은 Playwright `frameLocator`/`page.frames()` fallback으로 전환한다.
- same-origin quick check만 `./e2e/tools/pwc.sh eval`을 사용할 수 있다.

## 주의사항

- `connect ${E2E_CDP_PORT:-9333}` 없이 명령하면 **headless 새 브라우저가 열림** (보이지 않음!)
- `open URL --new-tab`은 **기존 탭을 덮어씀** → `tab new URL` 사용
- `→` 표시는 Chrome UI 포커스가 아닌 agent-browser 내부 상태
- eval IIFE 금지 -- 단순 표현식만
