#!/bin/bash
# Script to send Microsoft Teams notifications

set -eo pipefail

# Function to send Teams notification
send_teams_notification() {
    local webhook_url="$1"
    local title="$2"
    local subtitle="$3"
    local message="$4"
    local color="$5"
    local repository="$6"
    local commit="$7"
    local workflow="$8"
    local run_id="$9"
    
    # Default values
    color="${color:-0076D7}"  # Blue for success, use "FF0000" for failures
    subtitle="${subtitle:-Notification at $(date '+%Y-%m-%d %H:%M:%S')}"
    repository="${repository:-Unknown repository}"
    commit="${commit:-Unknown commit}"
    workflow="${workflow:-Unknown workflow}"
    
    # Create the payload for Teams webhook
    local payload=$(cat <<EOF
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "${color}",
  "summary": "${title}",
  "sections": [
    {
      "activityTitle": "${title}",
      "activitySubtitle": "${subtitle}",
      "activityImage": "https://raw.githubusercontent.com/jgraph/drawio-desktop/master/build/icon.png",
      "facts": [
        {
          "name": "Repository",
          "value": "${repository}"
        },
        {
          "name": "Commit",
          "value": "${commit}"
        },
        {
          "name": "Workflow",
          "value": "${workflow}"
        }
      ],
      "text": "${message}"
    }
  ]
EOF

    # Add potentialAction if run_id is provided
    if [[ -n "$run_id" ]]; then
        payload+=$(cat <<EOF
,
  "potentialAction": [
    {
      "@type": "OpenUri",
      "name": "View Workflow Run",
      "targets": [
        {
          "os": "default",
          "uri": "https://github.com/${repository}/actions/runs/${run_id}"
        }
      ]
    }
  ]
EOF
    )
    fi

    # Close the JSON payload
    payload+=$(cat <<EOF
}
EOF
    )
    
    # Send the notification
    curl -s -H "Content-Type: application/json" -d "$payload" "$webhook_url"
    
    echo "Teams notification sent successfully."
}

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if required arguments are provided
    if [[ $# -lt 3 ]]; then
        echo "Usage: $0 <webhook_url> <title> <message> [color] [repository] [commit] [workflow] [run_id]"
        exit 1
    fi
    
    send_teams_notification "$@"
fi
