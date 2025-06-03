# Draw.io Files Processing Workflow V2

This repository contains a **simplified and robust** GitHub Actions workflow for processing Draw.io diagram files. The V2 implementation focuses on reliability, maintainability, and high-quality PNG output.

## ✨ Features

- **Automatic Processing**: Detects and processes new/modified Draw.io files
- **Smart ID Assignment**: Assigns unique sequential IDs to new files
- **High-Quality PNG Output**: Converts diagrams to PNG format with optimal settings
- **Comprehensive Changelog**: Tracks all changes with versioning information
- **SharePoint Integration**: Automatically uploads changelog to SharePoint
- **Teams Notifications**: Sends processing status to Microsoft Teams
- **Clean & Simple**: Streamlined codebase focused on core functionality

## 🚀 What's New in V2

- **Single Clean Script**: Consolidated processing logic in `process_drawio_files_v2.sh`
- **Improved PNG Conversion**: Better error handling and placeholder creation for failed conversions
- **Robust File Detection**: Simplified Git-based file detection logic
- **Cleaner Codebase**: Moved legacy scripts to archive, keeping only essential functionality
- **Better Error Handling**: Clear error messages and graceful failure handling
- **Fixed Changelog Issues**: Prevented log message leakage into changelog entries

## 📁 Directory Structure

```
drawio_files/          # Original Draw.io diagram files
├── .counter           # ID counter for new files
└── *.drawio           # Draw.io diagram files

png_files/             # Generated PNG files and metadata
├── CHANGELOG.csv      # Processing changelog
├── .versions          # Version tracking file
└── *.png              # Generated PNG diagrams

scripts/               # Processing scripts
├── process_drawio_files_v2.sh  # Main processing script (clean V2)
└── archive/           # Legacy scripts (archived)

.github/workflows/     # GitHub Actions workflow
└── drawio_processing_v2_clean.yml  # Main workflow file
```

## 🔧 How It Works

### 1. File Detection
The workflow uses Git to detect changed Draw.io files:
- **Push events**: Compares current commit with previous commit
- **Manual triggers**: Processes specific files or all files
- **Initial commits**: Processes all available files

### 2. ID Assignment
- New files without IDs get sequential 3-digit IDs: `filename (001).drawio`
- Files with numeric names (e.g., `70.drawio`) are preserved as-is
- Existing files with IDs are not renamed

### 3. PNG Conversion
- Uses Draw.io's built-in PNG export with high-quality settings
- **Scale**: 2.0x for crisp diagrams
- **Quality**: Maximum quality for professional output
- **Fallback**: Creates error placeholders for failed conversions

### 4. Versioning
- **Major version** (e.g., 2.0): For commit messages containing "added" or "new"
- **Minor version** (e.g., 1.1): For updates and modifications
- Versions are tracked per file ID in `.versions` file

### 5. Changelog Management
Maintains a comprehensive CSV changelog with:
- Date, Time, Diagram name, File path
- Action taken, Commit message, Version
- Commit hash, Author name

## 🎯 File Naming and IDs

### New Files
- `my-diagram.drawio` → `my-diagram (001).drawio`
- `flowchart.drawio` → `flowchart (002).drawio`

### Preserved Files
- `70.drawio` → remains `70.drawio` (numeric names preserved)
- `existing (005).drawio` → keeps existing ID

## 📈 Versioning Logic

| Commit Message | Version Change | Example |
|----------------|----------------|---------|
| "Added new flow diagram" | Major increment | 1.0 → 2.0 |
| "Update user journey" | Minor increment | 1.2 → 1.3 |
| "Fixed typo in diagram" | Minor increment | 2.1 → 2.2 |

## 🔄 Manual Processing

You can manually trigger the workflow:

1. Go to **Actions** tab in GitHub
2. Select **Draw.io Files Processing V2**
3. Click **Run workflow**
4. Optionally specify a specific file to process

## ☁️ SharePoint Integration

The workflow automatically uploads the changelog to SharePoint using Microsoft Graph API.

### Required Repository Secrets
- `DIAGRAMS_SHAREPOINT_CLIENTSECRET`: SharePoint app client secret

### Required Repository Variables  
- `DIAGRAMS_SHAREPOINT_CLIENT_ID`: SharePoint app client ID
- `DIAGRAMS_SHAREPOINT_TENANT_ID`: Azure tenant ID

The changelog is uploaded to: `Documents/Diagrams/Diagrams_Changelog.csv`

## 📢 Teams Notifications

Optional Teams notifications are sent after processing.

### Setup
Add this repository secret:
- `DIAGRAMS_TEAMS_NOTIFICATION_WEBHOOK`: Microsoft Teams webhook URL

Notifications include:
- Processing status (success/failure)
- Number of files processed/failed
- Links to view the workflow run

## ⚙️ Configuration

Customize the workflow by editing environment variables in `.github/workflows/drawio_processing.yml`:

```yaml
env:
  # Draw.io settings
  DRAWIO_VERSION: "26.2.2"
  PNG_SCALE: "2.0"
  PNG_QUALITY: "100"
  
  # File paths
  CHANGELOG_FILE: "png_files/CHANGELOG.csv"
  COUNTER_FILE: "drawio_files/.counter"
  
  # SharePoint settings
  SHAREPOINT_FOLDER: "Diagrams"
  SHAREPOINT_OUTPUT_FILENAME: "Diagrams_Changelog.csv"
```

## 🛠️ Requirements

- **Draw.io Desktop**: Version 26.2.2 (automatically installed in workflow)
- **ImageMagick**: For error placeholder creation
- **Git**: For file detection and change tracking
- **Ubuntu Latest**: GitHub Actions runner environment

## 🚦 Troubleshooting

### Common Issues

1. **PNG files are 0 bytes**
   - Check if Draw.io files are valid XML format
   - Verify Draw.io installation in workflow logs

2. **Files not being processed**
   - Ensure files are in `drawio_files/` directory
   - Check that files have `.drawio` extension
   - Verify Git changes are committed

3. **SharePoint upload fails**
   - Verify client ID and secret are correct
   - Check that the SharePoint site and folder exist
   - Ensure proper permissions are granted to the app

4. **Teams notifications not working**
   - Verify webhook URL is correct and active
   - Check webhook permissions in Teams

### Manual Testing

Test the processing script locally:
```bash
cd /path/to/repository
SPECIFIC_FILE="drawio_files/test.drawio" ./scripts/process_drawio_files_v2.sh
```

## 📜 Migration from V1

The V2 implementation is a complete rewrite focused on simplicity and reliability:

- **Removed**: Complex fallback mechanisms, multiple SharePoint scripts, verbose error handling
- **Simplified**: File detection, ID assignment, PNG conversion process  
- **Improved**: Error handling, placeholder creation, changelog management
- **Archived**: Legacy scripts moved to `scripts/archive/` for reference

## 🤝 Contributing

1. Follow the V2 specification in `workflow_v2_specification.md`
2. Test changes locally before committing
3. Update documentation for any configuration changes
4. Keep the codebase simple and maintainable

---

**Version**: 2.0  
**Status**: Production Ready  
**Last Updated**: June 2025
