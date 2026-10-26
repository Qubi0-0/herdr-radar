#!/usr/bin/env bash
# Put idle Claude sessions to sleep: the agent exits (its transcript stays on
# disk) and bin/agent-sleeper.sh takes the pane over, keeping the session in
# the Agents list as a faded "💤" row. Enter in the pane resumes it.
#
#   sleep-agent.sh <pane_id>...          the given panes
#   sleep-agent.sh --idle-days N         every idle Claude pane idle >= N days
set -euo pipefail

sleeper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-sleeper.sh"
self="${HERDR_PANE_ID:-}"

sleep_pane() {
  local pane=$1 info agent status session title
  info=$(herdr pane get "$pane" | jq -c '.result.pane')
  agent=$(jq -r '.agent // ""' <<<"$info")
  status=$(jq -r '.agent_status' <<<"$info")
  session=$(jq -r '.agent_session.value // ""' <<<"$info")
  title=$(jq -r '.terminal_title_stripped // ""' <<<"$info")
  [ -n "$title" ] || title=$session
  if [ "$pane" = "$self" ]; then echo "$pane: own pane, skipped"; return; fi
  if [ "$agent" != claude ] || [ "$status" != idle ]; then echo "$pane: not an idle Claude ($agent/$status), skipped"; return; fi
  if [ -z "$session" ]; then echo "$pane: no session id, skipped"; return; fi
  if ! compgen -G "$HOME/.claude/projects/*/$session.jsonl" >/dev/null; then echo "$pane: no transcript for $session, skipped"; return; fi

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

if [ "${1:-}" = --idle-days ]; then
  days=${2:?--idle-days needs a number}
  mapfile -t panes < <(herdr pane list | jq -r --argjson d "$days" '.result.panes[]
    | select(.agent == "claude" and .agent_status == "idle")
    | select((.tokens.title_idle_stale // "") | capture("^\\((?<n>[0-9]+)d\\)").n | tonumber >= $d)
    | .pane_id')
else
  panes=("$@")
fi
[ ${#panes[@]} -gt 0 ] || { echo "nothing to put to sleep"; exit 0; }
for pane in "${panes[@]}"; do sleep_pane "$pane"; done
