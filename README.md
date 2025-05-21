# Draw.io Files Processing Workflow V2

This repository contains a GitHub Actions workflow for processing Draw.io diagram files according to the V2 specification.

## Features

- Automatically detects new and modified draw.io files
- Assigns unique IDs to new files
- Converts draw.io files to high-quality PNG format
- Maintains a comprehensive changelog
- Uploads the changelog to SharePoint
- Sends notifications to Microsoft Teams

## Workflow Overview

When a new draw.io file is committed or modified, the workflow will:

1. Detect the changed files
2. Assign IDs to new files if needed
3. Convert the draw.io files to PNG format
4. Update the changelog with version information
5. Upload the changelog to SharePoint
6. Send a notification to Microsoft Teams

## Directory Structure

- `drawio_files/`: Contains the original draw.io diagram files
- `png_files/`: Contains the generated PNG files and the changelog
- `scripts/`: Contains the processing scripts
- `.github/workflows/`: Contains the GitHub Actions workflow definition

## File Naming and IDs

- New files without an ID will be assigned a sequential 3-digit ID
- Files that already have an ID pattern (e.g., "Diagram (001).drawio") will keep their ID
- Files with simple numeric names (e.g., "70.drawio") will be preserved as-is

## Versioning

- For commit messages containing "added" or "new" → major version increment (1.0, 2.0, etc.)
- For other commit messages → minor version increment (1.1, 1.2, etc.)

## Manual Processing

You can manually process specific draw.io files by triggering the workflow from the GitHub Actions tab and providing the file path.

## SharePoint Integration

The workflow uploads the changelog to SharePoint using the Microsoft Graph API. The necessary credentials should be configured as repository secrets:

- `SHAREPOINT_CLIENT_ID`
- `SHAREPOINT_CLIENT_SECRET`
- `SHAREPOINT_TENANT_ID`
- `SHAREPOINT_SITE_ID`

## Teams Notifications

The workflow sends notifications to Microsoft Teams after processing, including:
- Success notifications with a list of processed diagrams
- Failure notifications with error details

To enable Teams notifications, add this secret to your repository:
- `DIAGRAMS_TEAMS_NOTIFICATION_WEBHOOK`: The Microsoft Teams webhook URL

## Requirements

- DrawIO Desktop version 26.2.2 (configurable in the workflow)
- Git with commit history

## Configuration

You can configure various aspects of the workflow by modifying the environment variables in the workflow file:

```yaml
env:
  # Draw.io configuration
  DRAWIO_VERSION: "26.2.2"
  PNG_SCALE: "2.0"
  PNG_QUALITY: "100"
  
  # File paths
  CHANGELOG_FILE: "png_files/CHANGELOG.csv"
  COUNTER_FILE: "drawio_files/.counter"
  
  # SharePoint configuration
  SHAREPOINT_FOLDER: "Diagrams"
  SHAREPOINT_OUTPUT_FILENAME: "Diagrams_Changelog.csv"
  
  # Teams notification configuration
  TEAMS_NOTIFICATION_TITLE: "Draw.io Diagrams Processing Update"
```
