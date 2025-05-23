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

# Extract user's display name from git config or use environment variable
# Prioritize the AUTHOR_NAME passed from the workflow (which is from git log '%an' - full name)
DISPLAY_NAME="${AUTHOR_NAME}" 

# If empty, try to extract from commit
if [[ -z "$DISPLAY_NAME" ]]; then
    DISPLAY_NAME=$(git log -1 --format="%an") # author name, full name not username
fi

# If still empty, fall back to GitHub actor with pretty formatting
if [[ -z "$DISPLAY_NAME" ]]; then
    # Try to format the GitHub actor to look more like a name if possible
    if [[ -n "$GITHUB_ACTOR" ]]; then
        # Convert username like "john-doe" to "John Doe"
        FORMATTED_NAME=$(echo "$GITHUB_ACTOR" | sed 's/-/ /g' | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
        DISPLAY_NAME="$FORMATTED_NAME"
    else
        DISPLAY_NAME="System"
    fi
fi

# Create success message in the requested format
# The main title is now handled by the send_teams_notification.sh script's title parameter
MESSAGE="**Repository**<br>"
MESSAGE+="${GITHUB_REPOSITORY}<br><br>"
MESSAGE+="**Workflow**<br>"
MESSAGE+="${GITHUB_WORKFLOW}<br><br>"
MESSAGE+="**Commit**<br>"
MESSAGE+="${GITHUB_SHA}<br><br>"
MESSAGE+="**Triggered by**<br>"
MESSAGE+="${DISPLAY_NAME}<br><br>"
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
