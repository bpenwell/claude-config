#!/usr/bin/env bash
# football-janitor: tidy the Crater Bowl (football-game) checkouts on this machine.
#
#   janitor.sh            dry run: print the plan, change nothing
#   janitor.sh --apply    do the safe actions in the plan
#   janitor.sh --apply --remote   also delete merged branches on origin (no open PR)
#
# Safe = nothing can be lost: a worktree/clone is removed only when it is clean,
# its HEAD is already in origin/main, no open PR uses its branch, and no live
# process (Claude/Codex/Godot session) has its cwd inside it. Everything else is
# reported as KEEP with the reason. Scope: football-game only.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0   # never rewrite other sessions' index files while inspecting

APPLY=0; REMOTE=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --remote) REMOTE=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

CODING="${FOOTBALL_ROOT:-$HOME/Coding}"
MAIN="$CODING/football-game"                       # canonical checkout (never removed)
PROTECT_DIRS="${FOOTBALL_PROTECT:-$CODING/football-game-codex}"   # Codex gap runner's clone (cron)
PROTECT_BRANCHES="main codex-gaps"
USERDATA="$HOME/.local/share/crater-bowl"
FRESH_WT_MIN="${FOOTBALL_FRESH_MIN:-30}"    # a worktree touched this recently may be mid-task
FRESH_TMP_MIN="${FOOTBALL_FRESH_TMP_MIN:-60}"

[ -d "$MAIN/.git" ] || { echo "no football-game checkout at $MAIN"; exit 1; }
cd "$MAIN"
git fetch -q --prune origin || echo "WARN: fetch failed; using cached origin/main"
OM=$(git rev-parse origin/main)

act() {   # act "description" cmd...
  local what=$1; shift
  if [ $APPLY -eq 1 ]; then
    if "$@" >/dev/null 2>&1; then echo "  DONE   $what"; else echo "  FAILED $what"; fi
  else
    echo "  PLAN   $what"
  fi
}
keep() { echo "  KEEP   $1"; }

# cwd of every live process -> "is anyone working in this dir?"
LIVE=$(for p in /proc/[0-9]*; do readlink "$p/cwd" 2>/dev/null; done | sort -u)
live_in() { grep -qxF "$1" <<<"$LIVE" || grep -q "^$1/" <<<"$LIVE"; }

OPEN_PR_BRANCHES=""
if command -v gh >/dev/null; then
  OPEN_PR_BRANCHES=$(gh pr list --state open --limit 200 --json headRefName -q '.[].headRefName' 2>/dev/null || true)
fi
has_open_pr() { grep -qxF "$1" <<<"$OPEN_PR_BRANCHES"; }
protected_branch() { for p in $PROTECT_BRANCHES; do [ "$1" = "$p" ] && return 0; done; return 1; }
protected_dir() { for p in $PROTECT_DIRS; do [ "$1" = "$p" ] && return 0; done; return 1; }
# Recent activity = the worktree's own reflog (commit/checkout/reset) or any file edited
# outside .git/.godot. (Not the index mtime: plain `git status` rewrites that.)
fresh_wt() {
  local t now; now=$(date +%s)
  t=$(git -C "$1" log -g -1 --format=%ct HEAD 2>/dev/null || echo 0)
  [ $(( now - ${t:-0} )) -lt $(( FRESH_WT_MIN * 60 )) ] && return 0
  [ -n "$(find "$1" \( -name .git -o -name .godot \) -prune -o -type f -mmin -"$FRESH_WT_MIN" -print -quit 2>/dev/null)" ]
}
declare -A REMOVING
merged() { git -C "$1" merge-base --is-ancestor HEAD "$OM" 2>/dev/null; }

echo "== Crater Bowl janitor ($( [ $APPLY -eq 1 ] && echo APPLY || echo 'DRY RUN: nothing changes; rerun with --apply'))"
echo "   origin/main = $(git log -1 --format='%h %s' "$OM")"

echo; echo "== Canonical checkout ($MAIN)"
if live_in "$MAIN"; then
  keep "main checkout: a live session is working in it; not updating"
elif [ -n "$(git status --porcelain)" ] || [ -f .git/MERGE_HEAD ]; then
  keep "main checkout has uncommitted changes or a merge in progress: not updating"
elif [ "$(git branch --show-current)" = main ] && git merge-base --is-ancestor HEAD "$OM"; then
  if [ "$(git rev-parse HEAD)" != "$OM" ]; then act "fast-forward main to origin/main" git merge -q --ff-only "$OM"; else echo "  OK     main is up to date"; fi
else
  keep "main checkout is not on main or has unpushed commits: review by hand"
fi

echo; echo "== Worktrees and clones"
declare -A SEEN
while read -r wt; do
  [ -n "$wt" ] && SEEN["$wt"]=1
done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
CANDIDATES=$( { git worktree list --porcelain | sed -n 's/^worktree //p'; ls -d "$CODING"/football-game-* /tmp/crater-push.* 2>/dev/null; } | sort -u)
for d in $CANDIDATES; do
  [ "$d" = "$MAIN" ] && continue
  [ -d "$d" ] || { act "prune missing worktree record $d" git worktree prune; continue; }
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || { keep "$d (not a git checkout; check by hand)"; continue; }
  b=$(git -C "$d" branch --show-current); b=${b:-detached}
  if protected_dir "$d"; then keep "$d [$b]: protected"; continue; fi
  if live_in "$d"; then keep "$d [$b]: a live process is working in it"; continue; fi
  dirty=$(git -C "$d" status --porcelain | wc -l)
  if fresh_wt "$d"; then keep "$d [$b]: touched in the last ${FRESH_WT_MIN} min (may be mid-task)"; continue; fi
  if [ "$dirty" -gt 0 ]; then keep "$d [$b]: $dirty uncommitted change(s)"; continue; fi
  if ! merged "$d"; then keep "$d [$b]: $(git -C "$d" rev-list --count "$OM"..HEAD) commit(s) not in origin/main (open a PR)"; continue; fi
  if [ "$b" != detached ] && has_open_pr "$b"; then keep "$d [$b]: open PR uses this branch"; continue; fi
  size=$(du -sh "$d" 2>/dev/null | cut -f1)
  REMOVING["$d"]=1
  if [ -n "${SEEN[$d]:-}" ]; then
    act "remove worktree $d [$b] ($size, merged, clean)" git worktree remove --force "$d"
  else
    act "delete clone $d [$b] ($size, merged, clean)" rm -rf "$d"
  fi
done
[ $APPLY -eq 1 ] && git worktree prune

echo; echo "== Local branches"
for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
  protected_branch "$b" && continue
  if git worktree list --porcelain | grep -qx "branch refs/heads/$b"; then continue; fi   # still checked out
  if git merge-base --is-ancestor "$b" "$OM"; then
    has_open_pr "$b" && { keep "branch $b: open PR"; continue; }
    act "delete merged branch $b" git branch -D "$b"
  else
    keep "branch $b: $(git rev-list --count "$OM".."$b") commit(s) not in origin/main"
  fi
done

echo; echo "== Remote branches on origin $( [ $REMOTE -eq 1 ] || echo '(report only; --remote to delete)')"
for rb in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v '^origin$\|^origin/HEAD$'); do
  b=${rb#origin/}
  protected_branch "$b" && continue
  if git merge-base --is-ancestor "$rb" "$OM" && ! has_open_pr "$b"; then
    if [ $REMOTE -eq 1 ]; then act "delete merged origin/$b" git push -q origin --delete "$b"; else echo "  MERGED origin/$b (deletable)"; fi
  else
    keep "origin/$b: unmerged or open PR"
  fi
done

echo; echo "== Generated artifacts (gitignored; all regenerate)"
for d in "$MAIN" $(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -v "^$MAIN\$"); do
  [ -d "$d" ] || continue
  [ -n "${REMOVING[$d]:-}" ] && continue   # whole worktree goes anyway
  if live_in "$d"; then keep "artifacts in $d: a live process is working there"; continue; fi
  for junk in build .parity-shots tools/__pycache__ .flow-output.log .menu-flow.log .smoke-output.log .test-output.log \
              .net-host.log .net-client.log .parity-smoke.log .mm-a.log .mm-b.log .mm-server.log; do
    p="$d/$junk"
    [ -e "$p" ] || continue
    git -C "$d" check-ignore -q "$junk" || { keep "$p is not gitignored"; continue; }
    act "delete $p ($(du -sh "$p" | cut -f1))" rm -rf "$p"
  done
  # Untracked (not ignored) images are someone's: report, don't delete.
  git -C "$d" ls-files --others --exclude-standard -- '*.png' '*.jpg' '*.jpeg' '*.webp' '*.gif' | sed "s|^|  REVIEW untracked image $d/|"
done

echo; echo "== Temp screenshots / scratch dirs"
for p in /tmp/crater-* /tmp/fourth-and-long-shots* /tmp/fl-userdata.* /tmp/fl-check-*; do
  [ -e "$p" ] || continue
  live_in "$p" && { keep "$p: in use"; continue; }
  [ -n "$(find "$p" -maxdepth 0 -mmin -"$FRESH_TMP_MIN" 2>/dev/null)" ] && { keep "$p: modified in the last ${FRESH_TMP_MIN} min"; continue; }
  case "$p" in /tmp/crater-push.*) continue ;; esac   # handled as a worktree above
  act "delete $p ($(du -sh "$p" 2>/dev/null | cut -f1))" rm -rf "$p"
done

echo; echo "== Game user data ($USERDATA)"
for p in "$USERDATA"/test_* "$USERDATA"/test_flow_replays; do
  [ -e "$p" ] && act "delete test leftover $p" rm -rf "$p"
done
echo "  KEEP   real profile/settings/replays (player data; never touched)"

echo; [ $APPLY -eq 1 ] && echo "== Done." || echo "== Dry run only. Review, then: $0 --apply"
