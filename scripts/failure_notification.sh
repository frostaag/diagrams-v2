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

# Create failure message
ERROR_MESSAGE="The Draw.io processing workflow failed.<br><br>"
ERROR_MESSAGE+="**Possible issues to check:**<br>"
ERROR_MESSAGE+="- Draw.io installation problems<br>"
ERROR_MESSAGE+="- File access permissions<br>"
ERROR_MESSAGE+="- SharePoint connectivity<br>"
ERROR_MESSAGE+="- Invalid diagram files<br><br>"
ERROR_MESSAGE+="Please check the [workflow logs](https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) for details."

# Escape special characters in message to avoid JSON issues
ERROR_MESSAGE=$(echo "$ERROR_MESSAGE" | sed 's/"/\\"/g')

# Send notification
./scripts/send_teams_notification.sh \
  "$WEBHOOK_URL" \
  "⚠️ Draw.io Processing Failed" \
  "Error occurred at $(date '+%Y-%m-%d %H:%M:%S')" \
  "$ERROR_MESSAGE" \
  "FF0000" \
  "$GITHUB_REPOSITORY" \
  "$GITHUB_SHA" \
  "$GITHUB_WORKFLOW" \
  "$GITHUB_RUN_ID"
