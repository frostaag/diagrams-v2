#!/bin/bash
# Test script for SharePoint integration with b! format drive ID

# Configuration from environment or defaults
TENANT_ID="${1:-a8d22be6-5bda-4bd7-8278-226c60c037ed}"
SITE_ID="${2:-e39939c2-992f-47cc-8b32-20aa466d71f4}"
CLIENT_ID="${3}"
CLIENT_SECRET="${4}"

# Basic validation
if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "Usage: $0 [tenant_id] [site_id] client_id client_secret"
  echo "Missing client credentials. Please provide CLIENT_ID and CLIENT_SECRET."
  exit 1
fi

DRIVE_ID_BASE="21e1e0f0-9247-45ab-9f8c-1d50c5c077db"
DRIVE_ID_FORMATTED="b!wjmZ4y-ZzEeLMiCqRm1x9H3mO71JixdIg12xZz2kwrAhUCwRmjE_SLgzjLG1gDSD"

echo "=== SHAREPOINT CONNECTION TEST ==="
echo "Testing with:"
echo "- Tenant ID: $TENANT_ID"
echo "- Site ID: $SITE_ID"
echo "- Client ID: ${CLIENT_ID:0:5}*** (length: ${#CLIENT_ID})"
echo "- Client Secret: ****** (length: ${#CLIENT_SECRET})"
echo "==============================="

# Function to test drive ID format
test_drive_id() {
  local drive_id="$1"
  local format_name="$2"
  
  echo "🔍 Testing drive ID format ($format_name): $drive_id"
  
  # Get access token
  local auth_response=$(curl --silent -X POST \
    "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}&scope=https://graph.microsoft.com/.default&client_secret=${CLIENT_SECRET}&grant_type=client_credentials")
  
  local access_token=$(echo "$auth_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
  
  if [[ -z "$access_token" ]]; then
    echo "❌ Failed to get access token"
    echo "Response: $auth_response"
    return 1
  fi
  
  echo "✅ Got access token (${#access_token} characters)"
  
  # Test the drive ID
  local drive_response=$(curl --silent -X GET \
    "https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives/${drive_id}" \
    -H "Authorization: Bearer $access_token" \
    -H "Accept: application/json")
  
  if [[ "$drive_response" == *"error"* ]]; then
    echo "❌ Drive ID test failed"
    echo "Error: $(echo "$drive_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
    return 1
  else
    echo "✅ Drive ID test succeeded"
    echo "Drive name: $(echo "$drive_response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)"
    return 0
  fi
}

# Test base drive ID format first
echo "===== TESTING BASE DRIVE ID ====="
if test_drive_id "$DRIVE_ID_BASE" "base format"; then
  echo "✅ Base drive ID format works!"
else
  echo "❌ Base drive ID format failed"
fi

echo ""

# Test formatted b! drive ID
echo "===== TESTING b! FORMATTED DRIVE ID ====="
if test_drive_id "$DRIVE_ID_FORMATTED" "b! format"; then
  echo "✅ b! formatted drive ID works!"
else
  echo "❌ b! formatted drive ID failed"
fi

echo ""
echo "===== TEST SUMMARY ====="
echo "Use the drive ID format that worked in your workflow file:"
echo "DIAGRAMS_SHAREPOINT_DRIVE_ID: \"$DRIVE_ID_FORMATTED\""
