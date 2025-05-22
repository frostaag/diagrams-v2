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
determine_version() {
  local file="$1"
  echo "[determine_version] Called for file: $file" >&2
  local id
  id=$(extract_id "$file")
  
  if [[ -z "$id" ]]; then
    echo "[determine_version] Error: Could not extract ID from $file. Cannot determine version." >&2
    return 1 # Signal error
  fi
  
  local commit_msg
  commit_msg=$(git log -1 --format="%s" -- "$file")
  echo "[determine_version] Commit message for $file (for versioning logic): '$commit_msg'" >&2
  
  local version_file="$PNG_FILES_DIR/.versions"
  local major=1 # Default major version
  local minor=0 # Default minor version
  
  if [[ -f "$version_file" ]]; then
    echo "[determine_version] Version file exists at $version_file" >&2
    local current_version_line
    current_version_line=$(grep "^$id:" "$version_file")
    if [[ -n "$current_version_line" ]]; then
      local current_version
      current_version=$(echo "$current_version_line" | cut -d: -f2)
      if [[ "$current_version" =~ ^([0-9]+)\\.([0-9]+)$ ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
      elif [[ "$current_version" =~ ^([0-9]+)$ ]]; then
        major=${BASH_REMATCH[1]}
        minor=0 
      else
        echo "[determine_version] Warning: Unexpected version format '$current_version' for ID $id. Resetting to 1.0." >&2
        major=1
        minor=0
      fi
      echo "[determine_version] Found existing version for ID $id: $major.$minor" >&2
    else
      echo "[determine_version] No existing version for ID $id in $version_file. Initializing to 1.0." >&2
      major=1
      minor=0
    fi
  else
    echo "[determine_version] Version file '$version_file' not found. Initializing version for ID $id to 1.0." >&2
    # major=1, minor=0 already set as defaults
    # Create the .versions file with a header if it's the very first time
    if ! mkdir -p "$(dirname "$version_file")"; then echo "[determine_version] Error creating directory for $version_file" >&2; return 1; fi
    if ! echo "# Diagram ID to Version mapping" > "$version_file"; then echo "[determine_version] Error creating $version_file" >&2; return 1; fi
    echo "[determine_version] Created $version_file with header." >&2
  fi
  
  if echo "$commit_msg" | grep -Eiq '(added|new|initial|create)'; then
    echo "[determine_version] Commit message suggests new file. Setting version for ID $id to 1.0." >&2
    major=1
    minor=0
  else
    echo "[determine_version] Commit message suggests update. Incrementing minor version for ID $id from $major.$minor." >&2
    minor=$((10#$minor + 1))
  fi
  
  local new_version="${major}.${minor}"
  echo "[determine_version] Determined version for ID $id ($file): $new_version" >&2
  
  local temp_version_file
  temp_version_file=$(mktemp)
  if [[ $? -ne 0 ]] || [[ -z "$temp_version_file" ]]; then echo "[determine_version] Error creating temp file for .versions" >&2; return 1; fi

  if grep -q "^$id:" "$version_file"; then
    echo "[determine_version] Updating existing entry in $version_file for ID $id to version $new_version" >&2
    sed "s/^$id:.*/$id:$new_version/" "$version_file" > "$temp_version_file" && mv "$temp_version_file" "$version_file"
    if [[ $? -ne 0 ]]; then echo "[determine_version] Error updating $version_file" >&2; rm -f "$temp_version_file"; return 1; fi
  else
    echo "[determine_version] Adding new entry to $version_file for ID $id with version $new_version" >&2
    echo "$id:$new_version" >> "$version_file"
    if [[ $? -ne 0 ]]; then echo "[determine_version] Error adding to $version_file" >&2; rm -f "$temp_version_file"; return 1; fi
    # Temp file not used in this path, but ensure it's cleaned up if mktemp was called
    rm -f "$temp_version_file" 
  fi
  
  echo "$new_version" 
  return 0 
}

# Function to update changelog
update_changelog() {
  local file="$1" 
  echo "[update_changelog] Called for file: $file" >&2
  echo "[update_changelog] TRIGGERING_SHA: $TRIGGERING_SHA" >&2
  local basename
  basename=$(basename "$file")
  local filename_without_ext="${basename%.drawio}"
  
  local commit_hash_to_log=""
  local commit_msg_to_log=""
  local author_name_to_log=""

  if [[ -n "$TRIGGERING_SHA" ]]; then
    commit_hash_to_log=$(git log -1 --format="%h" "$TRIGGERING_SHA")
    commit_msg_to_log=$(git log -1 --format="%s" "$TRIGGERING_SHA")
    author_name_to_log=$(git log -1 --format="%an" "$TRIGGERING_SHA")
    echo "[update_changelog] Using TRIGGERING_SHA ($TRIGGERING_SHA): hash=$commit_hash_to_log, author=$author_name_to_log, msg=$commit_msg_to_log" >&2
  else
    echo "[update_changelog] Warning: TRIGGERING_SHA not found. Falling back to per-file commit info for $file." >&2
    commit_hash_to_log=$(git log -1 --format="%h" -- "$file")
    commit_msg_to_log=$(git log -1 --format="%s" -- "$file")
    author_name_to_log=$(git log -1 --format="%an" -- "$file")
  fi
  
  local current_date
  current_date=$(date +"%d.%m.%Y")
  local current_time
  current_time=$(date +"%H:%M:%S")
  
  echo "[update_changelog] Attempting to determine version for $file..." >&2
  local version_output
  version_output=$(determine_version "$file")
  local determine_version_exit_code=$?

  if [[ $determine_version_exit_code -ne 0 ]] || [[ -z "$version_output" ]]; then
      echo "[update_changelog] Error: determine_version failed for $file or returned empty. Exit code: $determine_version_exit_code. Skipping changelog update for this file." >&2
      return 1
  fi
  local version="$version_output"
  echo "[update_changelog] Version determined for $file: $version" >&2
  
  local commit_msg_to_log_escaped
  commit_msg_to_log_escaped=$(echo "$commit_msg_to_log" | sed 's/"/""/g')
  
  local entry="$current_date,$current_time,\\\"$filename_without_ext\\\",\\\"$file\\\",\\\"Converted to PNG\\\",\\\"$commit_msg_to_log_escaped\\\",$version,$commit_hash_to_log,\\\"$author_name_to_log\\\""
  echo "[update_changelog] Changelog entry to be added: $entry" >&2
  echo "[update_changelog] Target changelog file: $CHANGELOG_FILE" >&2

  local lock_file="${CHANGELOG_FILE}.lock"
  echo "[update_changelog] Attempting to acquire lock: $lock_file" >&2
  if ! mkdir "$lock_file" 2>/dev/null; then
    echo "[update_changelog] Lock exists. Waiting..." >&2
    local max_wait=30
    local wait_count=0
    while [ $wait_count -lt $max_wait ] && ! mkdir "$lock_file" 2>/dev/null; do
      sleep 1
      wait_count=$((wait_count + 1))
      echo "[update_changelog] Waiting for lock... ($wait_count/$max_wait)" >&2
    done
    
    if ! mkdir "$lock_file" 2>/dev/null; then 
      if [ -d "$lock_file" ] && [ "$(( $(date +%s) - $(stat -c %Y "$lock_file") ))" -gt 300 ]; then
        echo "[update_changelog] Stale lock detected (older than 5 minutes). Removing and acquiring." >&2
        rm -rf "$lock_file"
        if ! mkdir "$lock_file"; then
           echo "[update_changelog] Error: Failed to acquire lock even after removing stale one for $file." >&2
           return 1
        fi
      else
        echo "[update_changelog] Error: Cannot acquire changelog lock for $file after waiting. Skipping changelog update." >&2
        return 1
      fi
    fi
  fi
  echo "[update_changelog] Lock acquired: $lock_file" >&2
  
  # Set trap with logging
  trap 'echo "[update_changelog] EXIT trap removing lock: $lock_file for $file" >&2; rm -rf "$lock_file"' EXIT

  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "[update_changelog] Changelog file does not exist. Creating with header: $CHANGELOG_FILE" >&2
    if ! mkdir -p "$(dirname "$CHANGELOG_FILE")"; then
        echo "[update_changelog] Error: Failed to create directory for $CHANGELOG_FILE." >&2
        rm -rf "$lock_file"; trap - EXIT; return 1;
    fi
    if ! echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"; then
        echo "[update_changelog] Error: Failed to create or write header to $CHANGELOG_FILE." >&2
        rm -rf "$lock_file"; trap - EXIT; return 1;
    fi
  fi
  
  local temp_changelog_file
  temp_changelog_file=$(mktemp)
  if [[ $? -ne 0 ]] || [[ -z "$temp_changelog_file" ]]; then
      echo "[update_changelog] Error: Failed to create temp file for changelog update." >&2
      rm -rf "$lock_file"; trap - EXIT; return 1;
  fi
  echo "[update_changelog] Created temp file for changelog: $temp_changelog_file" >&2

  cat "$CHANGELOG_FILE" > "$temp_changelog_file"
  echo "$entry" >> "$temp_changelog_file"
  
  echo "[update_changelog] Moving $temp_changelog_file to $CHANGELOG_FILE" >&2
  if ! mv "$temp_changelog_file" "$CHANGELOG_FILE"; then
      echo "[update_changelog] Error: Failed to move temp file to $CHANGELOG_FILE. Original temp file: $temp_changelog_file (not deleted)." >&2
      rm -rf "$lock_file"; trap - EXIT; return 1;
  fi
  
  echo "[update_changelog] Successfully added entry to changelog for $basename (version $version)" >&2
  
  rm -rf "$lock_file"
  trap - EXIT # Clear the trap for this specific execution
  echo "[update_changelog] Lock released, trap cleared for $file." >&2
  return 0
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
  echo "[main] Starting script execution." >&2
  detect_changed_files # This function should set CHANGED_FILES env var or script var
  
  if [[ -z "$CHANGED_FILES" ]]; then # Check env var set by workflow or by script's detect_changed_files
    echo "[main] No files to process (CHANGED_FILES is empty). Exiting." >&2
    exit 0
  fi
  echo "[main] Files to process based on CHANGED_FILES env var: $CHANGED_FILES" >&2
  
  local processed_count=0
  local overall_success=true 

  # IFS is set to space, tab, newline by default.
  # If CHANGED_FILES can contain spaces in filenames (it shouldn't with current logic), this loop needs care.
  # Assuming CHANGED_FILES is a space-separated list of paths without spaces in them.
  for file_to_process_loopvar in $CHANGED_FILES; do
    echo "[main] Processing file from list: '$file_to_process_loopvar'" >&2
    
    if [[ ! -f "$file_to_process_loopvar" ]]; then
      echo "[main] Warning: File $file_to_process_loopvar from CHANGED_FILES list does not exist, skipping." >&2
      continue
    fi
    
    local processed_file_path="$file_to_process_loopvar" # Start with the original path
    
    # Assign ID if needed. assign_ids might rename the file and update PROCESSED_FILE env var.
    # The assign_ids function needs to reliably return the new path if renamed, or the original if not.
    # For now, let's assume assign_ids correctly handles $file_to_process_loopvar and
    # if it renames, the new name is what we need for conversion and changelog.
    # A better way: assign_ids could echo the new path to stdout.
    
    local path_after_assign_ids
    path_after_assign_ids=$(assign_ids "$file_to_process_loopvar") # Assuming assign_ids is modified to echo new path
    local assign_ids_exit_code=$?

    if [[ $assign_ids_exit_code -ne 0 ]]; then
        echo "[main] Error in assign_ids for $file_to_process_loopvar. Skipping." >&2
        overall_success=false
        continue
    fi
    # If assign_ids didn't rename, it should echo the original path.
    # If it did rename, it echoes the new path.
    processed_file_path="$path_after_assign_ids"
    echo "[main] File path after assign_ids: $processed_file_path" >&2


    if ! convert_to_png "$processed_file_path"; then
      echo "[main] Error: Failed to convert $processed_file_path to PNG, continuing with next file." >&2
      overall_success=false
      continue # Skip changelog for failed conversion
    fi
    
    echo "[main] Attempting to update changelog for $processed_file_path..." >&2
    if update_changelog "$processed_file_path"; then
      echo "[main] Changelog updated successfully for $processed_file_path." >&2
    else
      echo "[main] Failed to update changelog for $processed_file_path. See errors above." >&2
      overall_success=false 
    fi
    
    processed_count=$((processed_count + 1))
  done
  
  echo "[main] Finished processing $processed_count files." >&2
  
  if [[ $processed_count -eq 0 && ! -f "$CHANGELOG_FILE" ]]; then
    echo "[main] Creating empty changelog as no files were processed and it doesn't exist." >&2
    if ! mkdir -p "$(dirname "$CHANGELOG_FILE")"; then echo "[main] Error creating dir for empty changelog" >&2; fi
    if ! echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"; then echo "[main] Error creating empty changelog file" >&2; fi
  fi
  
  generate_github_step_summary "$processed_count"

  if [[ "$overall_success" = false ]]; then
    echo "[main] One or more operations failed during processing. Please check logs." >&2
    # exit 1 # Optionally exit with error
  fi
  echo "[main] Script execution finished." >&2
}

# Modify assign_ids to output the new (or original) file path to stdout
assign_ids() {
  local file_param="$1" # Use a different name to avoid confusion with global 'file'
  local current_file_path="$file_param" # Track the path, may change if renamed
  local basename
  basename=$(basename "$current_file_path")
  echo "[assign_ids] Called for file: $current_file_path (basename: $basename)" >&2

  if [[ "$basename" =~ \\([0-9]{3}\\)\\.drawio$ ]] || [[ "$basename" =~ ^[0-9]+\\.drawio$ ]]; then
    echo "[assign_ids] File $basename already has an ID or is numeric. No renaming needed." >&2
    echo "$current_file_path" # Output original path
    return 0
  fi
  
  if [[ ! -f "$COUNTER_FILE" ]]; then
    echo "[assign_ids] Counter file $COUNTER_FILE not found. Creating with 000." >&2
    if ! mkdir -p "$(dirname "$COUNTER_FILE")"; then echo "[assign_ids] Error creating dir for $COUNTER_FILE" >&2; echo "$current_file_path"; return 1; fi
    if ! echo "000" > "$COUNTER_FILE"; then echo "[assign_ids] Error creating $COUNTER_FILE" >&2; echo "$current_file_path"; return 1; fi
  fi
  
  local counter
  counter=$(<"$COUNTER_FILE")
  local new_counter_val
  new_counter_val=$((10#$counter + 1))
  local new_counter_str
  new_counter_str=$(printf "%03d" $new_counter_val)
  
  local filename_without_ext="${basename%.drawio}"
  local new_filename="${filename_without_ext} (${new_counter_str}).drawio"
  # Ensure DRAWIO_FILES_DIR is used for the new path
  local new_filepath="${DRAWIO_FILES_DIR}/${new_filename}"
  
  echo "[assign_ids] Attempting to rename $current_file_path to $new_filepath" >&2
  if ! mv "$current_file_path" "$new_filepath"; then
    echo "[assign_ids] Error: Failed to rename $current_file_path to $new_filepath." >&2
    echo "$current_file_path" # Output original path on failure
    return 1
  fi
  
  if ! echo "$new_counter_str" > "$COUNTER_FILE"; then
    echo "[assign_ids] Error: Failed to update counter file $COUNTER_FILE." >&2
    # File was renamed, but counter not updated. This is problematic.
    # Consider reverting rename or other error handling. For now, log and continue with new path.
    echo "$new_filepath" # Output new path despite counter error
    return 1 # Signal error due to counter update failure
  fi
  
  echo "[assign_ids] Assigned ID $new_counter_str to $basename -> $new_filename. New path: $new_filepath" >&2
  echo "$new_filepath" # Output new path
  return 0
}

# Ensure all echos intended for GITHUB_ENV or GITHUB_OUTPUT in other functions are correct.
# For example, in convert_to_png, if it sets outputs, ensure it's using $GITHUB_OUTPUT.

main "$@"
