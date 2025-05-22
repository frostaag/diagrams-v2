#!/bin/bash
# Script to correctly identify and test SharePoint drive ID format
# Usage: ./fix_sharepoint_drive.sh -c CLIENT_ID -s CLIENT_SECRET -t TENANT_ID -i SITE_ID

# Parse command line arguments
while getopts "c:s:t:i:f:" opt; do
  case $opt in
    c) CLIENT_ID="$OPTARG" ;;
    s) CLIENT_SECRET="$OPTARG" ;;
    t) TENANT_ID="$OPTARG" ;;
    i) SITE_ID="$OPTARG" ;;
    f) FOLDER="$OPTARG" ;;
    *) echo "Usage: $0 -c CLIENT_ID -s CLIENT_SECRET -t TENANT_ID -i SITE_ID [-f FOLDER]" >&2
       exit 1 ;;
  esac
done

# Check required parameters
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$TENANT_ID" || -z "$SITE_ID" ]]; then
    echo "Missing required parameters. Usage: $0 -c CLIENT_ID -s CLIENT_SECRET -t TENANT_ID -i SITE_ID [-f FOLDER]"
    exit 1
fi

# Default folder name
FOLDER="${FOLDER:-Diagrams}"

# Set curl options for better performance and compatibility
CURL_OPTS="--noproxy '*' --tlsv1.2 -s -L --connect-timeout 15 --max-time 30"

echo "🔑 Obtaining OAuth token..."
AUTH_RESPONSE=$(curl $CURL_OPTS -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID}&scope=https://graph.microsoft.com/.default&client_secret=${CLIENT_SECRET}&grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "❌ Failed to get access token. Response: $AUTH_RESPONSE"
    exit 1
fi

echo "✅ OAuth token obtained successfully (${#ACCESS_TOKEN} characters)"

# Function to get the drive ID with various formats
get_drive_id_and_test() {
    local site_id="$1"
    
    echo "📂 Getting drive information for site: $site_id"
    
    # Get all drives in the site
    DRIVES_RESPONSE=$(curl $CURL_OPTS -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Accept: application/json" \
        "https://graph.microsoft.com/v1.0/sites/$site_id/drives")
    
    echo "Drive response received: $(echo "$DRIVES_RESPONSE" | grep -o "\"value\":\[[^]]*\]" | head -c 100)..."
    
    # Extract the first drive ID (typically the Documents library)
    DRIVE_ID=$(echo "$DRIVES_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$DRIVE_ID" ]]; then
        echo "❌ Failed to get drive ID. Response: $DRIVES_RESPONSE"
        return 1
    fi
    
    echo "📂 Found drive ID: $DRIVE_ID"
    
    # Try alternative formats that SharePoint might require
    echo "Testing different drive ID formats..."
    
    # Format 1: Standard ID
    test_drive_access "$site_id" "$DRIVE_ID" "Standard ID"
    
    # Format 2: b! prefixed format that SharePoint sometimes uses
    B_FORMAT=$(echo "$DRIVES_RESPONSE" | grep -o '"driveType":"documentLibrary"' -A 5 -B 5 | grep -o '"id":"b![^"]*"' | cut -d'"' -f4 || echo "")
    if [[ -n "$B_FORMAT" ]]; then
        test_drive_access "$site_id" "$B_FORMAT" "b! prefixed format"
    fi
    
    # Format 3: URL encoded path
    URL_FORMAT=$(echo "$DRIVES_RESPONSE" | grep -o '"webUrl":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's|.*/||')
    if [[ -n "$URL_FORMAT" ]]; then
        test_drive_access "$site_id" "$URL_FORMAT" "URL encoded path"
    fi
    
    return 0
}

# Function to test drive access with a specific ID format
test_drive_access() {
    local site_id="$1"
    local drive_id="$2"
    local format_desc="$3"
    
    echo "🔍 Testing drive ID format: $format_desc - $drive_id"
    
    # Try to access the root of the drive
    ROOT_RESPONSE=$(curl $CURL_OPTS -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Accept: application/json" \
        "https://graph.microsoft.com/v1.0/sites/$site_id/drives/$drive_id/root")
    
    if [[ "$ROOT_RESPONSE" == *"error"* ]]; then
        echo "❌ Failed with format: $format_desc"
        echo "   Error: $(echo "$ROOT_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
    else
        echo "✅ Success with format: $format_desc"
        echo "   Root name: $(echo "$ROOT_RESPONSE" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)"
        # Try accessing the target folder
        FOLDER_RESPONSE=$(curl $CURL_OPTS -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Accept: application/json" \
            "https://graph.microsoft.com/v1.0/sites/$site_id/drives/$drive_id/root:/Documents/$FOLDER")
        
        if [[ "$FOLDER_RESPONSE" == *"error"* && "$FOLDER_RESPONSE" == *"itemNotFound"* ]]; then
            echo "   Folder Documents/$FOLDER not found. Would need to be created."
        elif [[ "$FOLDER_RESPONSE" == *"error"* ]]; then
            echo "   Error accessing folder: $(echo "$FOLDER_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
        else
            echo "   ✅ Folder Documents/$FOLDER exists. ID: $(echo "$FOLDER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)"
        fi
        
        # Test with a file upload to verify write access
        echo "Test content from GitHub Actions" > test_file.txt
        FILE_SIZE=$(wc -c < test_file.txt)
        
        echo "   📤 Testing file upload to root..."
        UPLOAD_RESPONSE=$(curl $CURL_OPTS -X PUT \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: text/plain" \
            -H "Content-Length: $FILE_SIZE" \
            --data-binary @test_file.txt \
            "https://graph.microsoft.com/v1.0/sites/$site_id/drives/$drive_id/root:/test_file.txt:/content")
        
        if [[ "$UPLOAD_RESPONSE" == *"error"* ]]; then
            echo "   ❌ File upload failed: $(echo "$UPLOAD_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
        else
            echo "   ✅ File upload successful. ID: $(echo "$UPLOAD_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)"
            echo "WORKING_DRIVE_ID=$drive_id" > .sharepoint_working_drive
        fi
        
        # Remove the test file
        rm -f test_file.txt
    fi
    echo "---"
}

# Try to get the drive ID with various formats
get_drive_id_and_test "$SITE_ID"

# Check if we found a working drive ID
if [[ -f ".sharepoint_working_drive" ]]; then
    source ./.sharepoint_working_drive
    echo "========================================="
    echo "✅ SUCCESS: Found working drive ID format"
    echo "Drive ID: $WORKING_DRIVE_ID"
    echo ""
    echo "Update your workflow with the correct drive ID:"
    echo "DIAGRAMS_SHAREPOINT_DRIVE_ID: \"$WORKING_DRIVE_ID\""
    echo "========================================="
    exit 0
else
    echo "========================================="
    echo "❌ Failed to find a working drive ID format"
    echo "Please check your SharePoint site ID and permissions"
    echo "========================================="
    exit 1
fi
