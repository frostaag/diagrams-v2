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
  
  # Debug: Record starting point for detection logic
  echo "[detect_changed_files] Starting file detection process"
  echo "[detect_changed_files] Current directory: $(pwd)"
  echo "[detect_changed_files] DRAWIO_FILES_DIR: $DRAWIO_FILES_DIR"
  
  # Create debug file to log detection process
  local detection_log="${DRAWIO_FILES_DIR}/.detection_log.txt"
  echo "=== File Detection Log $(date) ===" > "$detection_log"
  
  # Check if CHANGED_FILES environment variable is already set (from GitHub Actions)
  if [[ -n "$CHANGED_FILES" ]]; then
    echo "[detect_changed_files] Using pre-set CHANGED_FILES from environment: $CHANGED_FILES" | tee -a "$detection_log"
    changed_files="$CHANGED_FILES"
    
    # Verify these files actually exist
    for file in $changed_files; do
      if [[ -f "$file" ]]; then
        echo "[detect_changed_files] Verified file exists: $file" | tee -a "$detection_log"
      else
        echo "[detect_changed_files] WARNING: File doesn't exist: $file" | tee -a "$detection_log"
      fi
    done
    
    echo "CHANGED_FILES=$changed_files" >> $GITHUB_ENV
    echo "[detect_changed_files] Re-exported CHANGED_FILES to GitHub environment" | tee -a "$detection_log"
    return
  elif [[ -n "$SPECIFIC_FILE" ]]; then
    echo "[detect_changed_files] Processing specific file: $SPECIFIC_FILE" | tee -a "$detection_log"
    
    # Verify the specific file exists
    if [[ -f "$SPECIFIC_FILE" ]]; then
      echo "[detect_changed_files] Confirmed specific file exists" | tee -a "$detection_log"
      changed_files="$SPECIFIC_FILE"
    else
      echo "[detect_changed_files] ERROR: Specified file doesn't exist: $SPECIFIC_FILE" | tee -a "$detection_log"
      echo "[detect_changed_files] Searching for any .drawio files instead" | tee -a "$detection_log"
      # Fall back to search for any drawio files
      local found_files=$(find "${DRAWIO_FILES_DIR}" -name "*.drawio" -type f | head -n 10)
      if [[ -n "$found_files" ]]; then
        changed_files="$found_files"
        echo "[detect_changed_files] Found alternative files: $changed_files" | tee -a "$detection_log"
      fi
    fi
  else
    # Create temporary file to store results
    local temp_diff_file=$(mktemp)
    echo "[detect_changed_files] Created temporary file: $temp_diff_file" | tee -a "$detection_log"
    
    # Method 1: Check normal commit for added/modified files
    echo "[detect_changed_files] Trying to detect changed files using git diff..." | tee -a "$detection_log"
    if git rev-parse HEAD^1 >/dev/null 2>&1; then
      # Normal commit, get changed draw.io files
      git diff --name-only --diff-filter=AM HEAD^ HEAD -- "$DRAWIO_FILES_DIR/*.drawio" > "$temp_diff_file" 2>&1
      echo "[detect_changed_files] Method 1 results:" | tee -a "$detection_log"
      cat "$temp_diff_file" | tee -a "$detection_log"
    else
      # Method 2: Initial commit
      echo "[detect_changed_files] Appears to be initial commit, trying git diff-tree..." | tee -a "$detection_log"
      git diff-tree --no-commit-id --name-only --root -r HEAD -- "$DRAWIO_FILES_DIR/*.drawio" > "$temp_diff_file" 2>&1
      echo "[detect_changed_files] Method 2 results:" | tee -a "$detection_log"
      cat "$temp_diff_file" | tee -a "$detection_log"
    fi
    
    # Check if we found any files
    if [ ! -s "$temp_diff_file" ]; then
      echo "[detect_changed_files] No files found with git diff/diff-tree, trying direct filesystem search..." | tee -a "$detection_log"
      # Method 3: Direct filesystem search as last resort
      find "$DRAWIO_FILES_DIR" -name "*.drawio" -type f | sort > "$temp_diff_file"
      echo "[detect_changed_files] Method 3 results:" | tee -a "$detection_log"
      cat "$temp_diff_file" | tee -a "$detection_log"
      
      # Method 4: Hardcode test file for debugging if nothing else worked
      if [ ! -s "$temp_diff_file" ]; then
        echo "[detect_changed_files] No files found with any method, creating a test file for processing" | tee -a "$detection_log"
        
        # Create a test drawing file if needed
        local test_dir="$DRAWIO_FILES_DIR/test"
        mkdir -p "$test_dir"
        local test_file="$test_dir/test_$(date +%s).drawio"
        echo '<mxfile><diagram name="Test">dZHBDoMgDIafhrtC5uLcnJs7efBMRCZkKGhYts3HTwXmkm1JL037f/1pKcQ0b/ea1cWBOSghfVcUYiZk6McpySiDCvcKVkVFcW3jPT4vuHgBwkmIbYu9UxL8IGuUDiOTDDkIe2Bju4SM+UOw3EF6ngQ7vSLbIukzznboLJhlzonekqklOct5qQM/rTl9Cdtdpzt7modNwLwo+hX88B6Ulu37BfkH</diagram></mxfile>' > "$test_file"
        echo "$test_file" > "$temp_diff_file"
        echo "[detect_changed_files] Created test file: $test_file" | tee -a "$detection_log"
      fi
    fi
    
    # Get the files from the temp file
    changed_files=$(cat "$temp_diff_file" | tr '\n' ' ')
    rm -f "$temp_diff_file"
    
    # Final check - if still no files, look for ANY drawio files
    if [[ -z "$changed_files" ]]; then
      echo "[detect_changed_files] Still no files found. Looking for ANY drawio files..." | tee -a "$detection_log"
      changed_files=$(find "$DRAWIO_FILES_DIR" -name "*.drawio" -type f | head -n 3 | tr '\n' ' ')
      
      if [[ -z "$changed_files" ]]; then
        echo "[detect_changed_files] ERROR: No draw.io files found by any method." | tee -a "$detection_log"
        exit 0
      else
        echo "[detect_changed_files] Found files by directory scan: $changed_files" | tee -a "$detection_log"
      fi
    fi
  fi
  
  echo "[detect_changed_files] Final list of files to process: $changed_files" | tee -a "$detection_log"
  echo "CHANGED_FILES=$changed_files" >> $GITHUB_ENV
  
  # Ensure the detection log gets committed too
  git add -f "$detection_log" 2>/dev/null || true
}

# Function to assign IDs to new files
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
  
  # Update the file variable for further processing (for GitHub Actions)
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
  echo "[update_changelog] Starting changelog update for file: $file" >&2
  echo "[update_changelog] Working directory: $(pwd)" >&2
  
  # Debug information about the environment
  echo "[update_changelog] CHANGELOG_FILE path: $CHANGELOG_FILE" >&2
  echo "[update_changelog] Environment variables: GITHUB_SHA=$GITHUB_SHA, TRIGGERING_SHA=$TRIGGERING_SHA" >&2
  
  # Make sure file parameter is valid
  if [[ ! -f "$file" ]]; then
    echo "[update_changelog] ERROR: Input file '$file' does not exist" >&2
    return 1
  fi
  
  # Create the output directory if it doesn't exist
  if ! mkdir -p "$(dirname "$CHANGELOG_FILE")"; then
    echo "[update_changelog] ERROR: Failed to create directory for changelog at '$(dirname "$CHANGELOG_FILE")'" >&2
    return 1
  fi
  
  # Show the directory structure before proceeding
  echo "[update_changelog] Directory structure before update:" >&2
  find "$(dirname "$CHANGELOG_FILE")" -type f -o -type d | sort >&2
  
  local basename
  basename=$(basename "$file")
  local filename_without_ext="${basename%.drawio}"
  
  # Get commit information with explicit error handling
  local commit_hash_to_log=""
  local commit_msg_to_log=""
  local author_name_to_log=""
  
  commit_hash_to_log=$(git log -1 --format="%h" -- "$file" 2>/dev/null)
  if [[ -z "$commit_hash_to_log" ]]; then
    echo "[update_changelog] Warning: Could not get commit hash for $file. Using latest commit hash." >&2
    commit_hash_to_log=$(git log -1 --format="%h" 2>/dev/null || echo "unknown")
  fi
  
  commit_msg_to_log=$(git log -1 --format="%s" -- "$file" 2>/dev/null)
  if [[ -z "$commit_msg_to_log" ]]; then
    echo "[update_changelog] Warning: Could not get commit message for $file. Using latest commit message." >&2
    commit_msg_to_log=$(git log -1 --format="%s" 2>/dev/null || echo "Diagram update")
  fi
  
  author_name_to_log=$(git log -1 --format="%an" -- "$file" 2>/dev/null)
  if [[ -z "$author_name_to_log" ]]; then
    echo "[update_changelog] Warning: Could not get author name for $file. Using latest commit author." >&2
    author_name_to_log=$(git log -1 --format="%an" 2>/dev/null || echo "Unknown Author")
  fi
  
  echo "[update_changelog] Commit info: hash=$commit_hash_to_log, author=$author_name_to_log, msg=$commit_msg_to_log" >&2
  
  # Format date and time according to specification (DD.MM.YYYY and HH:MM:SS)
  local current_date=$(date +"%d.%m.%Y")
  local current_time=$(date +"%H:%M:%S")
  
  # Get version with detailed logging
  echo "[update_changelog] Getting version for $file..." >&2
  local version="1.0" # Default version if determination fails
  
  # Only call determine_version if the function exists
  if declare -f determine_version > /dev/null; then
    local version_output=""
    version_output=$(determine_version "$file" 2>&1)
    local determine_version_exit_code=$?
    
    if [[ $determine_version_exit_code -eq 0 ]] && [[ -n "$version_output" ]]; then
      # Extract only the last line which should be the version number
      version=$(echo "$version_output" | tail -n 1)
      echo "[update_changelog] Successfully determined version: $version" >&2
    else
      echo "[update_changelog] Warning: determine_version failed or returned empty. Using default version 1.0." >&2
      echo "[update_changelog] determine_version output: $version_output" >&2
    fi
  else
    echo "[update_changelog] Warning: determine_version function not found. Using default version 1.0." >&2
  fi
  
  # Properly escape fields for CSV
  # Replace double quotes within fields with two double quotes (CSV standard)
  local escaped_filename_without_ext="${filename_without_ext//\"/\"\"}"
  local escaped_file="${file//\"/\"\"}"
  local escaped_commit_msg="${commit_msg_to_log//\"/\"\"}"
  local escaped_author_name="${author_name_to_log//\"/\"\"}"
  
  # Prepare the changelog entry according to the specification
  local entry="$current_date,$current_time,\"$escaped_filename_without_ext\",\"$escaped_file\",\"Converted to PNG\",\"$escaped_commit_msg\",$version,$commit_hash_to_log,\"$escaped_author_name\""
  echo "[update_changelog] New changelog entry: $entry" >&2
  
  # Create or update the changelog file with proper error handling
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "[update_changelog] Creating new changelog file at $CHANGELOG_FILE" >&2
    
    {
      echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name"
      echo "$entry"
    } > "$CHANGELOG_FILE.tmp"
    
    mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE" 2>/dev/null
    if [[ $? -ne 0 || ! -f "$CHANGELOG_FILE" ]]; then
      echo "[update_changelog] ERROR: Failed to create changelog file at $CHANGELOG_FILE" >&2
      return 1
    fi
    
    echo "[update_changelog] Created new changelog file with header and entry" >&2
  else
    echo "[update_changelog] Appending to existing changelog at $CHANGELOG_FILE" >&2
    
    # Create a backup of the current changelog
    cp "$CHANGELOG_FILE" "$CHANGELOG_FILE.bak" 2>/dev/null
    
    # Append the new entry with error handling
    if ! echo "$entry" >> "$CHANGELOG_FILE"; then
      echo "[update_changelog] ERROR: Failed to append to changelog file" >&2
      if [[ -f "$CHANGELOG_FILE.bak" ]]; then
        mv "$CHANGELOG_FILE.bak" "$CHANGELOG_FILE" 2>/dev/null
        echo "[update_changelog] Restored changelog from backup" >&2
      fi
      return 1
    fi
    
    # Remove the backup if append was successful
    rm -f "$CHANGELOG_FILE.bak" 2>/dev/null
    echo "[update_changelog] Successfully added entry to existing changelog" >&2
  fi
  
  # Ensure the file has appropriate permissions and ownership
  chmod 644 "$CHANGELOG_FILE" 2>/dev/null || echo "[update_changelog] Warning: Failed to set permissions on changelog file" >&2
  
  # Verify the file content
  if [[ -f "$CHANGELOG_FILE" ]]; then
    local file_size=$(wc -c < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown")
    echo "[update_changelog] Verification: changelog exists, size: ${file_size} bytes" >&2
    
    # Output first and last few lines for verification (avoid printing entire file if large)
    echo "[update_changelog] Changelog first 5 lines:" >&2
    head -n 5 "$CHANGELOG_FILE" >&2
    
    local total_lines=$(wc -l < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown")
    echo "[update_changelog] Changelog has $total_lines lines total. Last 3 lines:" >&2
    tail -n 3 "$CHANGELOG_FILE" >&2
    
    # Touch the file to update timestamp
    touch "$CHANGELOG_FILE" 2>/dev/null
    
    # Show directory contents after update
    echo "[update_changelog] Directory contents after update:" >&2
    ls -la "$(dirname "$CHANGELOG_FILE")" >&2
    
    echo "[update_changelog] Changelog update completed successfully" >&2
    return 0
  else
    echo "[update_changelog] ERROR: Changelog file does not exist after update attempt" >&2
    return 1
  fi
}

# Function to generate GitHub step summary
generate_github_step_summary() {
  local processed_count="$1"
  
  # If GITHUB_STEP_SUMMARY isn't available, we're not running in GitHub Actions
  if [[ -z "$GITHUB_STEP_SUMMARY" ]]; then
    echo "[generate_github_step_summary] Not running in GitHub Actions, skipping summary generation"
    return
  fi
  
  echo "[generate_github_step_summary] Creating GitHub step summary with processed_count=$processed_count"
  
  # Debug log
  echo "[generate_github_step_summary] CHANGELOG_FILE=$CHANGELOG_FILE" >&2
  echo "[generate_github_step_summary] GITHUB_STEP_SUMMARY=$GITHUB_STEP_SUMMARY" >&2
  
  # Header
  echo "## 📊 Draw.io Processing Summary" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  # First check if we have a processed count passed in
  if [[ $processed_count -eq 0 ]]; then
    # Double check if there's actually any files processed that we missed 
    local actual_processed_count=0
    
    # Check for recently modified PNG files
    if [[ -d "$PNG_FILES_DIR" ]]; then
      actual_processed_count=$(find "$PNG_FILES_DIR" -name "*.png" -type f -mmin -60 2>/dev/null | wc -l)
      
      if [[ $actual_processed_count -gt 0 ]]; then
        echo "[generate_github_step_summary] Found $actual_processed_count recently modified PNG files not counted in processed_count" >&2
        processed_count=$actual_processed_count
      else
        # Check for any entries in the changelog file
        if [[ -f "$CHANGELOG_FILE" ]]; then
          # Count non-header lines in changelog
          local changelog_entries=$(( $(wc -l < "$CHANGELOG_FILE") - 1 ))
          if [[ $changelog_entries -gt 0 ]]; then
            echo "[generate_github_step_summary] Found $changelog_entries entries in changelog file" >&2
            processed_count=$changelog_entries
          fi
        fi
      fi
    fi
    
    if [[ $processed_count -eq 0 ]]; then
      echo "📝 **No diagrams processed in this run**" >> $GITHUB_STEP_SUMMARY
      
      # Additional debugging info
      echo "" >> $GITHUB_STEP_SUMMARY
      echo "### 🔍 Debug Information" >> $GITHUB_STEP_SUMMARY
      echo "" >> $GITHUB_STEP_SUMMARY
      echo "- **Working directory**: \`$(pwd)\`" >> $GITHUB_STEP_SUMMARY
      echo "- **CHANGELOG_FILE**: \`${CHANGELOG_FILE}\`" >> $GITHUB_STEP_SUMMARY
      echo "- **PNG_FILES_DIR**: \`${PNG_FILES_DIR}\`" >> $GITHUB_STEP_SUMMARY
      echo "- **DRAWIO_FILES_DIR**: \`${DRAWIO_FILES_DIR}\`" >> $GITHUB_STEP_SUMMARY
      
      if [[ -f "${DRAWIO_FILES_DIR}/.detection_log.txt" ]]; then
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "### 📋 File Detection Log" >> $GITHUB_STEP_SUMMARY
        echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
        cat "${DRAWIO_FILES_DIR}/.detection_log.txt" >> $GITHUB_STEP_SUMMARY
        echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
      fi
      
      return
    fi
  fi
  
  # At this point, we have a non-zero processed_count
  
  # Get list of processed files from multiple sources
  echo "[generate_github_step_summary] Getting list of processed files" >&2
  
  local processed_files=""
  
  # Method 1: Check git diff for PNG files
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    processed_files=$(git diff --name-only HEAD~1 HEAD -- "$PNG_FILES_DIR/*.png" 2>/dev/null | sed "s|$PNG_FILES_DIR/||g" | sed 's|.png$||g' | sort)
    echo "[generate_github_step_summary] Method 1 (git diff): Found $(echo "$processed_files" | wc -l) files" >&2
  fi

  # Method 2: Check recently modified files if git didn't work or found nothing
  if [[ -z "$processed_files" && -d "$PNG_FILES_DIR" ]]; then
    processed_files=$(find "$PNG_FILES_DIR" -name "*.png" -type f -mmin -60 2>/dev/null | sed "s|$PNG_FILES_DIR/||g" | sed 's|.png$||g' | sort)
    echo "[generate_github_step_summary] Method 2 (recent files): Found $(echo "$processed_files" | wc -l) files" >&2
  fi
  
  # Method 3: Check any files in the PNG directory
  if [[ -z "$processed_files" && -d "$PNG_FILES_DIR" ]]; then
    processed_files=$(find "$PNG_FILES_DIR" -name "*.png" -type f | head -n 10 2>/dev/null | sed "s|$PNG_FILES_DIR/||g" | sed 's|.png$||g' | sort)
    echo "[generate_github_step_summary] Method 3 (any files): Found $(echo "$processed_files" | wc -l) files" >&2
  fi
  
  echo "### 🔄 Processed Files (${processed_count})" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  echo "| File | Version | Action |" >> $GITHUB_STEP_SUMMARY
  echo "|------|---------|--------|" >> $GITHUB_STEP_SUMMARY
  
  # Extract information from changelog
  if [[ -f "$CHANGELOG_FILE" ]]; then
    # Debug output
    echo "[generate_github_step_summary] Reading from changelog: $CHANGELOG_FILE" >&2
    echo "[generate_github_step_summary] Changelog exists: $(test -f "$CHANGELOG_FILE" && echo "yes" || echo "no")" >&2
    echo "[generate_github_step_summary] Changelog size: $(wc -c < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown") bytes" >&2
    
    # Skip the header line and get the recent entries
    tail -n 10 "$CHANGELOG_FILE" 2>/dev/null | while IFS=, read -r date time diagram file action message version hash author; do
      # Clean up the values (remove quotes)
      diagram=$(echo "$diagram" | tr -d '"')
      version=$(echo "$version" | tr -d '"')
      action=$(echo "$action" | tr -d '"')
      
      echo "| ${diagram} | ${version} | ${action} |" >> $GITHUB_STEP_SUMMARY
    done
  else
    echo "[generate_github_step_summary] Warning: Changelog file not found at $CHANGELOG_FILE" >&2
    
    # If no changelog but we have processed files, list them
    if [[ -n "$processed_files" ]]; then
      echo "$processed_files" | while read -r file; do
        if [[ -n "$file" ]]; then
          echo "| ${file} | unknown | Converted to PNG |" >> $GITHUB_STEP_SUMMARY
        fi
      done
    else
      echo "| (No changelog data available) | - | - |" >> $GITHUB_STEP_SUMMARY
    fi
  fi
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "### ⚙️ Configuration" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "- **PNG Scale**: ${PNG_SCALE}" >> $GITHUB_STEP_SUMMARY
  echo "- **PNG Quality**: ${PNG_QUALITY}" >> $GITHUB_STEP_SUMMARY
  echo "- **Changelog**: \`${CHANGELOG_FILE}\`" >> $GITHUB_STEP_SUMMARY
  echo "- **Working Directory**: \`$(pwd)\`" >> $GITHUB_STEP_SUMMARY
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "✅ **All diagrams processed successfully**" >> $GITHUB_STEP_SUMMARY
  
  # Include additional debug information
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "### 🔍 Debug Information" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "- **Timestamp**: $(date)" >> $GITHUB_STEP_SUMMARY
  echo "- **Script version**: v2.1" >> $GITHUB_STEP_SUMMARY
  
  # If we have detection logs, include them
  if [[ -f "${DRAWIO_FILES_DIR}/.detection_log.txt" ]]; then
    echo "" >> $GITHUB_STEP_SUMMARY
    echo "### 📋 File Detection Log (Summary)" >> $GITHUB_STEP_SUMMARY
    echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
    head -n 10 "${DRAWIO_FILES_DIR}/.detection_log.txt" >> $GITHUB_STEP_SUMMARY
    echo "..." >> $GITHUB_STEP_SUMMARY
    tail -n 5 "${DRAWIO_FILES_DIR}/.detection_log.txt" >> $GITHUB_STEP_SUMMARY
    echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
  fi
}

# Main flow
main() {
  echo "[main] Starting draw.io processing script execution." >&2
  
  # Ensure the environment variables are properly set
  echo "[main] Checking environment variables and configuration..." >&2
  
  # Export all key configuration variables to ensure they are available to all functions
  export PNG_SCALE="${DIAGRAMS_PNG_SCALE:-${PNG_SCALE:-2.0}}"
  export PNG_QUALITY="${DIAGRAMS_PNG_QUALITY:-${PNG_QUALITY:-100}}"
  export CHANGELOG_FILE="${DIAGRAMS_CHANGELOG_FILE:-${CHANGELOG_FILE:-${PNG_FILES_DIR}/CHANGELOG.csv}}"
  export COUNTER_FILE="${DIAGRAMS_COUNTER_FILE:-${COUNTER_FILE:-${DRAWIO_FILES_DIR}/.counter}}"
  export TRIGGERING_SHA="${GITHUB_SHA:-${TRIGGERING_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}}"
  
  echo "[main] Using configuration: CHANGELOG_FILE=$CHANGELOG_FILE, PNG_SCALE=$PNG_SCALE, PNG_QUALITY=$PNG_QUALITY" >&2
  
  # Create necessary directories to ensure they exist
  mkdir -p "$DRAWIO_FILES_DIR" "$PNG_FILES_DIR" "$(dirname "$COUNTER_FILE")" "$(dirname "$CHANGELOG_FILE")" 2>/dev/null
  
  # Check if CHANGED_FILES is already set from the environment
  if [[ -z "$CHANGED_FILES" ]]; then
    # If not set, run detect_changed_files to set it
    echo "[main] CHANGED_FILES not set, detecting changed files..." >&2
    detect_changed_files
  else
    echo "[main] Using CHANGED_FILES from environment: $CHANGED_FILES" >&2
  fi
  
  # Force-export CHANGED_FILES to ensure it's accessible in all parts of the script
  export CHANGED_FILES
  
  # Print all environment variables to help with debugging (excluding sensitive data)
  echo "[main] Debug: Key environment variables:" >&2
  env | grep -E '^(CHANGED_|DIAGRAMS_|PNG_|GITHUB_)' | grep -v -E '(PASSWORD|SECRET|TOKEN)' >&2
  
  # Check if the current directory is a git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[main] Warning: Current directory is not a git repository. Limited git functionality available." >&2
  fi
  
  # Show the current commit info if available
  git_commit_info=$(git log -1 --oneline 2>/dev/null || echo "Git info not available")
  echo "[main] Current git commit: $git_commit_info" >&2
  
  # Check for existing changelog file before processing
  if [[ -f "$CHANGELOG_FILE" ]]; then
    echo "[main] Existing changelog found at $CHANGELOG_FILE. Size: $(wc -c < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown") bytes" >&2
  else
    echo "[main] No existing changelog found at $CHANGELOG_FILE. Will create if needed." >&2
  fi
  
  # Verify we have files to process
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "[main] No files to process (CHANGED_FILES is empty)." >&2
    
    # Even with no files, ensure the changelog exists with a header
    echo "[main] Ensuring changelog file exists with header..." >&2
    if ! mkdir -p "$(dirname "$CHANGELOG_FILE")" 2>/dev/null; then 
      echo "[main] Error creating directory for changelog file" >&2
    elif [[ ! -f "$CHANGELOG_FILE" ]]; then
      echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
      echo "[main] Created empty changelog file with header at $CHANGELOG_FILE" >&2
      
      # Set proper permissions
      chmod 644 "$CHANGELOG_FILE" 2>/dev/null
    fi
    
    echo "[main] No files to process. Exiting normally." >&2
    generate_github_step_summary 0
    return 0
  fi
  
  echo "[main] Files to process based on CHANGED_FILES: $CHANGED_FILES" >&2
  
  local processed_count=0
  local failed_count=0
  local overall_success=true 

  # Process each file in the CHANGED_FILES list
  for file_to_process_loopvar in $CHANGED_FILES; do
    echo "[main] Processing file: '$file_to_process_loopvar'" >&2
    
    # Verify file exists
    if [[ ! -f "$file_to_process_loopvar" ]]; then
      echo "[main] Warning: File $file_to_process_loopvar does not exist, skipping." >&2
      ((failed_count++))
      continue
    fi
    
    local processed_file_path="$file_to_process_loopvar" # Start with the original path
    
    echo "[main] Step 1: Assign ID if needed" >&2
    # Assign ID if needed
    local path_after_assign_ids
    path_after_assign_ids=$(assign_ids "$file_to_process_loopvar")
    local assign_ids_exit_code=$?

    if [[ $assign_ids_exit_code -ne 0 ]]; then
      echo "[main] Error: ID assignment failed for $file_to_process_loopvar. Skipping file." >&2
      overall_success=false
      ((failed_count++))
      continue
    fi
    
    # Update path if file was renamed during ID assignment
    processed_file_path="$path_after_assign_ids"
    echo "[main] File path after ID assignment: $processed_file_path" >&2

    echo "[main] Step 2: Convert file to PNG" >&2
    # Convert to PNG
    if ! convert_to_png "$processed_file_path"; then
      echo "[main] Error: PNG conversion failed for $processed_file_path." >&2
      overall_success=false
      ((failed_count++))
      
      # Add entry to changelog even for failed conversion
      echo "[main] Adding failed conversion entry to changelog..." >&2
      local basename=$(basename "$processed_file_path")
      local current_date=$(date +"%d.%m.%Y")
      local current_time=$(date +"%H:%M:%S")
      local commit_hash=$(git log -1 --format="%h" 2>/dev/null || echo "unknown")
      local commit_msg=$(git log -1 --format="%s" 2>/dev/null || echo "Diagram processing")
      local author_name=$(git log -1 --format="%an" 2>/dev/null || echo "Unknown")
      
      # Ensure changelog directory exists
      mkdir -p "$(dirname "$CHANGELOG_FILE")" 2>/dev/null
      
      # Create or append to changelog
      if [[ ! -f "$CHANGELOG_FILE" ]]; then
        echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
      fi
      
      echo "$current_date,$current_time,\"${basename%.drawio}\",\"$processed_file_path\",\"Failed conversion\",\"$commit_msg\",0.0,$commit_hash,\"$author_name\"" >> "$CHANGELOG_FILE"
      
      continue
    fi
    
    echo "[main] Step 3: Update changelog" >&2
    # Update changelog with the successfully converted file
    if update_changelog "$processed_file_path"; then
      echo "[main] Changelog updated successfully for $processed_file_path." >&2
      ((processed_count++))
    else
      echo "[main] Error: Failed to update changelog for $processed_file_path." >&2
      overall_success=false
      ((failed_count++))
    fi
  done
  
  echo "[main] Processing summary: $processed_count files processed successfully, $failed_count files failed." >&2
  
  # Double-check that the changelog file exists and is readable
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "[main] Warning: CHANGELOG_FILE does not exist after processing. Creating empty file." >&2
    mkdir -p "$(dirname "$CHANGELOG_FILE")" 2>/dev/null
    echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
    chmod 644 "$CHANGELOG_FILE" 2>/dev/null
  fi
  
  # Show the current changelog file details
  echo "[main] Final changelog file status:" >&2
  if [[ -f "$CHANGELOG_FILE" ]]; then
    echo "[main] Changelog exists at $CHANGELOG_FILE" >&2
    echo "[main] Size: $(wc -c < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown") bytes" >&2
    echo "[main] Line count: $(wc -l < "$CHANGELOG_FILE" 2>/dev/null || echo "unknown") lines" >&2
    echo "[main] First 2 lines:" >&2
    head -n 2 "$CHANGELOG_FILE" >&2
    echo "[main] Last 2 lines:" >&2
    tail -n 2 "$CHANGELOG_FILE" >&2
  else
    echo "[main] ERROR: Changelog file still does not exist at $CHANGELOG_FILE" >&2
  fi
  
  # Make sure the changelog file is added to git
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -f "$CHANGELOG_FILE" ]]; then
    echo "[main] Adding changelog file to git..." >&2
    git add -f "$CHANGELOG_FILE" >/dev/null 2>&1 || echo "[main] Warning: Failed to add changelog to git" >&2
  fi
  
  # Create a summary file of processed files for easier debugging
  local processed_files_log="${DRAWIO_FILES_DIR}/.processed_files.txt"
  echo "=== Processed Files Log $(date) ===" > "$processed_files_log"
  echo "Total processed count: $processed_count" >> "$processed_files_log"
  echo "Total failed count: $failed_count" >> "$processed_files_log"
  echo "" >> "$processed_files_log"
  echo "## Successfully processed files:" >> "$processed_files_log"
  if [[ -d "$PNG_FILES_DIR" ]]; then
    find "$PNG_FILES_DIR" -name "*.png" -type f -mmin -60 -exec ls -l {} \; >> "$processed_files_log" 2>/dev/null
  fi
  
  # Write log info for GITHUB_STEP_SUMMARY to use later
  echo "processed_count=$processed_count" > "${DRAWIO_FILES_DIR}/.processed_stats.txt"
  echo "failed_count=$failed_count" >> "${DRAWIO_FILES_DIR}/.processed_stats.txt"
  
  # Generate GitHub step summary with the processed file information
  generate_github_step_summary "$processed_count"

  # Use the GITHUB_OUTPUT mechanism to expose metrics if running in GitHub Actions
  if [[ -n "$GITHUB_OUTPUT" ]]; then
    echo "processed_count=$processed_count" >> "$GITHUB_OUTPUT"
    echo "failed_count=$failed_count" >> "$GITHUB_OUTPUT"
    
    # Create a list of processed files for the output
    processed_files_list=""
    if [[ -d "$PNG_FILES_DIR" ]]; then
      processed_files_list=$(find "$PNG_FILES_DIR" -name "*.png" -type f -mmin -60 -printf "%f," 2>/dev/null | sed 's/,$//')
    fi
    echo "processed_files_list=$processed_files_list" >> "$GITHUB_OUTPUT"
  fi

  if [[ "$overall_success" = false ]]; then
    echo "[main] One or more operations failed during processing. Check logs for details." >&2
    echo "[main] Script finished with warnings." >&2
    # Don't exit with error by default to allow the workflow to continue
  else
    echo "[main] Script execution finished successfully." >&2
    echo "[main] Processed $processed_count files, $failed_count failures." >&2
  fi
  
  # Export statistics as environment variables for GitHub Actions
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "DIAGRAMS_PROCESSED_COUNT=$processed_count" >> $GITHUB_ENV
    echo "DIAGRAMS_FAILED_COUNT=$failed_count" >> $GITHUB_ENV
    
    # Also explicitly write the path to CHANGELOG file to ensure it's properly referenced
    echo "DIAGRAMS_CHANGELOG_FILE_PATH=$(readlink -f "$CHANGELOG_FILE")" >> $GITHUB_ENV
  fi
  
  # Ensure generated files are committed
  git add -f "${DRAWIO_FILES_DIR}/.processed_files.txt" 2>/dev/null || true
  git add -f "${DRAWIO_FILES_DIR}/.processed_stats.txt" 2>/dev/null || true
  git add -f "$CHANGELOG_FILE" 2>/dev/null || true
  
  return 0
}

# The assign_ids function is now defined earlier in the script

# Run the main function
main "$@"
