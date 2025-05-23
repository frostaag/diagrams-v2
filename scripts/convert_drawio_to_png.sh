#!/bin/bash
# Simple script for converting draw.io files to PNG with multiple fallback methods

set -eo pipefail

# Function to convert Draw.io file to PNG
convert_drawio_to_png() {
  local input_file="$1"
  local output_png="$2"
  local scale="${3:-2.0}"
  local quality="${4:-100}"
  
  echo "Converting $input_file to PNG..."
  echo "Output file: $output_png"
  echo "Scale: $scale, Quality: $quality"
  
  # Create output directory if it doesn't exist
  mkdir -p "$(dirname "$output_png")"

  # Method 1: Try with xvfb-run
  if xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" drawio -x -f png --scale "$scale" --quality "$quality" -o "$output_png" "$input_file"; then
    echo "✅ Method 1 (xvfb-run) successful"
    return 0
  else
    echo "❌ Method 1 (xvfb-run) failed with exit code $?"
  fi

  # Method 2: Try with export browser display and xvfb
  export DISPLAY=:99
  Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &
  XVFB_PID=$!
  sleep 2
  if drawio -x -f png --scale "$scale" --quality "$quality" -o "$output_png" "$input_file"; then
    echo "✅ Method 2 (export DISPLAY) successful"
    kill $XVFB_PID || true
    return 0
  else
    kill $XVFB_PID || true
    echo "❌ Method 2 (export DISPLAY) failed with exit code $?"
  fi

  # Method 3: Try with basic export command
  if drawio --export --format png --scale "$scale" --output "$output_png" "$input_file"; then
    echo "✅ Method 3 (basic export) successful"
    return 0
  else
    echo "❌ Method 3 (basic export) failed with exit code $?"
  fi

  # Method 4: Try with headless mode and no xvfb
  if drawio --no-sandbox --headless --export --format png --scale "$scale" --output "$output_png" "$input_file"; then
    echo "✅ Method 4 (headless no-sandbox) successful"
    return 0
  else
    echo "❌ Method 4 (headless no-sandbox) failed with exit code $?"
  fi

  # Method 5: Try with chromium as the browser
  if DRAWIO_BROWSER=chromium xvfb-run --auto-servernum drawio -x -f png --scale "$scale" --quality "$quality" -o "$output_png" "$input_file"; then
    echo "✅ Method 5 (chromium browser) successful"
    return 0
  else
    echo "❌ Method 5 (chromium browser) failed with exit code $?"
  fi

  # Create a placeholder image using ImageMagick if available
  if command -v convert >/dev/null 2>&1; then
    echo "Creating placeholder PNG with ImageMagick..."
    convert -size 800x600 xc:white \
      -fill red \
      -gravity Center \
      -pointsize 24 \
      -annotate 0 "Error converting diagram:\n$(basename "$input_file")\n\nPlease check the diagram file for errors." \
      "$output_png" && echo "Created placeholder PNG with ImageMagick" && return 1
  fi

  # Failed to convert or create placeholder
  echo "All conversion methods failed for $input_file"
  return 1
}

# Main script execution
main() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_file> <output_png> [scale] [quality]"
    exit 1
  fi

  local input_file="$1"
  local output_png="$2"
  local scale="${3:-2.0}"
  local quality="${4:-100}"

  # Check if input file exists
  if [ ! -f "$input_file" ]; then
    echo "Error: Input file does not exist: $input_file"
    exit 1
  fi

  # Perform conversion
  if convert_drawio_to_png "$input_file" "$output_png" "$scale" "$quality"; then
    echo "Conversion successful: $output_png"
    exit 0
  else
    echo "Conversion failed for: $input_file"
    exit 1
  fi
}

# Execute main function with all arguments
main "$@"
