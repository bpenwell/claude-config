#!/usr/bin/env bash
# Install this Claude Code configuration into ~/.claude.
#
#   ./install.sh            symlink config into ~/.claude (stays in sync with git)
#   ./install.sh --copy     copy instead of symlink (independent snapshot)
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Anything already present at a target path is moved to ~/.claude/backups/<timestamp>/
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
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
run() { if [[ $DRY -eq 1 ]]; then say "  [dry-run] $*"; else "$@"; fi; }

backup() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  # An existing symlink already pointing at this repo needs no backup.
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$2")" ]]; then
    return 1
  fi
  run mkdir -p "$BACKUP_DIR"
  run mv "$target" "$BACKUP_DIR/$(basename "$target")"
  say "  backed up existing $(basename "$target") -> $BACKUP_DIR/"
  return 0
}

link() {
  local src="$1" dest="$2"
  backup "$dest" "$src" || { say "  $(basename "$dest") already linked"; return 0; }
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

say "settings:"
link "$REPO/settings/settings.json" "$CLAUDE_DIR/settings.json"

say "hooks:"
link "$REPO/hooks" "$CLAUDE_DIR/hooks"

say "skills:"
# Skills are merged per-directory so machine-local skills in ~/.claude/skills survive.
run mkdir -p "$CLAUDE_DIR/skills"
for skill in "$REPO"/skills/*/; do
  link "${skill%/}" "$CLAUDE_DIR/skills/$(basename "$skill")"
done

say "mcp servers:"
if [[ -f "$ENV_FILE" ]]; then
  if [[ $DRY -eq 1 ]]; then
    say "  [dry-run] would merge mcp/servers.template.json into ~/.claude.json using $ENV_FILE"
  else
    "$REPO/mcp/apply-mcp.sh" "$ENV_FILE"
  fi
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
