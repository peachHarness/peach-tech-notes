#!/usr/bin/env bash
# 세션 시작 시 스킬 상태를 점검한다 (Claude Code + Codex 공용).
#
# 스킬 본문(.claude/skills/)은 git 으로 추적되므로 워크트리 체크아웃 즉시 존재한다.
# 반면 .agents/skills/ 심링크는 git 무시 대상이라 새 워크트리에서 비어 있다 —
# Codex 쪽 경로가 그것이므로 여기서 자동 복구한다. 심링크 생성은 로컬 파일 작업이라
# 네트워크가 필요 없고 즉시 끝나므로 hook 안에서 해도 안전하다.
#
# 반대로 설치(npx skills add)는 여기서 하지 않는다:
#   - 네트워크로 스킬을 받아오므로 hook timeout(10초)을 넘긴다.
#   - SessionStart 를 블로킹하면 첫 응답이 그만큼 늦어진다.
#   - 오프라인 환경에서 실패해 세션이 막히면 안 된다.
# 그래서 본문 누락은 감지해 알리기만 하고, 실제 설치는 사용자가 실행한다.
#
# ★ 이 파일에는 프로젝트별 설정이 한 줄도 없다. 점검 대상은 .claude/peach-skills.state 의
#   skill 줄에서 도출하므로, 스킬을 추가·제거해도 이 파일을 고칠 일이 없다.
#   이 저장소에서 직접 만든 스킬은 state 에 없으니 점검 대상에서 자연히 빠진다(의도된 동작 —
#   원본이 없어 복구할 방법도 없으므로 알려봐야 할 일이 없다).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 0

# 1) .agents/skills 심링크 자동 복구 — Codex 가 스킬을 보려면 이 경로가 필요하다.
#    peach-skills.sh link 와 같은 일을 하지만, hook 은 스크립트가 없어도 죽지 않아야 하므로
#    여기서 직접 만든다(의존성 없이 동작).
if [[ -d .claude/skills ]]; then
  mkdir -p .agents/skills 2>/dev/null || true
  linked=0
  for src in .claude/skills/*; do
    [[ -e "$src" ]] || continue
    name="$(basename "$src")"
    link=".agents/skills/${name}"
    [[ -L "$link" && "$(readlink "$link")" == "../../.claude/skills/${name}" ]] && continue
    rm -rf "$link" 2>/dev/null || true
    ln -s "../../.claude/skills/${name}" "$link" 2>/dev/null && linked=$((linked + 1))
  done
  # 대상이 사라진 dangling 링크 정리
  for link in .agents/skills/*; do
    [[ -L "$link" && ! -e "$link" ]] && rm -f "$link" 2>/dev/null || true
  done
  if [[ $linked -gt 0 ]]; then
    echo "ℹ .agents/skills 심링크 ${linked}개를 복구했습니다 (Codex 스킬 경로)."
  fi
fi

# 2) 스킬 본문 누락 점검. git 추적 대상이라 정상적인 워크트리에서는 비어 있지 않다.
#    비어 있다면 .gitignore 설정이 어긋났거나 pull 전 상태다.
STATE=".claude/peach-skills.state"
if [[ ! -f "$STATE" ]]; then
  echo "⚠ ${STATE} 가 없습니다 — 스킬 하네스가 세팅되지 않았습니다."
  echo "→ 세팅: gh api repos/peachHarness/peach-harness/contents/scripts/setup-project-skills.sh -H 'Accept: application/vnd.github.raw' | bash -s -- <스택>"
  exit 0
fi

missing=()
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  # -e 는 심링크 대상까지 따라가므로 dangling 링크도 "없음"으로 잡힌다.
  [[ -e ".claude/skills/${name}" ]] || missing+=("$name")
done < <(awk '$1=="skill" {sub(/:.*/, "", $2); print $2}' "$STATE")

if [[ ${#missing[@]} -eq 0 ]]; then
  exit 0
fi

echo "⚠ 에이전트 스킬 ${#missing[@]}개가 없습니다: ${missing[*]}"
echo "→ 설치:  .claude/peach-skills.sh pull"
exit 0
