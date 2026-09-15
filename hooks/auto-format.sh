#!/usr/bin/env bash
# Auto-format file after Claude writes/edits it.
# Reads CLAUDE_FILE_PATH from env; exits 0 always to not block Claude.

FILE="${CLAUDE_FILE_PATH:-}"
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

# Only format source files
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.html|*.md) ;;
  *) exit 0 ;;
esac

DIR=$(dirname "$FILE")

# Walk up to find prettier config
find_config() {
  local d="$DIR"
  while [[ "$d" != "/" ]]; do
    for f in .prettierrc .prettierrc.js .prettierrc.json .prettierrc.yaml prettier.config.js prettier.config.cjs; do
      [[ -f "$d/$f" ]] && echo "$d" && return 0
    done
    d=$(dirname "$d")
  done
  return 1
}

ROOT=$(find_config)
if [[ -n "$ROOT" ]]; then
  PRETTIER=$(cd "$ROOT" && npx --no prettier --version &>/dev/null && echo "$(cd "$ROOT" && npx --no prettier)" || which prettier 2>/dev/null)
  if [[ -n "$PRETTIER" ]]; then
    cd "$ROOT" && npx --no prettier --write "$FILE" &>/dev/null
  fi
fi

exit 0
