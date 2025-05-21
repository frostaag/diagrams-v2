#!/bin/bash
# Script for sending failure notification to Teams
# This is separated out to avoid GitHub Actions validation issues

# Get parameters from environment
WEBHOOK_URL="$1"
GITHUB_REPOSITORY="$2"
GITHUB_SHA="$3"
GITHUB_WORKFLOW="$4"
GITHUB_RUN_ID="$5"

# Create failure message
ERROR_MESSAGE="The Draw.io processing workflow failed.<br><br>"
ERROR_MESSAGE+="**Possible issues to check:**<br>"
ERROR_MESSAGE+="- Draw.io installation problems<br>"
ERROR_MESSAGE+="- File access permissions<br>"
ERROR_MESSAGE+="- SharePoint connectivity<br>"
ERROR_MESSAGE+="- Invalid diagram files<br><br>"
ERROR_MESSAGE+="Please check the [workflow logs](https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) for details."

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
