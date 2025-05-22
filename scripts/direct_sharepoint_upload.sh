#!/bin/bash
# Direct SharePoint upload script - simplified for reliability
# This script uploads directly to the Documents/Diagrams folder using a fixed drive ID

set -e

# Config
CHANGELOG_FILE="${CHANGELOG_FILE:-png_files/CHANGELOG.csv}"
SHAREPOINT_FOLDER="${SHAREPOINT_FOLDER:-Diagrams}"
OUTPUT_FILENAME="${SHAREPOINT_OUTPUT_FILENAME:-Diagrams_Changelog.csv}"

# Hard-coded drive ID from advanced_sharepoint_test.sh
DRIVE_ID="${SHAREPOINT_DRIVE_ID}"

# Use b! format if the drive ID doesn't already have it
if [[ "$DRIVE_ID" != "b!"* && "$DRIVE_ID" != *"/" ]]; then
  # Based on the error message, we need to convert to the b! format that SharePoint expects
  # This is derived from the site ID and drive ID which we have
  SITE_ID_NO_DASHES=$(echo "$SHAREPOINT_SITE_ID" | tr -d '-')
  DRIVE_ID_NO_DASHES=$(echo "$DRIVE_ID" | tr -d '-')
  
  # Construct the b! format ID that SharePoint expects
  # Format: b!<site-id-no-dashes>-<drive-id-no-dashes>
  B_FORMATTED_ID="b!${SITE_ID_NO_DASHES}-${DRIVE_ID_NO_DASHES}"
  
  echo "🔄 Converting drive ID to b! format: $B_FORMATTED_ID"
  DRIVE_ID="$B_FORMATTED_ID"
fi

# Required values
if [[ -z "$SHAREPOINT_CLIENT_ID" || -z "$SHAREPOINT_CLIENT_SECRET" || -z "$SHAREPOINT_TENANT_ID" || -z "$SHAREPOINT_SITE_ID" ]]; then
  echo "❌ Error: Missing required SharePoint configuration"
  echo "Required: SHAREPOINT_CLIENT_ID, SHAREPOINT_CLIENT_SECRET, SHAREPOINT_TENANT_ID, SHAREPOINT_SITE_ID"
  exit 1
fi

# Verify file exists
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "❌ Error: Changelog file not found: $CHANGELOG_FILE"
  exit 1
fi

echo "===== DIRECT SHAREPOINT UPLOAD ====="
echo "Using fixed path and known drive ID"
echo "Site ID: $SHAREPOINT_SITE_ID"
echo "Drive ID: $DRIVE_ID"
echo "Target: Documents/$SHAREPOINT_FOLDER/$OUTPUT_FILENAME"
echo "====================================="

# Get token
echo "🔑 Getting access token..."
AUTH_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X POST \
  "https://login.microsoftonline.com/${SHAREPOINT_TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${SHAREPOINT_CLIENT_ID}&scope=https://graph.microsoft.com/.default&client_secret=${SHAREPOINT_CLIENT_SECRET}&grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "❌ Failed to get access token"
  echo "Response: $AUTH_RESPONSE"
  exit 1
else
  echo "✅ Got access token (${#ACCESS_TOKEN} characters)"
fi

# Ensure Diagrams folder exists
echo "📁 Ensuring Documents/Diagrams folder exists..."
FOLDER_CHECK_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/root:/Documents/Diagrams"
FOLDER_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X GET "$FOLDER_CHECK_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

if [[ "$FOLDER_RESPONSE" == *"error"* && "$FOLDER_RESPONSE" == *"itemNotFound"* ]]; then
  echo "📁 Diagrams folder does not exist. Creating it..."
  
  # Create Diagrams folder
  CREATE_FOLDER_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/root:/Documents:/children"
  CREATE_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X POST "$CREATE_FOLDER_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"Diagrams","folder":{},"@microsoft.graph.conflictBehavior":"replace"}')
  
  if [[ "$CREATE_RESPONSE" == *"id"* ]]; then
    echo "✅ Diagrams folder created successfully"
  else
    echo "⚠️ Failed to create Diagrams folder. Will try upload anyway."
  fi
elif [[ "$FOLDER_RESPONSE" == *"id"* ]]; then
  echo "✅ Diagrams folder already exists"
else
  echo "⚠️ Could not check if Diagrams folder exists. Will try upload anyway."
fi

# Upload file directly using drive ID approach
echo "📤 Uploading changelog to SharePoint..."
FILE_SIZE=$(wc -c < "$CHANGELOG_FILE")

# Try multiple path formats for maximum compatibility
echo "Trying multiple path formats to ensure compatibility..."

# Option 1: Using the b! format with /root:/Documents/path (standard path)
UPLOAD_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/root:/Documents/${SHAREPOINT_FOLDER}/${OUTPUT_FILENAME}:/content"
echo "🔄 Trying upload with URL (format 1 - Documents): $UPLOAD_URL"

# Upload with curl
UPLOAD_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$UPLOAD_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: text/csv" \
  -H "Content-Length: $FILE_SIZE" \
  --data-binary "@$CHANGELOG_FILE" 2>&1)

# Check for success with first format
if [[ "$UPLOAD_RESPONSE" == *"\"id\""* ]]; then
  echo "✅ Upload successful with format 1 (Documents path)!"
  
  # Extract the URL if available
  WEB_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4 || echo "")
  if [[ -n "$WEB_URL" ]]; then
    echo "📄 Changelog uploaded to: $WEB_URL"
  fi
  
  exit 0
else
  echo "❌ Format 1 upload failed (Documents path)"
  if [[ "$UPLOAD_RESPONSE" == *"error"* ]]; then
    ERROR_MSG=$(echo "$UPLOAD_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
    echo "Error: $ERROR_MSG"
  fi
  
  # Try with "Shared Documents" path instead of "Documents"
  echo "🔄 Trying with 'Shared Documents' path..."
  SHARED_DOCS_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/root:/Shared%20Documents/${SHAREPOINT_FOLDER}/${OUTPUT_FILENAME}:/content"
  echo "URL: $SHARED_DOCS_URL"
  
  SHARED_DOCS_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$SHARED_DOCS_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: text/csv" \
    -H "Content-Length: $FILE_SIZE" \
    --data-binary "@$CHANGELOG_FILE" 2>&1)
  
  if [[ "$SHARED_DOCS_RESPONSE" == *"\"id\""* ]]; then
    echo "✅ Upload successful with 'Shared Documents' path!"
    # Extract the URL if available
    WEB_URL=$(echo "$SHARED_DOCS_RESPONSE" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4 || echo "")
    if [[ -n "$WEB_URL" ]]; then
      echo "📄 Changelog uploaded to: $WEB_URL"
    fi
    exit 0
  else
    echo "❌ 'Shared Documents' path upload failed"
    if [[ "$SHARED_DOCS_RESPONSE" == *"error"* ]]; then
      ERROR_MSG=$(echo "$SHARED_DOCS_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
      echo "Error: $ERROR_MSG"
    fi
  
  # Attempt fallback with format 2: Using items/root: path
  echo "🔄 Trying fallback format 2..."
  FALLBACK_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/items/root:/Documents/${SHAREPOINT_FOLDER}/${OUTPUT_FILENAME}:/content"
  echo "URL: $FALLBACK_URL"
  
  FALLBACK_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$FALLBACK_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: text/csv" \
    -H "Content-Length: $FILE_SIZE" \
    --data-binary "@$CHANGELOG_FILE" 2>&1)
  
  if [[ "$FALLBACK_RESPONSE" == *"\"id\""* ]]; then
    echo "✅ Format 2 upload successful!"
    exit 0
  else
    echo "❌ Format 2 upload failed"
    if [[ "$FALLBACK_RESPONSE" == *"error"* ]]; then
      ERROR_MSG=$(echo "$FALLBACK_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
      echo "Error: $ERROR_MSG"
    fi
    
    # Try with "Shared Documents" path with items format
    echo "🔄 Trying with 'Shared Documents' path (items format)..."
    SHARED_DOCS_ITEMS_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/items/root:/Shared%20Documents/${SHAREPOINT_FOLDER}/${OUTPUT_FILENAME}:/content"
    echo "URL: $SHARED_DOCS_ITEMS_URL"
    
    SHARED_DOCS_ITEMS_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$SHARED_DOCS_ITEMS_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: text/csv" \
      -H "Content-Length: $FILE_SIZE" \
      --data-binary "@$CHANGELOG_FILE" 2>&1)
    
    if [[ "$SHARED_DOCS_ITEMS_RESPONSE" == *"\"id\""* ]]; then
      echo "✅ 'Shared Documents' items format upload successful!"
      exit 0
    else
      echo "❌ 'Shared Documents' items format upload failed"
      if [[ "$SHARED_DOCS_ITEMS_RESPONSE" == *"error"* ]]; then
        ERROR_MSG=$(echo "$SHARED_DOCS_ITEMS_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
        echo "Error: $ERROR_MSG"
      fi
      
      # Last attempt with format 3: Try direct Diagrams folder
      echo "🔄 Trying fallback format 3 (direct to Diagrams folder)..."
      LAST_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${DRIVE_ID}/root:/Diagrams/${OUTPUT_FILENAME}:/content"
      echo "URL: $LAST_URL"
      
      LAST_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$LAST_URL" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: text/csv" \
        -H "Content-Length: $FILE_SIZE" \
        --data-binary "@$CHANGELOG_FILE" 2>&1)
      
      if [[ "$LAST_RESPONSE" == *"\"id\""* ]]; then
        echo "✅ Format 3 upload successful!"
        exit 0
      else
        echo "❌ All standard upload formats failed"
        echo "Final error: $(echo "$LAST_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")"
        
        # Try directly using drive ID without the b! prefix as a last resort
        echo "🔄 Trying last resort with base drive ID..."
        BASE_DRIVE_ID="${DRIVE_ID#b!}"  # Remove b! prefix if present
        BASE_URL="https://graph.microsoft.com/v1.0/sites/${SHAREPOINT_SITE_ID}/drives/${BASE_DRIVE_ID}/root:/Shared%20Documents/${SHAREPOINT_FOLDER}/${OUTPUT_FILENAME}:/content"
        
        BASE_RESPONSE=$(curl --noproxy '*' --tlsv1.2 -s -X PUT "$BASE_URL" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "Content-Type: text/csv" \
          -H "Content-Length: $FILE_SIZE" \
          --data-binary "@$CHANGELOG_FILE" 2>&1)
        
        if [[ "$BASE_RESPONSE" == *"\"id\""* ]]; then
          echo "✅ Last resort upload successful!"
          exit 0
        else
          echo "❌ All upload formats failed"
          echo "Final error: $(echo "$BASE_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")"
          exit 1
        fi
      fi
    fi
  fi
fi
