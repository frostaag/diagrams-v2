#!/bin/bash
# Simple batch converter for draw.io files

set -e

DRAWIO_DIR="drawio_files"
PNG_DIR="png_files"
CHANGELOG_FILE="${PNG_DIR}/CHANGELOG.csv"
PNG_SCALE="${PNG_SCALE:-2.0}"
PNG_QUALITY="${PNG_QUALITY:-100}"

# Create output directory
mkdir -p "$PNG_DIR"

# Initialize or maintain changelog
if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "Date,Time,File Name,PNG Output,Commit Hash" > "$CHANGELOG_FILE"
fi

# Setup virtual display for draw.io
export DISPLAY=:99
Xvfb :99 -screen 0 1920x1080x24 > /dev/null 2>&1 &
XVFB_PID=$!

# Wait for Xvfb to start
sleep 2

# Count of successful conversions
SUCCESS_COUNT=0
TOTAL_FILES=0

# Process all drawio files
for file in "${DRAWIO_DIR}"/*.drawio; do
  if [ -f "$file" ]; then
    TOTAL_FILES=$((TOTAL_FILES + 1))
    filename=$(basename "$file")
    basename="${filename%.drawio}"
    output_png="${PNG_DIR}/${basename}.png"
    
    echo "Converting $filename to PNG..."
    
    # Try multiple methods to convert the file
    if drawio -x -f png --scale "$PNG_SCALE" --quality "$PNG_QUALITY" -o "$output_png" "$file"; then
      echo "✅ Successfully converted $filename"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif drawio --no-sandbox --export --format png --scale "$PNG_SCALE" --output "$output_png" "$file"; then
      echo "✅ Successfully converted $filename (method 2)"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif drawio --no-sandbox --headless --export --format png --scale "$PNG_SCALE" --output "$output_png" "$file"; then
      echo "✅ Successfully converted $filename (method 3)"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      echo "❌ Failed to convert $filename"
      continue
    fi
    
    # Add entry to changelog
    if [ -f "$output_png" ]; then
      CURRENT_DATE=$(date +"%d.%m.%Y")
      CURRENT_TIME=$(date +"%H:%M:%S")
      COMMIT_HASH="${GITHUB_SHA:-$(git rev-parse HEAD)}"
      echo "$CURRENT_DATE,$CURRENT_TIME,$basename,$(basename "$output_png"),$COMMIT_HASH" >> "$CHANGELOG_FILE"
    fi
  fi
done

# Clean up Xvfb
kill $XVFB_PID || true

echo "Conversion complete: $SUCCESS_COUNT of $TOTAL_FILES files successfully converted"

# Return success if at least one file was converted successfully
if [ "$SUCCESS_COUNT" -gt 0 ]; then
  exit 0
else
  exit 1
fi
