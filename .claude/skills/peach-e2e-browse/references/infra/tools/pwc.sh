#!/bin/bash
# pwc.sh — playwright-cli CDP 래퍼
# 사용법: ./e2e/tools/pwc.sh <command> [args]
#
# zsh alias 'pwc' 대체 스크립트.
# Claude Bash(비인터랙티브 셸)에서 alias가 동작하지 않으므로 스크립트로 래핑.
#
# 예시:
#   ./e2e/tools/pwc.sh snapshot
#   ./e2e/tools/pwc.sh click e10
#   ./e2e/tools/pwc.sh eval "document.title"

set -euo pipefail

CONFIG="$HOME/.playwright/cli.config.json"

if ! command -v playwright-cli &> /dev/null; then
  echo "❌ playwright-cli가 설치되어 있지 않습니다."
  echo "   실행: cd e2e && ./e2e.sh setup"
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "❌ playwright-cli 설정 파일이 없습니다: ${CONFIG}"
  echo "   실행: cd e2e && ./e2e.sh setup"
  exit 1
fi

exec playwright-cli --config="$CONFIG" "$@"
