#!/bin/bash
# e2e — E2E 테스트 통합 CLI
#
# HARNESS_E2E_VERSION: e2e 인프라(e2e.sh + lib/connect.js + lib/run-scenario.js) 계약 버전.
# peach-e2e-browse 셋업 절차(references/셋업-배포.md)가 배포하는 인프라가 의미 있게 바뀔 때만 올린다(connect.js의 같은 상수와 함께 갱신).
# scenario/suite 실행 게이트가 이 값을 읽어 기대 버전보다 낮으면 실행을 멈추고 셋업 절차로 갱신한다.
HARNESS_E2E_VERSION="1.2.9"
#
# 사용법: ./e2e.sh <command> [args]
#
# Commands:
#   setup               환경 체크 + 자동 설치/설정 (처음 실행 시 먼저 실행)
#   chrome              Chrome Beta CDP 모드 실행
#   list                시나리오 목록 출력
#   run [N|all|파일명]   시나리오 실행
#   record [URL]        Playwright codegen 녹화
#   test                인프라 순수 로직 테스트 (Chrome 불필요)
#   status              CDP 연결 상태 확인
#   help                도움말
#
# 탭 선택:
#   사용자가 로그인한 탭을 그대로 사용.
#   selector TUI 또는 E2E_TAB_ID로 탭 지정. --tab N은 하위 호환 편의 입력.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CDP_PORT="${E2E_CDP_PORT:-9333}"
CDP_URL="http://127.0.0.1:${CDP_PORT}"
SCENARIOS_DIR="${SCRIPT_DIR}/시나리오"
STATE_FILE="${SCRIPT_DIR}/.e2e-state.json"
SCENARIO_RUNNER="${SCRIPT_DIR}/lib/run-scenario.js"

# ─── OS 감지 ──────────────────────────────────────────────
case "$(uname -s)" in
  Darwin*)
    PLATFORM="macos"
    CHROME_BETA="/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta"
    CHROME_BETA_APP="Google Chrome Beta"
    PROFILE_DIR="${E2E_CHROME_PROFILE_DIR:-$HOME/.chrome-beta-e2e-profile}"
    PYTHON_CMD="python3"
    _chrome_installed() { [ -d "/Applications/Google Chrome Beta.app" ]; }
    _chrome_install_msg() {
      echo "📥 설치: https://www.google.com/chrome/beta/"
      echo "💡 기본 Chrome과 동시 실행 가능. E2E 전용으로 분리 사용."
    }
    ;;
  MINGW*|MSYS*)
    PLATFORM="windows"
    CHROME_BETA="/c/Program Files/Google/Chrome Beta/Application/chrome.exe"
    # Chrome은 Windows 네이티브 경로 필요 — cygpath로 변환
    if [ -n "${E2E_CHROME_PROFILE_DIR:-}" ]; then
      PROFILE_DIR="$(cygpath -w "$E2E_CHROME_PROFILE_DIR")"
    else
      PROFILE_DIR="$(cygpath -w "$HOME/.chrome-beta-e2e-profile")"
    fi
    PYTHON_CMD="python"
    _chrome_installed() { [ -f "$CHROME_BETA" ]; }
    _chrome_install_msg() {
      echo "📥 설치: https://www.google.com/chrome/beta/"
      echo "💡 기본 Chrome과 동시 실행 가능. E2E 전용으로 분리 사용."
    }
    ;;
  *)
    echo "❌ 지원하지 않는 OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# 전역 npm 모듈 경로 설정 (playwright-core 전역 설치 대응)
export NODE_PATH="${NODE_PATH:+${NODE_PATH}:}$(npm root -g 2>/dev/null || echo "")"

# ─── 공통 함수 ─────────────────────────────────────────────

check_cdp() {
  curl --max-time 3 -s "${CDP_URL}/json/version" > /dev/null 2>&1
}

running_browser_version() {
  curl --max-time 3 -s "${CDP_URL}/json/version" | $PYTHON_CMD -c "
import json, sys
try:
    print(json.load(sys.stdin).get('Browser', '').split('/')[-1])
except Exception:
    print('')
" 2>/dev/null
}

installed_browser_version() {
  "$CHROME_BETA" --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

check_browser_version() {
  local running installed
  running=$(running_browser_version)
  installed=$(installed_browser_version)
  [ -z "$running" ] || [ -z "$installed" ] || [ "$running" = "$installed" ]
}

run_scenario() {
  local filepath="$1"
  if [ ! -f "$SCENARIO_RUNNER" ]; then
    echo "❌ 시나리오 실행기를 찾을 수 없습니다: ${SCENARIO_RUNNER}"
    return 1
  fi
  if [[ "$filepath" != /* ]]; then
    filepath="$(cd "$(dirname "$filepath")" && pwd)/$(basename "$filepath")"
  fi
  node "$SCENARIO_RUNNER" "$filepath"
}

require_cdp() {
  if ! check_cdp; then
    echo "❌ Chrome Beta CDP가 연결되지 않았습니다."
    echo "   실행: ./e2e.sh chrome"
    exit 1
  fi
  if ! check_browser_version; then
    echo "❌ Chrome Beta 실행본과 설치본 버전이 다릅니다."
    echo "   실행본: $(running_browser_version) / 설치본: $(installed_browser_version)"
    echo "   탭 세션에 영향이 있으므로 사용자 승인 후 Chrome Beta를 재시작하세요."
    exit 1
  fi
}

# CDP /json에서 비-chrome 페이지 탭 목록 (status/--tab 공통 기준)
# 출력: JSON 배열 [{url, title}, ...]
get_page_tabs() {
  curl -s "${CDP_URL}/json" | $PYTHON_CMD -c "
import json, sys
tabs = json.load(sys.stdin)
pages = [t for t in tabs if t.get('type') == 'page' and not t.get('url', '').startswith('chrome')]
for t in pages:
    print(json.dumps({'url': t.get('url',''), 'title': t.get('title','')}, ensure_ascii=False))
" 2>/dev/null || true
}

# --tab N → CDP 조회 후 해당 탭의 targetId를 E2E_TAB_ID로 설정 (하위 호환 편의 입력)
resolve_tab_index() {
  local tab_index="$1"
  local result
  result=$(curl -s "${CDP_URL}/json" | $PYTHON_CMD -c "
import json, sys
tabs = json.load(sys.stdin)
pages = [t for t in tabs if t.get('type') == 'page' and not t.get('url', '').startswith('chrome')]
idx = int(sys.argv[1])
if 0 <= idx < len(pages):
    t = pages[idx]
    print(t.get('id', ''))
    print(t.get('title', '') or t.get('url', ''))
else:
    print('')
" "$tab_index" 2>/dev/null || echo "")

  local tab_id tab_title
  tab_id=$(echo "$result" | head -1)
  tab_title=$(echo "$result" | tail -1)

  if [ -z "$tab_id" ]; then
    echo "❌ ${tab_index}번 탭이 없습니다."
    echo "   ./e2e.sh status 로 탭 목록을 확인하세요."
    exit 1
  fi

  export E2E_TAB_ID="$tab_id"
  echo "🎯 ${tab_index}번 탭: ${tab_title}"
}

# 시나리오 목록 수집
collect_scenarios() {
  find "$SCENARIOS_DIR" -name "*.js" -type f 2>/dev/null | sort
}

print_scenarios() {
  local i=1
  while IFS= read -r file; do
    local rel="${file#$SCENARIOS_DIR/}"
    echo "  ${i}) ${rel}"
    i=$((i + 1))
  done <<< "$(collect_scenarios)"
}

get_scenario_by_number() {
  local num=$1
  collect_scenarios | sed -n "${num}p"
}

get_scenario_count() {
  collect_scenarios | wc -l | tr -d ' '
}

# ─── chrome: Chrome Beta CDP 실행 ──────────────────────────

cmd_chrome() {
  if check_cdp; then
    if ! check_browser_version; then
      echo "❌ Chrome CDP는 응답하지만 실행본과 설치본 버전이 다릅니다."
      echo "   실행본: $(running_browser_version) / 설치본: $(installed_browser_version)"
      echo "   사용자 승인 후 기존 Chrome Beta를 종료하고 이 명령을 다시 실행하세요."
      return 1
    fi
    echo "✅ Chrome CDP가 이미 실행 중입니다 (포트: ${CDP_PORT})"
    curl -s "${CDP_URL}/json/version" | grep -o '"Browser"[^,]*' | head -1 || true
    return 0
  fi

  if ! _chrome_installed; then
    echo "❌ Chrome Beta가 설치되어 있지 않습니다."
    echo ""
    _chrome_install_msg
    return 1
  fi

  echo "🚀 Chrome Beta CDP 모드 실행..."
  echo "   포트: ${CDP_PORT}"
  echo "   프로파일: ${PROFILE_DIR}"
  echo "   규칙: 고정 프로필(--user-data-dir) 필수"

  # --disable-extensions: 확장 프로그램이 웹 콘텐츠에 다크모드를 강제 적용하는 문제 방지
  # 아래 4개: 백그라운드 탭 렌더러가 freeze되면 connectOverCDP의 자동 attach가 그 탭에서
  # 무응답에 빠져 전체 attach가 hang한다. freeze 자체를 막는 예방책이며, 이미 얼어버린 탭은
  # tools/pwt.js --fix 로 복구한다.
  # 실측: 2026-08-16 Chrome Beta 151, page 타깃 7개 중 6개 무응답 / 2026-08-17 Chrome Beta
  # 152.0.7977.42, 이 플래그 없이 기동된 인스턴스에서 page 타깃 10개 중 5개 freeze.
  if [ "${PLATFORM}" = "macos" ]; then
    /usr/bin/open -na "${CHROME_BETA_APP}" --args \
      --remote-debugging-port=${CDP_PORT} \
      "--remote-allow-origins=*" \
      "--user-data-dir=${PROFILE_DIR}" \
      --disable-extensions \
      --no-first-run \
      --no-default-browser-check \
      --disable-renderer-backgrounding \
      --disable-background-timer-throttling \
      --disable-backgrounding-occluded-windows \
      --disable-features=CalculateNativeWinOcclusion
  else
    "$CHROME_BETA" \
      --remote-debugging-port=${CDP_PORT} \
      "--remote-allow-origins=*" \
      --user-data-dir="${PROFILE_DIR}" \
      --disable-extensions \
      --disable-renderer-backgrounding \
      --disable-background-timer-throttling \
      --disable-backgrounding-occluded-windows \
      --disable-features=CalculateNativeWinOcclusion &
  fi

  echo "⏳ CDP 연결 대기..."
  for i in $(seq 1 20); do
    if check_cdp; then
      echo "✅ Chrome Beta CDP 연결 성공!"
      echo ""
      echo "💡 Chrome Beta 고정 프로필에서 로그인/필요한 인증을 완료한 뒤 시나리오를 실행하세요:"
      echo "   인증은 사용자가 직접 처리하고, AI는 완료된 세션을 이어받습니다."
      echo "   직접 Chrome을 실행할 때도 --user-data-dir=${PROFILE_DIR} 옵션을 생략하지 마세요."
      echo "   ./e2e.sh run"
      return 0
    fi
    sleep 0.5
  done

  echo "❌ CDP 연결 실패."
  return 1
}

# ─── reset-state: suite state 파일 초기화 ───────────────────
# suite 실행 전 이전 실행의 state 잔류(PK 오염)를 제거한다. suite md "실행 계약"이 호출한다.

cmd_reset_state() {
  local files
  files=$(ls "${SCRIPT_DIR}/.tmp/"e2e_*_state.json 2>/dev/null || true)
  if [ -z "$files" ]; then
    echo "✅ 초기화할 state 파일 없음 (e2e/.tmp/e2e_*_state.json)"
    return 0
  fi
  echo "$files" | while read -r f; do
    rm -f "$f"
    echo "🗑  삭제: ${f#"${SCRIPT_DIR}/"}"
  done
  echo "✅ state 초기화 완료"
}

# ─── status: CDP 상태 확인 ──────────────────────────────────

cmd_status() {
  # 인프라 계약 버전을 기계가 읽기 쉬운 형식으로 먼저 출력한다(suite/scenario 버전 게이트가 파싱).
  echo "E2E_INFRA_VERSION=${HARNESS_E2E_VERSION:-unknown}"
  echo "E2E_CDP_PORT=${CDP_PORT}"
  echo "E2E_SCENARIO_TIMEOUT_SEC=${E2E_SCENARIO_TIMEOUT_SEC:-300}"
  if check_cdp; then
    local running_version installed_version browser_state
    running_version=$(running_browser_version)
    installed_version=$(installed_browser_version)
    browser_state="ready"
    if [ -n "$running_version" ] && [ -n "$installed_version" ] && [ "$running_version" != "$installed_version" ]; then
      browser_state="stale"
    elif [ -z "$running_version" ] || [ -z "$installed_version" ]; then
      browser_state="unverified"
    fi
    # 실행 인스턴스에 freeze 방지 플래그 4종이 붙어 있는지. 빠진 채 기동된 Chrome 은
    # 백그라운드 탭 렌더러가 freeze 되어 attach hang 이 재발한다(2026-08-19 실측).
    local flags_state="unknown" missing_flags="" chrome_cmd f
    # 헬퍼 프로세스(--type=renderer 등)도 이 포트 인자를 갖지만 기동 플래그는 없다.
    # --type= 이 없는 것이 브라우저 메인 프로세스다.
    chrome_cmd=$(ps -axo command= 2>/dev/null | grep -e "remote-debugging-port=${CDP_PORT}" | grep -v grep | grep -v -e '--type=' | head -1)
    if [ -n "$chrome_cmd" ]; then
      flags_state="ok"
      for f in --disable-renderer-backgrounding --disable-background-timer-throttling \
               --disable-backgrounding-occluded-windows --disable-features=CalculateNativeWinOcclusion; do
        case "$chrome_cmd" in
          *"$f"*) ;;
          *) flags_state="missing"; missing_flags="$missing_flags $f" ;;
        esac
      done
    fi
    echo "E2E_CDP_HTTP_STATUS=ok"
    echo "E2E_PLAYWRIGHT_STATUS=unchecked"
    echo "E2E_BROWSER_STATE=${browser_state}"
    echo "E2E_BROWSER_RUNNING_VERSION=${running_version:-unknown}"
    echo "E2E_BROWSER_INSTALLED_VERSION=${installed_version:-unknown}"
    echo "E2E_BROWSER_FLAGS=${flags_state}"
    if [ "$flags_state" = "missing" ]; then
      echo "❌ 실행 중 Chrome Beta 에 freeze 방지 플래그가 없습니다:${missing_flags}"
      echo "   attach hang 재발 위험 — 사용자 승인 후 ./e2e.sh chrome 으로 재시작하세요."
    fi
    if [ "$browser_state" = "stale" ]; then
      echo "❌ Chrome Beta 실행본과 설치본 버전이 다릅니다. 사용자 승인 후 재시작이 필요합니다."
    else
      echo "✅ Chrome CDP HTTP 응답 정상 (포트: ${CDP_PORT}, Playwright attach는 실제 조작 시 검증)"
    fi
    curl -s "${CDP_URL}/json/version" | grep -o '"Browser"[^,]*' | head -1 || true
    echo ""
    echo "열린 탭:"
    curl -s "${CDP_URL}/json" | $PYTHON_CMD -c "
import json, sys
tabs = json.load(sys.stdin)
pages = [t for t in tabs if t.get('type') == 'page' and not t.get('url', '').startswith('chrome')]
for i, t in enumerate(pages):
    url = t.get('url', '')
    title = t.get('title', '') or url
    print(f'  [{i}] {title[:60]}')
    print(f'        {url[:80]}')
    if i >= 9: break
" || true
    [ "$browser_state" != "stale" ] && [ "$flags_state" != "missing" ]
  else
    echo "E2E_CDP_HTTP_STATUS=fail"
    echo "E2E_PLAYWRIGHT_STATUS=unchecked"
    echo "E2E_BROWSER_STATE=stopped"
    echo "❌ Chrome CDP 미연결"
    echo "   실행: ./e2e.sh chrome"
    return 1
  fi
}

# ─── list: 시나리오 목록 ────────────────────────────────────

cmd_list() {
  local count
  count=$(get_scenario_count)

  if [ "$count" -eq 0 ]; then
    echo "📭 시나리오가 없습니다."
    return 0
  fi

  echo "=== 시나리오 목록 (${count}개) ==="
  echo ""
  print_scenarios
}

# ─── Node.js 실시간 한글 검색 선택기 ──────────────────────

_node_selector_run() {
  local selector="${SCRIPT_DIR}/lib/selector.js"

  if [ ! -f "$selector" ]; then
    echo "❌ selector.js 를 찾을 수 없습니다: ${selector}"
    return 1
  fi

  # selector.js 실행 — stderr: TUI 화면, stdout: "TAB_ID=id\nSCENARIO=경로"
  local output
  output=$(node "$selector" "$SCENARIOS_DIR" "$STATE_FILE" </dev/tty) || true

  if [ -z "$output" ]; then
    return 0
  fi

  # 결과 파싱
  local tab_id scenario
  tab_id=$(echo "$output"  | grep '^TAB_ID='   | head -1 | cut -d= -f2-)
  scenario=$(echo "$output" | grep '^SCENARIO=' | head -1 | cut -d= -f2-)

  if [ -z "$scenario" ]; then
    return 0
  fi

  # 탭 ID 설정
  if [ -n "$tab_id" ]; then
    export E2E_TAB_ID="$tab_id"
  fi

  local filepath="${SCENARIOS_DIR}/${scenario}"
  echo ""
  echo "▶ 실행: ${scenario}"
  echo "────────────────────────────────"
  run_scenario "$filepath"
  echo "────────────────────────────────"
}

# ─── run: 시나리오 실행 ─────────────────────────────────────

cmd_run() {
  require_cdp

  # --tab 옵션 파싱
  local tab_index=""
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --tab)
        tab_index="$2"
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  # --tab N → CDP 조회 후 targetId로 변환
  if [ -n "$tab_index" ]; then
    echo "⚠️  --tab N은 인덱스라 반복/suite 실행 중 탭 순서가 바뀌면 대상이 흔들립니다. E2E_TAB_ID=<targetId> 사용을 권장합니다."
    resolve_tab_index "$tab_index"
  fi

  local arg="${args[0]:-}"

  # 인자 없으면 시나리오 선택
  if [ -z "$arg" ]; then
    case "$(uname -s)" in
      MINGW*|MSYS*)
        # Windows: TUI 미지원 — 목록 출력 + 사용법 안내
        cmd_list
        echo ""
        echo "💡 사용법: ./e2e.sh run <번호>     예) ./e2e.sh run 1"
        echo "         ./e2e.sh run all         전체 실행"
        echo "         ./e2e.sh run 1-3         범위 실행"
        return 0
        ;;
      *)
        _node_selector_run
        return $?
        ;;
    esac
  fi

  # all: 전체 순차 실행
  if [ "$arg" = "all" ]; then
    echo "🚀 전체 시나리오 순차 실행"
    echo ""
    local i=1
    while IFS= read -r file; do
      local rel="${file#$SCENARIOS_DIR/}"
      echo "▶ [${i}] ${rel}"
      echo "────────────────────────────────"
      run_scenario "$file"
      echo "────────────────────────────────"
      echo ""
      i=$((i + 1))
    done <<< "$(collect_scenarios)"
    echo "✅ 전체 실행 완료"
    return 0
  fi

  # 숫자: N번째 시나리오
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    local file
    file=$(get_scenario_by_number "$arg")
    if [ -z "$file" ]; then
      echo "❌ ${arg}번 시나리오가 없습니다."
      return 1
    fi
    local rel="${file#$SCENARIOS_DIR/}"
    echo "▶ 실행: ${rel}"
    echo "────────────────────────────────"
    run_scenario "$file"
    echo "────────────────────────────────"
    return $?
  fi

  # 범위: N-M
  if [[ "$arg" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    local start="${BASH_REMATCH[1]}"
    local end="${BASH_REMATCH[2]}"
    echo "🚀 시나리오 ${start}~${end} 순차 실행"
    echo ""
    for i in $(seq "$start" "$end"); do
      local file
      file=$(get_scenario_by_number "$i")
      if [ -n "$file" ]; then
        local rel="${file#$SCENARIOS_DIR/}"
        echo "▶ [${i}] ${rel}"
        echo "────────────────────────────────"
        run_scenario "$file"
        echo "────────────────────────────────"
        echo ""
      fi
    done
    echo "✅ 실행 완료"
    return 0
  fi

  # 파일 경로
  local filepath="$arg"
  if [ ! -f "$filepath" ]; then
    filepath="${SCENARIOS_DIR}/${arg}"
  fi
  if [ ! -f "$filepath" ]; then
    echo "❌ 시나리오를 찾을 수 없습니다: ${arg}"
    return 1
  fi

  local rel="${filepath#$SCENARIOS_DIR/}"
  echo "▶ 실행: ${rel}"
  echo "────────────────────────────────"
  local rc=0
  run_scenario "$filepath" || rc=$?
  echo "────────────────────────────────"
  if [ "$rc" -ne 0 ]; then
    # 실패 evidence는 connect.js가 e2e/.tmp/evidence/ 아래에 자동 저장한다(있으면 stderr에 경로 출력됨).
    echo "❌ 시나리오 실패 (exit=${rc}). 실패 evidence가 있으면 .tmp/evidence/ 아래에 저장됩니다."
  fi
  return $rc
}

# ─── setup: 환경 체크 + 자동 설치/설정 ────────────────────────

cmd_setup() {
  echo "🔧 E2E 환경 체크"
  echo "════════════════════════════════════════"
  local all_ok=true

  # 1. Chrome Beta 설치 여부
  if _chrome_installed; then
    echo "✅ Chrome Beta 설치됨"
  else
    echo "❌ Chrome Beta 미설치"
    _chrome_install_msg
    all_ok=false
  fi

  # 2. playwright-core 전역 설치 여부
  # playwright-core: API만 포함 (~2MB). 브라우저 바이너리 없음.
  # CDP 모드에서는 Chrome Beta를 직접 사용하므로 브라우저 포함된 playwright(~50MB+) 불필요.
  if node -e "require('playwright-core')" 2>/dev/null; then
    local pw_ver
    pw_ver=$(node -e "console.log(require('playwright-core/package.json').version)" 2>/dev/null || echo '?')
    echo "✅ playwright-core 설치됨 (${pw_ver})"
  else
    echo "⚙️  playwright-core 전역 설치 중..."
    if npm install -g playwright-core; then
      echo "✅ playwright-core 설치 완료"
    else
      echo "❌ playwright-core 설치 실패"
      echo "   수동 실행: npm install -g playwright-core"
      all_ok=false
    fi
  fi

  # 3. agent-browser 전역 설치 여부 (탐색/검증/확인용 기본 도구)
  if command -v agent-browser &> /dev/null; then
    echo "✅ agent-browser 설치됨 ($(agent-browser --version 2>/dev/null || echo '버전 확인 불가'))"
  else
    echo "⚙️  agent-browser 설치 중..."
    if npm install -g agent-browser; then
      echo "✅ agent-browser 설치 완료"
    else
      echo "❌ agent-browser 설치 실패"
      echo "   수동 실행: npm install -g agent-browser"
      all_ok=false
    fi
  fi

  # 4. playwright-cli 전역 설치 여부 (시나리오 실행 + iframe fallback용)
  if command -v playwright-cli &> /dev/null; then
    echo "✅ playwright-cli 설치됨 ($(playwright-cli --version 2>/dev/null || echo '버전 확인 불가'))"
  else
    echo "⚙️  playwright-cli 설치 중..."
    if npm install -g @playwright/cli; then
      echo "✅ playwright-cli 설치 완료"
    else
      echo "❌ playwright-cli 설치 실패"
      echo "   수동 실행: npm install -g @playwright/cli"
      all_ok=false
    fi
  fi

  # 5. ~/.playwright/cli.config.json 설정 파일 존재 여부
  local CONFIG_FILE="$HOME/.playwright/cli.config.json"
  if [ -f "$CONFIG_FILE" ] && grep -q "\"cdpEndpoint\": \"${CDP_URL}\"" "$CONFIG_FILE"; then
    echo "✅ playwright-cli 설정 파일 존재 (${CONFIG_FILE})"
  else
    echo "⚙️  playwright-cli 설정 파일 생성/갱신 중..."
    mkdir -p "$HOME/.playwright"
    cat > "$CONFIG_FILE" << PCONFIG
{
  "browser": {
    "cdpEndpoint": "${CDP_URL}",
    "isolated": false
  }
}
PCONFIG
    echo "✅ 설정 파일 생성됨: ${CONFIG_FILE}"
    echo "   (cdpEndpoint: ${CDP_URL}, isolated: false)"
  fi

  # 5. CDP 연결 상태
  echo "────────────────────────────────────────"
  if check_cdp; then
    echo "✅ Chrome CDP 연결됨 (포트: ${CDP_PORT})"
  else
    echo "⚠️  Chrome CDP 미연결"
    echo "   실행: ./e2e.sh chrome  →  브라우저 로그인 후 E2E 사용 가능"
    all_ok=false
  fi

  echo "════════════════════════════════════════"
  if $all_ok; then
    echo "✨ 환경 설정 완료! E2E를 시작할 수 있습니다."
    echo "   탭 확인:  ./e2e.sh status"
    echo "   탐색:     agent-browser connect ${CDP_PORT} && agent-browser eval \"document.title\""
    echo "   시나리오:  ./e2e.sh run"
  else
    echo "⚠️  위 항목을 해결한 후 다시 ./e2e.sh setup 을 실행하세요."
  fi
}

# ─── record: Playwright codegen 녹화 ───────────────────────

# 인프라 순수 로직 회귀 테스트 (Chrome 불필요). 상단에서 export한 NODE_PATH를 그대로 쓴다.
cmd_test() {
  echo "🧪 e2e 인프라 테스트 (Chrome 불필요)"
  node --test "${SCRIPT_DIR}"/lib/*.test.js
}

cmd_record() {
  local url="${1:-}"

  echo "🎬 Playwright 녹화 시작"
  echo ""
  echo "   새 브라우저 창이 열립니다."
  echo "   브라우저에서 조작하면 코드가 자동 생성됩니다."
  echo "   녹화 창을 닫으면 종료됩니다."
  echo ""
  echo "💡 녹화 완료 후:"
  echo "   1. 생성된 코드를 복사"
  echo "   2. Claude Code에서 /peach-e2e-scenario create 스킬에 전달"
  echo "   3. CDP 시나리오 파일로 자동 변환"
  echo ""

  cd "$SCRIPT_DIR"

  if [ -n "$url" ]; then
    npx playwright codegen --target javascript --color-scheme light "$url"
  else
    npx playwright codegen --target javascript --color-scheme light
  fi
}

# ─── help: 도움말 ──────────────────────────────────────────

cmd_help() {
  cat << 'EOF'
e2e — E2E 테스트 통합 CLI

사용법: ./e2e.sh <command> [args]

Commands:
  setup                              환경 체크 + 자동 설치/설정 (처음 실행 시 먼저 실행)
  chrome                             Chrome Beta CDP 모드 실행
  status                             CDP 연결 상태 + 열린 탭 확인
  list                               시나리오 목록 출력
  run                                한글 실시간 검색 선택 UI (탭 선택 → 시나리오 선택)
  run <시나리오>                      시나리오 직접 실행 (E2E_TAB_ID 권장)
  run all                            전체 시나리오 순차 실행 (E2E_TAB_ID 권장)
  run <N-M>                          N~M번 범위 순차 실행 (E2E_TAB_ID 권장)
  run [--tab N] <시나리오>            하위 호환 편의 입력: 즉시 E2E_TAB_ID로 변환
  reset-state                        suite state 파일 초기화 (e2e/.tmp/e2e_*_state.json)
  record [URL]                       Playwright codegen 녹화
  test                               인프라 순수 로직 테스트 (Chrome 불필요)
  help                               이 도움말

탭 선택:
  사용자가 로그인한 탭을 그대로 사용합니다.
  E2E_TAB_ID  CDP targetId로 탭 고정 (권장)
  --tab N     status에서 확인한 N번 탭을 즉시 E2E_TAB_ID로 변환 (하위 호환)
  미지정    selector TUI에서 탭 선택 또는 자동 탐지

워크플로우:
  0. ./e2e.sh setup                      최초 환경 구성
  1. ./e2e.sh chrome                     Chrome Beta CDP 실행
  2. 브라우저에서 로그인                  (사람이 1회)
  3. ./e2e.sh status                     targetId 확인
  4. E2E_TAB_ID=<targetId> ./e2e.sh run  TUI에서 시나리오 선택 실행
  또는
  4. ./e2e.sh run --tab 1 1              1번 탭에서 1번 시나리오 실행
  또는
  3. ./e2e.sh record [URL]               녹화 → /peach-e2e-scenario create로 변환

playwright-cli CDP 래퍼:
  ./e2e/tools/pwc.sh <command>   playwright-cli --config=~/.playwright/cli.config.json 래퍼
  예: ./e2e/tools/pwc.sh snapshot
      ./e2e/tools/pwc.sh click e10
      ./e2e/tools/pwc.sh eval "document.title"

Claude Code 스킬:
  /peach-e2e-browse       AI가 현재 탭 탐색/디버깅
  /peach-e2e-scenario     단위 시나리오·통합 suite 생성/실행/자동수정
EOF
}

# ─── 메인 ──────────────────────────────────────────────────

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
  setup)    cmd_setup "$@" ;;
  chrome)   cmd_chrome "$@" ;;
  status)   cmd_status "$@" ;;
  list)     cmd_list "$@" ;;
  run)      cmd_run "$@" ;;
  reset-state) cmd_reset_state "$@" ;;
  record)   cmd_record "$@" ;;
  test)     cmd_test "$@" ;;
  help|-h|--help) cmd_help ;;
  *)
    echo "❌ 알 수 없는 명령: ${COMMAND}"
    echo "   ./e2e.sh help 로 사용법을 확인하세요."
    exit 1
    ;;
esac
