# iframe 모달 패턴

iframe 구조의 모달을 처리하는 패턴. 기본값은 Playwright `frameLocator` 또는 `page.frames()`다.
same-origin 단순 확인은 `./e2e/tools/pwc.sh eval`로 볼 수 있지만, nested/cross-origin iframe은 시나리오/helper 코드에서 Playwright 프레임 API로 처리한다.

> **주의: playwright-cli eval은 단순 표현식만 지원. IIFE 사용 금지.**
> 여러 동작은 각각 별도 eval로 분리해서 실행한다.

## 구조

```html
<!-- jQuery UI Dialog가 생성하는 DOM -->
<div class="ui-dialog">
  <div class="ui-dialog-titlebar">제목</div>
  <iframe id="ui-id-1" class="ui-dialog-content" src="/path/to/content"></iframe>
</div>
<div class="ui-widget-overlay"></div>
```

## Playwright: iframe 내부 요소 접근

### same-origin quick check

```bash
# same-origin iframe 내부 텍스트 읽기
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=target]').contentDocument.querySelector('#list').innerText.substring(0,300)"

# 모든 iframe 확인
./e2e/tools/pwc.sh eval "JSON.stringify(Array.from(document.querySelectorAll('iframe')).map(f => f.id + ': ' + f.src))"
```

> `contentDocument` 방식은 same-origin에서만 유효하다. cross-origin iframe은 브라우저 보안 정책으로 막힐 수 있으므로 `pwc.sh eval`이 아니라 시나리오 코드에서 `page.frameLocator()` 또는 `page.frames()`를 사용한다.

### nested/cross-origin fallback

```js
// 시나리오/helper 코드에서 사용
const frame = page.frameLocator('iframe[src*=target]');
await frame.locator('#keyword').fill('검색어');
await frame.locator('input[type=submit]').click();

// 동적 iframe은 page.frames()로 URL 패턴을 폴링
const popupFrame = page.frames().find((f) => f.url().includes('/target'));
await popupFrame.locator('#keyword').fill('검색어');
```

### 입력 + 클릭 (별도 eval로 분리)

```bash
# same-origin quick check 1. 검색어 입력
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=target]').contentDocument.querySelector('#keyword').value = '검색어'"

# same-origin quick check 2. 검색 실행
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=target]').contentDocument.querySelector('input[type=submit]').click()"
```

### 검색 결과 확인 후 클릭

```bash
# 결과 텍스트 확인
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=target]').contentDocument.querySelector('#list').innerText.substring(0,300)"

# 특정 행의 링크 클릭 (첫 번째 행)
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=target]').contentDocument.querySelector('#list tr a').click()"
```

## iframe ID 동적 변경 문제

jQuery UI Dialog는 모달을 열 때마다 iframe ID가 증가한다 (ui-id-1, ui-id-2, ui-id-4, ...).
정확한 iframe을 찾으려면 src로 검색한다:

```bash
# src에 특정 경로가 포함된 iframe 찾기
./e2e/tools/pwc.sh eval "document.querySelector('iframe[src*=customer/list]') ? document.querySelector('iframe[src*=customer/list]').id : '미발견'"
```

## 오버레이가 클릭을 막는 경우

이전 모달의 `.ui-widget-overlay`가 남아있으면 버튼 클릭이 차단된다.
중요한 조작 전에 잔여 오버레이를 제거한다:

```bash
# 오버레이 제거
./e2e/tools/pwc.sh eval "document.querySelectorAll('.ui-widget-overlay').forEach(el => el.remove())"

# 모달 숨기기
./e2e/tools/pwc.sh eval "document.querySelectorAll('.ui-dialog').forEach(el => el.style.display = 'none')"
```

## 모달 닫기

```bash
# jQuery UI Dialog 강제 닫기 -- 별도 eval로 분리
./e2e/tools/pwc.sh eval "document.querySelectorAll('.ui-dialog').forEach(d => d.style.display = 'none')"
./e2e/tools/pwc.sh eval "document.querySelectorAll('.ui-widget-overlay').forEach(o => o.remove())"
```

## window.open 새창과의 구분

- **jQuery UI Dialog + iframe**: 페이지 내 오버레이 모달 → eval 단순 표현식으로 접근
- **window.open 새창**: 별도 브라우저 탭/창 → playwright-cli에서는 tab-list로 확인

구분이 불확실하면:
1. `./e2e/tools/pwc.sh eval "document.querySelectorAll('iframe').length"` -- iframe이 있으면 모달
2. `./e2e/tools/pwc.sh tab-list` -- 새 탭이 생겼으면 window.open
