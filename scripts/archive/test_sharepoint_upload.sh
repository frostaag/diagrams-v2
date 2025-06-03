#!/bin/bash
# Test script for SharePoint upload

# Set the environment variables
export SHAREPOINT_CLIENT_ID="c878baed-309e-421c-b967-a9851c6f54bd"
export SHAREPOINT_CLIENT_SECRET="your-client-secret-here"  # Replace with actual value from DIAGRAMS_SHAREPOINT_CLIENTSECRET
export SHAREPOINT_TENANT_ID="a8d22be6-5bda-4bd7-8278-226c60c037ed"
export SHAREPOINT_SITE_ID="e39939c2-992f-47cc-8b32-20aa466d71f4"
export SHAREPOINT_FOLDER="Diagrams"
export SHAREPOINT_OUTPUT_FILENAME="Diagrams_Changelog.csv"
export CHANGELOG_FILE="png_files/CHANGELOG.csv"

# Make sure changelog file exists for testing
if [ ! -f "$CHANGELOG_FILE" ]; then
  mkdir -p $(dirname "$CHANGELOG_FILE")
  echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
  echo "$(date +"%Y-%m-%d"),$(date +"%H:%M:%S"),Test Diagram,test.drawio,Create,Test commit,001,abcdef,Test User" >> "$CHANGELOG_FILE"
fi

# Run the upload script
echo "Running SharePoint upload with test credentials..."
bash ./scripts/upload_to_sharepoint.sh
exit_code=$?

# Check the result
if [ $exit_code -eq 0 ]; then
  echo "Upload script completed successfully."
else
  echo "Upload script failed with exit code $exit_code"
fi

exit $exit_code
