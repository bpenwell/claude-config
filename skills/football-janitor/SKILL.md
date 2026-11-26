---
name: football-janitor
description: Clean up the Crater Bowl / football-game checkouts on this machine. Removes worktrees and clones whose work is merged, clean and idle; deletes merged branches, gitignored build/test artifacts, temp screenshots and test leftovers; fast-forwards the main checkout. Never touches dirty, unmerged, live or protected work, and only football-game. Use when asked to tidy, consolidate or delete football-game repos/worktrees/branches/screenshots, or when invoked as /football-janitor.
---

# football-janitor

Housekeeping for the football game only (`~/Coding/football-game*`, origin `bpenwell/CraterBowl`, football temp dirs, the game's `~/.local/share/crater-bowl` test leftovers). Leave every other project alone.

Many sessions (Claude and Codex) work on this game in parallel worktrees. A worktree being "done" is a fact you check, not a guess. The script only removes things where nothing can be lost.

## Steps

1. **Dry run first** and read the whole plan:
   ```bash
   ~/.claude/skills/football-janitor/janitor.sh
   ```
2. **Get every `KEEP` item into a PR first.** The owner reviews and merges everything as a PR, so work must not sit stranded in a worktree.
   - `N commit(s) not in origin/main`: if no open PR exists for that branch and no live process is in the worktree, push the branch and open one (`gh pr create --fill`, adding test evidence from `scripts/check.sh`). Don't merge it yourself. If a session is live in it, leave it and say so.
   - `uncommitted change(s)`: someone's work in progress. Report it and don't touch it. If it clearly belongs to a finished session (no live process, idle for hours), ask the user before committing it to a branch and opening a PR.
   - `protected` (`football-game-codex`, Codex's cron clone) and `main`: never remove.
3. **Apply** the safe actions:
   ```bash
   ~/.claude/skills/football-janitor/janitor.sh --apply
   ```
   Add `--remote` to also delete branches on origin that are fully merged and have no open PR. That deletion is safe (their commits are in main), but it is outward-facing, so do it only when the user asked to clean up remote branches too.
4. **Review list.** The script prints `REVIEW untracked image …` for images that aren't ignored. Those may be someone's screenshots. Check whether a doc or PR references them. Commit the needed ones through a PR, and ask before deleting the rest.
5. **Report** a short table: removed (with sizes freed), kept (with reasons), PRs opened, anything that needs the user.

## Safety rules (the script enforces them; follow them in manual steps too)

- Remove a worktree or clone only if: clean, HEAD already in `origin/main`, no open PR on its branch, and no live process has its cwd inside it.
- Never delete tracked files, the main checkout, `football-game-codex`, or real player data (profile, settings, replays).
- Never `git stash`, reset, or check out files in someone else's worktree.
- Generated artifacts (`build/` export zips, `.parity-shots/`, `.*.log`, `__pycache__`) are deleted only when gitignored. They regenerate (`scripts/export.sh`, `scripts/smoke.sh`).
- Temp dirs: `/tmp/crater-*`, `/tmp/fourth-and-long-shots*`, `/tmp/fl-userdata.*`, `/tmp/fl-check-*`.

Override paths with `FOOTBALL_ROOT` (default `~/Coding`) and `FOOTBALL_PROTECT` (space-separated dirs to never remove).
