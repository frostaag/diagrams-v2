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
  
  if [[ -n "$SPECIFIC_FILE" ]]; then
    echo "Processing specific file: $SPECIFIC_FILE"
    changed_files="$SPECIFIC_FILE"
  else
    # Check if this is the first commit
    if git rev-parse HEAD^1 >/dev/null 2>&1; then
      # Normal commit, get changed draw.io files
      changed_files=$(git diff --name-only --diff-filter=AM HEAD^ HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" | tr '\n' ' ')
    else
      # Initial commit
      changed_files=$(git diff-tree --no-commit-id --name-only --root -r HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" | tr '\n' ' ')
    fi
    
    if [[ -z "$changed_files" ]]; then
      echo "No draw.io files changed in this commit."
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
  
  # Run drawio conversion with xvfb-run
  xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" \
    drawio -x -f png --scale "$PNG_SCALE" --quality "$PNG_QUALITY" -o "$output_png" "$input_file"
  
  if [[ -f "$output_png" ]]; then
    echo "Successfully created $output_png"
    return 0
  else
    echo "Error: Failed to create PNG for $input_file"
    return 1
  fi
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
  
  # Add to changelog
  echo "$entry" >> "$CHANGELOG_FILE"
  
  echo "Added entry to changelog for $basename (version $version)"
}

# Main flow
main() {
  detect_changed_files
  
  for file in $CHANGED_FILES; do
    if [[ ! -f "$file" ]]; then
      echo "Warning: File $file does not exist, skipping."
      continue
    fi
    
    local processed_file="$file"
    
    # Assign ID if needed
    assign_ids "$file"
    if [[ -n "$PROCESSED_FILE" ]]; then
      processed_file="$PROCESSED_FILE"
    fi
    
    # Convert to PNG
    if ! convert_to_png "$processed_file"; then
      echo "Error: Failed to convert $processed_file to PNG, continuing with next file."
      continue
    fi
    
    # Update changelog
    update_changelog "$processed_file"
  done
}

# Run main function
main
