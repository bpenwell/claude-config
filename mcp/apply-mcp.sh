#!/usr/bin/env bash
# Merge mcp/servers.template.json into ~/.claude.json, substituting values from
# an env file. Existing servers with the same name are replaced; every other key
# in ~/.claude.json is left untouched. A timestamped backup is written first.
#
#   ./apply-mcp.sh [env-file]      default env file: ~/.claude-config.env
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/merge-mcp.py" \
  --template "$HERE/servers.template.json" \
  --env-file "${1:-$HOME/.claude-config.env}" \
  --target "${CLAUDE_JSON:-$HOME/.claude.json}"
