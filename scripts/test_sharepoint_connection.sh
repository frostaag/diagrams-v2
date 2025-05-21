#!/bin/bash
# This script tests SharePoint/Microsoft Graph API connection
# It can be run separately to validate credentials and permissions

set -e

# Check if required environment variables are set
if [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" ]]; then
  echo "Usage: $0 <client_id> <client_secret> <tenant_id> <site_id>"
  echo "Example: $0 \"26d1a5-app-id\" \"your-client-secret\" \"a8d22be6-5bda-4bd7-8278-226c60c037ed\" \"e39939c2-992f-47cc-8b32-20aa466d71f4\""
  exit 1
fi

CLIENT_ID="$1"
CLIENT_SECRET="$2"
TENANT_ID="$3"
SITE_ID="$4"

echo "================================"
echo "🔑 GRAPH API CONNECTION TEST"
echo "================================"
echo "Testing connection with:"
echo "- Client ID: ${CLIENT_ID:0:6}... (truncated)"
echo "- Tenant ID: $TENANT_ID"
echo "- Site ID: $SITE_ID"

# Get access token
echo -e "\n📤 Getting access token..."
TOKEN_URL="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
SCOPE="https://graph.microsoft.com/.default"

TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID}&scope=${SCOPE}&client_secret=${CLIENT_SECRET}&grant_type=client_credentials")

# Check if token was received
if [[ "$TOKEN_RESPONSE" == *"access_token"* ]]; then
  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  echo "✅ Access token obtained successfully"
  echo "Token length: ${#ACCESS_TOKEN} characters"
else
  echo "❌ Failed to get access token"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

# Test different SharePoint site URL formats
echo -e "\n🌐 Testing SharePoint site access..."

# Site formats to try
SITE_FORMATS=(
  # Direct site ID format
  "https://graph.microsoft.com/v1.0/sites/${SITE_ID}"
  
  # Site path with colon notation (standard)
  "https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com:/sites/DatasphereFileConnector"
  
  # Site path with slash notation
  "https://graph.microsoft.com/v1.0/sites/frostaag.sharepoint.com/sites/DatasphereFileConnector"
)

SUCCESS=false

for FORMAT in "${SITE_FORMATS[@]}"; do
  echo -e "\n⏳ Trying format: $FORMAT"
  
  SITE_RESPONSE=$(curl -s -X GET "$FORMAT" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
  
  # Check if response contains site ID
  if [[ "$SITE_RESPONSE" == *"\"id\":"* ]]; then
    echo "✅ SUCCESS: Connected to SharePoint site!"
    echo "$SITE_RESPONSE" | grep -o '"displayName":"[^"]*' | cut -d'"' -f4
    echo "$SITE_RESPONSE" | grep -o '"webUrl":"[^"]*' | cut -d'"' -f4
    
    # Extract the full site ID from the response
    FULL_SITE_ID=$(echo "$SITE_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "Full Site ID: $FULL_SITE_ID"
    
    SUCCESS=true
    echo -e "\n✅ WORKING FORMAT: $FORMAT"
    break
  else
    echo "❌ Failed with this format"
    if [[ "$SITE_RESPONSE" == *"error"* ]]; then
      ERROR_CODE=$(echo "$SITE_RESPONSE" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
      ERROR_MSG=$(echo "$SITE_RESPONSE" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
      echo "Error code: $ERROR_CODE"
      echo "Error message: $ERROR_MSG"
    fi
  fi
done

if [[ "$SUCCESS" != "true" ]]; then
  echo -e "\n❌ FAILED: Could not connect to SharePoint with any format"
  exit 1
else
  echo -e "\n✅ CONNECTION TEST SUCCESSFUL"
fi

# Test listing drives (document libraries)
echo -e "\n📁 Testing document libraries access..."
WORKING_SITE_URL=$(echo "$FORMAT" | cut -d'?' -f1)
DRIVES_URL="${WORKING_SITE_URL}/drives"

echo "Listing document libraries from: $DRIVES_URL"

DRIVES_RESPONSE=$(curl -s -X GET "$DRIVES_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

if [[ "$DRIVES_RESPONSE" == *"\"value\":"* ]]; then
  echo "✅ Successfully accessed document libraries"
  echo "$DRIVES_RESPONSE" | grep -o '"name":"[^"]*' | cut -d'"' -f4
  
  # Look for Documents library
  if [[ "$DRIVES_RESPONSE" == *"\"name\":\"Documents\""* ]]; then
    echo "Found 'Documents' library"
    DRIVE_ID=$(echo "$DRIVES_RESPONSE" | grep -o '"name":"Documents".*"id":"[^"]*' | 
              grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "Documents library ID: $DRIVE_ID"
  fi
else
  echo "❌ Failed to access document libraries"
  if [[ "$DRIVES_RESPONSE" == *"error"* ]]; then
    ERROR_CODE=$(echo "$DRIVES_RESPONSE" | grep -o '"code":"[^"]*' | cut -d'"' -f4)
    ERROR_MSG=$(echo "$DRIVES_RESPONSE" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
    echo "Error code: $ERROR_CODE"
    echo "Error message: $ERROR_MSG"
  fi
fi

echo -e "\n✅ TEST COMPLETE"
