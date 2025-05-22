#!/bin/bash
# Script to process Draw.io files according to v2 specification

set -eo pipefail

# Configuration
DRAWIO_FILES_DIR="drawio_files"
PNG_FILES_DIR="png_files"
COUNTER_FILE="${DIAGRAMS_COUNTER_FILE:-${DRAWIO_FILES_DIR}/.counter}"
CHANGELOG_FILE="${DIAGRAMS_CHANGELOG_FILE:-${PNG_FILES_DIR}/CHANGELOG.csv}"
PNG_SCALE="${DIAGRAMS_PNG_SCALE:-${PNG_SCALE:-2.0}}"
PNG_QUALITY="${DIAGRAMS_PNG_QUALITY:-${PNG_QUALITY:-100}}"
SPECIFIC_FILE="${SPECIFIC_FILE:-}"
TRIGGERING_SHA="${GITHUB_SHA}" # Use GITHUB_SHA for the triggering commit

# Function to detect changed files
detect_changed_files() {
  local changed_files=""
  
  # Check if CHANGED_FILES environment variable is set (from GitHub Actions)
  if [[ -n "$CHANGED_FILES" ]]; then
    echo "Using CHANGED_FILES from environment: $CHANGED_FILES"
    changed_files="$CHANGED_FILES"
    return
  elif [[ -n "$SPECIFIC_FILE" ]]; then
    echo "Processing specific file: $SPECIFIC_FILE"
    changed_files="$SPECIFIC_FILE"
  else
    # Create temporary file to store results
    local temp_diff_file=$(mktemp)
    echo "Created temporary file: $temp_diff_file"
    
    # Method 1: Check normal commit for added/modified files
    echo "Trying to detect changed files using git diff..."
    if git rev-parse HEAD^1 >/dev/null 2>&1; then
      # Normal commit, get changed draw.io files
      git diff --name-only --diff-filter=AM HEAD^ HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" > "$temp_diff_file"
      echo "Method 1 results:"
      cat "$temp_diff_file"
    else
      # Method 2: Initial commit
      echo "Appears to be initial commit, trying git diff-tree..."
      git diff-tree --no-commit-id --name-only --root -r HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" > "$temp_diff_file"
      echo "Method 2 results:"
      cat "$temp_diff_file"
    fi
    
    # Check if we found any files
    if [ ! -s "$temp_diff_file" ]; then
      echo "No files found with git diff/diff-tree, trying direct filesystem search..."
      # Method 3: Direct filesystem search as last resort
      find "${DRAWIO_FILES_DIR}" -name "*.drawio" -type f | sort > "$temp_diff_file"
      echo "Method 3 results:"
      cat "$temp_diff_file"
    fi
    
    # Get the files from the temp file
    changed_files=$(cat "$temp_diff_file" | tr '\n' ' ')
    rm -f "$temp_diff_file"
    
    if [[ -z "$changed_files" ]]; then
      echo "No draw.io files found by any method."
      exit 0
    fi
  fi
  
  echo "Changed files: $changed_files"
  echo "CHANGED_FILES=$changed_files" >> $GITHUB_ENV
}

# Function to assign IDs to new files
assign_ids() {
  local file="$1"
  local basename
  basename=$(basename "$file")
  
  # Check if file already has an ID pattern (###) or is a numeric filename
  if [[ "$basename" =~ \\([0-9]{3}\\)\\.drawio$ ]] || [[ "$basename" =~ ^[0-9]+\\.drawio$ ]]; then
    echo "File $basename already has an ID, skipping ID assignment."
    return 0
  fi
  
  # Read current counter
  local counter
  counter=$(<"$COUNTER_FILE")
  # Increment counter
  local new_counter_val
  new_counter_val=$((10#$counter + 1))
  local new_counter_str
  new_counter_str=$(printf "%03d" $new_counter_val)
  # New filename with ID
  local filename_without_ext="${basename%.drawio}"
  local new_filename="${filename_without_ext} (${new_counter_str}).drawio"
  # Ensure DRAWIO_FILES_DIR is used for the new path
  local new_filepath="${DRAWIO_FILES_DIR}/${new_filename}"
  
  # Rename the file
  mv "$file" "$new_filepath"
  
  # Update counter file
  echo "$new_counter_str" > "$COUNTER_FILE"
  
  echo "Assigned ID $new_counter_str to $basename -> $new_filename"
  # Update the file variable for further processing
  echo "PROCESSED_FILE=$new_filepath" >> $GITHUB_ENV
}

# Function to extract ID from filename
extract_id() {
  local file="$1"
  local basename
  basename=$(basename "$file")
  
  if [[ "$basename" =~ \\(([0-9]{3})\\)\\.drawio$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$basename" =~ ^([0-9]+)\\.drawio$ ]]; then # Also match if filename is just digits.drawio
    echo "${BASH_REMATCH[1]}"
  else
    echo "" # Return empty if no ID pattern matches
  fi
}

# Function to convert drawio to PNG
convert_to_png() {
  local input_file="$1"
  local basename=$(basename "$input_file" .drawio)
  local output_png="${PNG_FILES_DIR}/${basename}.png"
  
  echo "Converting $input_file to PNG..."
  echo "Output file: $output_png"
  echo "Scale: $PNG_SCALE, Quality: $PNG_QUALITY"
  
  # Create a temporary conversion script for better error handling
  local converter_script=$(mktemp)
  echo "#!/bin/bash" > "$converter_script"
  echo "set -o pipefail" >> "$converter_script"
  echo "input_file=\"\$1\"" >> "$converter_script"
  echo "output_file=\"\$2\"" >> "$converter_script"
  echo "scale=\"\$3\"" >> "$converter_script"
  echo "quality=\"\$4\"" >> "$converter_script"
  echo "echo \"Converting: \$input_file to \$output_file with scale=\$scale quality=\$quality\"" >> "$converter_script"
  echo "" >> "$converter_script"
  
  echo "# Method 1: Try with xvfb-run" >> "$converter_script"
  echo "if xvfb-run --auto-servernum --server-args=\"-screen 0 1280x1024x24\" drawio -x -f png --scale \"\$scale\" --quality \"\$quality\" -o \"\$output_file\" \"\$input_file\"; then" >> "$converter_script"
  echo "  echo \"✅ Method 1 (xvfb-run) successful\"" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  echo \"❌ Method 1 (xvfb-run) failed with exit code \$?\"" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# Method 2: Try with export browser display and xvfb" >> "$converter_script"
  echo "export DISPLAY=:99" >> "$converter_script"
  echo "Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &" >> "$converter_script"
  echo "XVFB_PID=\$!" >> "$converter_script"
  echo "sleep 2" >> "$converter_script"
  echo "if drawio -x -f png --scale \"\$scale\" --quality \"\$quality\" -o \"\$output_file\" \"\$input_file\"; then" >> "$converter_script"
  echo "  echo \"✅ Method 2 (export DISPLAY) successful\"" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  echo \"❌ Method 2 (export DISPLAY) failed with exit code \$?\"" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# All conversion methods failed" >> "$converter_script"
  echo "exit 1" >> "$converter_script"
  chmod +x "$converter_script"
  
  # Execute the converter script
  echo "Executing conversion script..."
  if "$converter_script" "$input_file" "$output_png" "$PNG_SCALE" "$PNG_QUALITY"; then
    echo "✓ Successfully created $output_png"
    
    # Verify output file exists and has appropriate size
    if [[ -f "$output_png" && -s "$output_png" ]]; then
      file_size=$(du -k "$output_png" | cut -f1)
      echo "Output PNG file size: ${file_size}KB"
      
      if [[ $file_size -lt 2 ]]; then
        echo "⚠️ Warning: Output file seems too small, might be corrupted"
      fi
    else
      echo "⚠️ Warning: Output file wasn't created or is empty"
      # Create placeholder since we didn't get a proper output
      create_placeholder_png "$input_file" "$output_png"
    fi
    
    rm -f "$converter_script"
    return 0
  else
    local exit_code=$?
    echo "✗ Conversion failed with exit code $exit_code"
    
    # If conversion failed, create a placeholder PNG
    create_placeholder_png "$input_file" "$output_png"
    
    rm -f "$converter_script"
    return 1
  fi
}

# Helper function to create placeholder PNGs for failed conversions
create_placeholder_png() {
  local input_file="$1"
  local output_png="$2"
  local basename=$(basename "$input_file")
  
  echo "Creating placeholder PNG for failed conversion of $basename..."
  
  # Try using ImageMagick if available
  if command -v convert >/dev/null 2>&1; then
    convert -size 800x600 xc:white \
      -fill red \
      -gravity Center \
      -pointsize 24 \
      -annotate 0 "Error converting diagram:\n$(basename "$input_file")\n\nPlease check the diagram file for errors." \
      "$output_png" && echo "✓ Created placeholder PNG with ImageMagick" && return 0
  fi
  
  # If ImageMagick failed or is not available, try using HTML/CSS with wkhtmltoimage
  if command -v wkhtmltoimage >/dev/null 2>&1; then
    local temp_html=$(mktemp --suffix=.html)
    echo "<html><body style='display:flex;justify-content:center;align-items:center;height:100vh;'>" > "$temp_html"
    echo "<div style='text-align:center;color:red;font-size:24px;'>" >> "$temp_html"
    echo "<p>Error converting diagram:</p>" >> "$temp_html"
    echo "<p><b>$(basename "$input_file")</b></p>" >> "$temp_html"
    echo "<p>Please check the diagram file for errors.</p>" >> "$temp_html"
    echo "</div></body></html>" >> "$temp_html"
    
    wkhtmltoimage "$temp_html" "$output_png" && echo "✓ Created placeholder PNG with wkhtmltoimage" && rm -f "$temp_html" && return 0
    rm -f "$temp_html"
  fi
  
  # Last resort: create an empty file with error note
  echo "Could not create placeholder PNG. Creating empty file with .error extension"
  echo "Failed to convert $(basename "$input_file") at $(date)" > "${output_png}.error"
  touch "$output_png"
  return 1
}

# Function to determine version increment
determine_version() 
