#!/usr/bin/env bash
# football-ralph picker: print a HIGH and a LOW Crater Bowl issue that live in different code zones.
#
#   pick.sh                 # print the pair as two TSV lines: lane  number  zone  labels  title
#   pick.sh --list          # print every eligible issue with its lane and zone
#   pick.sh --exclude 12,40 # skip these issue numbers too (ones you just shipped or abandoned)
#
# Eligible = open, not type:decision, not status:in-progress|blocked|needs-decision, and no open PR
# that mentions "#N" (title, body or branch fix/N-...).
# HIGH lane: type:bug first, then P0, then P1 (oldest first within each).
# LOW lane:  P2 (bugs, then improvement/tech-debt/docs, then features; oldest first), in a zone different from HIGH's and sharing no area label.
set -euo pipefail
REPO="${FOOTBALL_REPO:-bpenwell/CraterBowl}"
MODE=pair EXCLUDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE=list ;;
    --exclude) EXCLUDE="$2"; shift ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done

issues=$(gh issue list --repo "$REPO" --state open --limit 300 --json number,title,labels,createdAt)
prs=$(gh pr list --repo "$REPO" --state open --limit 100 --json title,body,headRefName)
# Issue numbers referenced by open PRs (#N in title/body, or branch <type>/N-slug).
taken=$(jq -r '.[] | (.title + " " + (.body // "")), .headRefName' <<<"$prs" \
  | { grep -oE '#[0-9]+|/[0-9]+-' || true; } | tr -dc '0-9\n' | sort -u | paste -sd, -)
taken="${taken},${EXCLUDE}"

jq -r --arg taken "$taken" --arg mode "$MODE" '
  def zone:
    # Code zones = parts of the tree that rarely touch the same files.
    if   any(.[]; . == "type:docs") then "docs"
    elif any(.[]; . == "area:process") then "docs"
    elif any(.[]; . == "area:infra") then "infra"            # scripts/, tools/, export, CI
    elif any(.[]; . == "area:online" or . == "area:netcode" or . == "area:social") then "net"  # src/net, lobby UI
    elif any(.[]; . == "area:presentation" or . == "area:audio" or . == "area:replays" or . == "area:ui"
                  or . == "area:accessibility" or . == "area:chaosball" or . == "area:training") then "view"  # src/game, src/ui
    else "sim" end;                                         # src/sim rules/movement/bots/kicking/progression
  ($taken | split(",") | map(select(. != "") | tonumber)) as $skip
  | map({n: .number, t: .title, c: .createdAt, l: [.labels[].name]})
  | map(select(.n as $n | ($skip | index($n)) | not))
  | map(select(.l | any(.[]; . == "type:decision" or . == "status:in-progress" or . == "status:blocked" or . == "status:needs-decision") | not))
  | map(. + {z: (.l | zone), bug: (.l | index("type:bug") != null),
             p: (if (.l | index("P0")) then 0 elif (.l | index("P1")) then 1 else 2 end)})
  | map(. + {lane: (if .p == 2 then "LOW" else "HIGH" end)})
  | (map(select(.lane == "HIGH")) | sort_by([(if .bug then 0 else 1 end), .p, .c])) as $high
  | (map(select(.lane == "LOW"))  | sort_by([(if .bug then 0 elif (.l | index("type:feature")) then 2 else 1 end), .c])) as $low
  | def row: [.lane, (.n|tostring), .z, (.l | join(",")), .t] | @tsv;
    if $mode == "list" then ($high + $low)[] | row
    else
      ($high[0]) as $h
      | (if $h == null then $low[0]
         else [$low[] | select(.z != $h.z and ((.l - (.l - $h.l)) | map(select(startswith("area:"))) | length) == 0)][0]
         end) as $lo
      | ([$h, $lo] | map(select(. != null)))[] | row
    end
' <<<"$issues"
