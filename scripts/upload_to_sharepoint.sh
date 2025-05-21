#!/bin/bash
# Script to upload changelog to SharePoint

set -eo pipefail

# Configuration
CHANGELOG_FILE="${CHANGELOG_FILE:-png_files/CHANGELOG.csv}"
SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-Diagrams}"
OUTPUT_FILENAME="${SHAREPOINT_OUTPUT_FILENAME:-Diagrams_Changelog.csv}"

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

# Check if we have a custom SharePoint URL defined
CUSTOM_SHAREPOINT_URL="${SHAREPOINT_URL:-}"
if [[ -n "$CUSTOM_SHAREPOINT_URL" ]]; then
  echo "Using custom SharePoint URL: $CUSTOM_SHAREPOINT_URL"
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
  local test_mode="${4:-false}"  # Optional test mode parameter
  
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
  
  # First try to get domain from custom URL if available
  if [[ -n "$CUSTOM_SHAREPOINT_URL" && "$CUSTOM_SHAREPOINT_URL" =~ ([a-zA-Z0-9_-]+\.sharepoint\.com) ]]; then
    sharepoint_domain="${BASH_REMATCH[1]}"
    echo "Extracted SharePoint domain from custom URL: $sharepoint_domain"
  # Otherwise try to extract from site ID
  elif [[ "$SHAREPOINT_SITE_ID" =~ ([a-zA-Z0-9_-]+)\.sharepoint\.com ]]; then
    sharepoint_domain="${BASH_REMATCH[1]}.sharepoint.com"
    echo "Extracted SharePoint domain from site ID: $sharepoint_domain"
  else
    # Default domain if not found in SITE_ID or custom URL
    sharepoint_domain="frostaag.sharepoint.com"
    echo "Using default SharePoint domain: $sharepoint_domain"
  fi
  
  # Verify the SharePoint site exists before uploading
  echo "Verifying SharePoint site ID: ${SHAREPOINT_SITE_ID}"
  echo "TIP: If connection fails, test these URLs in Graph Explorer: https://developer.microsoft.com/en-us/graph/graph-explorer"
  
  # Print important debug info
  echo "======== SHAREPOINT CONNECTION DEBUG ========"
  echo "Site ID: ${SHAREPOINT_SITE_ID}"
  echo "Custom URL: ${CUSTOM_SHAREPOINT_URL:-None}"
  echo "Tenant ID: ${SHAREPOINT_TENANT_ID}"
  echo "============================================"
  
  # URLs to test - prioritizing formats that worked in Postman tests
  local site_formats=(
    # Host-relative format with site name - confirmed working in your tests
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain}:/sites/DatasphereFileConnector"
    
    # Direct site ID format - confirmed working with specific ID format
    "https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
    
    # Full site ID format with three-part structure - worked in your tests
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain},${SHAREPOINT_SITE_ID},bd3be67d-8b49-4817-835d-b1673da4c2b0"
  )
  
  # Add custom URL format if provided
  if [[ -n "$CUSTOM_SHAREPOINT_URL" ]]; then
    # Extract domain and site name from custom URL
    if [[ "$CUSTOM_SHAREPOINT_URL" =~ ([a-zA-Z0-9_-]+\.sharepoint\.com)/sites/([a-zA-Z0-9_-]+) ]]; then
      local extracted_domain="${BASH_REMATCH[1]}"
      local site_name="${BASH_REMATCH[2]}"
      echo "Extracted domain from custom URL: $extracted_domain"
      echo "Extracted site name from URL: $site_name"
      
      # Add formats using the custom URL
      site_formats+=(
        "https://graph.microsoft.com/v1.0/sites/${extracted_domain}:/sites/${site_name}"
        "https://graph.microsoft.com/v1.0/sites/${extracted_domain}:${CUSTOM_SHAREPOINT_URL#*${extracted_domain}}"
        "https://graph.microsoft.com/v1.0/sites/${extracted_domain}:/sites/${site_name}:"
        "https://graph.microsoft.com/v1.0/sites/${extracted_domain}/sites/${site_name}"
      )
    fi
    
    # Add direct format using custom URL - with and without trailing slash
    site_formats+=("https://graph.microsoft.com/v1.0/sites/${CUSTOM_SHAREPOINT_URL#https://}")
    if [[ "$CUSTOM_SHAREPOINT_URL" == */ ]]; then
      site_formats+=("https://graph.microsoft.com/v1.0/sites/${CUSTOM_SHAREPOINT_URL%/}")
    else
      site_formats+=("https://graph.microsoft.com/v1.0/sites/${CUSTOM_SHAREPOINT_URL}/")
    fi
  fi
  
  # Add optimized formats for DatasphereFileConnector that worked in your tests
  site_formats+=(
    # Known working SharePoint site ID reference format 
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain},${SHAREPOINT_SITE_ID}"
    
    # Optimized host name formats - exact pattern that worked in tests
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain}:/sites/DatasphereFileConnector"
    "https://graph.microsoft.com/v1.0/sites/${sharepoint_domain}/sites/DatasphereFileConnector"
    
    # Try with tenant ID and site ID combination (for completeness)
    "https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_TENANT_ID}/${SHAREPOINT_SITE_ID}"
  )
  
  # If we have a GUID, add more formats
  local site_guid=$(echo "${SHAREPOINT_SITE_ID}" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}')
  if [ -n "$site_guid" ]; then
    site_formats+=("https://graph.microsoft.com/v1.0/sites/${sharepoint_domain},${site_guid},${site_guid}")
    site_formats+=("https://graph.microsoft.com/v1.0/sites/root/sites/${site_guid}")
    site_formats+=("https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:${SHAREPOINT_FOLDER}")
    site_formats+=("https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:/sites/Diagrams")
  fi
  
  # Try direct site GUID format if name extraction succeeded
  if [[ -n "$site_name" && -n "$extracted_domain" ]]; then
    echo "Adding site name + GUID combination formats..."
    site_formats+=(
      "https://graph.microsoft.com/v1.0/sites/${extracted_domain},${SHAREPOINT_SITE_ID}"
      "https://graph.microsoft.com/v1.0/sites/${extracted_domain}/sites/${site_name}"
    )
  fi
  
  # Try each format until one works
  local site_url=""
  local site_info=""
  
  # First try with direct SharePoint REST API (which has different auth requirements)
  echo "Trying direct SharePoint API first..."
  if [[ -n "$CUSTOM_SHAREPOINT_URL" ]]; then
    local sp_rest_url="${CUSTOM_SHAREPOINT_URL}/_api/site?$select=Id"
    echo "Testing REST API: $sp_rest_url"
    echo "Note: This may fail due to different auth, but worth trying"
    
    # This might fail due to different auth mechanism, but worth trying
    curl -v -X GET "$sp_rest_url" \
      -H "Authorization: Bearer $access_token" \
      -H "Accept: application/json" || echo "Failed with REST API as expected"
  fi
  
  # Now try with Graph API formats
  for format in "${site_formats[@]}"; do
    echo "Trying site format: $format"
    
    # Debug request
    echo "curl -X GET \"$format\" -H \"Authorization: Bearer [TOKEN]\" -H \"Accept: application/json\""
    
    local site_response=$(curl -s -X GET "$format" \
      -H "Authorization: Bearer $access_token" \
      -H "Accept: application/json")
    
    if echo "$site_response" | grep -q '"id"'; then
      echo "✅ Success with format: $format"
      site_url="$format"
      site_info="$site_response"
      
      # Extract the full site ID for future reference
      local full_site_id=$(echo "$site_response" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
      echo "📝 Full site ID from response: $full_site_id"
      echo "For future reference, this is the complete SharePoint site ID"
      
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
    echo ""
    echo "❌ ERROR: Could not connect to SharePoint site with any format"
    echo ""
    echo "======================= TROUBLESHOOTING GUIDE ======================="
    echo "1️⃣ SITE INFORMATION"
    echo "   Site URL provided: ${CUSTOM_SHAREPOINT_URL:-No custom URL provided}"
    echo "   Site ID provided: ${SHAREPOINT_SITE_ID}"
    echo ""
    echo "2️⃣ WORKING URL FORMATS (confirmed from your successful tests):"
    echo "   a) Site path format: https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:/sites/DatasphereFileConnector"
    echo "   b) Direct site ID: https://graph.microsoft.com/v1.0/sites/e39939c2-992f-47cc-8b32-20aa466d71f4"
    echo ""
    echo "3️⃣ REQUIRED PERMISSIONS"
    echo "   Your app registration MUST have these Graph API permissions:"
    echo "   - Sites.Read.All"
    echo "   - Sites.ReadWrite.All" 
    echo "   - Files.ReadWrite.All"
    echo "   ⚠️ These permissions must be GRANTED by an admin in Azure portal"
    echo ""
    echo "4️⃣ AUTHENTICATION DETAILS"
    echo "   - Verify that SHAREPOINT_CLIENT_ID is correct"
    echo "   - Verify that SHAREPOINT_CLIENT_SECRET is correct"
    echo "   - Verify that SHAREPOINT_TENANT_ID (${SHAREPOINT_TENANT_ID}) is correct"
    echo "   - Verify that SHAREPOINT_SITE_ID is the correct format (GUID or site path)"
    echo ""
    echo "5️⃣ TESTING TOOLS"
    echo "   - Test in Graph Explorer: https://developer.microsoft.com/en-us/graph/graph-explorer"
    echo "   - Try these test URLs:"
    echo "     1. https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:/sites/DatasphereFileConnector"
    echo "     2. https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
    echo "=================================================================="
    
    # Check app permissions to help with troubleshooting
    echo ""
    echo "Checking application permissions (this will likely fail, but provides useful error info)..."
    local permissions_url="https://graph.microsoft.com/v1.0/me"
    
    local permission_response=$(curl -s -X GET "$permissions_url" \
      -H "Authorization: Bearer $access_token" \
      -H "Accept: application/json")
      
    if echo "$permission_response" | grep -q "error"; then
      local error_code=$(echo "$permission_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
      local error_message=$(echo "$permission_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
      echo "Error code: $error_code"
      echo "Error message: $error_message"
      
      # Provide specific guidance based on error
      case "$error_code" in
        "InvalidAuthenticationToken")
          echo "⚠️ Authentication token is invalid. Check your client ID, secret, and tenant ID."
          ;;
        "AuthenticationError")
          echo "⚠️ Authentication failed. Verify your app credentials and permissions."
          ;;
        "AccessDenied")
          echo "⚠️ Access denied. Your app doesn't have sufficient permissions."
          ;;
        *)
          echo "⚠️ Check that all permissions are properly configured."
          ;;
      esac
    fi
    
    return 1
  fi
  
  # Extract site details for better debugging
  local site_display_name=$(echo "$site_info" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
  local site_web_url=$(echo "$site_info" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
  echo "Connected to site: $site_display_name"
  echo "Site URL: $site_web_url"
  
  # Construct upload URL from successful site format
  
  # Extract site details for better debugging
  local site_display_name=$(echo "$site_info" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
  local site_web_url=$(echo "$site_info" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
  echo "Connected to site: $site_display_name ($site_web_url)"
  
  # Check for document libraries
  echo "Retrieving document libraries..."
  
  local drives_response=$(curl -s -X GET "${site_url}/drives" \
    -H "Authorization: Bearer $access_token" \
    -H "Accept: application/json")
  
  # Initialize drive path
  local drive_path=""
  local drive_id=""
  
  # Find document libraries by name with improved detection
  echo "Looking for document libraries in the site..."
  
  # Extract all available libraries for better diagnostics
  local all_libraries=$(echo "$drives_response" | grep -o '"name":"[^"]*' | cut -d'"' -f4 || echo "")
  if [ -n "$all_libraries" ]; then
    echo "Available document libraries:"
    echo "$all_libraries" | while read -r lib; do
      echo "- $lib"
    done
  fi
  
  # Try to find the best document library to use
  if echo "$drives_response" | grep -q '"name":"Documents"'; then
    echo "✅ Found 'Documents' library"
    drive_id=$(echo "$drives_response" | grep -o '"name":"Documents".*"id":"[^"]*' | 
               grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "")
    echo "Documents library ID: $drive_id"
    drive_path="${site_url}/drive/root:/Documents/${destination}/${OUTPUT_FILENAME}:/content"
    echo "Path: ${drive_path}"
  elif echo "$drives_response" | grep -q '"name":"Shared Documents"'; then
    echo "✅ Found 'Shared Documents' library"
    drive_id=$(echo "$drives_response" | grep -o '"name":"Shared Documents".*"id":"[^"]*' | 
               grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "")
    echo "Shared Documents library ID: $drive_id"
    drive_path="${site_url}/drive/root:/Shared%20Documents/${destination}/${OUTPUT_FILENAME}:/content"
    echo "Path: ${drive_path}"
  elif echo "$drives_response" | grep -q '"name":"DatasphereFileConnector"'; then
    echo "✅ Found 'DatasphereFileConnector' library"
    drive_id=$(echo "$drives_response" | grep -o '"name":"DatasphereFileConnector".*"id":"[^"]*' | 
               grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "")
    echo "DatasphereFileConnector library ID: $drive_id"
    drive_path="${site_url}/drive/root:/DatasphereFileConnector/${destination}/${OUTPUT_FILENAME}:/content"
    echo "Path: ${drive_path}"
  else
    # Default to the 'root' drive if no specific library found
    echo "⚠️ No specific document library found. Using default root drive."
    drive_path="${site_url}/drive/root:/${destination}/${OUTPUT_FILENAME}:/content"
    
    # Try to get the default drive ID
    drive_id=$(echo "$drives_response" | grep -o '"id":"[^"]*' | head -n1 | cut -d'"' -f4 || echo "")
    if [ -n "$drive_id" ]; then
      echo "Using first available drive ID: $drive_id"
    fi
  fi
  
  # Alternative direct ID-based path if we found a drive ID
  if [ -n "$drive_id" ]; then
    echo "✅ Found drive ID: $drive_id"
    echo "Alternative path: ${site_url}/drives/$drive_id/root:/${destination}/${OUTPUT_FILENAME}:/content"
  fi
  
  # Debug the final upload URL
  echo "Final upload URL: ${drive_path}"
  
  # If test mode is enabled, stop here without uploading
  if [ "$test_mode" = "true" ]; then
    echo "TEST MODE: Connection to SharePoint successful. Not uploading file."
    
    # Extract more detailed site information for better diagnostics
    local site_id=$(echo "$site_info" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
    local site_name=$(echo "$site_info" | grep -o '"name":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
    local site_display_name=$(echo "$site_info" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
    
    echo "==================== SHAREPOINT CONNECTION DETAILS ===================="
    echo "✅ Connected to SharePoint site: $site_display_name"
    echo "✅ Site internal name: $site_name"
    echo "✅ Full site ID: $site_id"
    echo "✅ Working URL format: $site_url"
    echo "======================================================================"
    
    # Recommend this format for future use
    echo ""
    echo "📝 RECOMMENDED: Use this site ID format in your configuration:"
    echo "$site_id"
    echo ""
    
    # Try to list drives in the site to validate deeper access
    echo "Testing document library access..."
    local drives_url="${site_url}/drives"
    echo "Drives URL: $drives_url"
    
    local drives_response=$(curl -s -X GET "$drives_url" \
      -H "Authorization: Bearer $access_token" \
      -H "Accept: application/json")
      
    echo "Response from document libraries request:"
    if echo "$drives_response" | grep -q '"name"'; then
      echo "✅ Successfully listed document libraries:"
      
      # Create a formatted table of library names and IDs
      echo "==================== DOCUMENT LIBRARIES ===================="
      echo "| Library Name | Library ID |"
      echo "|--------------+------------|"
      
      # Extract and print each library with its ID
      local libraries=$(echo "$drives_response" | grep -o '"name":"[^"]*.*?id":"[^"]*' || echo "")
      echo "$libraries" | while read -r line; do
        local name=$(echo "$line" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
        local id=$(echo "$line" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
        if [ -n "$name" ] && [ -n "$id" ]; then
          echo "| $name | $id |"
        fi
      done
      echo "=========================================================="
      
      # Extract the main document library ID for future use
      local document_library_id=$(echo "$drives_response" | grep -o '"name":"Documents".*' | 
                                 grep -o '"id":"[^"]*' | cut -d'"' -f4 || echo "")
      if [ -n "$document_library_id" ]; then
        echo "✅ Found Documents library with ID: $document_library_id"
        echo "📝 RECOMMENDED: Use this library ID for direct uploads:"
        echo "$document_library_id"
      fi
    else
      echo "❌ Failed to list document libraries:"
      if echo "$drives_response" | grep -q "error"; then
        local error_code=$(echo "$drives_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
        local error_message=$(echo "$drives_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
        echo "Error code: $error_code"
        echo "Error message: $error_message"
        
        echo ""
        echo "⚠️ TROUBLESHOOTING: Unable to access document libraries."
        echo "This typically indicates your app registration lacks sufficient permissions."
        echo "Please make sure your Azure app has these Graph API permissions:"
        echo "- Files.Read.All"
        echo "- Files.ReadWrite.All"
        echo "- Sites.Read.All"
        echo "- Sites.ReadWrite.All"
      else
        echo "Unexpected response format. Check API version and permissions."
      fi
    fi
    
    return 0
  fi
  
  echo "Uploading to SharePoint: ${destination}/${OUTPUT_FILENAME}"
  echo "Using API endpoint: $drive_path"
  
  # Upload file with exponential backoff retry
  local max_retries=4
  local retry=0
  local success=false
  local wait_time=5
  
  # Try alternative upload path if we have a drive ID (preferred method)
  if [ -n "$drive_id" ]; then
    echo "Using drive ID-based upload path as primary method (more reliable)"
    
    # Direct drive ID path is more reliable than path-based access
    drive_path="${site_url}/drives/$drive_id/root:/${destination}/${OUTPUT_FILENAME}:/content"
    echo "Final upload path: $drive_path"
    
    # Also create a backup path without the destination folder prefix
    # in case the full folder path doesn't exist
    backup_drive_path="${site_url}/drives/$drive_id/root:/${OUTPUT_FILENAME}:/content"
    echo "Backup upload path (if folder doesn't exist): $backup_drive_path"
    
    # Store these for potential fallback
    export BACKUP_DRIVE_PATH="$backup_drive_path"
    export DRIVE_ID="$drive_id"
  fi
  
  while (( retry < max_retries )) && [[ "$success" != "true" ]]; do
    echo "Upload attempt $((retry+1)) of $max_retries..."
    echo "Using path: $drive_path"
    
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
      
      # Record the successful URL format for future reference
      echo "Working URL format: $site_url" > /tmp/working_sharepoint_format.txt
      
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
            
            # Try to use backup path without the folder structure if available
            if [ -n "$BACKUP_DRIVE_PATH" ] && [ "$drive_path" != "$BACKUP_DRIVE_PATH" ]; then
              echo "Trying upload with simplified path (directly to root of document library)"
              drive_path="$BACKUP_DRIVE_PATH"
              echo "New path: $drive_path"
              continue  # Skip to next retry attempt with the new path
            fi
            
            # Try to create the destination folder
            echo "Attempting to create folder: $destination"
            
            # Use drive ID path if available (more reliable)
            if [ -n "$DRIVE_ID" ]; then
              local create_folder_url="${site_url}/drives/$DRIVE_ID/root:/children"
              echo "Creating folder using drive ID: $create_folder_url"
              curl -s -X POST "$create_folder_url" \
                -H "Authorization: Bearer $access_token" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"$destination\",\"folder\":{},\"@microsoft.graph.conflictBehavior\":\"replace\"}"
            else
              # Fallback to path-based folder creation
              local create_folder_url="${site_url}/drive/root:/$(dirname "$destination"):/children"
              echo "Creating folder using path: $create_folder_url"
              curl -s -X POST "$create_folder_url" \
                -H "Authorization: Bearer $access_token" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"$(basename "$destination")\",\"folder\":{},\"@microsoft.graph.conflictBehavior\":\"replace\"}"
            fi
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
  local test_mode="${TEST_MODE:-false}"
  
  if [ "$test_mode" = "true" ]; then
    echo "Running in TEST MODE: Will only test connection, not upload files."
  fi
  
  # Get access token
  local access_token=$(get_access_token)
  if [[ -z "$access_token" ]]; then
    exit 1
  fi
  
  # Upload changelog (or just test connection if in test mode)
  if ! upload_to_sharepoint "$access_token" "$CHANGELOG_FILE" "$SHAREPOINT_FOLDER" "$test_mode"; then
    exit 1
  fi
  
  echo "SharePoint upload completed successfully"
}

# Run main function
main
