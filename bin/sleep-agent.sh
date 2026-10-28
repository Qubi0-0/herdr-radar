#!/usr/bin/env bash
# Put idle Claude sessions to sleep: the agent exits (its transcript stays on
# disk) and bin/agent-sleeper.sh takes the pane over, keeping the session in
# the Agents list as a faded "💤" row. Enter in the pane resumes it.
#
#   sleep-agent.sh <pane_id>...          the given panes
#   sleep-agent.sh --idle-hours N        every idle Claude pane untouched >= N hours,
#                                        except the focused one
#   sleep-agent.sh --dry-run ...         report what would be put to sleep
#
# A session is left alone while its prompt holds unsent text (`/exit` would be
# appended to it and sent) or it still runs background agents, shells or tasks.
set -euo pipefail

sleeper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-sleeper.sh"
activity="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/hhdebb.herdr-radar/activity.json"
self="${HERDR_PANE_ID:-}"
dry_run=0
if [ "${1:-}" = --dry-run ]; then dry_run=1; shift; fi

transcript() { compgen -G "$HOME/.claude/projects/*/$1.jsonl" | head -1; }

# Epoch ms of the session's last activity: the later of the radar's last
# "working" stamp for the pane and the transcript's last user/assistant record.
last_active_ms() {
  local pane=$1 session=$2 stamp file ts from_transcript=0
  stamp=$(jq -r --arg p "$pane" '.[$p] // 0' "$activity" 2>/dev/null || echo 0)
  file=$(transcript "$session")
  if [ -n "$file" ]; then
    ts=$(tail -c 262144 "$file" |
      jq -rR 'fromjson? | select(.type == "user" or .type == "assistant") | .timestamp // empty' | tail -1)
    [ -n "$ts" ] && from_transcript=$(date -d "$ts" +%s%3N)
  fi
  echo $((stamp > from_transcript ? stamp : from_transcript))
}

# The bottom of the visible screen: the prompt line must be a bare `❯`, and
# the footer must not report background agents, shells or tasks. (The constant
# "← N agents" hint every session shows is not background work.)
safe_to_exit() {
  local screen prompt
  screen=$(herdr pane read "$1" --source visible --lines 80)
  prompt=$(grep '^❯' <<<"$screen" | tail -1 | sed 's/\xc2\xa0/ /g; s/^❯[[:space:]]*//')
  if ! grep -q '^❯' <<<"$screen"; then echo "no prompt line on screen"; return 1; fi
  if [ -n "$prompt" ]; then echo "unsent text in the prompt"; return 1; fi
  if tail -4 <<<"$screen" | grep -Eqi '[0-9]+ (background (agents?|tasks?)|shells?|tasks?)\b'; then
    echo "background work still running"
    return 1
  fi
}

sleep_pane() {
  local pane=$1 info agent status session title reason
  info=$(herdr pane get "$pane" | jq -c '.result.pane')
  agent=$(jq -r '.agent // ""' <<<"$info")
  status=$(jq -r '.agent_status' <<<"$info")
  session=$(jq -r '.agent_session.value // ""' <<<"$info")
  title=$(jq -r '.terminal_title_stripped // ""' <<<"$info")
  [ -n "$title" ] || title=$session
  if [ "$pane" = "$self" ]; then echo "$pane: own pane, skipped"; return; fi
  if [ "$agent" != claude ] || [ "$status" != idle ]; then echo "$pane: not an idle Claude ($agent/$status), skipped"; return; fi
  if [ -z "$session" ]; then echo "$pane: no session id, skipped"; return; fi
  if [ -z "$(transcript "$session")" ]; then echo "$pane: no transcript for $session, skipped"; return; fi
  if ! reason=$(safe_to_exit "$pane"); then echo "$pane: $reason, skipped"; return; fi
  if [ "$dry_run" = 1 ]; then echo "$pane: would sleep ($title)"; return; fi

  herdr pane send-text "$pane" "/exit" >/dev/null
  sleep 0.5
  herdr pane send-keys "$pane" enter >/dev/null
  for _ in $(seq 40); do
    agent=$(herdr pane get "$pane" | jq -r '.result.pane.agent // ""')
    [ -z "$agent" ] && break
    sleep 0.5
  done
  if [ -n "$agent" ]; then echo "$pane: Claude did not exit, check it"; return; fi

  sleep 0.3
  herdr pane run "$pane" "$(printf '%q %q %q' "$sleeper" "$session" "$title")" >/dev/null
  echo "$pane: asleep ($title)"
}

if [ "${1:-}" = --idle-hours ]; then
  hours=${2:?--idle-hours needs a number}
  cutoff=$(($(date +%s%3N) - hours * 3600000))
  listing=$(herdr pane list 2>/dev/null) || { echo "herdr is not running"; exit 0; }
  panes=()
  while IFS=$'\t' read -r pane session; do
    [ -n "$session" ] || continue
    at=$(last_active_ms "$pane" "$session")
    # 0 means no stamp and no transcript: the age is unknown, not old.
    [ "$at" -gt 0 ] && [ "$at" -le "$cutoff" ] && panes+=("$pane")
  done < <(jq -r '.result.panes[]
    | select(.agent == "claude" and .agent_status == "idle" and (.focused | not))
    | [.pane_id, (.agent_session.value // "")] | @tsv' <<<"$listing")
else
  panes=("$@")
fi
[ ${#panes[@]} -gt 0 ] || { echo "nothing to put to sleep"; exit 0; }
for pane in "${panes[@]}"; do sleep_pane "$pane"; done
