#!/bin/bash

# Advanced SharePoint Connection Test Script
# Tests connectivity to Microsoft Graph API and SharePoint sites with enhanced diagnostics

# Set colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --client-id CLIENT_ID       Azure AD application client ID"
    echo "  -s, --client-secret SECRET      Azure AD application client secret"
    echo "  -t, --tenant-id TENANT_ID       Azure AD tenant ID"
    echo "  -i, --site-id SITE_ID           SharePoint site ID"
    echo "  -u, --site-url URL              SharePoint site URL"
    echo "  -f, --full-diagnostics          Run full network diagnostics"
    echo "  -h, --help                      Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -c 26d1a5-app-id -s your-secret -t a8d22be6-tenant -i e39939c2-site-id"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--client-id)
            CLIENT_ID="$2"
            shift 2
            ;;
        -s|--client-secret)
            CLIENT_SECRET="$2"
            shift 2
            ;;
        -t|--tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        -i|--site-id)
            SITE_ID="$2"
            shift 2
            ;;
        -u|--site-url)
            SITE_URL="$2"
            shift 2
            ;;
        -f|--full-diagnostics)
            FULL_DIAGNOSTICS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$TENANT_ID" ]]; then
    echo -e "${RED}ERROR: Client ID, Client Secret, and Tenant ID are required.${NC}"
    usage
    exit 1
fi

# Default site URL if not provided
if [[ -z "$SITE_URL" && -z "$SITE_ID" ]]; then
    echo -e "${YELLOW}WARNING: No site URL or ID provided, only testing authentication and basic connectivity${NC}"
fi

echo -e "${BLUE}============== SharePoint Connection Test ==============${NC}"
echo "Testing connectivity to Microsoft Graph API and SharePoint..."
echo ""

# Function to check network connectivity
check_network_connectivity() {
    local target="$1"
    local timeout="${2:-5}"
    echo -e "${BLUE}🔌 Testing network connectivity to $target...${NC}"
    
    # Test connection with timeout
    local result=$(curl -s --max-time "$timeout" -o /dev/null -w "%{http_code}" "$target")
    echo "HTTP status code: $result"
    
    if echo "$result" | grep -q "2[0-9][0-9]\|3[0-9][0-9]"; then
        echo -e "${GREEN}✅ Network connectivity to $target is working${NC}"
        return 0
    else
        echo -e "${RED}❌ Cannot connect to $target${NC}"
        return 1
    fi
}

# Function to test with various connectivity options
test_connectivity_options() {
    local target="$1"
    local description="$2"
    
    echo -e "${BLUE}========== TESTING CONNECTION OPTIONS: $description ==========${NC}"
    
    # 1. Standard connection attempt
    echo -e "${YELLOW}1. Standard connection...${NC}"
    if curl -s --max-time 10 -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" "$target"; then
        echo -e "${GREEN}✅ Standard connection works!${NC}"
        CONNECTION_TYPE="standard"
        return 0
    else
        echo -e "${YELLOW}⚠️ Standard connection failed${NC}"
    fi
    
    # 2. Try without proxy
    echo -e "${YELLOW}2. No proxy connection...${NC}"
    if curl --noproxy '*' -s --max-time 10 -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" "$target"; then
        echo -e "${GREEN}✅ Direct connection (no proxy) works!${NC}"
        CONNECTION_TYPE="noproxy"
        export USE_DIRECT_CONNECTION="true"
        return 0
    else
        echo -e "${YELLOW}⚠️ No proxy connection failed${NC}"
    fi
    
    # 3. Force TLS version
    echo -e "${YELLOW}3. Forcing TLSv1.2...${NC}"
    if curl --tlsv1.2 -s --max-time 10 -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" "$target"; then
        echo -e "${GREEN}✅ TLSv1.2 connection works!${NC}"
        CONNECTION_TYPE="tlsv1.2"
        export FORCE_TLS="tlsv1.2"
        return 0
    else
        echo -e "${YELLOW}⚠️ TLSv1.2 connection failed${NC}"
    fi
    
    # 4. Combination of no proxy and TLS version
    echo -e "${YELLOW}4. No proxy + TLSv1.2...${NC}"
    if curl --noproxy '*' --tlsv1.2 -s --max-time 10 -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" "$target"; then
        echo -e "${GREEN}✅ No proxy + TLSv1.2 connection works!${NC}"
        CONNECTION_TYPE="noproxy+tlsv1.2"
        export USE_DIRECT_CONNECTION="true"
        export FORCE_TLS="tlsv1.2"
        return 0
    else
        echo -e "${YELLOW}⚠️ No proxy + TLSv1.2 connection failed${NC}"
    fi
    
    echo -e "${RED}❌ All connection methods failed${NC}"
    return 1
}

# Function to run advanced network diagnostics
run_network_diagnostics() {
    echo -e "${BLUE}========== RUNNING NETWORK DIAGNOSTICS ==========${NC}"
    
    # Check system information
    echo -e "${YELLOW}System Information:${NC}"
    uname -a
    
    # Check DNS resolution
    echo -e "\n${YELLOW}DNS Resolution:${NC}"
    echo -n "login.microsoftonline.com: "
    nslookup login.microsoftonline.com || echo "Failed"
    
    echo -n "graph.microsoft.com: "
    nslookup graph.microsoft.com || echo "Failed"
    
    # Check TLS/SSL capabilities
    echo -e "\n${YELLOW}TLS/SSL Capabilities:${NC}"
    echo "Testing TLS handshake with login.microsoftonline.com..."
    curl -v --tlsv1.2 --max-time 5 https://login.microsoftonline.com/ 2>&1 | grep -i "SSL\|TLS\|handshake" | head -5
    
    # Check proxy settings
    echo -e "\n${YELLOW}Proxy Environment Variables:${NC}"
    env | grep -i proxy || echo "No proxy environment variables set"
    
    # Check outbound connectivity
    echo -e "\n${YELLOW}Outbound Connectivity:${NC}"
    for port in 80 443; do
        echo "Testing outbound connectivity to graph.microsoft.com:$port..."
        nc -zv graph.microsoft.com $port 2>&1 || echo "Failed to connect to port $port"
    done
    
    # Check HTTPS with verbose output
    echo -e "\n${YELLOW}HTTPS Connection Details:${NC}"
    curl -v --max-time 10 https://graph.microsoft.com/v1.0/$metadata 2>&1 | grep -v "^*" | head -20
    
    echo -e "${BLUE}========== END OF NETWORK DIAGNOSTICS ==========${NC}"
}

# Function to test proxy settings
test_proxy_settings() {
    echo -e "${BLUE}========== TESTING PROXY CONFIGURATIONS ==========${NC}"
    
    # Check if proxy environment variables are set
    if [[ -n "$HTTP_PROXY" || -n "$HTTPS_PROXY" || -n "$http_proxy" || -n "$https_proxy" ]]; then
        echo -e "${YELLOW}Proxy environment variables detected:${NC}"
        [[ -n "$HTTP_PROXY" ]] && echo "  HTTP_PROXY=$HTTP_PROXY"
        [[ -n "$HTTPS_PROXY" ]] && echo "  HTTPS_PROXY=$HTTPS_PROXY"
        [[ -n "$http_proxy" ]] && echo "  http_proxy=$http_proxy"
        [[ -n "$https_proxy" ]] && echo "  https_proxy=$https_proxy"
        [[ -n "$NO_PROXY" ]] && echo "  NO_PROXY=$NO_PROXY"
        [[ -n "$no_proxy" ]] && echo "  no_proxy=$no_proxy"
        
        # Test connection with proxy
        echo -e "${YELLOW}Testing connection with system proxy settings...${NC}"
        if curl -s --max-time 10 -o /dev/null -w "HTTP Status: %{http_code}\n" "https://graph.microsoft.com/v1.0/$metadata"; then
            echo -e "${GREEN}✅ Connection using system proxy settings works!${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️ Connection using system proxy settings failed${NC}"
        fi
    else
        echo "No proxy environment variables detected"
    fi
    
    # Try direct connection
    echo -e "${YELLOW}Testing direct connection (no proxy)...${NC}"
    if curl --noproxy '*' -s --max-time 10 -o /dev/null -w "HTTP Status: %{http_code}\n" "https://graph.microsoft.com/v1.0/$metadata"; then
        echo -e "${GREEN}✅ Direct connection works!${NC}"
        export USE_DIRECT_CONNECTION="true"
        return 0
    else
        echo -e "${YELLOW}⚠️ Direct connection failed${NC}"
    fi
    
    echo -e "${BLUE}===============================================${NC}"
    return 1
}

# Function to get OAuth token with optimal connection settings
get_oauth_token() {
    echo -e "${BLUE}🔑 Obtaining OAuth token...${NC}"
    
    # Base curl options based on successful connection method
    local curl_opts="-s --connect-timeout 15 --max-time 30"
    if [[ "$USE_DIRECT_CONNECTION" == "true" ]]; then
        curl_opts="$curl_opts --noproxy '*'"
    fi
    if [[ -n "$FORCE_TLS" ]]; then
        curl_opts="$curl_opts --$FORCE_TLS"
    fi
    
    echo "Using curl options: $curl_opts"
    
    local token_url="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"
    local scope="https://graph.microsoft.com/.default"
    
    # Try to get token
    local token_response=$(curl $curl_opts -X POST \
        "$token_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&scope=$scope&client_secret=$CLIENT_SECRET&grant_type=client_credentials")
    
    # Check if token was obtained successfully
    if [[ "$token_response" == *"access_token"* ]]; then
        TOKEN=$(echo "$token_response" | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')
        
        # Check token length
        if [[ -n "$TOKEN" && ${#TOKEN} -gt 50 ]]; then
            echo -e "${GREEN}✅ OAuth token obtained successfully (${#TOKEN} characters)${NC}"
            return 0
        else
            echo -e "${RED}❌ Token obtained but seems invalid (${#TOKEN} characters)${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to obtain OAuth token${NC}"
        echo "Response: $token_response"
        
        # Check for specific error codes
        if [[ "$token_response" == *"error"* ]]; then
            local error_code=$(echo "$token_response" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
            local error_description=$(echo "$token_response" | grep -o '"error_description":"[^"]*' | cut -d'"' -f4)
            echo "Error code: $error_code"
            echo "Error description: $error_description"
        fi
    fi
    
    return 1
}

# Function to test SharePoint site access
test_site_access() {
    local site_id="$1"
    local site_url="$2"
    
    echo -e "${BLUE}🔍 Testing SharePoint site access...${NC}"
    
    # Base curl options
    local curl_opts="-s --connect-timeout 15 --max-time 30"
    if [[ "$USE_DIRECT_CONNECTION" == "true" ]]; then
        curl_opts="$curl_opts --noproxy '*'"
    fi
    if [[ -n "$FORCE_TLS" ]]; then
        curl_opts="$curl_opts --$FORCE_TLS"
    fi
    
    # Array of URL formats to try
    local formats=(
        # Direct site ID format (most reliable)
        "https://graph.microsoft.com/v1.0/sites/$site_id"
    )
    
    # Extract domain and site name if URL is provided
    if [[ -n "$site_url" ]]; then
        domain=$(echo "$site_url" | sed -E 's|https?://([^/]+)/.*|\1|')
        site_name=$(echo "$site_url" | sed -E 's|.*/sites/([^/]+).*|\1|')
        
        if [[ -n "$domain" && -n "$site_name" ]]; then
            formats+=(
                "https://graph.microsoft.com/v1.0/sites/$domain:/sites/$site_name"
                "https://graph.microsoft.com/v1.0/sites/$domain/sites/$site_name"
            )
        fi
    fi
    
    # Add frostaag-specific formats
    formats+=(
        "https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:/sites/DatasphereFileConnector"
        "https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com/sites/DatasphereFileConnector"
    )
    
    # Test each format
    local success=false
    local best_format=""
    local site_info=""
    
    for format in "${formats[@]}"; do
        echo -e "${YELLOW}Testing: $format${NC}"
        
        # Send request
        local response=$(curl $curl_opts \
            -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/json" \
            "$format")
        
        # Check for successful response (look for id in response)
        if [[ "$response" == *"\"id\":"* ]]; then
            echo -e "${GREEN}✅ Success with format: $format${NC}"
            echo "Response fields:"
            echo "$response" | grep -E '"id"|"name"|"displayName"|"webUrl"' | sed 's/,$//'
            success=true
            best_format="$format"
            site_info="$response"
            break
        else
            echo -e "${RED}❌ Failed with format: $format${NC}"
            
            # Check for specific error patterns
            if [[ "$response" == *"\"error\":"* ]]; then
                local error_code=$(echo "$response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
                local error_message=$(echo "$response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
                echo "Error code: $error_code"
                echo "Error message: $error_message"
            fi
        fi
    done
    
    # Save successful format and info
    if [[ "$success" == "true" ]]; then
        export BEST_SITE_FORMAT="$best_format"
        export SITE_INFO="$site_info"
        
        # Extract site details for future use
        export SITE_ID_FROM_RESPONSE=$(echo "$site_info" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
        export SITE_NAME=$(echo "$site_info" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
        export SITE_DISPLAY_NAME=$(echo "$site_info" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4)
        export SITE_WEB_URL=$(echo "$site_info" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
        
        return 0
    else
        return 1
    fi
}

# Function to test Drive (document libraries) access
test_drive_access() {
    echo -e "${BLUE}📂 Testing Drive access...${NC}"
    
    # Base curl options
    local curl_opts="-s --connect-timeout 15 --max-time 30"
    if [[ "$USE_DIRECT_CONNECTION" == "true" ]]; then
        curl_opts="$curl_opts --noproxy '*'"
    fi
    if [[ -n "$FORCE_TLS" ]]; then
        curl_opts="$curl_opts --$FORCE_TLS"
    fi
    
    # Use best site format from previous test
    local drives_url="$BEST_SITE_FORMAT/drives"
    echo -e "${YELLOW}Requesting drives from: $drives_url${NC}"
    
    # Send request
    local response=$(curl $curl_opts \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json" \
        "$drives_url")
    
    # Check for successful response
    if [[ "$response" == *"\"value\":"* ]]; then
        echo -e "${GREEN}✅ Successfully retrieved document libraries${NC}"
        
        # Extract drive info
        echo "Available document libraries:"
        echo "$response" | grep -o '"name":"[^"]*' | cut -d'"' -f4 | sort | uniq | while read -r lib; do
            echo "- $lib"
        done
        
        # Find Documents library
        if [[ "$response" == *"\"name\":\"Documents\""* ]]; then
            echo -e "\n${GREEN}✅ Found 'Documents' library${NC}"
            DOCUMENTS_DRIVE_ID=$(echo "$response" | grep -o '"name":"Documents".*"id":"[^"]*' | 
                              grep -o '"id":"[^"]*' | cut -d'"' -f4)
            echo "Documents library ID: $DOCUMENTS_DRIVE_ID"
            export DOCUMENTS_DRIVE_ID
        fi
        
        return 0
    else
        echo -e "${RED}❌ Failed to retrieve document libraries${NC}"
        
        # Check for specific error patterns
        if [[ "$response" == *"\"error\":"* ]]; then
            local error_code=$(echo "$response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
            local error_message=$(echo "$response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
            echo "Error code: $error_code"
            echo "Error message: $error_message"
        fi
        
        return 1
    fi
}

# Function to test file upload capability
test_file_upload() {
    echo -e "${BLUE}📤 Testing file upload capability...${NC}"
    
    # Skip if no drive ID found
    if [[ -z "$DOCUMENTS_DRIVE_ID" ]]; then
        echo -e "${YELLOW}⚠️ No document library ID found, skipping upload test${NC}"
        return 0
    fi
    
    # Create a small test file
    local test_file="/tmp/sharepoint_test_file.txt"
    echo "This is a test file created at $(date)" > "$test_file"
    
    # Base curl options
    local curl_opts="-s --connect-timeout 15 --max-time 30"
    if [[ "$USE_DIRECT_CONNECTION" == "true" ]]; then
        curl_opts="$curl_opts --noproxy '*'"
    fi
    if [[ -n "$FORCE_TLS" ]]; then
        curl_opts="$curl_opts --$FORCE_TLS"
    fi
    
    # Compute file size
    local file_size=$(wc -c < "$test_file")
    
    # Upload URL
    local upload_url="$BEST_SITE_FORMAT/drives/$DOCUMENTS_DRIVE_ID/root:/sharepoint_connection_test.txt:/content"
    echo -e "${YELLOW}Uploading test file to: $upload_url${NC}"
    
    # Send request
    local response=$(curl $curl_opts -X PUT \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: text/plain" \
        -H "Content-Length: $file_size" \
        --data-binary "@$test_file" \
        "$upload_url")
    
    # Check for successful response
    if [[ "$response" == *"\"id\":"* ]]; then
        echo -e "${GREEN}✅ Successfully uploaded test file${NC}"
        
        # Extract file info
        local file_id=$(echo "$response" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
        local web_url=$(echo "$response" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4)
        
        echo "File ID: $file_id"
        echo "Web URL: $web_url"
        
        return 0
    else
        echo -e "${RED}❌ Failed to upload test file${NC}"
        
        # Check for specific error patterns
        if [[ "$response" == *"\"error\":"* ]]; then
            local error_code=$(echo "$response" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
            local error_message=$(echo "$response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
            echo "Error code: $error_code"
            echo "Error message: $error_message"
        fi
        
        return 1
    fi
}

# Main test sequence
echo -e "${BLUE}=== 1. TESTING NETWORK CONNECTIVITY ===${NC}"
check_network_connectivity "https://login.microsoftonline.com" 5
check_network_connectivity "https://graph.microsoft.com" 5
test_connectivity_options "https://graph.microsoft.com/v1.0/$metadata" "Microsoft Graph API"

# Run full diagnostics if requested
if [[ "$FULL_DIAGNOSTICS" == "true" ]]; then
    echo -e "\n${BLUE}=== RUNNING FULL NETWORK DIAGNOSTICS ===${NC}"
    run_network_diagnostics
fi

echo -e "\n${BLUE}=== 2. TESTING AUTHENTICATION ===${NC}"
if get_oauth_token; then
    echo -e "${GREEN}✅ Authentication successful${NC}"
    
    if [[ -n "$SITE_ID" || -n "$SITE_URL" ]]; then
        echo -e "\n${BLUE}=== 3. TESTING SITE ACCESS ===${NC}"
        if test_site_access "$SITE_ID" "$SITE_URL"; then
            echo -e "${GREEN}✅ Site access successful${NC}"
            echo "Site name: $SITE_DISPLAY_NAME"
            echo "Site URL: $SITE_WEB_URL"
            
            echo -e "\n${BLUE}=== 4. TESTING DRIVE ACCESS ===${NC}"
            if test_drive_access; then
                echo -e "${GREEN}✅ Drive access successful${NC}"
                
                # Test file upload if we have a drive ID
                if [[ -n "$DOCUMENTS_DRIVE_ID" ]]; then
                    echo -e "\n${BLUE}=== 5. TESTING FILE UPLOAD ===${NC}"
                    if test_file_upload; then
                        echo -e "\n${GREEN}✅ ALL TESTS PASSED! Your SharePoint connection is working correctly.${NC}"
                        
                        # Save successful connection settings
                        echo -e "\n${BLUE}=== SAVING SUCCESSFUL CONNECTION SETTINGS ===${NC}"
                        echo "Connection type: $CONNECTION_TYPE"
                        echo "Site format: $BEST_SITE_FORMAT"
                        echo "Site ID from response: $SITE_ID_FROM_RESPONSE"
                        
                        if [[ -n "$DOCUMENTS_DRIVE_ID" ]]; then
                            echo "Documents library ID: $DOCUMENTS_DRIVE_ID"
                        fi
                        
                        # Create a settings file
                        cat > "/tmp/sharepoint_connection_settings.txt" << EOF
# SharePoint connection settings that worked
CONNECTION_TYPE=$CONNECTION_TYPE
USE_DIRECT_CONNECTION=$USE_DIRECT_CONNECTION
FORCE_TLS=$FORCE_TLS
SITE_FORMAT=$BEST_SITE_FORMAT
SITE_ID=$SITE_ID_FROM_RESPONSE
DOCUMENTS_DRIVE_ID=$DOCUMENTS_DRIVE_ID
EOF
                        
                        echo -e "${GREEN}Settings saved to /tmp/sharepoint_connection_settings.txt${NC}"
                        exit 0
                    else
                        echo -e "${YELLOW}⚠️ Partial success: Authentication, site access, and drive listing worked, but file upload failed.${NC}"
                        exit 3
                    fi
                else
                    echo -e "\n${GREEN}✅ TESTS COMPLETED SUCCESSFULLY! Your SharePoint connection is working correctly.${NC}"
                    echo -e "${YELLOW}⚠️ Note: File upload test was skipped because no Documents library was found.${NC}"
                    exit 0
                fi
            else
                echo -e "${RED}❌ Drive access failed${NC}"
                echo -e "${YELLOW}⚠️ Partial success: Authentication and site access worked, but drive access failed.${NC}"
                exit 3
            fi
        else
            echo -e "${RED}❌ Site access failed${NC}"
            echo -e "${YELLOW}⚠️ Partial success: Authentication worked, but site access failed.${NC}"
            exit 2
        fi
    else
        echo -e "${GREEN}✅ Basic authentication test passed${NC}"
        echo -e "${YELLOW}⚠️ No site ID or URL provided, skipping site access tests.${NC}"
        exit 0
    fi
else
    echo -e "${RED}❌ Authentication failed${NC}"
    exit 1
fi
