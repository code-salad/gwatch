#!/usr/bin/env bash
# Watches GitHub for unassigned, non-blocked issues and dispatches them to claude.
# Installs itself as a cron job on start, removes cron on exit/kill.
#
# Usage: ./poll_issues.sh <owner/repo>
# Requires: gh (GitHub CLI, authenticated), claude CLI

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo>}"
SCRIPT_PATH="$(realpath "$0")"
CRON_SCHEDULE="* * * * *"
CRON_TAG="# gwatch:${REPO}"
PIDFILE="/tmp/gwatch-${REPO//\//-}.pid"
LOGFILE="/tmp/gwatch-${REPO//\//-}.log"

# ── Prevent duplicate instances ──────────────────────────────────────
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Already running (PID $(cat "$PIDFILE")). Exiting."
  exit 1
fi
echo $$ > "$PIDFILE"

# ── Install cron job ────────────────────────────────────────────────
install_cron() {
  # Cron entry runs this script; output appends to log
  local cron_line="${CRON_SCHEDULE} ${SCRIPT_PATH} ${REPO} >> ${LOGFILE} 2>&1 ${CRON_TAG}"
  # Avoid duplicates
  ( crontab -l 2>/dev/null | grep -v "$CRON_TAG"; echo "$cron_line" ) | crontab -
  echo "Cron installed: ${cron_line}"
}

# ── Remove cron job + pidfile on exit ───────────────────────────────
cleanup() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up..."
  ( crontab -l 2>/dev/null | grep -v "$CRON_TAG" ) | crontab -
  rm -f "$PIDFILE"
  echo "Cron removed. Goodbye."
}
trap cleanup EXIT INT TERM

install_cron

# ── Poll for issues ─────────────────────────────────────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watching ${REPO} for unassigned, non-blocked issues..."

while true; do
  ISSUE_URL=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --assignee "" \
    --limit 50 \
    --json number,title,labels,url \
    --jq '
      [ .[] | select(
        (.labels | map(.name) | any(test("block"; "i"))) | not
      ) ] | first // empty | .url // empty
    ')

  if [[ -n "$ISSUE_URL" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found issue: ${ISSUE_URL}"
    echo "Dispatching to claude..."
    claude -p "/looper ${ISSUE_URL}" &
    # Wait before next poll to avoid double-dispatch while claude assigns the issue
    sleep 120
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No matching issues. Sleeping 60s..."
    sleep 60
  fi
done
