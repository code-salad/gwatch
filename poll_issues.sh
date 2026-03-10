#!/usr/bin/env bash
# Polls GitHub every 60 seconds for 1 unassigned, non-blocked issue.
# Usage: ./poll_issues.sh <owner/repo>
# Requires: gh (GitHub CLI), authenticated

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo>}"
INTERVAL=60

while true; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for unassigned, non-blocked issues..."

  ISSUE=$(gh issue list \
    --repo "$REPO" \
    --state open \
    --assignee "" \
    --limit 50 \
    --json number,title,labels,url \
    --jq '
      [ .[] | select(
        (.labels | map(.name) | any(test("block"; "i"))) | not
      ) ] | first // empty
    ')

  if [[ -n "$ISSUE" ]]; then
    echo "Found issue:"
    echo "$ISSUE" | jq .
    exit 0
  fi

  echo "No matching issues found. Retrying in ${INTERVAL}s..."
  sleep "$INTERVAL"
done
