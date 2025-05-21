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

# Function to detect changed files
detect_changed_files() {
  local changed_files=""
  
  # Check if CHANGED_FILES environment variable is set (from GitHub Actions)
  if [[ -n "$CHANGED_FILES" ]]; then
    echo "Using CHANGED_FILES from environment: $CHANGED_FILES"
    echo "DEBUG: CHANGED_FILES environment variable is set to: '$CHANGED_FILES'"
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
  local basename=$(basename "$file")
  
  # Check if file already has an ID pattern (###) or is a numeric filename
  if [[ "$basename" =~ \([0-9]{3}\)\.drawio$ ]]; then
    echo "File $basename already has an ID, skipping ID assignment."
    return 0
  elif [[ "$basename" =~ ^[0-9]+\.drawio$ ]]; then
    echo "File $basename has a numeric name, preserving as-is."
    return 0
  fi
  
  # Read current counter
  local counter=$(<"$COUNTER_FILE")
  # Increment counter
  local new_counter=$(printf "%03d" $((10#$counter + 1)))
  # New filename with ID
  local filename_without_ext="${basename%.drawio}"
  local new_filename="${filename_without_ext} (${new_counter}).drawio"
  local new_filepath="${DRAWIO_FILES_DIR}/${new_filename}"
  
  # Rename the file
  mv "$file" "$new_filepath"
  
  # Update counter file
  echo "$new_counter" > "$COUNTER_FILE"
  
  echo "Assigned ID $new_counter to $basename -> $new_filename"
  # Update the file variable for further processing
  echo "PROCESSED_FILE=$new_filepath" >> $GITHUB_ENV
}

# Function to extract ID from filename
extract_id() {
  local file="$1"
  local basename=$(basename "$file")
  
  if [[ "$basename" =~ \(([0-9]{3})\)\.drawio$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$basename" =~ ^([0-9]+)\.drawio$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
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
  echo "# Method 1: Try direct command" >> "$converter_script"
  echo "if drawio -x -f png --scale \"\$scale\" --quality \"\$quality\" -o \"\$output_file\" \"\$input_file\"; then" >> "$converter_script"
  echo "  echo \"✅ Method 1 (direct conversion) successful\"" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  echo \"❌ Method 1 (direct conversion) failed with exit code \$?\"" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# Method 2: Try with xvfb-run as fallback" >> "$converter_script"
  echo "if xvfb-run --auto-servernum --server-args=\"-screen 0 1280x1024x24\" drawio -x -f png --scale \"\$scale\" --quality \"\$quality\" -o \"\$output_file\" \"\$input_file\"; then" >> "$converter_script"
  echo "  echo \"✅ Method 2 (xvfb-run) successful\"" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  echo \"❌ Method 2 (xvfb-run) failed with exit code \$?\"" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# Method 3: Try with export browser display and xvfb" >> "$converter_script"
  echo "export DISPLAY=:99" >> "$converter_script"
  echo "Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &" >> "$converter_script"
  echo "XVFB_PID=\$!" >> "$converter_script"
  echo "sleep 2" >> "$converter_script"
  echo "if drawio -x -f png --scale \"\$scale\" --quality \"\$quality\" -o \"\$output_file\" \"\$input_file\"; then" >> "$converter_script"
  echo "  echo \"✅ Method 3 (export DISPLAY) successful\"" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  echo \"❌ Method 3 (export DISPLAY) failed with exit code \$?\"" >> "$converter_script"
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
determine_version() {
  local file="$1"
  local id=$(extract_id "$file")
  
  if [[ -z "$id" ]]; then
    echo "Error: Could not extract ID from $file"
    return 1
  fi
  
  # Get the commit message
  local commit_msg=$(git log -1 --format="%s" -- "$file")
  
  # Check if file exists in version tracking file
  local version_file="$PNG_FILES_DIR/.versions"
  local major=1
  local minor=0
  
  if [[ -f "$version_file" ]]; then
    local current_version=$(grep "^$id:" "$version_file" | cut -d: -f2)
    if [[ -n "$current_version" ]]; then
      major=$(echo "$current_version" | cut -d. -f1)
      minor=$(echo "$current_version" | cut -d. -f2)
    fi
  else
    touch "$version_file"
  fi
  
  # Determine version increment based on commit message
  if echo "$commit_msg" | grep -Eiq '(added|new)'; then
    # Major version increment for new files
    major=$((major+1))
    minor=0
  else
    # Minor version increment for updates
    minor=$((minor+1))
  fi
  
  local new_version="${major}.${minor}"
  
  # Update the version file
  if grep -q "^$id:" "$version_file"; then
    sed -i "s/^$id:.*/$id:$new_version/" "$version_file"
  else
    echo "$id:$new_version" >> "$version_file"
  fi
  
  echo "$new_version"
}

# Function to update changelog
update_changelog() {
  local file="$1"
  local basename=$(basename "$file")
  local filename_without_ext="${basename%.drawio}"
  
  # Get commit info
  local commit_hash=$(git log -1 --format="%h" -- "$file")
  local commit_msg=$(git log -1 --format="%s" -- "$file")
  local author_name=$(git log -1 --format="%an" -- "$file")
  
  # Get current date and time
  local current_date=$(date +"%d.%m.%Y")
  local current_time=$(date +"%H:%M:%S")
  
  # Determine version
  local version=$(determine_version "$file")
  
  # Create changelog entry
  local entry="$current_date,$current_time,\"$filename_without_ext\",\"$file\",\"Converted to PNG\",\"$commit_msg\",$version,$commit_hash,\"$author_name\""
  
  # Make sure changelog file exists
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Creating new changelog file: $CHANGELOG_FILE"
    mkdir -p "$(dirname "$CHANGELOG_FILE")"
    echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
  fi
  
  # Add to changelog
  echo "$entry" >> "$CHANGELOG_FILE"
  
  echo "Added entry to changelog for $basename (version $version)"
  
  # Touch the changelog file to update its timestamp
  touch "$CHANGELOG_FILE"
}

# Main flow
main() {
  detect_changed_files
  
  # Debug information
  echo "DEBUG: About to process files in CHANGED_FILES: '$CHANGED_FILES'"
  
  # Check if CHANGED_FILES is empty
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "ERROR: No files to process. CHANGED_FILES is empty."
    exit 0
  fi
  
  # Initialize a counter for processed files
  local processed_count=0
  
  for file in $CHANGED_FILES; do
    echo "Processing file: '$file'"
    
    if [[ ! -f "$file" ]]; then
      echo "Warning: File $file does not exist, skipping."
      continue
    fi
    
    local processed_file="$file"
    
    # Assign ID if needed
    assign_ids "$file"
    if [[ -n "$PROCESSED_FILE" ]]; then
      processed_file="$PROCESSED_FILE"
      echo "File was renamed to: $processed_file"
    fi
    
    # Convert to PNG
    if ! convert_to_png "$processed_file"; then
      echo "Error: Failed to convert $processed_file to PNG, continuing with next file."
      continue
    fi
    
    # Update changelog
    update_changelog "$processed_file"
    
    # Increment counter
    processed_count=$((processed_count+1))
  done
  
  echo "Finished processing $processed_count files."
  
  # Force create an empty changelog if none processed
  if [[ $processed_count -eq 0 && ! -f "$CHANGELOG_FILE" ]]; then
    echo "Creating empty changelog as no files were processed."
    mkdir -p "$(dirname "$CHANGELOG_FILE")"
    echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
  fi
}

# Run main function
main
