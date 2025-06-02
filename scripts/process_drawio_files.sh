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
  # Check if CHANGED_FILES environment variable is set (from GitHub Actions)
  if [[ -n "$CHANGED_FILES" ]]; then
    echo "Using CHANGED_FILES from environment: $CHANGED_FILES"
    # Make sure CHANGED_FILES is available globally
    export CHANGED_FILES
    return
  elif [[ -n "$SPECIFIC_FILE" ]]; then
    echo "Processing specific file: $SPECIFIC_FILE"
    export CHANGED_FILES="$SPECIFIC_FILE"
    return
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
    local changed_files=$(cat "$temp_diff_file" | tr '\n' ' ')
    rm -f "$temp_diff_file"
    
    if [[ -z "$changed_files" ]]; then
      echo "No draw.io files found by any method."
      export CHANGED_FILES=""
      return
    fi
    
    export CHANGED_FILES="$changed_files"
  fi
  
  echo "Changed files: $CHANGED_FILES"
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
  
  # Ensure input file exists and is readable
  if [[ ! -f "$input_file" ]]; then
    echo "❌ Error: Input file $input_file does not exist"
    create_placeholder_png "$input_file" "$output_png"
    return 1
  fi
  
  if [[ ! -r "$input_file" ]]; then
    echo "❌ Error: Input file $input_file is not readable"
    create_placeholder_png "$input_file" "$output_png"
    return 1
  fi
  
  # Check if input file has content
  local file_size=$(wc -c < "$input_file")
  if [[ $file_size -lt 100 ]]; then
    echo "⚠️ Warning: Input file seems very small ($file_size bytes), might be corrupted"
  fi
  
  # Create a temporary conversion script for better error handling
  local converter_script=$(mktemp)
  echo "#!/bin/bash" > "$converter_script"
  echo "set -o pipefail" >> "$converter_script"
  echo "input_file=\"\$1\"" >> "$converter_script"
  echo "output_file=\"\$2\"" >> "$converter_script"
  echo "scale=\"\$3\"" >> "$converter_script"
  echo "echo \"Converting: \$input_file to \$output_file with scale=\$scale\"" >> "$converter_script"
  echo "" >> "$converter_script"
  
  echo "# Method 1: Try with xvfb-run (recommended approach)" >> "$converter_script"
  echo "if xvfb-run --auto-servernum --server-args=\"-screen 0 1280x1024x24\" drawio -x -f png --scale \"\$scale\" -o \"\$output_file\" \"\$input_file\" 2>&1; then" >> "$converter_script"
  echo "  echo \"✅ Method 1 (xvfb-run) successful\"" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  echo \"❌ Method 1 (xvfb-run) failed with exit code \$?\"" >> "$converter_script"
  echo "  echo \"Error output:\"" >> "$converter_script"
  echo "  xvfb-run --auto-servernum --server-args=\"-screen 0 1280x1024x24\" drawio -x -f png --scale \"\$scale\" -o \"\$output_file\" \"\$input_file\" 2>&1 || true" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# Method 2: Try with export browser display and xvfb" >> "$converter_script"
  echo "export DISPLAY=:99" >> "$converter_script"
  echo "Xvfb :99 -screen 0 1280x1024x24 > /dev/null 2>&1 &" >> "$converter_script"
  echo "XVFB_PID=\$!" >> "$converter_script"
  echo "sleep 2" >> "$converter_script"
  echo "if drawio -x -f png --scale \"\$scale\" -o \"\$output_file\" \"\$input_file\" 2>&1; then" >> "$converter_script"
  echo "  echo \"✅ Method 2 (export DISPLAY) successful\"" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  exit 0" >> "$converter_script"
  echo "else" >> "$converter_script"
  echo "  kill \$XVFB_PID || true" >> "$converter_script"
  echo "  echo \"❌ Method 2 (export DISPLAY) failed with exit code \$?\"" >> "$converter_script"
  echo "  echo \"Error output:\"" >> "$converter_script"
  echo "  drawio -x -f png --scale \"\$scale\" -o \"\$output_file\" \"\$input_file\" 2>&1 || true" >> "$converter_script"
  echo "fi" >> "$converter_script"
  echo "" >> "$converter_script"
  echo "# All conversion methods failed" >> "$converter_script"
  echo "exit 1" >> "$converter_script"
  chmod +x "$converter_script"
  
  # Execute the converter script (note: quality parameter removed as it's not valid for PNG)
  echo "Executing conversion script..."
  if "$converter_script" "$input_file" "$output_png" "$PNG_SCALE" 2>&1; then
    echo "✓ Successfully created $output_png"
    
    # Verify output file exists and has appropriate size
    if [[ -f "$output_png" && -s "$output_png" ]]; then
      file_size=$(du -k "$output_png" | cut -f1)
      echo "Output PNG file size: ${file_size}KB"
      
      if [[ $file_size -lt 2 ]]; then
        echo "⚠️ Warning: Output file seems too small, might be corrupted"
        echo "Treating this as a conversion failure..."
        rm -f "$output_png"  # Remove the corrupted file
        create_placeholder_png "$input_file" "$output_png"
        rm -f "$converter_script"
        return 1
      fi
    else
      echo "⚠️ Warning: Output file wasn't created or is empty"
      # Create placeholder since we didn't get a proper output
      create_placeholder_png "$input_file" "$output_png"
      rm -f "$converter_script"
      return 1
    fi
    
    rm -f "$converter_script"
    return 0
  else
    local exit_code=$?
    echo "✗ Conversion failed with exit code $exit_code"
    
    # If conversion failed, create a placeholder PNG or error file
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
    if convert -size 800x600 xc:white \
      -fill red \
      -gravity Center \
      -pointsize 24 \
      -annotate 0 "Error converting diagram:\n$(basename "$input_file")\n\nPlease check the diagram file for errors." \
      "$output_png"; then
      echo "✓ Created placeholder PNG with ImageMagick"
      return 0
    fi
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
    
    if wkhtmltoimage "$temp_html" "$output_png"; then
      echo "✓ Created placeholder PNG with wkhtmltoimage"
      rm -f "$temp_html"
      return 0
    fi
    rm -f "$temp_html"
  fi
  
  # Last resort: create an error file instead of empty PNG
  echo "Could not create placeholder PNG. Creating error file."
  echo "Failed to convert $(basename "$input_file") at $(date)" > "${output_png}.error"
  # Don't create empty PNG file - just the error file
  return 1
}

# Function to determine version increment
determine_version() {
  local file="$1"
  local id=$(extract_id "$file")
  
  if [[ -z "$id" ]]; then
    echo "Error: Could not extract ID from $file" >&2
    echo "1.0"  # Return a default value instead of failing
    return 0
  fi
  
  # Get the commit message
  local commit_msg=$(git log -1 --format="%s" -- "$file")
  echo "Commit message for $file: '$commit_msg'" >&2
  
  # Check if file exists in version tracking file
  local version_file="$PNG_FILES_DIR/.versions"
  local major=1
  local minor=0
  
  if [[ -f "$version_file" ]]; then
    echo "Version file exists at $version_file" >&2
    local current_version=$(grep "^$id:" "$version_file" | cut -d: -f2)
    if [[ -n "$current_version" ]]; then
      major=$(echo "$current_version" | cut -d. -f1)
      minor=$(echo "$current_version" | cut -d. -f2)
      echo "Found existing version for ID $id: $current_version" >&2
    else
      echo "No existing version for ID $id, will start with 1.0" >&2
    fi
  else
    echo "Version file doesn't exist, creating new one at $version_file" >&2
    touch "$version_file"
  fi
  
  # Determine version based on commit message
  if echo "$commit_msg" | grep -Eiq '(added|new)'; then
    # For new files, always start with version 1.0
    major=1
    minor=0
    echo "This is a new file, setting initial version to 1.0" >&2
  else
    # For updates, increment minor version
    minor=$((minor+1))
    echo "This is an update, incrementing minor version to $major.$minor" >&2
  fi
  
  local new_version="${major}.${minor}"
  
  # Update the version file - ensure there are no duplicate IDs
  # First remove any existing entry for this ID to avoid duplicates
  if grep -q "^$id:" "$version_file"; then
    echo "Updating existing entry for ID $id to version $new_version" >&2
    # Use platform-independent way to update the version file
    # Create a temporary file for sed output
    local temp_version_file=$(mktemp)
    grep -v "^$id:" "$version_file" > "$temp_version_file"
    echo "$id:$new_version" >> "$temp_version_file"
    mv "$temp_version_file" "$version_file"
  else
    echo "Adding new entry for ID $id with version $new_version" >&2
    echo "$id:$new_version" >> "$version_file"
  fi
  
  echo "$new_version" # This is the actual return value and should go to stdout
}

# Function to update changelog
update_changelog() {
  local file="$1"
  local conversion_success="${2:-true}"  # Default to true for backward compatibility
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
  
  # Ensure we have a version
  if [[ -z "$version" || "$version" == "" ]]; then
    echo "Warning: No version obtained for $file, using default 1.0"
    version="1.0"
  fi
  
  # Determine action based on conversion success
  local action="Converted to PNG"
  if [[ "$conversion_success" != "true" ]]; then
    action="Conversion failed - placeholder created"
  fi
  
  # Create changelog entry
  local entry="$current_date,$current_time,\"$filename_without_ext\",\"$file\",\"$action\",\"$commit_msg\",$version,$commit_hash,\"$author_name\""
  
  # Create lock file for atomic updates
  local lock_file="${CHANGELOG_FILE}.lock"
  
  # Try to acquire lock - only continue if we can create the lock file
  if ! mkdir "$lock_file" 2>/dev/null; then
    echo "Another process is updating the changelog. Waiting for lock..."
    local max_wait=30
    local wait_count=0
    
    # Wait for the lock to be released
    while [ $wait_count -lt $max_wait ] && ! mkdir "$lock_file" 2>/dev/null; do
      sleep 1
      wait_count=$((wait_count + 1))
      echo "Waiting for lock... ($wait_count/$max_wait)"
    done
    
    # If we still can't get the lock after waiting, try to force it
    if ! mkdir "$lock_file" 2>/dev/null; then
      echo "Warning: Lock file exists for too long. Checking if process is still active..."
      
      # If the lock is more than 5 minutes old, assume it's stale and force it
      if [ -d "$lock_file" ] && [ $(($(date +%s) - $(stat -c %Y "$lock_file"))) -gt 300 ]; then
        echo "Lock appears to be stale. Removing and continuing."
        rm -rf "$lock_file"
        mkdir "$lock_file"
      else
        echo "Error: Cannot acquire changelog lock. Skipping changelog update."
        return 1
      fi
    fi
  fi
  
  # We now have the lock
  trap 'rm -rf "$lock_file"' EXIT
  
  # Make sure changelog file exists
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Creating new changelog file: $CHANGELOG_FILE"
    mkdir -p "$(dirname "$CHANGELOG_FILE")"
    echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
  fi
  
  # Atomic update of the changelog file to prevent conflicts
  local temp_file=$(mktemp)
  cat "$CHANGELOG_FILE" > "$temp_file"
  echo "$entry" >> "$temp_file"
  mv "$temp_file" "$CHANGELOG_FILE"
  
  echo "Added entry to changelog for $basename (version $version)"
  
  # Touch the changelog file to update its timestamp
  touch "$CHANGELOG_FILE"
  
  # Release the lock
  rm -rf "$lock_file"
  trap - EXIT
}

# Function to generate GitHub step summary
generate_github_step_summary() {
  local processed_count="$1"
  
  # If GITHUB_STEP_SUMMARY isn't available, we're not running in GitHub Actions
  if [[ -z "$GITHUB_STEP_SUMMARY" ]]; then
    echo "Not running in GitHub Actions, skipping summary generation"
    return
  fi
  
  echo "Generating GitHub step summary..."
  
  # Header
  echo "## 📊 Draw.io Processing Summary" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  if [[ $processed_count -eq 0 ]]; then
    echo "📝 **No diagrams processed in this run**" >> $GITHUB_STEP_SUMMARY
    return
  fi
  
  # Get list of processed files from the latest changes
  local processed_files=$(git diff --name-only HEAD~1 HEAD -- 'png_files/*.png' | sed 's|png_files/||g' | sed 's|.png$||g')
  
  echo "### 🔄 Processed Files (${processed_count})" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  echo "| File | Version | Action |" >> $GITHUB_STEP_SUMMARY
  echo "|------|---------|--------|" >> $GITHUB_STEP_SUMMARY
  
  # Extract information from changelog
  if [[ -f "$CHANGELOG_FILE" ]]; then
    # Skip the header line and get the last $processed_count lines
    tail -n "$processed_count" "$CHANGELOG_FILE" | while IFS=, read -r date time diagram file action message version hash author; do
      # Clean up the values (remove quotes)
      diagram=$(echo "$diagram" | tr -d '"')
      version=$(echo "$version" | tr -d '"')
      action=$(echo "$action" | tr -d '"')
      
      echo "| ${diagram} | ${version} | ${action} |" >> $GITHUB_STEP_SUMMARY
    done
  fi
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "### ⚙️ Configuration" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "- **PNG Scale**: ${PNG_SCALE}" >> $GITHUB_STEP_SUMMARY
  echo "- **PNG Quality**: ${PNG_QUALITY}" >> $GITHUB_STEP_SUMMARY
  echo "- **Changelog**: \`${CHANGELOG_FILE}\`" >> $GITHUB_STEP_SUMMARY
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "✅ **All diagrams processed successfully**" >> $GITHUB_STEP_SUMMARY
}

# Main flow
main() {
  detect_changed_files
  
  # Prepare to process files
  
  # Check if CHANGED_FILES is empty
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "ERROR: No files to process. CHANGED_FILES is empty."
    exit 0
  fi
  
  # Initialize a counter for processed files
  local processed_count=0
  
  # Convert CHANGED_FILES to an array to properly handle spaces in filenames
  IFS=$'\n' read -rd '' -a files_array <<< "$CHANGED_FILES"
  
  for file in "${files_array[@]}"; do
    # Skip empty entries
    [[ -z "$file" ]] && continue
    
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
    local conversion_success=true
    if ! convert_to_png "$processed_file"; then
      echo "Warning: Failed to convert $processed_file to PNG, but placeholder was created."
      conversion_success=false
    fi
    
    # Update changelog regardless of conversion success (since we create placeholders)
    update_changelog "$processed_file" "$conversion_success"
    
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
  
  # Generate GitHub step summary
  generate_github_step_summary "$processed_count"
}

# Run main function
main
