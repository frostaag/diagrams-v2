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
    
    # Validate required parameters
    if [[ -z "$webhook_url" ]]; then
        echo "Error: Teams webhook URL is required"
        return 1
    fi
    
    # Default values
    color="${color:-0076D7}"  # Blue for success, use "FF0000" for failures
    subtitle="${subtitle:-Notification at $(date '+%Y-%m-%d %H:%M:%S')}"
    repository="${repository:-Unknown repository}"
    commit="${commit:-Unknown commit}"
    workflow="${workflow:-Unknown workflow}"
    
    # Get workflow run URL
    local workflow_run_url=""
    if [[ -n "$repository" && -n "$run_id" ]]; then
        workflow_run_url="https://github.com/${repository}/actions/runs/${run_id}"
    fi
    
    # Format commit hash for display
    local commit_display="${commit:0:7}"
    if [[ -n "$repository" && -n "$commit" ]]; then
        commit_display="[${commit:0:7}](https://github.com/${repository}/commit/${commit})"
    fi
    
    # Add date information
    local current_date=$(date '+%Y-%m-%d')
    local current_time=$(date '+%H:%M:%S')
    
    # Create the payload for Teams webhook with richer formatting
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
          "name": "Date",
          "value": "${current_date}"
        },
        {
          "name": "Time",
          "value": "${current_time}"
        },
        {
          "name": "Repository",
          "value": "${repository}"
        },
        {
          "name": "Commit",
          "value": "${commit_display}"
        },
        {
          "name": "Workflow",
          "value": "${workflow}"
        }
      ],
      "markdown": true,
      "text": "${message}"
    }
  ]
EOF

    # Add potentialAction if run_id is provided
    if [[ -n "$workflow_run_url" ]]; then
        payload+=$(cat <<EOF
,
  "potentialAction": [
    {
      "@type": "OpenUri",
      "name": "View Workflow Run",
      "targets": [
        {
          "os": "default",
          "uri": "${workflow_run_url}"
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
    
    echo "Sending Teams notification with webhook URL (partial): ${webhook_url:0:15}..."
    
    # Send the notification with response capturing and retry logic
    local max_retries=3
    local retry=0
    local success=false
    
    while [[ $retry -lt $max_retries && "$success" != "true" ]]; do
        echo "Attempt $((retry+1)) to send Teams notification..."
        
        local response=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" -d "$payload" "$webhook_url")
        local http_code=$(echo "$response" | tail -n1)
        local response_body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" == "200" ]]; then
            echo "✅ Teams notification sent successfully (HTTP 200)"
            success=true
        else
            echo "❌ Failed to send Teams notification: HTTP $http_code"
            echo "Response: $response_body"
            
            retry=$((retry+1))
            if [[ $retry -lt $max_retries ]]; then
                echo "Retrying in 3 seconds..."
                sleep 3
            fi
        fi
    done
    
    if [[ "$success" != "true" ]]; then
        echo "Error: Failed to send Teams notification after $max_retries attempts"
        return 1
    fi
    
    return 0
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
