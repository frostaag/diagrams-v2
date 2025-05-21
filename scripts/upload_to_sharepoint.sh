#!/bin/bash
# Script to upload changelog to SharePoint

set -eo pipefail

# Configuration
CHANGELOG_FILE="${CHANGELOG_FILE:-png_files/CHANGELOG.csv}"
SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-Diagrams}"
OUTPUT_FILENAME="${SHAREPOINT_OUTPUT_FILENAME:-Diagrams_Changelog.csv}"

# Check if required environment variables are set
if [[ -z "$SHAREPOINT_CLIENT_ID" ]] || [[ -z "$SHAREPOINT_CLIENT_SECRET" ]] || \
   [[ -z "$SHAREPOINT_TENANT_ID" ]] || [[ -z "$SHAREPOINT_SITE_ID" ]]; then
  echo "Error: SharePoint credentials are not set."
  exit 1
fi

# Function to get access token
get_access_token() {
  local token_url="https://login.microsoftonline.com/${SHAREPOINT_TENANT_ID}/oauth2/v2.0/token"
  local scope="https://graph.microsoft.com/.default"
  
  local response=$(curl -s -X POST "$token_url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${SHAREPOINT_CLIENT_ID}&scope=${scope}&client_secret=${SHAREPOINT_CLIENT_SECRET}&grant_type=client_credentials")
  
  # Extract token
  local access_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  
  if [[ -z "$access_token" ]]; then
    echo "Error: Failed to get access token"
    echo "$response"
    return 1
  fi
  
  echo "$access_token"
}

# Function to upload file to SharePoint
upload_to_sharepoint() {
  local access_token="$1"
  local file_path="$2"
  local destination="$3"
  
  # Make sure the file exists
  if [[ ! -f "$file_path" ]]; then
    echo "Error: File $file_path does not exist"
    return 1
  fi
  
  # API endpoint
  local upload_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drive/root:/${destination}/${OUTPUT_FILENAME}:/content"
  
  echo "Uploading to SharePoint: ${destination}/${OUTPUT_FILENAME}"
  
  # Upload file with retry logic
  local max_retries=3
  local retry=0
  local success=false
  
  while (( retry < max_retries )) && [[ "$success" != "true" ]]; do
    local response=$(curl -s -X PUT "$upload_url" \
      -H "Authorization: Bearer $access_token" \
      -H "Content-Type: text/csv" \
      --data-binary "@$file_path")
    
    if echo "$response" | grep -q '"id"'; then
      echo "Successfully uploaded to SharePoint"
      success=true
    else
      retry=$((retry+1))
      echo "Upload attempt $retry failed, retrying..."
      sleep 2
    fi
  done
  
  if [[ "$success" != "true" ]]; then
    echo "Error: Failed to upload after $max_retries attempts"
    echo "$response"
    return 1
  fi
  
  return 0
}

# Main function
main() {
  echo "Starting SharePoint upload process..."
  
  # Get access token
  local access_token=$(get_access_token)
  if [[ -z "$access_token" ]]; then
    exit 1
  fi
  
  # Upload changelog
  if ! upload_to_sharepoint "$access_token" "$CHANGELOG_FILE" "$SHAREPOINT_FOLDER"; then
    exit 1
  fi
  
  echo "SharePoint upload completed successfully"
}

# Run main function
main
