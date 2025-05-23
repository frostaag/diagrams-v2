#!/bin/bash
# Script to fix the format of CHANGELOG.csv

set -eo pipefail

CHANGELOG_FILE="png_files/CHANGELOG.csv"
BACKUP_FILE="png_files/CHANGELOG.csv.bak-$(date +%Y%m%d%H%M%S)"

# Check if changelog exists
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "Error: CHANGELOG.csv not found at $CHANGELOG_FILE"
  exit 1
fi

# Make a backup of the existing file
cp "$CHANGELOG_FILE" "$BACKUP_FILE"
echo "Created backup at $BACKUP_FILE"

# Create a temporary file for the new format
TMP_FILE=$(mktemp)

# Write the correct header
echo "Date,Time,Diagram ID,Diagram Name,File Path,Action,Commit Message,Version,Commit Hash,Author Name" > "$TMP_FILE"

# Process each line of the original file (skipping the header)
tail -n +2 "$CHANGELOG_FILE" | while IFS= read -r line; do
  # Skip empty lines
  if [[ -z "$line" ]]; then
    continue
  fi
  
  # Count the number of fields
  num_fields=$(echo "$line" | awk -F, '{print NF}')
  
  if [[ $num_fields -eq 10 ]]; then
    # Already in the correct format
    echo "$line" >> "$TMP_FILE"
  elif [[ $num_fields -eq 9 ]]; then
    # Format is likely Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name
    # Need to split Diagram into ID and Name
    IFS=',' read -r date time diagram file action commit_msg version hash author <<< "$line"
    # Remove quotes if present
    diagram=$(echo "$diagram" | sed 's/^"//;s/"$//')
    echo "$date,$time,\"$diagram\",\"$diagram\",$file,$action,$commit_msg,$version,$hash,$author" >> "$TMP_FILE"
  elif [[ $num_fields -eq 5 ]]; then
    # Likely the format Date,Time,Diagram ID,Diagram Name,Commit Hash
    IFS=',' read -r date time diagram_id diagram_name commit_hash <<< "$line"
    echo "$date,$time,$diagram_id,$diagram_name,\"$diagram_name.png\",\"Converted to PNG\",\"Auto-converted from draw.io\",1.0,$commit_hash,\"GitHub Action\"" >> "$TMP_FILE"
  elif [[ $num_fields -eq 4 ]]; then
    # Likely the format Date,Time,File Name,Commit Hash
    IFS=',' read -r date time file_name commit_hash <<< "$line"
    echo "$date,$time,\"$file_name\",\"$file_name\",\"$file_name.png\",\"Converted to PNG\",\"Auto-converted from draw.io\",1.0,$commit_hash,\"GitHub Action\"" >> "$TMP_FILE"
  else
    # Unknown format - add as a comment
    echo "# Unprocessed line: $line" >> "$TMP_FILE"
  fi
done

# Replace the original file with the fixed version
mv "$TMP_FILE" "$CHANGELOG_FILE"
chmod 644 "$CHANGELOG_FILE"

echo "CHANGELOG.csv has been updated to the correct format."
echo "Original file was backed up to $BACKUP_FILE"
