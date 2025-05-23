#!/bin/bash
# Test script to visualize the Teams notification without actually sending it

# Set test values
TITLE="Draw.io Processing - Success"
OUTCOME="Success"
DRAWIO_FILES=24
PNG_FILES=24
REPOSITORY="yourusername/diagrams-v2"
COMMIT="71549859f19ee06be17855cd7a2004b74ac54c29"
WORKFLOW="Draw.io Files Processing"
RUN_ID="1234567890"
CHANGELOG_ENTRIES=35

# Format commit hash for display
commit_display="${COMMIT:0:7}"
commit_url="https://github.com/${REPOSITORY}/commit/${COMMIT}"
commit_display="[${COMMIT:0:7}](${commit_url})"

# Get workflow run URL
workflow_run_url="https://github.com/${REPOSITORY}/actions/runs/${RUN_ID}"

# Current date and time for logging
current_date=$(date '+%Y-%m-%d')
current_time=$(date '+%H:%M:%S')

# Calculate conversion rate
conversion_rate=0
if [[ $DRAWIO_FILES -gt 0 ]]; then
    conversion_rate=$(( (PNG_FILES * 100) / DRAWIO_FILES ))
fi

# Get repository name for display
repo_name=$(echo "$REPOSITORY" | cut -d '/' -f 2)

# Set color based on outcome
color="138a07"  # Green for success
icon="✅"

if [[ "$OUTCOME" != "Success" ]]; then
    if [[ "$OUTCOME" == "Partial success" ]]; then
        color="FFA500"  # Orange for partial success
        icon="⚠️"
    else
        color="FF0000"  # Red for failures
        icon="❌"
    fi
fi

# Create the JSON payload
cat > teams_notification_preview.json <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "${color}",
    "summary": "${TITLE}",
    "sections": [
        {
            "activityTitle": "${icon} ${TITLE}",
            "activitySubtitle": "Processing completed at ${current_date} ${current_time}",
            "activityImage": "https://raw.githubusercontent.com/jgraph/drawio-desktop/master/build/icon.png",
            "facts": [
                {
                    "name": "Repository",
                    "value": "${repo_name}"
                },
                {
                    "name": "Status",
                    "value": "${OUTCOME}"
                },
                {
                    "name": "Draw.io Files",
                    "value": "${DRAWIO_FILES}"
                },
                {
                    "name": "PNG Files Generated",
                    "value": "${PNG_FILES}"
                },
                {
                    "name": "Conversion Rate",
                    "value": "${conversion_rate}%"
                },
                {
                    "name": "Changelog Entries",
                    "value": "${CHANGELOG_ENTRIES}"
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
                    "value": "${WORKFLOW}"
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
                    "uri": "https://github.com/${REPOSITORY}"
                }
            ]
        }
    ]
}
EOF

echo "Teams notification preview JSON has been saved to teams_notification_preview.json"
echo "You can visualize this using the Microsoft Adaptive Card Visualizer at:"
echo "https://adaptivecards.io/designer/"
echo ""
echo "Copy and paste the content of teams_notification_preview.json into the 'Card Payload Editor'"

# Print success and failure examples
cat > teams_notification_preview_success.json <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "138a07",
    "summary": "Draw.io Processing - Success",
    "sections": [
        {
            "activityTitle": "✅ Draw.io Processing - Success",
            "activitySubtitle": "Processing completed at ${current_date} ${current_time}",
            "activityImage": "https://raw.githubusercontent.com/jgraph/drawio-desktop/master/build/icon.png",
            "facts": [
                {
                    "name": "Repository",
                    "value": "diagrams-v2"
                },
                {
                    "name": "Status",
                    "value": "Success"
                },
                {
                    "name": "Draw.io Files",
                    "value": "24"
                },
                {
                    "name": "PNG Files Generated",
                    "value": "24"
                },
                {
                    "name": "Conversion Rate",
                    "value": "100%"
                },
                {
                    "name": "Changelog Entries",
                    "value": "35"
                }
            ],
            "markdown": true
        },
        {
            "title": "Commit Information",
            "facts": [
                {
                    "name": "Commit Hash",
                    "value": "[7154985](https://github.com/yourusername/diagrams-v2/commit/71549859f19ee06be17855cd7a2004b74ac54c29)"
                },
                {
                    "name": "Workflow",
                    "value": "Draw.io Files Processing"
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
                    "uri": "https://github.com/yourusername/diagrams-v2/actions/runs/1234567890"
                }
            ]
        },
        {
            "@type": "OpenUri",
            "name": "View Repository",
            "targets": [
                {
                    "os": "default",
                    "uri": "https://github.com/yourusername/diagrams-v2"
                }
            ]
        }
    ]
}
EOF

cat > teams_notification_preview_failure.json <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "FF0000",
    "summary": "Draw.io Processing - Failure",
    "sections": [
        {
            "activityTitle": "❌ Draw.io Processing - Failure",
            "activitySubtitle": "Processing completed at ${current_date} ${current_time}",
            "activityImage": "https://raw.githubusercontent.com/jgraph/drawio-desktop/master/build/icon.png",
            "facts": [
                {
                    "name": "Repository",
                    "value": "diagrams-v2"
                },
                {
                    "name": "Status",
                    "value": "Failure"
                },
                {
                    "name": "Draw.io Files",
                    "value": "24"
                },
                {
                    "name": "PNG Files Generated",
                    "value": "15"
                },
                {
                    "name": "Conversion Rate",
                    "value": "62%"
                },
                {
                    "name": "Changelog Entries",
                    "value": "15"
                }
            ],
            "markdown": true
        },
        {
            "title": "Commit Information",
            "facts": [
                {
                    "name": "Commit Hash",
                    "value": "[7154985](https://github.com/yourusername/diagrams-v2/commit/71549859f19ee06be17855cd7a2004b74ac54c29)"
                },
                {
                    "name": "Workflow",
                    "value": "Draw.io Files Processing"
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
                    "uri": "https://github.com/yourusername/diagrams-v2/actions/runs/1234567890"
                }
            ]
        },
        {
            "@type": "OpenUri",
            "name": "View Repository",
            "targets": [
                {
                    "os": "default",
                    "uri": "https://github.com/yourusername/diagrams-v2"
                }
            ]
        }
    ]
}
EOF

echo "Also created success and failure examples at:"
echo "  - teams_notification_preview_success.json"
echo "  - teams_notification_preview_failure.json"
