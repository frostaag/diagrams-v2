#!/bin/bash
# SharePoint upload script specifically targeting the Shared Documents library
# This script prioritizes the URL structure from the browser URL

set -e

# Configuration from environment or arguments
TENANT_ID="${SHAREPOINT_TENANT_ID}"
CLIENT_ID="${SHAREPOINT_CLIENT_ID}"
CLIENT_SECRET="${SHAREPOINT_CLIENT_SECRET}"
SITE_ID="${SHAREPOINT_SITE_ID}"
SITE_URL="${SHAREPOINT_URL:-https://frostaag.sharepoint.com/sites/DatasphereFileConnector}"
FOLDER="${SHAREPOINT_FOLDER:-Diagrams}"
OUTPUT_FILENAME="${SHAREPOINT_OUTPUT_FILENAME:-Diagrams_Changelog.csv}"
CHANGELOG_FILE="${CHANGELOG_FILE:-png_files/CHANGELOG.csv}"

# Validate required parameters
if [[ -z "$TENANT_ID" || -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$SITE_ID" ]]; then
    echo "❌ Missing required parameters"
    echo "Required: SHAREPOINT_TENANT_ID, SHAREPOINT_CLIENT_ID, SHAREPOINT_CLIENT_SECRET, SHAREPOINT_SITE_ID"
    exit 1
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "❌ File not found: $CHANGELOG_FILE"
    exit 1
fi

# Display configuration
echo "=== SHAREPOINT UPLOAD (SHARED DOCUMENTS) ==="
echo "Site ID: $SITE_ID"
echo "Site URL: $SITE_URL"
echo "Folder: $FOLDER"
echo "Target: Shared Documents/$FOLDER/$OUTPUT_FILENAME"
echo "========================================="

# Get file size
FILE_SIZE=$(wc -c < "$CHANGELOG_FILE")
echo "📄 File size: $FILE_SIZE bytes"

# Function to show the first few lines of the file
echo "First few lines of the file:"
head -n 5 "$CHANGELOG_FILE"
echo "..."

# Get access token
echo "🔑 Getting access token..."
AUTH_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID}&scope=https://graph.microsoft.com/.default&client_secret=${CLIENT_SECRET}&grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "❌ Failed to get access token"
    echo "Response: $AUTH_RESPONSE"
    exit 1
fi

echo "✅ Got access token (${#ACCESS_TOKEN} characters)"

# First, test site access to confirm connectivity
echo "🔍 Testing site access..."
SITE_TEST_URL="https://graph.microsoft.com/v1.0/sites/${SITE_ID}"
SITE_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X GET "$SITE_TEST_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

if [[ "$SITE_RESPONSE" == *"error"* ]]; then
    echo "❌ Site access failed"
    echo "Error: $(echo "$SITE_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
    exit 1
else
    echo "✅ Site access successful"
    SITE_NAME=$(echo "$SITE_RESPONSE" | grep -o '"displayName":"[^"]*"' | cut -d'"' -f4)
    echo "Site name: $SITE_NAME"
fi

# Get all drives in the site to find the right one
echo "📂 Getting drives in the site..."
DRIVES_URL="https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives"
DRIVES_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X GET "$DRIVES_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

if [[ "$DRIVES_RESPONSE" == *"error"* ]]; then
    echo "❌ Failed to get drives"
    echo "Error: $(echo "$DRIVES_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
    exit 1
fi

# Extract drive information with both "Documents" and "Shared Documents" names
DOCUMENTS_DRIVE_ID=""
SHARED_DOCUMENTS_DRIVE_ID=""
DOCUMENTS_DRIVE_NAME=""
SHARED_DOCUMENTS_DRIVE_NAME=""

# Parse the JSON response to find the drives
echo "Parsing drive information..."
if [[ "$DRIVES_RESPONSE" == *"\"name\":\"Documents\""* ]]; then
    DOCUMENTS_DRIVE_ID=$(echo "$DRIVES_RESPONSE" | grep -o -P '(?<="id":")(.*?)(?=","name":"Documents")' || echo "")
    DOCUMENTS_DRIVE_NAME="Documents"
    echo "✅ Found Documents drive: $DOCUMENTS_DRIVE_ID"
fi

if [[ "$DRIVES_RESPONSE" == *"\"name\":\"Shared Documents\""* ]]; then
    SHARED_DOCUMENTS_DRIVE_ID=$(echo "$DRIVES_RESPONSE" | grep -o -P '(?<="id":")(.*?)(?=","name":"Shared Documents")' || echo "")
    SHARED_DOCUMENTS_DRIVE_NAME="Shared Documents"
    echo "✅ Found Shared Documents drive: $SHARED_DOCUMENTS_DRIVE_ID"
fi

# If we couldn't find by name, get the default document library
if [[ -z "$DOCUMENTS_DRIVE_ID" && -z "$SHARED_DOCUMENTS_DRIVE_ID" ]]; then
    echo "⚠️ Could not find drives by name. Getting first document library..."
    FIRST_DRIVE_ID=$(echo "$DRIVES_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    FIRST_DRIVE_NAME=$(echo "$DRIVES_RESPONSE" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$FIRST_DRIVE_ID" ]]; then
        echo "Using first available drive: $FIRST_DRIVE_NAME ($FIRST_DRIVE_ID)"
        DOCUMENTS_DRIVE_ID="$FIRST_DRIVE_ID"
        DOCUMENTS_DRIVE_NAME="$FIRST_DRIVE_NAME"
    else
        echo "❌ No drives found in the site"
        exit 1
    fi
fi

# Create the Diagrams folder if it doesn't exist
create_folder() {
    local drive_id="$1"
    local drive_name="$2"
    local folder_path="$3"
    
    echo "📁 Checking if $folder_path folder exists in $drive_name..."
    FOLDER_CHECK_URL="https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives/${drive_id}/root:/${folder_path}"
    FOLDER_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X GET "$FOLDER_CHECK_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Accept: application/json")
    
    if [[ "$FOLDER_RESPONSE" == *"error"* && "$FOLDER_RESPONSE" == *"itemNotFound"* ]]; then
        echo "📁 $folder_path folder does not exist in $drive_name. Creating it..."
        CREATE_FOLDER_URL="https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives/${drive_id}/root:/children"
        CREATE_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X POST "$CREATE_FOLDER_URL" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"$folder_path\",\"folder\":{},\"@microsoft.graph.conflictBehavior\":\"replace\"}")
        
        if [[ "$CREATE_RESPONSE" == *"\"id\""* ]]; then
            echo "✅ $folder_path folder created successfully in $drive_name"
            return 0
        else
            echo "⚠️ Failed to create $folder_path folder in $drive_name"
            echo "Error: $(echo "$CREATE_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
            return 1
        fi
    elif [[ "$FOLDER_RESPONSE" == *"\"id\""* ]]; then
        echo "✅ $folder_path folder already exists in $drive_name"
        return 0
    else
        echo "⚠️ Unexpected response checking for $folder_path folder in $drive_name"
        return 1
    fi
}

# Upload file function
upload_file() {
    local drive_id="$1"
    local drive_name="$2"
    local folder_path="$3"
    local file_name="$4"
    
    echo "📤 Uploading file to $drive_name/$folder_path/$file_name..."
    UPLOAD_URL="https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives/${drive_id}/root:/${folder_path}/${file_name}:/content"
    echo "Upload URL: $UPLOAD_URL"
    
    UPLOAD_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$UPLOAD_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: text/csv" \
      -H "Content-Length: $FILE_SIZE" \
      --data-binary "@$CHANGELOG_FILE")
    
    if [[ "$UPLOAD_RESPONSE" == *"\"id\""* ]]; then
        echo "✅ File uploaded successfully to $drive_name/$folder_path/$file_name"
        # Extract the URL if available
        WEB_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4 || echo "")
        if [[ -n "$WEB_URL" ]]; then
            echo "📄 File accessible at: $WEB_URL"
        fi
        return 0
    else
        echo "❌ Upload failed to $drive_name/$folder_path/$file_name"
        echo "Error: $(echo "$UPLOAD_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")"
        return 1
    fi
}

# Try uploading to "Shared Documents" first, then "Documents" as fallback
SUCCESS=false

if [[ -n "$SHARED_DOCUMENTS_DRIVE_ID" ]]; then
    echo "🔄 Trying with Shared Documents drive..."
    create_folder "$SHARED_DOCUMENTS_DRIVE_ID" "Shared Documents" "$FOLDER"
    if upload_file "$SHARED_DOCUMENTS_DRIVE_ID" "Shared Documents" "$FOLDER" "$OUTPUT_FILENAME"; then
        SUCCESS=true
    fi
fi

if [[ "$SUCCESS" != "true" && -n "$DOCUMENTS_DRIVE_ID" ]]; then
    echo "🔄 Trying with Documents drive..."
    create_folder "$DOCUMENTS_DRIVE_ID" "Documents" "$FOLDER"
    if upload_file "$DOCUMENTS_DRIVE_ID" "Documents" "$FOLDER" "$OUTPUT_FILENAME"; then
        SUCCESS=true
    fi
fi

if [[ "$SUCCESS" != "true" ]]; then
    echo "❌ All upload attempts failed"
    exit 1
else
    echo "✅ File uploaded successfully"
    exit 0
fi
