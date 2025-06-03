#!/bin/bash
# Script for sending success notification to Teams
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

# Extract processed files from git
PROCESSED_FILES=$(git diff --name-only HEAD~1 HEAD -- 'png_files/*.png' | sed 's|png_files/||g' | sed 's|.png$||g')

# Create success message in the requested format
MESSAGE="✅ Draw.io Conversion Workflow Succeeded<br>"
MESSAGE+="GitHub Actions workflow run completed successfully<br><br>"
MESSAGE+="**Repository**<br>"
MESSAGE+="${GITHUB_REPOSITORY}<br><br>"
MESSAGE+="**Workflow**<br>"
MESSAGE+="${GITHUB_WORKFLOW}<br><br>"
MESSAGE+="**Commit**<br>"
MESSAGE+="${GITHUB_SHA}<br><br>"
MESSAGE+="**Triggered by**<br>"
MESSAGE+="${AUTHOR_NAME:-${GITHUB_ACTOR:-System}}<br><br>"
MESSAGE+="**Run ID**<br>"
MESSAGE+="${GITHUB_RUN_ID}<br><br>"

# Add file list if we have processed files
if [ -n "$PROCESSED_FILES" ]; then
  MESSAGE+="**Processed Files:**<br>"
  echo "$PROCESSED_FILES" | while read -r file; do
    if [ -n "$file" ]; then
      MESSAGE+="- $file<br>"
    fi
  done
else
  MESSAGE+="No diagrams were processed in this run."
fi

# Escape special characters in message to avoid JSON issues
MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g')

# Send notification
./scripts/send_teams_notification.sh \
  "$WEBHOOK_URL" \
  "✅ Draw.io Conversion Workflow Succeeded" \
  "GitHub Actions workflow run completed successfully" \
  "$MESSAGE" \
  "00FF00" \
  "$GITHUB_REPOSITORY" \
  "$GITHUB_SHA" \
  "$GITHUB_WORKFLOW" \
  "$GITHUB_RUN_ID"
