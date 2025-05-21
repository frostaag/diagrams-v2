#!/bin/bash
# Script for sending success notification to Teams
# This is separated out to avoid GitHub Actions validation issues

# Get parameters from environment
WEBHOOK_URL="$1"
GITHUB_REPOSITORY="$2"
GITHUB_SHA="$3"
GITHUB_WORKFLOW="$4"
GITHUB_RUN_ID="$5"

# Extract processed files from git
PROCESSED_FILES=$(git diff --name-only HEAD~1 HEAD -- 'png_files/*.png' | sed 's|png_files/||g' | sed 's|.png$||g')

# Create success message
MESSAGE="**Draw.io Diagrams Processing Completed**<br><br>"

# Add file list if we have processed files
if [ -n "$PROCESSED_FILES" ]; then
  MESSAGE+="Successfully processed the following diagrams:<br>"
  echo "$PROCESSED_FILES" | while read -r file; do
    if [ -n "$file" ]; then
      MESSAGE+="- $file<br>"
    fi
  done
else
  MESSAGE+="Workflow completed successfully, but no diagrams were processed."
fi

# Escape special characters in message to avoid JSON issues
MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g')

# Send notification
./scripts/send_teams_notification.sh \
  "$WEBHOOK_URL" \
  "Draw.io Diagrams Processing Update" \
  "Process completed at $(date '+%Y-%m-%d %H:%M:%S')" \
  "$MESSAGE" \
  "0076D7" \
  "$GITHUB_REPOSITORY" \
  "$GITHUB_SHA" \
  "$GITHUB_WORKFLOW" \
  "$GITHUB_RUN_ID"
