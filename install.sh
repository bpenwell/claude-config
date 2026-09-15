#!/usr/bin/env bash
# Install this Claude Code configuration into ~/.claude (Linux, macOS, WSL, Git Bash).
# Windows PowerShell users: run .\install.ps1 instead.
#
#   ./install.sh            symlink hooks+skills into ~/.claude (stays in sync with git)
#   ./install.sh --copy     copy instead of symlink (independent snapshot)
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Anything already at a target path is moved to ~/.claude/backups/install-<timestamp>/
# before being replaced. Nothing is deleted.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ENV_FILE="${CLAUDE_CONFIG_ENV:-$HOME/.claude-config.env}"
BACKUP_DIR="$CLAUDE_DIR/backups/install-$(date +%Y%m%d-%H%M%S)"

MODE=symlink
DRY=0
for arg in "$@"; do
  case "$arg" in
    --copy) MODE=copy ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v node >/dev/null || { echo "node is required but not on PATH" >&2; exit 1; }

say() { printf '%s\n' "$*"; }
run() { if [[ $DRY -eq 1 ]]; then say "  [dry-run] $*"; else "$@"; fi; }

backup() {
  local target="$1" src="$2"
  [[ -e "$target" || -L "$target" ]] || return 0
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$src")" ]]; then
    return 1   # already linked at this source; nothing to back up or redo
  fi
  # Copy mode: identical contents means there is nothing to back up or redo.
  if [[ $MODE == copy && -n "$src" ]] && node "$REPO/scripts/same-tree.mjs" "$src" "$target"; then
    return 1
  fi
  run mkdir -p "$BACKUP_DIR"
  run mv "$target" "$BACKUP_DIR/$(basename "$target")"
  say "  backed up existing $(basename "$target") -> $BACKUP_DIR/"
  return 0
}

link() {
  local src="$1" dest="$2"
  backup "$dest" "$src" || { say "  $(basename "$dest") already up to date"; return 0; }
  if [[ $MODE == symlink ]]; then
    run ln -s "$src" "$dest"
    say "  linked $(basename "$dest")"
  else
    run cp -r "$src" "$dest"
    say "  copied $(basename "$dest")"
  fi
}

say "Installing Claude config from $REPO into $CLAUDE_DIR (mode: $MODE)"
run mkdir -p "$CLAUDE_DIR"

say "hooks:"
link "$REPO/hooks" "$CLAUDE_DIR/hooks"

say "settings:"
# settings.json is rendered, not linked: hook commands need an absolute path to
# the hooks directory, which differs per machine. Use this to pull
# in-app preference changes back into the template: node scripts/sync-settings.mjs
node "$REPO/scripts/render-settings.mjs" \
  --template "$REPO/settings/settings.template.json" \
  --hooks-dir "$CLAUDE_DIR/hooks" \
  --out "$CLAUDE_DIR/settings.json" \
  --backup-dir "$BACKUP_DIR" \
  $([[ $DRY -eq 1 ]] && echo --dry-run)

say "skills:"
# Merged per-directory so skills that exist only on this machine survive.
run mkdir -p "$CLAUDE_DIR/skills"
for skill in "$REPO"/skills/*/; do
  link "${skill%/}" "$CLAUDE_DIR/skills/$(basename "$skill")"
done

say "mcp servers:"
if [[ -f "$ENV_FILE" ]]; then
  node "$REPO/mcp/merge-mcp.mjs" --env-file "$ENV_FILE" $([[ $DRY -eq 1 ]] && echo --dry-run)
else
  say "  skipped: no $ENV_FILE"
  say "  cp $REPO/mcp/env.example $ENV_FILE, fill it in, then re-run ./install.sh"
fi

cat <<EOF

Done. Remaining manual steps:
  1. Plugins install on first launch from settings.json (enabledPlugins). If the
     official marketplace is missing, run: claude  ->  /plugin marketplace add anthropics/claude-code
  2. Restart Claude Code so hooks and MCP servers are picked up.
EOF
