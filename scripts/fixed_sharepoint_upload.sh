#!/bin/bash
# Fixed upload_to_sharepoint.sh script that properly handles the multiline drive ID issue

set -eo pipefail

# Configuration
CHANGELOG_FILE="${CHANGELOG_FILE:-png_files/CHANGELOG.csv}"
SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-Diagrams}"
OUTPUT_FILENAME="${SHAREPOINT_OUTPUT_FILENAME:-Diagrams_Changelog.csv}"
SHAREPOINT_DRIVE_ID="21e1e0f0-9247-45ab-9f8c-1d50c5c077db"  # Fixed ID from test script

# Check if required environment variables are set
if [[ -z "$SHAREPOINT_CLIENT_ID" ]]; then
  echo "Error: SHAREPOINT_CLIENT_ID is not set."
  exit 1
fi

if [[ -z "$SHAREPOINT_CLIENT_SECRET" ]]; then
  echo "Error: SHAREPOINT_CLIENT_SECRET is not set."
  exit 1
fi

if [[ -z "$SHAREPOINT_TENANT_ID" ]]; then
  echo "Error: SHAREPOINT_TENANT_ID is not set."
  exit 1
fi

if [[ -z "$SHAREPOINT_SITE_ID" ]]; then
  echo "Error: SHAREPOINT_SITE_ID is not set."
  exit 1
fi

# Function to test and fix network connectivity issues
test_and_fix_connectivity() {
  local target="$1"
  local explanation="$2"
  echo "🔌 Testing network connectivity to $target ($explanation)..."
  
  # Try standard connection first
  if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    echo "✅ Network connectivity to $target is working"
    return 0
  else
    echo "❌ Cannot connect to $target directly"
    
    # Try with different connection options
    echo "🔄 Trying direct connection with --noproxy '*'..."
    if curl --noproxy '*' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
      echo "✅ Direct connection (no proxy) works! Using this for all requests."
      export USE_DIRECT_CONNECTION="true"
      return 0
    fi
    
    # Try with TLSv1.2 explicit setting
    echo "🔄 Testing with TLSv1.2 explicit setting..."
    if curl --tlsv1.2 --noproxy '*' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
      echo "✅ TLSv1.2 connection works! Using this for all requests."
      export USE_DIRECT_CONNECTION="true"
      export FORCE_TLS="true"
      return 0
    else
      echo "❌ All connection methods failed for $target"
      return 1
    fi
  fi
}

# Function to get access token
get_access_token() {
  local token_url="https://login.microsoftonline.com/${SHAREPOINT_TENANT_ID}/oauth2/v2.0/token"
  local scope="https://graph.microsoft.com/.default"
  
  # Set common curl options
  local curl_opts="--connect-timeout 20 --max-time 60 -s"
  
  # Apply direct connection if needed
  if [ "${USE_DIRECT_CONNECTION}" = "true" ]; then
    curl_opts="$curl_opts --noproxy '*'"
  fi
  
  # Apply TLS version if needed
  if [ "${FORCE_TLS}" = "true" ]; then
    curl_opts="$curl_opts --tlsv1.2"
  fi
  
  # Debug settings
  echo "🔐 Getting OAuth token from ${token_url}"
  echo "Using curl options: $curl_opts"
  
  local response=$(curl $curl_opts -X POST \
    "$token_url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${SHAREPOINT_CLIENT_ID}&scope=${scope}&client_secret=${SHAREPOINT_CLIENT_SECRET}&grant_type=client_credentials")
  
  # Extract token
  if [[ "$response" == *"access_token"* ]]; then
    local access_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    if [[ -n "$access_token" ]]; then
      echo "✅ OAuth token obtained successfully (${#access_token} characters)"
      echo "$access_token"
      return 0
    fi
  fi
  
  echo "Error: Failed to get access token"
  echo "Response: $response"
  return 1
}

# Function to upload file to SharePoint using direct method
upload_to_sharepoint() {
  local access_token="$1"
  local file_path="$2"
  local destination="$3" 
  local test_mode="${4:-false}"
  
  # Make sure the file exists
  if [[ ! -f "$file_path" ]]; then
    echo "Error: File $file_path does not exist"
    return 1
  fi
  
  # Verify file content
  local file_size=$(wc -c < "$file_path")
  echo "File to upload: $file_path (size: $file_size bytes)"
  head -n 3 "$file_path"
  
  # Direct URL to SharePoint site using ID
  local site_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
  
  # Set curl options
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ "${USE_DIRECT_CONNECTION}" = "true" ]; then
    curl_opts="$curl_opts --noproxy '*'"
  fi
  if [ "${FORCE_TLS}" = "true" ]; then
    curl_opts="$curl_opts --tlsv1.2"
  fi
  
  echo "🏢 Verifying SharePoint site access..."
  local site_response=$(curl $curl_opts -X GET \
    "$site_url" \
    -H "Authorization: Bearer $access_token" \
    -H "Accept: application/json")
  
  # Verify site access
  if [[ "$site_response" != *"\"id\":"* ]]; then
    echo "❌ Failed to access SharePoint site"
    echo "Response: $site_response"
    return 1
  fi
  
  # Extract site details
  local site_display_name=$(echo "$site_response" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
  echo "✅ Connected to SharePoint site: $site_display_name"
  
  # If test mode is enabled, stop here
  if [ "$test_mode" = "true" ]; then
    echo "TEST MODE: Connection to SharePoint successful. Not uploading file."
    return 0
  fi
  
  # Use direct drive ID from testing results
  echo "📁 Using fixed Documents library ID: $SHAREPOINT_DRIVE_ID"
  # Correct path format for Documents/Diagrams folder
  local upload_path="${site_url}/drives/${SHAREPOINT_DRIVE_ID}/root:/Documents/${destination}/${OUTPUT_FILENAME}:/content"
  echo "Final upload path: $upload_path"
  
  # Upload the file
  echo "📤 Uploading file to SharePoint..."
  local upload_response=$(curl $curl_opts -X PUT \
    "$upload_path" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: text/csv" \
    --data-binary "@$file_path")
  
  # Check for success
  if [[ "$upload_response" == *"\"id\":"* ]]; then
    echo "✅ Successfully uploaded file to SharePoint"
    local web_url=$(echo "$upload_response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
    echo "File URL: $web_url"
    return 0
  else
    echo "❌ Failed to upload file"
    echo "Response: $upload_response"
    
    # Try alternate paths
    echo "🔄 Trying alternate upload paths..."
    
    # Try path with Documents folder but no subfolder
    local alt_path="${site_url}/drives/${SHAREPOINT_DRIVE_ID}/root:/Documents/${OUTPUT_FILENAME}:/content"
    echo "Trying path: $alt_path"
    
    local alt_response=$(curl $curl_opts -X PUT \
      "$alt_path" \
      -H "Authorization: Bearer $access_token" \
      -H "Content-Type: text/csv" \
      --data-binary "@$file_path")
    
    if [[ "$alt_response" == *"\"id\":"* ]]; then
      echo "✅ Successfully uploaded file to SharePoint (using alternate path)"
      local web_url=$(echo "$alt_response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
      echo "File URL: $web_url"
      return 0
    else
      echo "❌ Failed to upload file (first alternate path failed)"
      
      # Try root path as final fallback
      echo "🔄 Trying root upload path as final fallback..."
      local root_path="${site_url}/drives/${SHAREPOINT_DRIVE_ID}/root:/${OUTPUT_FILENAME}:/content"
      echo "Trying path: $root_path"
      
      local root_response=$(curl $curl_opts -X PUT \
        "$root_path" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: text/csv" \
        --data-binary "@$file_path")
      
      if [[ "$root_response" == *"\"id\":"* ]]; then
        echo "✅ Successfully uploaded file to SharePoint (using root path)"
        local web_url=$(echo "$root_response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
        echo "File URL: $web_url"
        return 0
      else
        echo "❌ Failed to upload file (all paths failed)"
        echo "Response: $root_response"
        return 1
      fi
    fi
  fi
}

# Main function
main() {
  echo "🚀 Starting SharePoint upload process..."
  
  # Check network connectivity
  test_and_fix_connectivity "https://graph.microsoft.com/v1.0/" "Microsoft Graph API"
  
  # Get access token
  local access_token=$(get_access_token)
  if [[ -z "$access_token" ]]; then
    exit 1
  fi
  
  # Upload changelog
  local test_mode="${TEST_MODE:-false}"
  if ! upload_to_sharepoint "$access_token" "$CHANGELOG_FILE" "$SHAREPOINT_FOLDER" "$test_mode"; then
    exit 1
  fi
  
  echo "✅ SharePoint upload completed successfully"
}

# Run the script
main
