#!/bin/bash
# Advanced SharePoint Connectivity Test Script
# This script tests connectivity to SharePoint in multiple ways to help diagnose issues

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print header
print_header() {
  echo -e "\n${BLUE}====== $1 ======${NC}\n"
}

# Print success message
print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

# Print error message
print_error() {
  echo -e "${RED}❌ $1${NC}"
}

# Print warning message
print_warning() {
  echo -e "${YELLOW}⚠️ $1${NC}"
}

# Print info message
print_info() {
  echo -e "ℹ️ $1"
}

# Check if required environment variables are set
check_env_vars() {
  print_header "Checking environment variables"
  
  local missing=0
  if [[ -z "$SHAREPOINT_CLIENT_ID" ]]; then
    print_error "SHAREPOINT_CLIENT_ID is not set."
    missing=1
  else
    print_success "SHAREPOINT_CLIENT_ID is set."
  fi

  if [[ -z "$SHAREPOINT_CLIENT_SECRET" ]]; then
    print_error "SHAREPOINT_CLIENT_SECRET is not set."
    missing=1
  else
    print_success "SHAREPOINT_CLIENT_SECRET is set."
  fi

  if [[ -z "$SHAREPOINT_TENANT_ID" ]]; then
    print_error "SHAREPOINT_TENANT_ID is not set."
    missing=1
  else
    print_success "SHAREPOINT_TENANT_ID is set."
  fi

  if [[ -z "$SHAREPOINT_SITE_ID" ]]; then
    print_error "SHAREPOINT_SITE_ID is not set."
    missing=1
  else
    print_success "SHAREPOINT_SITE_ID is set."
  fi
  
  if [[ $missing -eq 1 ]]; then
    print_error "Required environment variables are missing."
    return 1
  fi
  
  return 0
}

# Function to test network connectivity with various options
test_network_connectivity() {
  local target="$1"
  local description="$2"
  
  print_info "Testing connectivity to $target ($description)..."
  
  # Try standard connection
  if curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    print_success "Standard connection to $target works"
    echo "CONN_METHOD=\"standard\"" >> "/tmp/sharepoint_conn_test_results.txt"
    return 0
  fi
  
  # Try direct connection (no proxy)
  if curl --noproxy '*' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    print_success "Direct connection (no proxy) to $target works"
    echo "CONN_METHOD=\"noproxy\"" >> "/tmp/sharepoint_conn_test_results.txt"
    return 0
  fi
  
  # Try with TLSv1.2 explicitly
  if curl --tlsv1.2 --noproxy '*' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    print_success "TLSv1.2 connection to $target works"
    echo "CONN_METHOD=\"tlsv1.2 noproxy\"" >> "/tmp/sharepoint_conn_test_results.txt"
    return 0
  fi
  
  # Try with TLSv1.1 explicitly
  if curl --tlsv1.1 --noproxy '*' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    print_success "TLSv1.1 connection to $target works"
    echo "CONN_METHOD=\"tlsv1.1 noproxy\"" >> "/tmp/sharepoint_conn_test_results.txt"
    return 0
  fi
  
  # Try with alternative ciphers
  if curl --tlsv1.2 --noproxy '*' --ciphers 'DEFAULT:!DH' -s --max-time 5 -o /dev/null -w "%{http_code}" "$target" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
    print_success "TLSv1.2 with alternative ciphers to $target works"
    echo "CONN_METHOD=\"tlsv1.2 noproxy alt-ciphers\"" >> "/tmp/sharepoint_conn_test_results.txt"
    return 0
  fi
  
  print_error "All connection methods to $target failed"
  return 1
}

# Test DNS resolution
test_dns() {
  print_header "Testing DNS resolution"
  
  echo "Resolving login.microsoftonline.com..."
  if host login.microsoftonline.com >/dev/null 2>&1; then
    print_success "DNS resolution for login.microsoftonline.com works"
  else
    print_error "DNS resolution for login.microsoftonline.com failed"
    # Try with dig as alternative
    if dig login.microsoftonline.com >/dev/null 2>&1; then
      print_success "Dig resolution for login.microsoftonline.com works"
    fi
  fi
  
  echo "Resolving graph.microsoft.com..."
  if host graph.microsoft.com >/dev/null 2>&1; then
    print_success "DNS resolution for graph.microsoft.com works"
  else
    print_error "DNS resolution for graph.microsoft.com failed"
    # Try with dig as alternative
    if dig graph.microsoft.com >/dev/null 2>&1; then
      print_success "Dig resolution for graph.microsoft.com works"
    fi
  fi
}

# Test network connectivity
test_network() {
  print_header "Testing network connectivity"
  
  rm -f /tmp/sharepoint_conn_test_results.txt
  touch /tmp/sharepoint_conn_test_results.txt
  
  test_network_connectivity "https://login.microsoftonline.com" "Authentication Endpoint"
  test_network_connectivity "https://graph.microsoft.com/v1.0/$metadata" "Microsoft Graph API"
}

# Get OAuth token
get_oauth_token() {
  print_header "Getting OAuth token"
  
  local token_url="https://login.microsoftonline.com/${SHAREPOINT_TENANT_ID}/oauth2/v2.0/token"
  local scope="https://graph.microsoft.com/.default"
  
  print_info "Getting token from: $token_url"
  
  # Read connection method if available
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    if [ -n "$CONN_METHOD" ]; then
      print_info "Using connection method: $CONN_METHOD"
      curl_opts="$curl_opts $CONN_METHOD"
    fi
  fi
  
  print_info "Using curl options: $curl_opts"
  
  # Get token
  local response=$(curl $curl_opts -X POST "$token_url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${SHAREPOINT_CLIENT_ID}&scope=${scope}&client_secret=${SHAREPOINT_CLIENT_SECRET}&grant_type=client_credentials" 2>&1)
  
  # Check if token was obtained
  if [[ "$response" == *"access_token"* ]]; then
    local access_token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    if [[ -n "$access_token" ]]; then
      print_success "Access token obtained (${#access_token} characters)"
      echo "ACCESS_TOKEN=\"$access_token\"" >> "/tmp/sharepoint_conn_test_results.txt"
      return 0
    fi
  fi
  
  print_error "Failed to get access token"
  if [[ "$response" == *"error"* && "$response" == *"{"* ]]; then
    local error_code=$(echo "$response" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
    local error_desc=$(echo "$response" | grep -o '"error_description":"[^"]*' | cut -d'"' -f4 || echo "No detailed description")
    print_error "Error code: $error_code"
    print_error "Error description: $error_desc"
  else
    print_error "Unexpected response: $response"
  fi
  
  return 1
}

# Test SharePoint site access
test_sharepoint_site() {
  print_header "Testing SharePoint site access"
  
  # Load access token
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    if [ -z "$ACCESS_TOKEN" ]; then
      print_error "No access token available"
      return 1
    fi
  else
    print_error "No test results file available"
    return 1
  fi
  
  # Set curl options
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ -n "$CONN_METHOD" ]; then
    curl_opts="$curl_opts $CONN_METHOD"
  fi
  
  # Test site access with direct ID
  local site_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
  print_info "Testing site access with URL: $site_url"
  
  local site_response=$(curl $curl_opts -X GET "$site_url" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
  
  if [[ "$site_response" == *"\"id\":"* ]]; then
    local site_name=$(echo "$site_response" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
    local site_display_name=$(echo "$site_response" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
    local site_web_url=$(echo "$site_response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
    
    print_success "SharePoint site access successful"
    print_info "Site name: $site_name"
    print_info "Display name: $site_display_name" 
    print_info "Web URL: $site_web_url"
    
    # Save site details
    echo "SITE_NAME=\"$site_name\"" >> "/tmp/sharepoint_conn_test_results.txt"
    echo "SITE_DISPLAY_NAME=\"$site_display_name\"" >> "/tmp/sharepoint_conn_test_results.txt"
    echo "SITE_WEB_URL=\"$site_web_url\"" >> "/tmp/sharepoint_conn_test_results.txt"
    
    return 0
  else
    print_error "Failed to access SharePoint site"
    if [[ "$site_response" == *"error"* ]]; then
      local error_code=$(echo "$site_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
      local error_message=$(echo "$site_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
      print_error "Error code: $error_code"
      print_error "Error message: $error_message"
    else
      print_error "Unexpected response: $site_response"
    fi
    
    return 1
  fi
}

# Test document libraries
test_document_libraries() {
  print_header "Testing document libraries access"
  
  # Load access token and site info
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    if [ -z "$ACCESS_TOKEN" ]; then
      print_error "No access token available"
      return 1
    fi
  else
    print_error "No test results file available"
    return 1
  fi
  
  # Set curl options
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ -n "$CONN_METHOD" ]; then
    curl_opts="$curl_opts $CONN_METHOD"
  fi
  
  # Get drives
  local site_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
  local drives_url="${site_url}/drives"
  print_info "Getting document libraries from: $drives_url"
  
  local drives_response=$(curl $curl_opts -X GET "$drives_url" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
  
  if [[ "$drives_response" == *"\"value\":"* ]]; then
    print_success "Document libraries access successful"
    
    # Extract and print each library with its ID
    print_info "Available document libraries:"
    echo "| Library Name | Library ID |"
    echo "|--------------+------------|"
    
    # Extract libraries using grep and JSON parsing
    echo "$drives_response" | grep -o '"name":"[^"]*.*?id":"[^"]*' | while read -r line; do
      local name=$(echo "$line" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
      local id=$(echo "$line" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
      if [ -n "$name" ] && [ -n "$id" ]; then
        echo "| $name | $id |"
        
        # Save Documents library ID if found
        if [ "$name" == "Documents" ]; then
          echo "DOCUMENTS_LIBRARY_ID=\"$id\"" >> "/tmp/sharepoint_conn_test_results.txt"
          print_success "Found Documents library with ID: $id"
        fi
      fi
    done
    
    return 0
  else
    print_error "Failed to access document libraries"
    if [[ "$drives_response" == *"error"* ]]; then
      local error_code=$(echo "$drives_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
      local error_message=$(echo "$drives_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
      print_error "Error code: $error_code"
      print_error "Error message: $error_message"
    else
      print_error "Unexpected response: $drives_response"
    fi
    
    return 1
  fi
}

# Test Diagrams folder existence
test_diagrams_folder() {
  print_header "Testing Diagrams folder existence"
  
  # Load access token and libraries info
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    if [ -z "$ACCESS_TOKEN" ] || [ -z "$DOCUMENTS_LIBRARY_ID" ]; then
      print_error "Missing access token or Documents library ID"
      return 1
    fi
  else
    print_error "No test results file available"
    return 1
  fi
  
  # Set curl options
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ -n "$CONN_METHOD" ]; then
    curl_opts="$curl_opts $CONN_METHOD"
  fi
  
  # Test Diagrams folder
  local site_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
  local diagrams_url="${site_url}/drives/${DOCUMENTS_LIBRARY_ID}/root:/Documents/Diagrams:/children"
  print_info "Testing Diagrams folder: $diagrams_url"
  
  local folder_response=$(curl $curl_opts -X GET "$diagrams_url" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
  
  if [[ "$folder_response" == *"\"value\":"* ]]; then
    print_success "Diagrams folder exists"
    return 0
  elif [[ "$folder_response" == *"itemNotFound"* ]]; then
    print_warning "Diagrams folder does not exist"
    print_info "You might need to create the folder before uploading"
    return 1
  else
    print_error "Failed to check Diagrams folder"
    if [[ "$folder_response" == *"error"* ]]; then
      local error_code=$(echo "$folder_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
      local error_message=$(echo "$folder_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
      print_error "Error code: $error_code"
      print_error "Error message: $error_message"
    else
      print_error "Unexpected response: $folder_response"
    fi
    
    return 1
  fi
}

# Test upload paths
test_upload_paths() {
  print_header "Testing upload paths"
  
  # Load access token and libraries info
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    if [ -z "$ACCESS_TOKEN" ] || [ -z "$DOCUMENTS_LIBRARY_ID" ]; then
      print_error "Missing access token or Documents library ID"
      return 1
    fi
  else
    print_error "No test results file available"
    return 1
  fi
  
  local site_url="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}"
  
  # Prepare possible upload paths
  local paths=(
    "${site_url}/drives/${DOCUMENTS_LIBRARY_ID}/root:/Documents/Diagrams/test_upload.txt:/content"
    "${site_url}/drives/${DOCUMENTS_LIBRARY_ID}/root:/Documents/test_upload.txt:/content"
    "${site_url}/drives/${DOCUMENTS_LIBRARY_ID}/root:/test_upload.txt:/content"
  )
  
  # Create a test file
  echo "SharePoint upload test at $(date)" > /tmp/test_upload.txt
  
  # Set curl options
  local curl_opts="-s --connect-timeout 20 --max-time 60"
  if [ -n "$CONN_METHOD" ]; then
    curl_opts="$curl_opts $CONN_METHOD"
  fi
  
  # Test each path
  for path in "${paths[@]}"; do
    print_info "Testing upload path: $path"
    
    local upload_response=$(curl $curl_opts -X PUT "$path" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: text/plain" \
      --data-binary "@/tmp/test_upload.txt")
    
    if [[ "$upload_response" == *"\"id\":"* ]]; then
      print_success "Upload to path successful: $path"
      local web_url=$(echo "$upload_response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
      print_info "File URL: $web_url"
      
      # Save the working path
      echo "WORKING_UPLOAD_PATH=\"$path\"" >> "/tmp/sharepoint_conn_test_results.txt"
      return 0
    else
      print_warning "Upload to path failed: $path"
      if [[ "$upload_response" == *"error"* ]]; then
        local error_code=$(echo "$upload_response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
        local error_message=$(echo "$upload_response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
        print_warning "Error code: $error_code"
        print_warning "Error message: $error_message"
      fi
    fi
  done
  
  print_error "All upload paths failed"
  return 1
}

# Print summary
print_summary() {
  print_header "Summary"
  
  if [ -f "/tmp/sharepoint_conn_test_results.txt" ]; then
    source "/tmp/sharepoint_conn_test_results.txt"
    
    echo -e "${BLUE}========================================"
    echo "SharePoint Connectivity Test Results"
    echo "========================================${NC}"
    
    # Connection method
    if [ -n "$CONN_METHOD" ]; then
      print_success "Working connection method: $CONN_METHOD"
      print_info "Add these options to your curl commands"
    else
      print_error "No working connection method found"
    fi
    
    # Authentication
    if [ -n "$ACCESS_TOKEN" ]; then
      print_success "OAuth authentication successful"
    else
      print_error "OAuth authentication failed"
    fi
    
    # Site access
    if [ -n "$SITE_NAME" ]; then
      print_success "SharePoint site access successful"
      print_info "Site name: $SITE_NAME"
      print_info "Display name: $SITE_DISPLAY_NAME"
    else
      print_error "SharePoint site access failed"
    fi
    
    # Documents library
    if [ -n "$DOCUMENTS_LIBRARY_ID" ]; then
      print_success "Documents library found"
      print_info "ID: $DOCUMENTS_LIBRARY_ID"
      print_info "Use this ID for direct upload paths"
    else
      print_error "Documents library not found"
    fi
    
    # Upload path
    if [ -n "$WORKING_UPLOAD_PATH" ]; then
      print_success "Working upload path found"
      print_info "Path: $WORKING_UPLOAD_PATH"
    else
      print_error "No working upload path found"
    fi
    
    # Recommendations
    echo -e "\n${BLUE}========== RECOMMENDATIONS ==========${NC}"
    
    if [ -n "$DOCUMENTS_LIBRARY_ID" ]; then
      echo "export SHAREPOINT_DRIVE_ID=\"$DOCUMENTS_LIBRARY_ID\""
    fi
    
    if [ -n "$CONN_METHOD" ]; then
      if [[ "$CONN_METHOD" == *"noproxy"* ]]; then
        echo "export USE_DIRECT_CONNECTION=\"true\""
      fi
      if [[ "$CONN_METHOD" == *"tlsv1.2"* ]]; then
        echo "export FORCE_TLS=\"true\""
      fi
    fi
    
    if [ -n "$WORKING_UPLOAD_PATH" ]; then
      local path_pattern=$(echo "$WORKING_UPLOAD_PATH" | sed 's|/test_upload.txt|/${OUTPUT_FILENAME}|g')
      echo -e "\nRecommended upload path format:"
      echo "$path_pattern"
    fi
  else
    print_error "No test results available"
  fi
}

# Main function
main() {
  # Create results file
  rm -f /tmp/sharepoint_conn_test_results.txt
  touch /tmp/sharepoint_conn_test_results.txt
  
  print_header "SharePoint Connectivity Test"
  print_info "Testing SharePoint connectivity with multiple methods"
  print_info "This may take a few minutes..."
  
  # Run all tests
  check_env_vars && \
  test_dns && \
  test_network && \
  get_oauth_token && \
  test_sharepoint_site && \
  test_document_libraries && \
  test_diagrams_folder && \
  test_upload_paths
  
  # Print summary regardless of test results
  print_summary
}

# Run main function
main "$@"
