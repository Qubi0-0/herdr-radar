#!/usr/bin/env bash
# Stand-in for a Claude session put to sleep by sleep-agent.sh. While it runs
# it holds the pane as an idle agent labelled "asleep", which the radar draws
# as a faded "💤 <title>" row, so the session keeps its place in the Agents
# list. Herdr drops a self-reported agent only once the pane's shell is idle
# again, which this foreground process prevents. Enter resumes the session in
# place; Ctrl+C leaves a plain shell.
#
#   agent-sleeper <session_id> <title>
#
# Installed on PATH as `agent-sleeper` (a symlink): Herdr accepts only a plain
# command name as the resume command it replays after a restart.
set -u

session=${1:?session id}
title=${2:?title}
pane=${HERDR_PANE_ID:?not inside a herdr pane}
source_id=herdr-sleep

release() {
  herdr pane release-agent "$pane" --source "$source_id" --agent asleep >/dev/null 2>&1
  herdr pane report-metadata "$pane" --source "$source_id" --clear-token asleep_session >/dev/null 2>&1
}

printf '\e]0;%s\a' "$title"
# Herdr keeps a session id only from official integrations; the radar reads
# this token instead to date the row from the session's transcript.
herdr pane report-metadata "$pane" --source "$source_id" --token "asleep_session=$session" >/dev/null
herdr pane report-agent "$pane" --source "$source_id" --agent asleep --state idle \
  --agent-session-id "$session" >/dev/null
# A restarted Herdr replays this command, so the pane comes back asleep rather
# than as a live session. Herdr rejects apostrophes in a resume command.
herdr pane report-agent-session "$pane" --source "$source_id" --agent asleep \
  --agent-session-id "$session" -- agent-sleeper "$session" "${title//\'/}" >/dev/null
trap 'release; exit 130' INT TERM

clear
printf '\n  💤 %s\n\n  Enter   wznów sesję (claude --resume %s)\n  Ctrl+C  zwykły shell\n' "$title" "$session"
read -r _
release
exec claude --resume "$session"
