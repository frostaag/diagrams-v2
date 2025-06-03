#!/bin/bash
# Script for sending failure notification to Teams
# This is separated out to avoid GitHub Actions validation issues

# Get parameters from environment
WEBHOOK_URL="$1"
GITHUB_REPOSITORY="${2:-Unknown}"
GITHUB_SHA="${3:-Unknown}"
GITHUB_WORKFLOW="${4:-Unknown}"
GITHUB_RUN_ID="${5:-Unknown}"

# Validate webhook URL
if [[ -z "$WEBHOOK_URL" ]]; then
    echo "Warning: No Teams webhook URL provided. Notification will not be sent."
    exit 0
fi

# Create failure message in the requested format
ERROR_MESSAGE="❌ Draw.io Conversion Workflow Failed<br>"
ERROR_MESSAGE+="GitHub Actions workflow run failed<br><br>"
ERROR_MESSAGE+="**Repository**<br>"
ERROR_MESSAGE+="${GITHUB_REPOSITORY}<br><br>"
ERROR_MESSAGE+="**Workflow**<br>"
ERROR_MESSAGE+="${GITHUB_WORKFLOW}<br><br>"
ERROR_MESSAGE+="**Commit**<br>"
ERROR_MESSAGE+="${GITHUB_SHA}<br><br>"
ERROR_MESSAGE+="**Triggered by**<br>"
ERROR_MESSAGE+="${GITHUB_ACTOR:-System}<br><br>"
ERROR_MESSAGE+="**Run ID**<br>"
ERROR_MESSAGE+="${GITHUB_RUN_ID}"

# Escape special characters in message to avoid JSON issues
ERROR_MESSAGE=$(echo "$ERROR_MESSAGE" | sed 's/"/\\"/g')

# Send notification
./scripts/send_teams_notification.sh \
  "$WEBHOOK_URL" \
  "❌ Draw.io Conversion Workflow Failed" \
  "GitHub Actions workflow run failed" \
  "$ERROR_MESSAGE" \
  "FF0000" \
  "$GITHUB_REPOSITORY" \
  "$GITHUB_SHA" \
  "$GITHUB_WORKFLOW" \
  "$GITHUB_RUN_ID"
