#!/bin/bash
# Script for sending failure notification to Teams
# This is separated out to avoid GitHub Actions validation issues

# Get parameters from environment
WEBHOOK_URL="$1"
GITHUB_REPOSITORY="${2:-Unknown}"
GITHUB_SHA="${3:-Unknown}"
GITHUB_WORKFLOW="${4:-Unknown}"
GITHUB_RUN_ID="${5:-Unknown}"
ERROR_MESSAGE="${6:-No specific error message provided}"

# Validate webhook URL
if [[ -z "$WEBHOOK_URL" ]]; then
    echo "Warning: No Teams webhook URL provided. Notification will not be sent."
    exit 0
fi

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

# Create failure message in the requested format
FAILURE_MESSAGE="❌ Draw.io Conversion Workflow Failed<br>"
FAILURE_MESSAGE+="GitHub Actions workflow run failed<br><br>"
FAILURE_MESSAGE+="**Repository**<br>"
FAILURE_MESSAGE+="${GITHUB_REPOSITORY}<br><br>"
FAILURE_MESSAGE+="**Workflow**<br>"
FAILURE_MESSAGE+="${GITHUB_WORKFLOW}<br><br>"
FAILURE_MESSAGE+="**Commit**<br>"
FAILURE_MESSAGE+="${GITHUB_SHA}<br><br>"
FAILURE_MESSAGE+="**Triggered by**<br>"
FAILURE_MESSAGE+="${DISPLAY_NAME}<br><br>"
FAILURE_MESSAGE+="**Run ID**<br>"
FAILURE_MESSAGE+="${GITHUB_RUN_ID}"

# Add error information if provided
if [[ "$ERROR_MESSAGE" != "No specific error message provided" ]]; then
    FAILURE_MESSAGE+="<br><br>**Error Details**<br>"
    FAILURE_MESSAGE+="<pre>${ERROR_MESSAGE}</pre>"
fi

# Escape special characters in message to avoid JSON issues
FAILURE_MESSAGE=$(echo "$FAILURE_MESSAGE" | sed 's/"/\\"/g')

# Send notification
./scripts/send_teams_notification.sh \
  "$WEBHOOK_URL" \
  "❌ Draw.io Conversion Workflow Failed" \
  "GitHub Actions workflow run failed" \
  "$FAILURE_MESSAGE" \
  "FF0000" \
  "$GITHUB_REPOSITORY" \
  "$GITHUB_SHA" \
  "$GITHUB_WORKFLOW" \
  "$GITHUB_RUN_ID"
