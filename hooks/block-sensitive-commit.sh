#!/usr/bin/env bash
# Block git commits that include sensitive files (.env, .key, .pem, credentials).
# Reads tool input from stdin as JSON. Exits 2 to block, 0 to allow.

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

# Only check git commit/add commands
if ! echo "$CMD" | grep -qE "^git (commit|add)"; then
  exit 0
fi

# Block if sensitive file patterns are staged or being added
if echo "$CMD" | grep -qE "\.(env|pem|key)(\s|$)|credentials|\.secret"; then
  echo "BLOCKED: Command targets sensitive files. Remove them first." >&2
  exit 2
fi

# For git commit, also check what's staged
if echo "$CMD" | grep -q "git commit"; then
  STAGED=$(git diff --cached --name-only 2>/dev/null)
  if echo "$STAGED" | grep -qE "\.(env|pem|key)$|credentials|secrets"; then
    echo "BLOCKED: Staged files include sensitive files: $(echo "$STAGED" | grep -E '\.(env|pem|key)$|credentials|secrets')" >&2
    exit 2
  fi
fi

exit 0
