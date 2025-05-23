#!/bin/bash
# Script to send fancy Microsoft Teams notifications with rich cards and adaptive elements

set -eo pipefail

# Function to send Teams notification with enhanced visualization
send_fancy_teams_notification() {
    local webhook_url="$1"
    local title="$2"
    local outcome="$3"  # Success, Partial success, or Failure
    local drawio_count="$4"
    local png_count="$5"
    local repository="$6"
    local commit="$7"
    local workflow="$8"
    local run_id="$9"
    local changelog_count="${10}"
    
    # Validate required parameters
    if [[ -z "$webhook_url" ]]; then
        echo "Error: Teams webhook URL is required"
        echo "Make sure the DIAGRAMS_TEAMS_NOTIFICATION_WEBHOOK secret is properly set in the repository settings."
        return 0  # Return success to prevent workflow failure, but log the error
    fi
    
    # Set color based on outcome
    local color="0076D7"  # Default blue
    local icon="🔄"       # Default processing icon
    
    if [[ "$outcome" == "Success" ]]; then
        color="138a07"    # Green for success
        icon="✅"
    elif [[ "$outcome" == "Partial success" ]]; then
        color="FFA500"    # Orange for partial success
        icon="⚠️"
    elif [[ "$outcome" == "Failure" ]]; then
        color="FF0000"    # Red for failures
        icon="❌"
    fi
    
    # Format commit hash for display
    local commit_display="${commit:0:7}"
    if [[ -n "$repository" && -n "$commit" ]]; then
        commit_url="https://github.com/${repository}/commit/${commit}"
        commit_display="[${commit:0:7}](${commit_url})"
    fi
    
    # Get workflow run URL
    local workflow_run_url=""
    if [[ -n "$repository" && -n "$run_id" ]]; then
        workflow_run_url="https://github.com/${repository}/actions/runs/${run_id}"
    fi
    
    # Current date and time for logging
    local current_date=$(date '+%Y-%m-%d')
    local current_time=$(date '+%H:%M:%S')
    
    # Calculate conversion rate and additional stats
    local conversion_rate=0
    if [[ $drawio_count -gt 0 ]]; then
        conversion_rate=$(( (png_count * 100) / drawio_count ))
    fi
    
    # Get repository name for display
    local repo_name=$(echo "$repository" | cut -d '/' -f 2)
    
    # Create a more visually appealing JSON payload with sections and facts
    local payload=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "${color}",
    "summary": "${title}",
    "sections": [
        {
            "activityTitle": "${icon} ${title}",
            "activitySubtitle": "Processing completed at ${current_date} ${current_time}",
            "activityImage": "https://raw.githubusercontent.com/jgraph/drawio-desktop/master/build/icon.png",
            "facts": [
                {
                    "name": "Repository",
                    "value": "${repo_name}"
                },
                {
                    "name": "Status",
                    "value": "${outcome}"
                },
                {
                    "name": "Draw.io Files",
                    "value": "${drawio_count}"
                },
                {
                    "name": "PNG Files Generated",
                    "value": "${png_count}"
                },
                {
                    "name": "Conversion Rate",
                    "value": "${conversion_rate}%"
                },
                {
                    "name": "Changelog Entries",
                    "value": "${changelog_count}"
                }
            ],
            "markdown": true
        },
        {
            "title": "Commit Information",
            "facts": [
                {
                    "name": "Commit Hash",
                    "value": "${commit_display}"
                },
                {
                    "name": "Workflow",
                    "value": "${workflow}"
                }
            ]
        }
    ],
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
        },
        {
            "@type": "OpenUri",
            "name": "View Repository",
            "targets": [
                {
                    "os": "default",
                    "uri": "https://github.com/${repository}"
                }
            ]
        }
    ]
}
EOF
)
    
    echo "Sending fancy Teams notification..."
    
    # Use curl to send the notification
    local response=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" -d "$payload" "$webhook_url")
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        echo "✅ Teams notification sent successfully (HTTP 200)"
    else
        echo "❌ Failed to send Teams notification: HTTP $http_code"
        echo "Response: $response_body"
        return 1
    fi
    
    return 0
}

# Main execution if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if required arguments are provided
    if [[ $# -lt 5 ]]; then
        echo "Usage: $0 <webhook_url> <title> <outcome> <drawio_count> <png_count> [repository] [commit] [workflow] [run_id] [changelog_count]"
        exit 1
    fi
    
    send_fancy_teams_notification "$@"
fi
