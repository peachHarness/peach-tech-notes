#!/usr/bin/env bash
# 프로젝트 에이전트 스킬 관리 — 원본 저장소와의 양방향 동기화.
#
# 파일명 주의: 스킬 설치 CLI(`skills` / `npx skills`)와 헷갈리지 않게 peach- 접두어를 붙였다.
#
# ── 설치 토폴로지: .claude/skills/ 단일 원본 + .agents/skills/ 링크 ──────────
# 모든 스킬의 실체(본문)는 .claude/skills/<이름> 한 곳에만 둔다.
#   - `-a claude-code --copy` 로 설치해 .claude/skills/ 에 실체를 받는다.
#     (--copy 없이 설치하면 skills.sh 가 .agents/ 를 실체로 만들고 .claude/ 를 링크로
#      걸어 방향이 뒤집힌다. Claude Code 의 권위 경로가 .claude/skills/ 이므로 --copy 로
#      방향을 고정한다.)
#   - `-a codex` 는 쓰지 않는다. 대신 link 서브커맨드가 .agents/skills/<이름> →
#     ../../.claude/skills/<이름> 상대 심링크를 만들어 Codex 쪽에 노출한다.
# 실체가 한 곳뿐이라 두 하네스가 항상 같은 본문을 본다(갱신 시 불일치가 생기지 않는다).
#
# ── 스킬 개선 워크플로우: 프로젝트에서 고치고 원본으로 밀어낸다 ───────────────
# 스킬의 문제는 실제로 쓰는 현장에서만 드러나고, 고친 결과도 그 자리에서 바로 검증된다.
# 그래서 개선 작업 공간은 이 프로젝트의 .claude/skills/ 이며 git 으로 추적한다.
#   1) .claude/skills/<이름>/ 을 직접 수정하고 이 프로젝트에서 검증한다.
#   2) `diff` 로 원본 대비 변경분을 확인한다.
#   3) `push <이름>` 으로 원본 저장소의 현재 브랜치에 복사·stage 한다(새 브랜치를 만들지 않는다).
#   4) 원본 저장소에서 리뷰·커밋·릴리스한다(커밋·푸시는 이 스크립트가 하지 않는다).
# 중간 피드백 문서를 거치지 않으므로 맥락 손실과 재구축 비용이 없다.
#
# ── 사용법 ──────────────────────────────────────────────────────────────────
#   .claude/peach-skills.sh pull            버전 확인 후 갱신이 필요할 때만 설치한다.
#                                           .claude/skills/ 에 커밋 안 한 변경이 있으면 중단한다
#                                           (덮어쓰려면 PEACH_SKILLS_ALLOW_DIRTY=1).
#   .claude/peach-skills.sh pull --force    버전과 무관하게 무조건 재설치한다.
#   .claude/peach-skills.sh check           설치하지 않고 버전 비교 결과만 표시한다.
#   .claude/peach-skills.sh link            .agents/skills 심링크만 재생성한다(네트워크 불필요).
#   .claude/peach-skills.sh diff [스킬]     원본 저장소 대비 변경분을 표시한다.
#   .claude/peach-skills.sh push <스킬>     개선분을 원본 저장소의 현재 브랜치에 복사·stage 한다.
#
# 인자 없이 실행하면 pull 로 동작한다.
#
# ── 이 파일은 어떻게 여기 왔나 ──────────────────────────────────────────────
# 원본 저장소의 scripts/setup-project-skills.sh 가 설치했다. 새 프로젝트에 세팅할 때는
# 그 스크립트를 파이프로 한 번 실행하면 된다(private 저장소라 curl 이 아니라 gh 로 받는다).
#
#   gh api repos/peachHarness/peach-harness/contents/scripts/setup-project-skills.sh \
#     -H 'Accept: application/vnd.github.raw' | bash -s -- php
#
# ── 자기 자신과 hook 의 자동 갱신 ───────────────────────────────────────────
# pull 은 실행할 때마다 원본 최신 릴리스의 이 스크립트·hook 을 로컬 사본과 비교해, 다르면
# 먼저 갱신하고 새 본문으로 재실행한다. 그래서 사용자가 스크립트를 따로 업데이트할 일이 없고
# 세팅 스크립트를 다시 부를 일도 없다. 끄려면 PEACH_SKILLS_NO_SELF_UPDATE=1 을 준다.
#
# ── ★ 이 스크립트는 모든 프로젝트에서 완전히 동일하다 ───────────────────────
# 프로젝트별 설정(스킬 목록)은 이 파일이 아니라 .claude/peach-skills.state 에 있다.
# 그래서 이 파일은 어느 프로젝트에 두어도 한 글자도 다르지 않고, 스킬과 똑같이 원본에서
# 받아 뿌릴 수 있다. 프로젝트마다 조금씩 다른 사본이 갈라지던 문제가 구조적으로 사라진다.
#
# 고칠 일이 있으면 이 파일이 아니라 .state 를 고친다. 이 파일을 프로젝트에서 수정하면
# 다음 배포 때 덮여 없어진다.
#
# ── 설정 파일: .claude/peach-skills.state ───────────────────────────────────
# 사람이 편집하는 영역과 pull 이 기록하는 영역이 한 파일에 공존한다.
#
#   skill peach-wiki:peachHarness/peach-harness     ← 사람이 편집(유일한 스킬 목록)
#   installed peachHarness/peach-harness v2.0.1     ← pull 이 기록(설치된 릴리스 태그)
#
# pull 은 사용자 영역을 한 글자도 건드리지 않는다 — skill 줄·주석·직접 적은 메모가 모두
# 살아남는다. 자세한 규칙은 write_state() 주석 참고.
#
# 포맷이 txt 인 이유: 파싱·재작성이 grep/awk 만으로 되고(의존성 0), 주석을 쓸 수 있어
# 파일 자체가 사용설명서가 되며, git diff 가 "1줄 = 1스킬"로 읽힌다. JSON 은 주석을
# 지원하지 않아 이 안내를 담을 수 없고, YAML 은 bash 표준 파서가 없다.
#
# 버전 단위는 저장소(릴리스 태그)다. SKILL.md 에 버전 필드가 없어 스킬별 버전은 존재하지
# 않는다. 스킬 단위 변경 감지는 `diff` 가 원본과 직접 비교해서 한다.
#
# 버전 비교 기준: GitHub 릴리스 태그. 릴리스 태그가 오르지 않고 커밋만 바뀐 경우엔 "최신"으로
# 판단해 건너뛰므로, 그 최신 커밋을 강제로 받으려면 `pull --force` 를 쓴다.
#
# ── 원본 저장소 경로 ────────────────────────────────────────────────────────
# 하드코딩하지 않는다(다른 사람 머신에서 동작해야 한다). 아래 순서로 찾는다.
#   1) 환경변수 — 저장소명에서 기계적으로 도출한다(대문자 + '-'→'_' + '_PATH').
#      peach-harness → PEACH_HARNESS_PATH,  peach-harness-php → PEACH_HARNESS_PHP_PATH
#   2) ~/source/<owner>/<저장소이름> — .state 의 owner 까지 일치하는 정석 경로.
#      같은 이름의 사본·워크트리가 ~/source 아래 여럿 있어도 여기서 확정된다.
#   3) ~/source/*/<저장소이름> glob 탐색
# 둘 다 실패하면 안내 후 종료한다.
#
# ══ git 추적 정책 — .gitignore 에 반드시 반영할 항목 ═════════════════════════
#
# 이 스크립트가 만들고 관리하는 파일들의 추적 여부를 아래에 확정한다.
# 새 워크트리나 새 프로젝트에 이 구조를 이식할 때, 이 섹션만 보고 .gitignore 를 작성하면 된다.
#
# ┌─ 다른 프로젝트로 이식할 때: .gitignore 에 이 블록을 그대로 붙인다 ───────┐
# │                                                                        │
# │   # ── 에이전트 스킬 (근거: .claude/peach-skills.sh "git 추적 정책") ── │
# │   # .claude/skills/ 는 의도적으로 추적한다 — 워크트리 즉시 사용 +       │
# │   #   스킬 개선 diff 기준선. 아래 둘만 무시한다.                       │
# │   .agents/skills/                                                      │
# │   skills-lock.json                                                     │
# │                                                                        │
# └────────────────────────────────────────────────────────────────────────┘
#
# 위 두 줄이 전부다. `.claude/skills/` 를 무시하는 줄은 넣지 않는다(추적해야 하므로).
# 이식 시 이 스크립트는 손대지 않는다 — 프로젝트마다 갈리는 것은 `.state` 의 skill 줄뿐이다.
#
# ── 무시하는 것과 그 근거 ────────────────────────────────────────────────────
#
# (1) `.agents/skills/`  ← 무시
#     정체: .claude/skills/<이름> 을 가리키는 상대 심링크 모음(Codex 가 읽는 경로).
#     근거: 실체가 아니라 포인터다. 같은 내용을 두 번 커밋하는 셈이고, 심링크는 Windows
#           체크아웃에서 깨질 수 있다. 세션 시작 hook(.claude/hooks/skills-check.sh)이
#           없으면 자동 생성하므로 커밋해서 얻을 이득이 없다.
#     복구: 자동(hook) 또는 `peach-skills.sh link`.
#
#     ⚠ 범위 주의 — `.agents/` 로 넓히지 않는다. `skills/` 까지만 무시한다.
#       ㄱ. 무시는 아는 만큼만 건다. `.agents/` 는 에이전트 하네스 공용 네임스페이스라
#           앞으로 AGENTS.md·설정·커스텀 서브에이전트 정의처럼 **추적해야 할** 것이 들어올 수
#           있다. 통째로 막으면 그때 파일을 만들어도 git 이 조용히 무시하고 원인 찾기가 어렵다.
#           반면 `.agents/skills/` 는 정체(심링크)와 재생성 방법(hook)을 아는 대상이다.
#       ㄴ. 실수를 드러낸다 — 좁혀두면 누가 `.agents/` 에 다른 파일을 만들 때 git status 에
#           보이고, 추적할지 무시할지 그때 판단할 수 있다. 넓히면 그 판단 기회가 사라진다.
#       (오픈소스 orca 도 `.gitignore` 에 `/.agents/skills/` 로 똑같이 좁혀 적었다)
#
# (2) `skills-lock.json`  ← 무시
#     정체: `npx skills add` 가 프로젝트 루트에 남기는 설치 락파일(스킬별 소스·해시 기록).
#     근거: pull 할 때마다 재생성되는 파생물이다. 워크트리마다 내용이 갈려 머지 충돌만
#           유발하고, 이 스크립트는 버전 판단에 이 파일을 쓰지 않는다(릴리스 태그를 쓴다).
#     주의: 루트에 생기므로 `.claude/` 하위 규칙으로는 걸러지지 않는다. 루트 경로로 적는다.
#
# ── 추적하는 것과 그 근거 (.gitignore 에 넣지 않는다) ────────────────────────
#
# (3) `.claude/skills/`  ← 추적 ★ 이 구조의 핵심 결정
#     정체: 모든 스킬의 실체(본문). 유일한 원본.
#     근거 세 가지:
#       ㄱ. 워크트리 즉시 사용 — 워크트리를 새로 만들면 체크아웃 순간 스킬이 존재한다.
#           설치를 기다리지 않고, 네트워크도 `npx` 실행도 필요 없다. 이 구조를 도입한
#           출발점이 바로 "워크트리 생성 직후 스킬이 없어 작업이 막힌다"는 문제였다.
#       ㄴ. diff/push 의 기준선 — 이 프로젝트에서 스킬을 개선하고 원본 저장소로 밀어내는
#           워크플로우(위 "스킬 개선 워크플로우" 참고)가 성립하려면, "무엇이 바뀌었는지"를
#           판별할 기준이 필요하다. 추적하지 않으면 개선분과 원본을 구분할 수 없어
#           diff/push 서브커맨드 자체가 무의미해진다.
#       ㄷ. 재현성·감사성 — 스킬 본문은 에이전트 행동을 직접 좌우한다. 원본 릴리스가 바뀔 때
#           의도치 않게 따라 변하지 않고, 변경은 커밋으로 리뷰를 거치는 것이 안전하다.
#           (오픈소스 orca 도 같은 이유로 skills/*/SKILL.md 를 커밋한다)
#     비용: 텍스트 파일 수백 K 수준. 원본과 이 저장소 모두 private 이고 소유가 같아
#           라이선스·유출 문제가 없다.
#     대가: 원본 최신 릴리스와 자동으로 동기화되지 않는다. `pull` 로 받아 커밋해야 반영된다.
#           이는 위 ㄷ 항목이 의도한 바이며, 갱신 누락은 `check` 로 감지한다.
#
# (4) `.claude/peach-skills.state`  ← 추적 ★ 이제 설정 파일이다
#     정체: 이 프로젝트가 쓸 스킬 목록(사람이 편집) + 설치된 릴리스 태그(pull 이 기록).
#     근거: 스킬 목록은 프로젝트의 정체를 정하는 설정이라 반드시 추적해야 한다. 설치 태그는
#           파생물이지만, (3)의 본문이 "어느 릴리스에서 왔는지"를 남겨야 이력이 완결된다.
#           본문만 추적하고 출처를 버리면 추적이 반쪽이 된다.
#     주의: 스킬 목록이 이 파일에만 있으므로 잃으면 복구해야 한다. write_state() 가 임시파일
#           → mv 로 원자적 교체하고 사용자 영역을 보존하지만, 최후 수단은 git checkout 이다.
#     이름: `.log` 가 아니라 `.state` 다 — append 되는 이력이 아니라 현재 상태이기 때문이다.
#           접두어를 스크립트와 맞춰 소속을 드러냈다.
#
# (5) `.claude/peach-skills.sh`, `.claude/hooks/`, `.claude/settings.json`, `.codex/hooks.json`
#     ← 모두 추적. 이 구조를 재현하는 데 필요한 스크립트와 하네스 설정이다.
#
# ── 스킬을 새로 추가할 때 ────────────────────────────────────────────────────
# .claude/skills/ 전체를 추적하므로 예외 줄을 추가할 일이 없다. 아래만 하면 된다.
#   원본 저장소 유래 스킬 : `.state` 에 skill 줄 한 줄 추가 후 `pull`
#                           (설치 인자·저장소 목록·환경변수 이름이 모두 여기서 도출된다)
#   이 저장소에서 만든 스킬: .claude/skills/<이름>/ 생성 후 `peach-skills.sh link`.
#                           `.state` 에 적지 않으면 diff/push 대상에서 자동 제외된다.
# 어느 쪽이든 hook(.claude/hooks/skills-check.sh)은 고치지 않는다 — 링크는 글롭으로,
# 누락 판정은 git index 로 자동 판단하므로 스킬 목록을 담고 있지 않다.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

STATE=".claude/peach-skills.state"
SELF=".claude/peach-skills.sh"
HOOK=".claude/hooks/skills-check.sh"

# 이 스크립트와 hook 의 원본이 있는 저장소. 스킬 저장소는 $STATE 에서 도출하지만,
# 자기 자신을 어디서 받을지는 스스로 알아야 하므로 여기 한 곳에만 적는다.
HARNESS_REPO="peachHarness/peach-harness"

# ── 설정 읽기: 스킬 목록은 이 스크립트가 아니라 $STATE 에 있다 ────────────────
# 이 스크립트에는 프로젝트별 설정이 한 줄도 없다. 그래서 모든 프로젝트에서 파일이
# 완전히 동일하고, 스킬처럼 원본에서 받아 뿌릴 수 있다.
#
# $STATE 의 `skill <이름>:<owner>/<repo>` 줄이 유일한 스킬 목록이며,
# pull(설치 인자), check(저장소 목록), diff, push 가 전부 여기서 도출된다.

SKILLS=()   # "이름:owner/repo" 목록 — $STATE 의 skill 줄
REPOS=()    # "owner/repo" 목록 — SKILLS 에서 중복 제거로 도출
LATEST=()   # "owner/repo 태그" 목록 — check_versions 가 조회한 값(write_state 가 재사용)

# $STATE 를 읽어 SKILLS/REPOS 를 채운다. 파일이 없으면 둘 다 빈 배열로 남는다
# (require_state 가 안내하며, link 처럼 목록이 필요 없는 명령은 그대로 동작한다).
load_state() {
  SKILLS=(); REPOS=()
  [[ -f "$STATE" ]] || return 0

  local line repo
  while IFS= read -r line; do
    [[ -n "$line" ]] && SKILLS+=("$line")
  done < <(grep '^skill ' "$STATE" | awk '{print $2}')

  # 이 가드는 SKILLS 가 실제로 빌 수 있는 유일한 지점이다(state 없음 / link 명령).
  # bash 3.2 는 set -u 에서 빈 배열 확장을 unbound variable 로 죽인다(macOS 기본 셸).
  for line in ${SKILLS[@]+"${SKILLS[@]}"}; do
    repo="${line##*:}"
    case " ${REPOS[*]:-} " in
      *" ${repo} "*) ;;
      *) REPOS+=("$repo") ;;
    esac
  done
}

# 스킬 목록이 필요한 명령의 진입 가드. 없으면 만드는 방법을 안내하고 종료한다.
require_state() {
  if [[ ! -f "$STATE" ]]; then
    echo "오류: ${STATE} 가 없습니다 — 이 프로젝트가 쓸 스킬 목록이 정의되지 않았습니다."
    echo
    echo "아래처럼 만드세요(스킬 줄은 필요한 만큼 늘립니다):"
    echo
    echo "  # 이 프로젝트가 쓰는 스킬"
    echo "  skill peach-wiki:peachHarness/peach-harness"
    echo
    echo "그 뒤 '${SELF} pull' 을 실행하면 설치하고 버전을 기록합니다."
    exit 1
  fi
  if [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo "오류: ${STATE} 에 'skill ' 로 시작하는 줄이 없습니다."
    echo "  형식: skill <스킬이름>:<owner>/<repo>"
    exit 1
  fi
}

# 스킬 이름으로 소속 저장소를 찾는다. 없으면 빈 문자열.
repo_of_skill() {
  local target="$1" entry
  for entry in "${SKILLS[@]}"; do
    if [[ "${entry%%:*}" == "$target" ]]; then
      echo "${entry##*:}"
      return 0
    fi
  done
  echo ""
}

# 원본 저장소의 로컬 체크아웃 경로를 찾는다(환경변수 → ~/source/<owner>/<name> → ~/source/*/ 탐색).
# 표준 출력에는 경로만 내보내고 안내 문구는 stderr 로 보낸다(호출부에서 $(...) 로 받기 때문).
resolve_repo_path() {
  local repo="$1" name env_value candidates=()
  name="${repo##*/}"

  # 환경변수 이름은 저장소명에서 기계적으로 만든다: 대문자 + '-'→'_' + '_PATH'.
  #   peach-harness → PEACH_HARNESS_PATH,  peach-harness-php → PEACH_HARNESS_PHP_PATH
  # 저장소별 표를 두지 않으므로 새 저장소를 써도 이 스크립트를 고칠 일이 없다.
  local env_name
  env_name="$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')_PATH"
  env_value="${!env_name:-}"

  if [[ -n "$env_value" ]]; then
    if [[ -d "$env_value/skills" ]]; then
      echo "$env_value"
      return 0
    fi
    echo "  ⚠ 환경변수 경로에 skills/ 가 없습니다: ${env_value}" >&2
    return 1
  fi

  # owner 까지 일치하는 정석 경로(~/source/<owner>/<name>)가 있으면 그것으로 확정한다.
  # 다른 워크트리·사본이 ~/source/*/<name> 에 함께 있어도 "후보가 여러 개" 로 막히지 않는다.
  local owner="${repo%%/*}"
  if [[ -n "$owner" && "$owner" != "$repo" && -d "$HOME/source/$owner/$name/skills" ]]; then
    echo "$HOME/source/$owner/$name"
    return 0
  fi

  # nullglob: 매치가 없을 때 리터럴 문자열이 남지 않게 한다.
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  candidates=("$HOME"/source/*/"$name")
  [[ $had_nullglob -eq 1 ]] || shopt -u nullglob

  local found=""
  local dir
  for dir in "${candidates[@]}"; do
    [[ -d "$dir/skills" ]] || continue
    if [[ -n "$found" ]]; then
      echo "  ⚠ ${name} 후보가 여러 개입니다. 환경변수로 지정하세요:" >&2
      printf '      %s\n' "${candidates[@]}" >&2
      return 1
    fi
    found="$dir"
  done

  if [[ -z "$found" ]]; then
    echo "  ⚠ ${name} 로컬 체크아웃을 찾지 못했습니다." >&2
    echo "    환경변수로 지정하세요. 예: export ${env_name}=~/source/<org>/${name}" >&2
    return 1
  fi

  echo "$found"
}

latest_tag() {
  gh release view --repo "$1" --json tagName -q .tagName 2>/dev/null || echo "확인불가"
}

# ── self-update: 이 스크립트와 hook 을 원본 최신 릴리스에 맞춘다 ─────────────
#
# 스킬만 갱신하고 스크립트는 낡은 채로 두면, 프로젝트마다 사본이 갈라져 "이 프로젝트는 왜
# 다르게 동작하지" 를 매번 추적하게 된다. 그래서 pull 이 스킬을 받기 전에 자신부터 맞춘다.
#
# 자기 자신을 바꾼 뒤에는 반드시 exec 로 재실행한다 — bash 는 실행 중에도 스크립트 파일을
# 조금씩 읽어 나가므로, 본문이 바뀌면 남은 부분을 엉뚱한 위치부터 읽는다. mv 로 교체하면
# 새 inode 가 되어 이미 열린 fd(=옛 본문)는 온전하고, exec 가 즉시 새 본문으로 넘긴다.
# PEACH_SKILLS_SYNCED 는 재실행 후 이 함수를 건너뛰게 하는 가드다(무한 재실행 방지).
sync_self() {
  [[ -z "${PEACH_SKILLS_SYNCED:-}" ]] || return 0
  [[ -z "${PEACH_SKILLS_NO_SELF_UPDATE:-}" ]] || return 0
  export PEACH_SKILLS_SYNCED=1

  local tag
  tag="$(latest_tag "$HARNESS_REPO")"
  # 오프라인이거나 릴리스 조회에 실패하면 조용히 건너뛴다 — 갱신 실패로 pull 을 막지 않는다.
  [[ "$tag" != "확인불가" ]] || return 0

  # hook 을 먼저, 자기 자신을 나중에 갱신한다 — 순서가 중요하다. self 교체 직후 exec 로
  # 빠져나가는데, 재실행된 프로세스는 위 가드에 걸려 이 함수를 건너뛰므로 그때는 hook 을
  # 손볼 기회가 없다. 먼저 끝내두면 한 번의 실행으로 둘 다 최신이 된다.
  sync_file "scripts/hooks/skills-check.sh" "$HOOK" "$tag" || true
  if sync_file "scripts/peach-skills.sh" "$SELF" "$tag"; then
    echo "  → 새 본문으로 재실행합니다."
    exec bash "$SELF" "$@"
  fi
}

# 원본 파일 하나를 로컬 사본과 맞춘다. 교체했으면 0, 이미 같거나 받지 못했으면 1.
# 같으면 mtime 을 건드리지 않는다(git 이 깨끗하게 유지된다). 받기에 실패하면(권한·네트워크)
# 아무것도 하지 않는다 — 빈 파일로 덮어 스크립트를 잃는 사고를 막는다.
sync_file() {
  local path="$1" dest="$2" tag="$3" tmp
  tmp="$(mktemp)"
  if ! gh api "repos/${HARNESS_REPO}/contents/${path}?ref=${tag}" \
         -H "Accept: application/vnd.github.raw" > "$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"; return 1
  fi
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$dest")"
  chmod +x "$tmp"
  mv "$tmp" "$dest"
  echo "  갱신: ${dest} → ${tag}"
}

# 기록된 설치 태그를 조회한다. 없으면 빈 문자열.
# awk 한 번으로 끝낸다 — grep|awk|head 파이프라인은 미기록 저장소에서 grep 이 1을 내고
# pipefail 이 그것을 전파해, 호출부가 조건절 밖이면 스크립트가 죽는다.
installed_tag() {
  [[ -f "$STATE" ]] || return 0
  awk -v r="$1" '$1=="installed" && $2==r {print $3; exit}' "$STATE"
}

# $STATE 의 기계 영역(설치 태그·설치 시각)만 갱신한다.
#
# ★ 사용자 영역은 한 글자도 건드리지 않는다 — skill 줄, 주석, 사용자가 적은 메모가
#   그대로 살아남는다. 아래 grep -v 의 세 패턴('installed ', '# 마지막 설치:',
#   '# ── 아래는 pull ')에 걸리는 줄만 지우고 끝에 새로 붙인다.
#   (패턴에 구분선 주석을 빼먹으면 매 실행마다 그 줄이 쌓인다 — 프로토타입에서 실측한 함정)
#
# 임시파일 → mv 로 원자적 교체: 쓰다가 죽어도 원본이 온전히 남는다. 스킬 목록이 이 파일에
# 있으므로 이 보호가 중요하다(그래도 사고 시 최후 수단은 git checkout).
#
# ⚠ 형식 계약 — 아래 두 줄 형식은 파서와 짝을 이룬다. 바꿀 때 함께 고친다.
#     "# 마지막 설치: <날짜>"                ← check_versions() 가 sed 로 추출
#     "installed <owner>/<repo> <태그>"      ← installed_tag() 가 awk 로 추출
#
# 기록하는 태그는 check_versions() 가 이미 조회해 $LATEST 에 남긴 값이다. 여기서 다시
# 묻지 않는다(이유는 check_versions 주석 참고). --force 처럼 비교를 건너뛴 경로에서만 묻는다.
write_state() {
  local tmp repo tag entry
  tmp="$(mktemp)"
  {
    # 사용자 영역 보존. 끝쪽 빈 줄은 정리해 반복 실행 시 누적되지 않게 한다.
    grep -v -e '^installed ' -e '^# 마지막 설치:' -e '^# ── 아래는 pull ' "$STATE" \
      | awk 'BEGIN{n=0} {if($0==""){n++} else {for(i=0;i<n;i++)print ""; n=0; print}}'
    echo
    echo "# ── 아래는 pull 이 기록한다. 직접 편집하지 않는다. ──"
    echo "# 마지막 설치: $(date '+%Y-%m-%d %H:%M:%S %z')"
    for repo in "${REPOS[@]}"; do
      tag=""
      for entry in ${LATEST[@]+"${LATEST[@]}"}; do
        [[ "${entry%% *}" == "$repo" ]] && { tag="${entry#* }"; break; }
      done
      echo "installed ${repo} ${tag:-$(latest_tag "$repo")}"
    done
  } > "$tmp"
  mv "$tmp" "$STATE"
}

# ── pull: 원본 → 프로젝트 ────────────────────────────────────────────────────

# pull 은 .claude/skills/ 를 덮어쓴다. 커밋하지 않은 개선분이 있으면 그대로 사라지므로,
# 설치 전에 막는다(git 이 없거나 저장소가 아니면 판단할 수 없어 통과시킨다).
# 의도적으로 덮어쓸 때만 PEACH_SKILLS_ALLOW_DIRTY=1 을 준다.
require_clean_skills() {
  [[ -z "${PEACH_SKILLS_ALLOW_DIRTY:-}" ]] || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  local dirty
  dirty="$(git status --porcelain -- .claude/skills)"
  [[ -n "$dirty" ]] || return 0

  echo "중단: .claude/skills/ 에 커밋하지 않은 변경이 있습니다 — pull 이 덮어쓰면 사라집니다."
  echo
  echo "$dirty" | sed 's/^/  /'
  echo
  echo "먼저 처리하세요."
  echo "  원본에 반영 : ${SELF} push <스킬이름>   (대상 확인: ${SELF} diff)"
  echo "  커밋만      : git add .claude/skills && git commit"
  echo "  버리기      : git checkout -- .claude/skills && git clean -fd .claude/skills"
  echo
  echo "그래도 덮어쓰려면: PEACH_SKILLS_ALLOW_DIRTY=1 ${SELF} pull"
  exit 1
}

install_skills() {
  require_clean_skills

  # 설치 대상은 $STATE 의 skill 줄에서 저장소별로 묶어 도출한다(목록을 여기 중복시키지 않는다).
  # --copy: .claude/skills/ 에 실체를 받는다(심링크 방향 뒤집힘 방지, 파일 상단 주석 참고).
  local repo entry skill_args
  for repo in "${REPOS[@]}"; do
    skill_args=()
    for entry in "${SKILLS[@]}"; do
      [[ "${entry##*:}" == "$repo" ]] && skill_args+=(-s "${entry%%:*}")
    done
    echo "설치: ${repo} — 스킬 $((${#skill_args[@]} / 2))개"
    npx skills add "$repo" -a claude-code --copy -y "${skill_args[@]}"
  done

  link_agents_skills

  write_state

  echo
  echo "완료. 버전 기록: ${STATE}"
  echo "⚠ pull 은 .claude/skills/ 를 덮어씁니다. 개선분이 있었다면 git diff 로 확인하세요."
}

# ── link: .agents/skills 심링크 재생성 ───────────────────────────────────────

# .claude/skills/ 의 모든 스킬을 .agents/skills/ 에 상대 심링크로 노출한다(Codex 쪽 경로).
# 상대경로(../../.claude/skills/<이름>)를 쓰므로 워크트리를 옮겨도 링크가 깨지지 않고,
# git 에 커밋해도 절대경로가 박히지 않는다.
link_agents_skills() {
  mkdir -p .agents/skills
  local created=0 src link
  for src in .claude/skills/*; do
    [[ -e "$src" ]] || continue          # 글롭 미매치 시 리터럴 문자열이 남는 것을 걸러낸다
    local name
    name="$(basename "$src")"
    link=".agents/skills/${name}"
    # 이미 올바른 링크면 건드리지 않는다. 깨진 링크·낡은 실체는 지우고 다시 만든다.
    if [[ -L "$link" && "$(readlink "$link")" == "../../.claude/skills/${name}" ]]; then
      continue
    fi
    rm -rf "$link"
    ln -s "../../.claude/skills/${name}" "$link"
    created=$((created + 1))
  done

  # .claude/skills/ 에서 사라진 스킬의 링크는 dangling 으로 남으므로 함께 정리한다.
  local removed=0
  for link in .agents/skills/*; do
    [[ -L "$link" ]] || continue
    if [[ ! -e "$link" ]]; then
      rm -f "$link"
      removed=$((removed + 1))
    fi
  done

  echo "  .agents/skills 링크: 생성/갱신 ${created}개, 정리 ${removed}개"
}

# ── check: 버전 비교 ─────────────────────────────────────────────────────────

# 저장소 최신 릴리스 태그와 로그 기록을 표로 비교한다.
#
# 반환값 세 가지 — "모른다" 를 "최신" 으로 뭉개지 않는다. 오프라인에서 최신이라고 단정하면
# 갱신이 조용히 누락된다(실측 함정).
#   0 갱신 필요(설치 기록 없음 포함)   1 모두 최신   2 릴리스 조회 실패가 있어 판단 불가
#
# 조회한 태그는 LATEST 에 남긴다 — write_state 가 같은 저장소를 다시 묻지 않기 위해서다.
# 다시 물으면 gh 호출이 두 배가 되고, 설치 도중 새 릴리스가 나오면 받지도 않은 태그를
# 기록해 다음 check 가 "최신" 이라 답한다(그 버전은 영구히 누락된다).
check_versions() {
  local installed_at
  installed_at=$(sed -n 's/^# 마지막 설치: //p' "$STATE")
  if [[ -z "$installed_at" ]]; then
    # 스킬 목록은 있는데 설치 기록이 없다 — 목록만 적고 아직 pull 하지 않은 상태다.
    echo "스킬 버전 상태 (설치 기록 없음 — 스킬 ${#SKILLS[@]}개가 목록에 있습니다)"
    echo
    echo "→ 최초 설치가 필요합니다."
    return 0
  fi

  echo "스킬 버전 상태 (마지막 설치: ${installed_at})"
  echo
  # 헤더는 한글(터미널 2칸 폭)이 섞여 printf 폭 계산과 어긋나므로 데이터 열폭에 맞춰 수동 정렬한다.
  echo "  저장소                     설치됨     최신       상태"

  local outdated=0 unknown=0
  LATEST=()
  for repo in "${REPOS[@]}"; do
    local name latest recorded status
    name="${repo##*/}"                                   # peachSolution/ 접두어 제거
    latest=$(latest_tag "$repo")
    LATEST+=("${repo} ${latest}")
    recorded="$(installed_tag "$repo")"
    recorded="${recorded:-없음}"
    if [[ "$latest" == "확인불가" ]]; then
      status="? 조회 실패"
      unknown=1
    elif [[ "$recorded" == "$latest" ]]; then
      status="✓ 최신"
    else
      status="⚠ 갱신 필요"
      outdated=1
    fi
    printf "  %-26s %-10s %-10s %s\n" "$name" "$recorded" "$latest" "$status"
  done
  echo
  # 갱신 필요가 하나라도 있으면 그것이 우선이다(조회 실패가 섞여 있어도 받을 것은 받는다).
  [[ $outdated -eq 1 ]] && return 0
  [[ $unknown  -eq 1 ]] && return 2
  return 1
}

# 원본 저장소 안에서 스킬의 실제 경로를 찾는다.
# 원본은 skills/ 아래를 분류 폴더로 나눈다(skills/peach/, skills/node/ …). 그래서
# skills/<이름>/ 을 그대로 쓰면 루트에 사본이 하나 더 생겨 조용히 갈라진다(실측 사고).
#
# ★ 규약 경로(접두어와 같은 이름의 폴더)를 먼저 본다. find 를 먼저 쓰면 안 된다 —
#   -print -quit 은 얕은 것부터 집으므로, 과거 사고로 skills/<이름>/ 잔해가 남아 있으면
#   깊이 1의 잔해를 깊이 2의 정본보다 먼저 골라 잔해만 계속 갱신한다(실측 사고).
#   find 는 규약을 벗어난 위치에 둔 스킬을 구제하는 폴백이다.
origin_skill_dir() {
  local repo_path="$1" name="$2" by_prefix found
  by_prefix="${repo_path}/skills/${name%%-*}/${name}"
  if [[ -d "$by_prefix" ]]; then
    echo "$by_prefix"
    return 0
  fi
  found="$(find "$repo_path/skills" -mindepth 1 -maxdepth 3 -type d -name "$name" -print -quit 2>/dev/null)"
  echo "${found:-$by_prefix}"
}

# ── diff: 원본 대비 변경분 ───────────────────────────────────────────────────

# 원본(왼쪽) → 로컬(오른쪽) 방향의 diff 를 들여쓰기해 출력한다. push 하면 로컬이 원본을 덮는다.
# diff 는 차이가 있으면 1을 내고 pipefail 이 그것을 전파하므로 여기서 흡수한다 — 현재 두
# 호출부는 모두 비치명 문맥이라 없어도 동작하지만, 그 사실에 의존하지 않게 함수 안에서 막는다.
print_skill_diff() {
  diff -ur "$1" "$2" | sed 's/^/    /' || true
}

# 스킬 하나를 원본과 비교한다. 차이가 있으면 0, 같으면 1, 비교 불가면 2.
diff_one_skill() {
  local name="$1" repo repo_path
  local local_dir=".claude/skills/${name}"

  if [[ ! -d "$local_dir" ]]; then
    echo "  ${name}: 로컬에 없음 (pull 로 설치하세요)"
    return 2
  fi

  repo="$(repo_of_skill "$name")"
  if [[ -z "$repo" ]]; then
    echo "  ${name}: 수동 관리 스킬 (원본 저장소 없음 — 비교 대상 아님)"
    return 2
  fi

  repo_path="$(resolve_repo_path "$repo")" || return 2
  local origin_dir
  origin_dir="$(origin_skill_dir "$repo_path" "$name")"
  if [[ ! -d "$origin_dir" ]]; then
    echo "  ${name}: 원본 저장소에 없음 (신규 스킬 — push 로 추가할 수 있습니다)"
    return 0
  fi

  if diff -qr "$origin_dir" "$local_dir" >/dev/null 2>&1; then
    echo "  ${name}: 동일"
    return 1
  fi

  echo "  ${name}: 변경분 있음 (원본: ${repo_path##*/})"
  print_skill_diff "$origin_dir" "$local_dir"
  return 0
}

cmd_diff() {
  local target="${1:-}"
  if [[ -n "$target" ]]; then
    diff_one_skill "$target" || true
    return 0
  fi

  echo "원본 저장소 대비 변경분 (원본 → 로컬 방향)"
  echo
  local changed=0 src
  for src in .claude/skills/*; do
    [[ -e "$src" ]] || continue
    local name
    name="$(basename "$src")"
    if diff_one_skill "$name"; then
      changed=$((changed + 1))
    fi
  done
  echo
  if [[ $changed -eq 0 ]]; then
    echo "→ 원본과 동일합니다."
  else
    echo "→ ${changed}개 스킬에 변경분이 있습니다. 반영: ${SELF} push <스킬이름>"
  fi
}

# ── push: 프로젝트 → 원본 ────────────────────────────────────────────────────

cmd_push() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "오류: 스킬 이름이 필요합니다."
    echo "사용법: ${SELF} push <스킬이름>    (대상 확인: ${SELF} diff)"
    exit 1
  fi

  local local_dir=".claude/skills/${name}"
  if [[ ! -d "$local_dir" ]]; then
    echo "오류: .claude/skills/${name} 가 없습니다."
    exit 1
  fi
  # 심링크를 그대로 복사하면 원본에 깨진 링크가 박힌다.
  if [[ -L "$local_dir" ]]; then
    echo "오류: ${local_dir} 가 심링크입니다. 실체여야 합니다(${SELF} pull --force 로 복구)."
    exit 1
  fi

  local repo
  repo="$(repo_of_skill "$name")"
  if [[ -z "$repo" ]]; then
    echo "오류: ${name} 의 원본 저장소를 모릅니다."
    echo "  ${STATE} 에 추가하세요: skill ${name}:<owner>/<repo>"
    exit 1
  fi

  local repo_path
  repo_path="$(resolve_repo_path "$repo")" || exit 1

  # 원본 저장소가 깨끗한지 먼저 본다. 남의 작업 위에 덮어쓰지 않는다.
  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    echo "오류: 원본 저장소에 커밋되지 않은 변경이 있습니다: ${repo_path}"
    echo "  정리 후 다시 실행하세요. (git -C '${repo_path}' status)"
    exit 1
  fi

  local origin_dir origin_rel
  origin_dir="$(origin_skill_dir "$repo_path" "$name")"
  origin_rel="${origin_dir:$(( ${#repo_path} + 1 ))}"

  echo "스킬 반영 계획"
  echo
  echo "  스킬      : ${name}"
  echo "  원본      : ${repo_path}"
  echo "  브랜치    : $(git -C "$repo_path" branch --show-current) (현재 브랜치에 그대로 적용 — 새 브랜치를 만들지 않는다)"
  echo "  동작      : ${local_dir}/ → ${origin_rel}/ 전체 교체"
  echo
  if [[ -d "$origin_dir" ]]; then
    echo "  변경 내용:"
    print_skill_diff "$origin_dir" "$local_dir"
  else
    echo "  (원본에 없는 신규 스킬입니다)"
    find "$local_dir" -type f | sed "s|^${local_dir}/|    + |"
  fi
  echo
  read -r -p "위 내용을 원본 저장소의 현재 브랜치에 복사할까요? [y/N] " answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "취소했습니다."
    exit 0
  fi

  rm -rf "$origin_dir"
  mkdir -p "$(dirname "$origin_dir")"
  cp -R "$local_dir" "$origin_dir"

  # 민감 정보 검사는 하지 않는다 — 원본 저장소의 커밋 훅이 담당한다.
  # 이 스크립트는 복사와 stage 까지만 책임진다(검사를 두 곳에 두면 어긋난다).
  (cd "$repo_path" && git add -A)

  echo
  echo "복사 완료. 원본 저장소의 현재 브랜치에 stage 되었습니다(커밋·푸시는 하지 않았습니다 — 원본에서 직접 처리)."
  echo "  확인 : git -C '${repo_path}' diff --cached"
  echo "  취소 : git -C '${repo_path}' reset && git -C '${repo_path}' checkout -- '${origin_rel}' && git -C '${repo_path}' clean -fd '${origin_rel}'"
}

# ── pull 진입점 ──────────────────────────────────────────────────────────────

cmd_pull() {
  require_state
  if [[ "${1:-}" == "--force" ]]; then
    echo "강제 재설치(--force): 버전과 무관하게 설치합니다."
    echo
    install_skills
    return
  fi
  local rc=0
  check_versions || rc=$?
  case "$rc" in
    0) install_skills ;;
    2) echo "→ 릴리스 조회에 실패해 최신 여부를 알 수 없습니다(오프라인·gh 인증 확인)."
       echo "  설치를 생략했습니다. 그래도 받으려면: ${SELF} pull --force" ;;
    *) echo "→ 모두 최신입니다. 설치를 생략합니다. (강제 재설치: ${SELF} pull --force)" ;;
  esac
}

usage() {
  echo "사용법: ${SELF} <명령>"
  echo
  echo "  pull [--force]   원본 → 프로젝트 설치/갱신 (인자 없이 실행 시 기본 동작)"
  echo "  check            버전 비교만 표시"
  echo "  link             .agents/skills 심링크 재생성 (네트워크 불필요)"
  echo "  diff [스킬]      원본 대비 변경분 표시"
  echo "  push <스킬>      개선분을 원본 저장소의 현재 브랜치에 복사·stage (커밋·푸시 안 함)"
}

# 스킬 목록을 먼저 읽는다. 파일이 없으면 빈 배열로 남고, 목록이 필요한 명령은
# require_state 가 막는다(link 는 .claude/skills/ 를 글롭하므로 목록이 필요 없다).
load_state

# 네트워크를 쓰는 명령에서만 자기 자신을 갱신한다. link/diff/push 는 오프라인에서도
# 동작해야 하므로 건드리지 않는다. 인자는 재실행 시 그대로 넘기기 위해 통째로 전달한다.
case "${1:-}" in
  pull|check|"") sync_self "$@" ;;
esac

case "${1:-}" in
  pull)  shift; cmd_pull "$@" ;;
  check)
    require_state
    rc=0
    check_versions || rc=$?
    case "$rc" in
      0) echo "→ 새 버전이 있습니다. '${SELF} pull' 을 실행해 갱신하세요." ;;
      2) echo "→ 릴리스 조회에 실패해 최신 여부를 알 수 없습니다(오프라인·gh 인증 확인)." ;;
      *) echo "→ 모두 최신입니다." ;;
    esac
    ;;
  link)  link_agents_skills ;;
  diff)  shift; require_state; cmd_diff "$@" ;;
  push)  shift; require_state; cmd_push "$@" ;;
  "")          cmd_pull ;;
  -h|--help)   usage ;;
  *)
    echo "알 수 없는 명령: $1"
    echo
    usage
    exit 1
    ;;
esac
