# Draw.io Files Processing Workflow V2 Specification

## Project Background

This project serves a critical function in our technical documentation workflow. Our team maintains numerous architectural and process diagrams as draw.io files that need to be converted to a standardized format, tracked for changes, and shared with stakeholders via SharePoint.

### Current Implementation Issues

The v1 implementation suffers from several problems:
1. **Excessive Complexity**: The file detection and ID assignment logic has grown too complex with multiple fallback mechanisms
2. **Output Format Limitations**: The SVG and HTML outputs require browser rendering to view properly
3. **Fragile Change Detection**: Multiple approaches to detect changed files create maintenance challenges
4. **Overcomplicated Error Handling**: Extensive error handling and diagnostic code
5. **Risky Merge Resolution**: The current approach to merge conflicts is fragile

## V2 Overview

The second version of this workflow will focus on generating high-quality PNG files from draw.io diagrams instead of SVG and HTML files. The workflow will maintain the same SharePoint connectivity but with a simplified approach that prioritizes reliability and maintainability.

## Key Requirements

1. **Trigger**: When a new draw.io file is committed, the GitHub workflow will automatically process it.

2. **Output Format**: 
   - Generate high-quality PNG files (instead of SVG and HTML)
   - Store these in a dedicated output directory

3. **Changelog Management**:
   - Track file names, dates, timestamps, commit numbers
   - Record the committer name (not username)
   - Maintain proper versioning
   - Upload to SharePoint using existing connection variables

4. **Version Numbering Logic**:
   - For commit messages containing "added" or "new" → major version increment (1.0, 2.0, etc.)
   - For commit messages containing "update" or similar terms → minor version increment (1.1, 1.2, etc.)

5. **ID Assignment**:
   - Maintain the current ID assignment mechanism for new files
   - Ensure IDs remain unchanged for file updates

### File Detection

Simplify the file detection logic using Git commands:
```bash
# Get all changed draw.io files in the latest commit
git diff --name-only --diff-filter=AM HEAD^ HEAD -- 'drawio_files/*.drawio'
```

### File Conversion

Use draw.io's built-in PNG export capability with high resolution:
```bash
drawio -x -f png --scale 2.0 --quality 100 -o "$output_png" "$input_file"
```
The `--scale 2.0` and `--quality 100` parameters ensure high-quality output suitable for documentation and presentations.

### ID Assignment Process

1. For new files (without an ID pattern):
   - Check if the file has a simple numeric name (e.g., "70.drawio") - these should be preserved as-is
   - For other files, read the last ID from the counter file
   - Increment the counter and format as a 3-digit number
   - Rename the file to include this ID in parentheses
   - Update the counter file

2. For existing files:
   - Preserve the existing ID
   - Only process the file for PNG conversion

### Versioning Logic

1. Extract the commit message using Git:
   ```bash
   commit_msg=$(git log -1 --format="%s" -- "$file")
   ```

2. Determine version increment based on keywords:
   ```bash
   if echo "$commit_msg" | grep -Eiq '(added|new)'; then
     # Major version increment
     major=$((major+1))
     minor=0
   else
     # Minor version increment
     minor=$((minor+1))
   fi
   ```

### Changelog Management

1. Structure:
   ```
   Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name
   ```

2. Entries:
   - Date: Current date (DD.MM.YYYY)
   - Time: Current time (HH:MM:SS)
   - Diagram: Basename of the file
   - File: Full path to the draw.io file
   - Action: "Converted to PNG"
   - Commit Message: Extracted from Git
   - Version: Determined by versioning logic
   - Commit Hash: Short hash from Git
   - Author Name: Full name from Git

### SharePoint Upload

Reuse existing SharePoint connection variables and upload process with the updated changelog format. The implementation should:

1. Create a standardized filename: `Diagrams_Changelog.csv`
2. Maintain the Diagrams folder path on SharePoint
3. Use Graph API authentication as implemented in v1
4. Implement simple retry logic in case of connection issues

## Implementation Guide

### 1. Workflow Structure

The following GitHub Actions workflow steps are recommended:

1. **Checkout**: Checkout repository with history
2. **Setup**: Install Draw.io and dependencies
3. **File Processing**:
   - Detect changed files
   - Assign IDs to new files if needed
   - Convert to PNG format
   - Update changelog
4. **Commit**: Commit changes back to repository
5. **SharePoint**: Upload changelog to SharePoint
6. **Notifications**: Send success/failure notifications

### 2. Code Structure

For better maintainability, structure the conversion script in functional blocks:

```bash
# Function to detect changed files
detect_changed_files() {
  # Implementation
}

# Function to assign IDs
assign_ids() {
  # Implementation
}

# Function to convert to PNG
convert_to_png() {
  # Implementation
}

# Function to update changelog
update_changelog() {
  # Implementation
}

# Main flow
main() {
  detect_changed_files
  for file in $CHANGED_FILES; do
    assign_ids "$file"
    convert_to_png "$file"
    update_changelog "$file"
  done
}

# Run main function
main
```

### 3. Error Handling Best Practices

1. **Fail fast and explicitly**: Check prerequisites early and exit with clear messages
2. **Create placeholder outputs**: For failed conversions, create placeholder PNGs with error messages
3. **Structured logging**: Use a consistent format for all log messages
4. **Retry logic**: Implement retries only for external service calls (SharePoint)
5. **Exit codes**: Use meaningful exit codes for different failure scenarios

### 4. Configuration and Environment

Store configuration in environment variables or at the top of the workflow file:

```yaml
env:
  DRAWIO_VERSION: "26.2.2"
  PNG_SCALE: "2.0"
  PNG_QUALITY: "100"
  CHANGELOG_FILE: "png_files/CHANGELOG.csv"
  SHAREPOINT_FOLDER: "Diagrams"
```

## Implementation Challenges and Solutions

### Challenge 1: Robust File Detection

**Problem**: The current implementation has numerous fallback mechanisms for detecting changed files, leading to complexity.

**Solution**: Simplify to a deterministic approach:
1. Use `git diff` for standard commits
2. Use `git diff-tree` for initial commits
3. Use workflow dispatch for manual processing
4. Eliminate other fallback mechanisms

### Challenge 2: ID Assignment Reliability

**Problem**: The current ID assignment process is complex and error-prone.

**Solution**: Implement a simplified, atomic approach:
1. Always use a centralized counter file
2. Perform ID assignment in a separate, focused step
3. Commit changes before proceeding to conversion
4. Add robust validation of ID patterns

### Challenge 3: High-Quality PNG Output

**Problem**: PNG output needs to be high-quality and consistent.

**Solution**:
1. Use fixed scale and quality parameters
2. Implement validation of output files (size and existence)
3. Use Xvfb with consistent screen dimensions
4. Add error handling for conversion failures

## Testing the Implementation

Before deploying the workflow, test it with:

1. **New file additions**: Verify ID assignment and PNG generation
2. **File updates**: Verify version increments correctly
3. **Manual triggers**: Test workflow_dispatch functionality
4. **Edge cases**: Test with files that have spaces, special characters
5. **Failure scenarios**: Test recovery from conversion failures

## Next Steps After Implementation

1. Create migration scripts to convert existing SVG/HTML files to PNG
2. Update documentation to reflect the new workflow
3. Train team members on the new process
4. Monitor the workflow in production for any issues
5. Collect feedback for future improvements

---

This specification provides a comprehensive guide for implementing version 2 of the Draw.io files processing workflow, focusing on simplification, reliability, and maintainability while ensuring high-quality PNG output and proper change tracking.
