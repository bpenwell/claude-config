---
name: football-ralph
description: Ralph-loop through the Crater Bowl (football-game, bpenwell/CraterBowl) GitHub issue backlog, shipping one PR per issue, until the rate limit or the backlog runs out. Each round runs two lanes in parallel, one high-priority issue (bug/P0/P1) and one low-priority issue (P2) in a different code zone, so their PRs rarely conflict. Use when asked to "ralph loop the football issues", grind the CraterBowl backlog, or when invoked as /football-ralph.
---

# football-ralph

Keep shipping Crater Bowl issues as PRs until you hit the usage limit. Each round has two lanes:

| Lane | Picks | Why |
|---|---|---|
| **HIGH** | `type:bug` first, then `P0`, then `P1`, oldest first | the work that matters |
| **LOW** | `P2`: bugs, then improvements/tech-debt/docs, then features, in a **different code zone** with no shared `area:*` label | cheap progress that won't conflict with HIGH |

Code zones (from area labels, in `pick.sh`): `docs` (type:docs / area:process), `infra` (scripts, tools, CI),
`net` (online/netcode/social → `src/net`, lobby UI), `view` (presentation/audio/replays/ui/accessibility/
chaosball/training → `src/game`, `src/ui`), `sim` (everything else → `src/sim`).

The repo's rules still apply: `AGENTS.md` "Shipping" + "Opening pull requests", `docs/workflow.md`
(issue lifecycle), `LOOP.md` (iteration shape). Read them once at the start of the session. Never commit to or push
`main`, and never merge a PR, not even a green one. The owner reviews and merges.

## Round

1. **Pick.**
   ```bash
   ~/.claude/skills/football-ralph/pick.sh                      # HIGH + LOW pair
   ~/.claude/skills/football-ralph/pick.sh --exclude 12,40      # skip ones handled this session
   ~/.claude/skills/football-ralph/pick.sh --list               # whole eligible queue
   ```
   It already skips claimed/blocked/needs-decision/type:decision issues and any issue an open PR mentions.
   Read both issue bodies (`gh issue view N --repo bpenwell/CraterBowl --comments`). Re-pick when:
   - the issue is too big for one PR. Split it: open child issues (`Part of #N`), comment on #N, then ship the first child.
   - it needs an owner decision with no documented default.
   - the touch points overlap the other lane's or an open PR's files (`gh pr diff <n> --name-only`).
   - LOW only: it's a conflict magnet even in its own zone, e.g. a refactor that touches many files (moving every
     `tuning.gd` constant into a data file) or a big feature. Use `--list` and take the next small, contained P2.
2. **Verify bugs still reproduce** on a clean `origin/main` before building. A stale bug gets a closing comment with
   evidence (the command, its output, the commit that fixed it). Then pick again. Gate bugs ("check.sh red")
   go stale often.
3. **Dispatch both lanes in parallel**, one `Agent` call each in the same message, with the lane prompt below.
   Don't build a lane yourself while its agent runs. Wait for the notifications.
4. **Review each result.** Confirm the PR exists (`gh pr view <n> --json url,files,body`). Check that the diff is only
   that issue's files (`git show --stat`), the body has Motivation/Solution/Testing with `CHECK PASS` and
   evidence images, and the issue has a PR comment. Fix small gaps yourself. Send larger ones back via `SendMessage`.
5. **Next round** right away, adding this session's issues to `--exclude`. Don't stop to report between rounds.

## Lane prompt (fill in the <...>)

> You are shipping Crater Bowl issue #<N> "<title>" (<labels>) as a single PR to bpenwell/CraterBowl. Another agent is
> working on #<M> in parallel (zone <zone>). Don't touch its likely files: <files>.
> Rules: read `~/Coding/football-game/AGENTS.md` (Shipping, Opening pull requests, Building your own loop, Testing),
> `docs/workflow.md` and `LOOP.md`, and follow them exactly. Specifically:
> 1. `cd ~/Coding/football-game && git fetch origin && git worktree add ../football-game-pr<N> -b <fix|feat|docs>/<N>-<slug> origin/main`. Work only there.
>    Never stash, reset or touch other worktrees, and never run a windowed game.
> 2. Claim: `gh issue edit <N> --add-label status:in-progress` + a comment naming "football-ralph", the branch and the worktree.
> 3. Bugs: reproduce first. If it no longer reproduces, close it with evidence, remove the worktree and report "stale".
> 4. Smallest complete change. Rules go in `src/sim` (pure RefCounted), visuals in `src/game`. Add tests for every acceptance bullet,
>    plus a `tests/visual/*_test.gd` screenshot for anything player-visible (`./scripts/visual_test.sh`). View the PNGs.
>    Update the owning `docs/features/<area>.md` and `ITERATIONS.md` (cite #<N>).
> 5. Every side finding gets its own new issue (`gh issue create`, labels type/P/area) at the moment you notice it.
> 6. Merge the latest `origin/main`, run `./scripts/check.sh` (must print `CHECK PASS`), `git add <your files>` only,
>    commit `<summary> (#<N>)` ending with the Co-Authored-By trailer, check `git show --stat`, push.
> 7. `gh pr create` with `### Motivation / ### Solution / ### Testing`, `Closes #<N>`, check.sh output, inline screenshots pushed
>    to an orphan `pr-evidence/<PR#>` branch (raw.githubusercontent URLs), and the Claude Code attribution line.
>    If `gh pr edit` fails, use `gh api -X PATCH repos/bpenwell/CraterBowl/pulls/<PR#> -f body=...`.
> 8. `gh issue comment <N> --body "PR #<PR#> open for review."` Never merge.
> 9. If you hit a usage/rate limit or can't finish: push what you have as a draft PR (`--draft`) if it's coherent.
>    Otherwise remove `status:in-progress` and comment where it stands.
> Report: PR URL, check.sh result, issues opened, anything left undone.

## Stopping

Stop when an agent or tool call fails with a usage/rate limit, or `pick.sh` returns nothing. Before stopping:
- Release claims for anything unfinished: remove `status:in-progress` and comment where it stands, then push a draft PR if the work is coherent.
- Leave worktrees with open PRs in place. `/football-janitor` cleans them up after merge.
- Report a table with issue, lane, PR, check.sh result and issues opened, end with a `result:` line, and save notable lessons to memory.

## Gotchas

- `pick.sh` only sees labels. Two issues in different zones can still touch `src/game/main.gd` or `tests/game_flow.gd`, so check touch points.
  `game_flow.gd` steps share one frame timeline: each PR must name the unused window it took.
- check.sh takes 3–4 min and several lanes share the machine. Run it only once a lane's change is done, not after every edit.
- A test that launches the real game can trip smoke.sh's user-data guard. Rerun before blaming the change.
