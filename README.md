# claude-config

My portable [Claude Code](https://claude.com/claude-code) setup: settings, hooks, skills, and
MCP server definitions, packaged so a second machine can be brought to parity with one command.

No credentials live in this repo. MCP servers are stored as a template with `${VAR}` placeholders
that resolve at install time from an env file you keep outside version control.

## Install on a new machine

```bash
git clone https://github.com/bpenwell/claude-config.git ~/claude-config
cd ~/claude-config

cp mcp/env.example ~/.claude-config.env
$EDITOR ~/.claude-config.env      # fill in tokens; leave any server blank to skip it

./install.sh
```

Then restart Claude Code.

| Flag | Effect |
| --- | --- |
| *(none)* | Symlinks config into `~/.claude` — `git pull` updates the live config |
| `--copy` | Copies instead, for a machine that should drift independently |
| `--dry-run` | Prints every action, changes nothing |

Anything already at a target path is moved into `~/.claude/backups/install-<timestamp>/` first.
The installer is idempotent and deletes nothing.

## What's in here

### `settings/settings.json`
Hook registrations, enabled plugins, and UI preferences. Symlinked to `~/.claude/settings.json`,
so preference changes made inside Claude Code show up as a diff in this repo — commit them to
carry the change to your other machine.

Plugins are not vendored. `enabledPlugins` names them and Claude Code installs them from the
official marketplace on first launch:
`frontend-design`, `context7`, `playwright`, `github`, `searchfit-seo`.

### `hooks/`
| Hook | Event | What it does |
| --- | --- | --- |
| `auto-format.sh` | PostToolUse (Write/Edit) | Walks up for a prettier config and formats the file Claude just wrote. Async, never blocks. |
| `block-sensitive-commit.sh` | PreToolUse (Bash) | Exits 2 on a `git add`/`git commit` touching `.env`, `.pem`, `.key`, or `credentials`, including files already staged. |
| `validate-stop.py` | Stop | Validates recent changes against the detected requirement and blocks stop with fix instructions on failure. Not wired up in `settings.json` by default — add a `Stop` hook entry to enable. |

### `skills/`
`acpx`, `brainstorming`, `grill-me`, `humanizer`, `saas-launch-checklist`, `validate`.

Each is symlinked individually into `~/.claude/skills/`, so skills that exist only on one machine
are left alone by the installer.

### `mcp/`
`servers.template.json` defines the servers; `merge-mcp.py` renders it and merges the result into
`~/.claude.json` under `mcpServers`. Every other key in that file is preserved, and a timestamped
`.bak-*` copy is written before each merge.

Run it on its own to rotate a credential without touching the rest of the install:

```bash
./mcp/apply-mcp.sh
```

A server whose credentials are still blank in the env file is skipped rather than written as a
broken entry. A `${VAR}` with no matching env key is a hard error — the script refuses to write a
placeholder into the live config.

Servers defined here: `zola` (stdio, needs a local `zola-mcp` install — invoke `node` against the
entrypoint directly, its `npx` shebang is broken), `gsc` (Google Search Console, needs a
service-account JSON on disk), and `posthog` (HTTP, bearer token + project id).

## Keeping private config out of this repo

This repo is public, so anything that names internal infrastructure stays out of it — deploy
runbooks with bucket and Lambda names, and Claude's per-project memory under
`~/.claude/projects/*/memory/`. Carry those across machines separately:

```bash
# from the machine that has them
rsync -av ~/.claude/skills/deploy-prod ~/.claude/projects new-machine:~/.claude/
```

`private/` is gitignored here if you'd rather keep a local overlay alongside the repo.

## Updating

```bash
cd ~/claude-config && git pull      # symlink install: live immediately
cd ~/claude-config && git pull && ./install.sh --copy   # copy install
```
