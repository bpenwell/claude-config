# claude-config

My portable [Claude Code](https://claude.com/claude-code) setup — settings, hooks, skills, and MCP
server definitions — packaged so a second machine can be brought to parity with one command.
Runs on **Windows (PowerShell)**, **Linux**, **macOS**, and **WSL**.

Hooks and install scripts are written in Node, which Claude Code already requires, so no bash,
Python, or WSL is needed on Windows.

No credentials live in this repo. MCP servers are stored as a template with `${VAR}` placeholders
that resolve at install time from an env file kept outside version control.

## Install

**Windows (PowerShell)**

```powershell
git clone https://github.com/bpenwell/claude-config.git $HOME\claude-config
cd $HOME\claude-config

copy mcp\env.example $HOME\.claude-config.env
notepad $HOME\.claude-config.env    # fill in tokens; leave a server blank to skip it

.\install.ps1
```

If PowerShell blocks the script, run it as
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

**Linux / macOS / WSL / Git Bash**

```bash
git clone https://github.com/bpenwell/claude-config.git ~/claude-config
cd ~/claude-config

cp mcp/env.example ~/.claude-config.env
$EDITOR ~/.claude-config.env

./install.sh
```

Then restart Claude Code.

### Options

| bash | PowerShell | Effect |
| --- | --- | --- |
| *(default)* | `-Link` | Symlink hooks and skills, so `git pull` updates the live config |
| `--copy` | *(default)* | Copy instead, for a machine that should drift independently |
| `--dry-run` | `-DryRun` | Print every action, change nothing |

Unix defaults to symlinks; Windows defaults to copies because symlinks there need Developer Mode
or an elevated shell. `-Link` probes for that support up front and falls back to copying with a
warning rather than failing.

Both installers are idempotent — a second run reports "already up to date" and writes nothing.
Anything replaced is moved to `~/.claude/backups/install-<timestamp>/` first, and nothing is
deleted.

## What's in here

### `settings/settings.template.json`
Hook registrations, enabled plugins, and UI preferences.

This is rendered rather than copied verbatim: hook commands need an absolute path to the hooks
directory, which differs per machine, so `{{HOOKS_DIR}}` is substituted at install time. After
changing preferences inside Claude Code, pull them back into the template:

```bash
node scripts/sync-settings.mjs      # re-templates the absolute path, then: git diff && commit
```

Plugins are not vendored. `enabledPlugins` names them and Claude Code installs them from the
official marketplace on first launch: `frontend-design`, `context7`, `playwright`, `github`,
`searchfit-seo`.

### `hooks/`
| Hook | Event | What it does |
| --- | --- | --- |
| `auto-format.mjs` | PostToolUse (Write/Edit) | Walks up for a prettier config and formats the file Claude just wrote, preferring the project's own `node_modules/.bin/prettier`. No config, no prettier, no action. Async, never blocks. |
| `block-sensitive-commit.mjs` | PreToolUse (Bash) | Exits 2 on a `git add`/`git commit` touching `.env`, `.pem`, `.key`, or `credentials`, including files already staged. |
| `validate-stop.mjs` | Stop | Validates recent changes against the requirement found in the transcript and blocks the stop with fix instructions on failure. **Not registered by default** — add a `Stop` entry to the settings template to enable. |

`validate-stop` looks for its validator at `$CLAUDE_VALIDATE_SCRIPT`, then `<cwd>/.claude/validate.*`,
then `~/.claude/validate.*` (`.ps1`/`.cmd` are tried first on Windows). If none exists it skips and
allows the stop. It fails open everywhere — a broken validator never traps Claude.

### `skills/`
`acpx`, `brainstorming`, `grill-me`, `humanizer`, `saas-launch-checklist`, `validate`.

Installed one directory at a time, so skills that exist only on one machine are left alone.

### `mcp/`
`servers.template.json` defines the servers; `merge-mcp.mjs` renders it and merges the result into
`~/.claude.json` under `mcpServers`. Every other key in that file is preserved, and a timestamped
`.bak-*` copy is written first.

Run it on its own to rotate a credential without touching the rest of the install:

```bash
node mcp/merge-mcp.mjs                  # add --dry-run to preview
```

A server whose credentials are still blank in the env file is skipped rather than written as a
broken entry. A `${VAR}` with no matching env key is a hard error — the script refuses to write a
placeholder into a live config. Env values may use `~`, `$HOME`, or `%USERPROFILE%`.

Servers defined here: `zola` (stdio, needs a local `zola-mcp` install — invoke `node` against the
entrypoint directly, its `npx` shebang is broken), `gsc` (Google Search Console, needs a
service-account JSON on disk), and `posthog` (HTTP, bearer token + project id).

## Keeping private config out of this repo

This repo is public, so anything naming internal infrastructure stays out of it — deploy runbooks
with bucket and Lambda names, and Claude's per-project memory under `~/.claude/projects/*/memory/`.
Carry those across machines separately:

```bash
rsync -av ~/.claude/skills/deploy-prod ~/.claude/projects new-machine:~/.claude/
```

`private/` is gitignored here if you'd rather keep a local overlay alongside the repo.

## Updating

```bash
git pull                     # symlink install: live immediately
git pull && ./install.sh     # copy install (or .\install.ps1 on Windows)
```

## Layout

```
hooks/              Node hooks, cross-platform
skills/             one directory per skill
settings/           settings.template.json ({{HOOKS_DIR}} placeholder)
mcp/                servers.template.json, env.example, merge-mcp.mjs
scripts/            render-settings, sync-settings, same-tree helpers
install.sh          Linux / macOS / WSL / Git Bash
install.ps1         Windows PowerShell 5.1+
```
