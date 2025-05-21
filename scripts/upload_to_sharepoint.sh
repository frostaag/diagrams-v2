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
  
  echo "Getting access token from: $token_url"
  echo "Using client ID: ${SHAREPOINT_CLIENT_ID:0:6}... (truncated for security)"
  
  # Try multiple times to get token in case of transient issues
  local max_retries=3
  local retry=0
  local access_token=""
  
  while [[ $retry -lt $max_retries && -z "$access_token" ]]; do
    echo "Attempt $((retry+1)) to get access token..."
    
    local response=$(curl -s -X POST "$token_url" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "client_id=${SHAREPOINT_CLIENT_ID}&scope=${scope}&client_secret=${SHAREPOINT_CLIENT_SECRET}&grant_type=client_credentials")
    
    # Extract token with more robust parsing
    if [[ "$response" == *"access_token"* ]]; then
      access_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
      if [[ -n "$access_token" ]]; then
        echo "Access token obtained successfully."
        break
      fi
    fi
    
    echo "Failed to get access token on attempt $((retry+1))"
    if [[ "$response" == *"error"* ]]; then
      local error_code=$(echo "$response" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
      local error_desc=$(echo "$response" | grep -o '"error_description":"[^"]*' | cut -d'"' -f4)
      echo "Error code: $error_code"
      echo "Error description: $error_desc"
    else
      echo "Unexpected response: $response"
    fi
    
    retry=$((retry+1))
    
    if [[ $retry -lt $max_retries ]]; then
      echo "Retrying in 3 seconds..."
      sleep 3
    fi
  done
  
  if [[ -z "$access_token" ]]; then
    echo "Error: Failed to get access token after $max_retries attempts"
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
  
  # Check file size and content
  local file_size=$(wc -c < "$file_path")
  echo "File size: $file_size bytes"
  if [[ $file_size -lt 100 ]]; then
    echo "Warning: File size is very small ($file_size bytes). Verifying content..."
    cat "$file_path"
    echo ""
  else
    echo "First 5 lines of the file:"
    head -n 5 "$file_path"
  fi
  
  # Extract company domain from site ID or use default
  local sharepoint_domain=""
  if [[ "$SHAREPOINT_SITE_ID" =~ ([a-zA-Z0-9_-]+)\.sharepoint\.com ]]; then
    sharepoint_domain="${BASH_REMATCH[1]}.sharepoint.com"
    echo "Extracted SharePoint domain: $sharepoint_domain"
  else
    # Default domain if not found in SITE_ID
    sharepoint_domain="frostaag.sharepoint.com"
    echo "Using default SharePoint domain: $sharepoint_domain"
  fi
  
  # Verify the SharePoint site exists before uploading
  echo "Verifying SharePoint site ID: ${SHAREPOINT_SITE_ID}"
  
  # Test site with multiple formats
  local site_formats=(
    "https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain}:/sites/${SHAREPOINT_SITE_ID#*/sites/}"
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain}"
  )
  
  # If we have a GUID, add more formats
  local site_guid=$(echo "${SHAREPOINT_SITE_ID}" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}')
  if [ -n "$site_guid" ]; then
    site_formats+=("https://graph.microsoft.com/v1.0/sites/${sharepoint_domain},${site_guid},${site_guid}")
    site_formats+=("https://graph.microsoft.com/v1.0/sites/root/sites/${site_guid}")
  fi
  
  # Try each format until one works
  local site_url=""
  local site_info=""
  
  for format in "${site_formats[@]}"; do
    echo "Trying site format: $format"
    local site_response=$(curl -s -X GET "$format" \
      -H "Authorization: Bearer $access_token" \
      -H "Accept: application/json")
    
    if echo "$site_response" | grep -q '"id"'; then
      echo "✅ Success with format: $format"
      site_url="$format"
      site_info="$site_response"
      break
    else
      echo "❌ Failed with format: $format"
      if echo "$site_response" | grep -q "error"; then
        local error_code=$(echo "$site_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
        local error_message=$(echo "$site_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
        echo "Error code: $error_code"
        echo "Error message: $error_message"
      fi
    fi
  done
  
  if [ -z "$site_url" ]; then
    echo "Error: Could not connect to SharePoint site with any format"
    echo "Please verify your SharePoint site ID and permissions"
    return 1
  fi
  
  # Extract site details for better debugging
  local site_display_name=$(echo "$site_info" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
  local site_web_url=$(echo "$site_info" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
  echo "Connected to site: $site_display_name"
  echo "Site URL: $site_web_url"
  
  # Construct upload URL from successful site format
  local drive_path="${site_url}/drive/root:/${destination}/${OUTPUT_FILENAME}:/content"
  
  echo "Uploading to SharePoint: ${destination}/${OUTPUT_FILENAME}"
  echo "Using API endpoint: $drive_path"
  
  # Upload file with exponential backoff retry
  local max_retries=4
  local retry=0
  local success=false
  local wait_time=5
  
  while (( retry < max_retries )) && [[ "$success" != "true" ]]; do
    echo "Upload attempt $((retry+1)) of $max_retries..."
    
    # Upload with verbose output to capture headers
    local response=$(curl -v -X PUT "$drive_path" \
      -H "Authorization: Bearer $access_token" \
      -H "Content-Type: text/csv" \
      -H "Content-Length: $file_size" \
      --data-binary "@$file_path" 2>&1)
    
    # Extract response body for better error analysis
    local response_body=$(echo "$response" | grep -v "^*" | grep -v "^>" | grep -v "^<" || echo "No response body")
    
    # Check for successful upload (id field in response indicates success)
    if echo "$response_body" | grep -q '"id"'; then
      echo "✅ Successfully uploaded to SharePoint"
      
      # Extract file metadata from response
      local item_id=$(echo "$response_body" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
      local web_url=$(echo "$response_body" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
      local name=$(echo "$response_body" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
      
      echo "Uploaded file details:"
      echo "- Name: $name"
      echo "- ID: $item_id"
      echo "- URL: $web_url"
      
      success=true
    else
      retry=$((retry+1))
      echo "❌ Upload attempt $retry failed."
      
      # Parse error information
      if echo "$response_body" | grep -q '"error"'; then
        local error_code=$(echo "$response_body" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
        local error_message=$(echo "$response_body" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
        echo "Error code: $error_code"
        echo "Error message: $error_message"
        
        # Handle specific error cases
        case "$error_code" in
          "accessDenied")
            echo "Authentication issue - check permissions and credentials"
            ;;
          "itemAlreadyExists")
            echo "File already exists - will be overwritten on next attempt"
            ;;
          "resourceNotFound")
            echo "Destination folder may not exist - check folder path"
            # Try to create the destination folder
            echo "Attempting to create folder: $destination"
            local create_folder_url="${site_url}/drive/root:/$(dirname "$destination"):/children"
            curl -s -X POST "$create_folder_url" \
              -H "Authorization: Bearer $access_token" \
              -H "Content-Type: application/json" \
              -d "{\"name\":\"$(basename "$destination")\",\"folder\":{},\"@microsoft.graph.conflictBehavior\":\"replace\"}"
            ;;
        esac
      else
        echo "Unexpected response: $response_body"
        # Check for HTTP status code
        local http_status=$(echo "$response" | grep -o "HTTP/[0-9.]* [0-9]*" | tail -1 | awk '{print $2}')
        echo "HTTP Status: $http_status"
      fi
      
      if (( retry < max_retries )); then
        # Exponential backoff
        echo "Retrying in $wait_time seconds..."
        sleep $wait_time
        wait_time=$((wait_time * 2))
      fi
    fi
  done
  
  if [[ "$success" != "true" ]]; then
    echo "Error: Failed to upload after $max_retries attempts"
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
