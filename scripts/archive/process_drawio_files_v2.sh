#!/bin/bash
# Simplified Draw.io Files Processing Script V2
# Based on workflow_v2_specification.md

set -euo pipefail

# Configuration
readonly DRAWIO_FILES_DIR="drawio_files"
readonly PNG_FILES_DIR="png_files"
readonly COUNTER_FILE="${DIAGRAMS_COUNTER_FILE:-${DRAWIO_FILES_DIR}/.counter}"
readonly CHANGELOG_FILE="${DIAGRAMS_CHANGELOG_FILE:-${PNG_FILES_DIR}/CHANGELOG.csv}"
readonly VERSION_FILE="${PNG_FILES_DIR}/.versions"
readonly PNG_SCALE="${DIAGRAMS_PNG_SCALE:-2.0}"
readonly PNG_QUALITY="${DIAGRAMS_PNG_QUALITY:-100}"

# Global variables
CHANGED_FILES=""
PROCESSED_FILES=()
FAILED_FILES=()

# Function to detect changed files
detect_changed_files() {
  echo "🔍 Detecting changed Draw.io files..."
  
  # Use environment variable if set (from GitHub Actions)
  if [[ -n "${CHANGED_FILES:-}" ]]; then
    echo "Using pre-detected files from environment"
    return 0
  fi
  
  # Use specific file if provided
  if [[ -n "${SPECIFIC_FILE:-}" ]]; then
    echo "Processing specific file: $SPECIFIC_FILE"
    CHANGED_FILES="$SPECIFIC_FILE"
    return 0
  fi
  
  # Detect files using Git (simplified approach)
  if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    # Normal commit - compare with previous commit
    CHANGED_FILES=$(git diff --name-only --diff-filter=AM HEAD^ HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" || true)
  else
    # Initial commit - get all files
    CHANGED_FILES=$(git diff-tree --no-commit-id --name-only --root -r HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" || true)
  fi
  
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "⚠️ No changed Draw.io files detected"
    return 0
  fi
  
  echo "📁 Found changed files:"
  echo "$CHANGED_FILES" | while IFS= read -r file; do
    [[ -n "$file" ]] && echo "  - $file"
  done
}

# Function to extract ID from filename
extract_id() {
  local file="$1"
  local basename=$(basename "$file")
  
  # Match (###) pattern
  if [[ "$basename" =~ \(([0-9]{3})\)\.drawio$ ]]; then
    echo "${BASH_REMATCH[1]}"
  # Match numeric filename
  elif [[ "$basename" =~ ^([0-9]+)\.drawio$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Function to assign ID to new files
assign_id() {
  local file="$1"
  local basename=$(basename "$file")
  
  # Skip if file already has ID or is numeric
  if [[ "$basename" =~ \([0-9]{3}\)\.drawio$ ]] || [[ "$basename" =~ ^[0-9]+\.drawio$ ]]; then
    echo "📝 File $basename already has ID, skipping assignment" >&2
    echo "$file"  # Return original file path
    return 0
  fi
  
  # Read and increment counter
  local counter
  if [[ -f "$COUNTER_FILE" ]]; then
    counter=$(<"$COUNTER_FILE")
  else
    counter="000"
  fi
  
  local new_counter=$(printf "%03d" $((10#$counter + 1)))
  local filename_without_ext="${basename%.drawio}"
  local new_filename="${filename_without_ext} (${new_counter}).drawio"
  local new_filepath="${DRAWIO_FILES_DIR}/${new_filename}"
  
  # Rename file
  echo "🏷️ Assigning ID $new_counter to $basename" >&2
  mv "$file" "$new_filepath"
  
  # Update counter
  echo "$new_counter" > "$COUNTER_FILE"
  
  # Return new file path
  echo "$new_filepath"
}

# Function to convert Draw.io file to PNG
convert_to_png() {
  local input_file="$1"
  local basename=$(basename "$input_file" .drawio)
  local output_png="${PNG_FILES_DIR}/${basename}.png"
  
  echo "🎨 Converting $basename to PNG..."
  
  # Ensure input file exists
  if [[ ! -f "$input_file" ]]; then
    echo "❌ Input file not found: $input_file"
    return 1
  fi
  
  # Remove any existing output file
  rm -f "$output_png"
  
  # Convert using Draw.io with xvfb
  if xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" \
     drawio -x -f png --scale "$PNG_SCALE" -o "$output_png" "$input_file" 2>/dev/null; then
    
    # Verify the output file
    if [[ -f "$output_png" && -s "$output_png" ]]; then
      local file_size=$(stat -f%z "$output_png" 2>/dev/null || stat -c%s "$output_png" 2>/dev/null)
      if [[ $file_size -gt 1000 ]]; then  # At least 1KB
        echo "✅ Successfully created $basename.png (${file_size} bytes)"
        return 0
      else
        echo "⚠️ Output file too small, removing: $basename.png"
        rm -f "$output_png"
      fi
    fi
  fi
  
  # Conversion failed - create placeholder with ImageMagick
  echo "❌ Draw.io conversion failed, creating placeholder"
  if command -v convert >/dev/null 2>&1; then
    convert -size 800x600 xc:white \
      -fill red -gravity Center -pointsize 24 \
      -annotate 0 "Conversion Failed\n\n$(basename "$input_file")\n\nPlease check the diagram file" \
      "$output_png" 2>/dev/null || {
        echo "❌ ImageMagick placeholder creation failed"
        return 1
      }
    echo "🔄 Created error placeholder for $basename.png"
    return 1
  else
    echo "❌ ImageMagick not available for placeholder creation"
    return 1
  fi
}

# Function to determine version for a file
determine_version() {
  local file="$1"
  local id=$(extract_id "$file")
  
  if [[ -z "$id" ]]; then
    echo "1.0"
    return
  fi
  
  # Get current version from version file
  local current_version="0.0"
  if [[ -f "$VERSION_FILE" ]] && grep -q "^$id:" "$VERSION_FILE"; then
    current_version=$(grep "^$id:" "$VERSION_FILE" | cut -d: -f2 | tail -1)
  fi
  
  # Parse current version
  local major minor
  IFS='.' read -r major minor <<< "$current_version"
  major=${major:-0}
  minor=${minor:-0}
  
  # Get commit message to determine version increment
  local commit_msg
  commit_msg=$(git log -1 --format="%s" -- "$file" 2>/dev/null || echo "")
  
  # Determine version increment
  if echo "$commit_msg" | grep -Eiq '(added|new)'; then
    # Major version increment for new files
    major=$((major + 1))
    minor=0
  else
    # Minor version increment for updates
    minor=$((minor + 1))
  fi
  
  local new_version="${major}.${minor}"
  
  # Update version file
  if [[ -f "$VERSION_FILE" ]]; then
    # Remove existing entry and add new one
    grep -v "^$id:" "$VERSION_FILE" > "${VERSION_FILE}.tmp" || true
    echo "$id:$new_version" >> "${VERSION_FILE}.tmp"
    mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
  else
    echo "$id:$new_version" > "$VERSION_FILE"
  fi
  
  echo "$new_version"
}

# Function to update changelog
update_changelog() {
  local file="$1"
  local success="$2"
  
  local basename=$(basename "$file")
  local diagram_name="${basename%.drawio}"
  
  # Get commit information
  local commit_hash=$(git log -1 --format="%h" -- "$file" 2>/dev/null || echo "")
  local commit_msg=$(git log -1 --format="%s" -- "$file" 2>/dev/null || echo "")
  local author_name=$(git log -1 --format="%an" -- "$file" 2>/dev/null || echo "")
  
  # Get current date and time
  local current_date=$(date +"%d.%m.%Y")
  local current_time=$(date +"%H:%M:%S")
  
  # Determine version and action
  local version=$(determine_version "$file")
  local action
  if [[ "$success" == "true" ]]; then
    action="Converted to PNG"
  else
    action="Conversion failed - placeholder created"
  fi
  
  # Create changelog entry
  local entry="${current_date},${current_time},\"${diagram_name}\",\"${file}\",\"${action}\",\"${commit_msg}\",\"${version}\",\"${commit_hash}\",\"${author_name}\""
  
  # Ensure changelog file exists with header
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
  fi
  
  # Add entry
  echo "$entry" >> "$CHANGELOG_FILE"
  echo "📊 Added changelog entry for $diagram_name (v$version)"
}

# Function to create output directories
setup_directories() {
  echo "📁 Setting up directories..."
  mkdir -p "$PNG_FILES_DIR" "$DRAWIO_FILES_DIR"
  
  # Initialize counter file if it doesn't exist
  if [[ ! -f "$COUNTER_FILE" ]]; then
    echo "001" > "$COUNTER_FILE"
    echo "📝 Initialized counter file"
  fi
}

# Function to generate summary
generate_summary() {
  local processed_count=${#PROCESSED_FILES[@]}
  local failed_count=${#FAILED_FILES[@]}
  
  echo ""
  echo "📊 Processing Summary:"
  echo "  ✅ Successfully processed: $processed_count files"
  echo "  ❌ Failed conversions: $failed_count files"
  
  if [[ $processed_count -gt 0 ]]; then
    echo "  📄 Processed files:"
    for file in "${PROCESSED_FILES[@]}"; do
      echo "    - $(basename "$file")"
    done
  fi
  
  if [[ $failed_count -gt 0 ]]; then
    echo "  ⚠️ Failed files:"
    for file in "${FAILED_FILES[@]}"; do
      echo "    - $(basename "$file")"
    done
  fi
  
  # Generate GitHub Actions summary if running in CI
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## 📊 Draw.io Processing Summary"
      echo ""
      echo "- **Successfully processed**: $processed_count files"
      echo "- **Failed conversions**: $failed_count files"
      echo ""
      
      if [[ $processed_count -gt 0 ]]; then
        echo "### ✅ Processed Files"
        for file in "${PROCESSED_FILES[@]}"; do
          echo "- $(basename "$file")"
        done
        echo ""
      fi
      
      if [[ $failed_count -gt 0 ]]; then
        echo "### ❌ Failed Files"
        for file in "${FAILED_FILES[@]}"; do
          echo "- $(basename "$file")"
        done
        echo ""
      fi
      
      echo "### ⚙️ Configuration"
      echo "- **PNG Scale**: $PNG_SCALE"
      echo "- **PNG Quality**: $PNG_QUALITY"
      echo "- **Changelog**: $CHANGELOG_FILE"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# Main processing function
main() {
  echo "🚀 Starting Draw.io Files Processing V2"
  echo "========================================="
  
  setup_directories
  detect_changed_files
  
  if [[ -z "$CHANGED_FILES" ]]; then
    echo "✨ No files to process"
    return 0
  fi
  
  # Process each changed file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    
    echo ""
    echo "📝 Processing: $file"
    
    # Verify file exists
    if [[ ! -f "$file" ]]; then
      echo "⚠️ File not found, skipping: $file"
      continue
    fi
    
    # Assign ID if needed (this may change the file path)
    file=$(assign_id "$file")
    
    # Convert to PNG
    local conversion_success=false
    if convert_to_png "$file"; then
      conversion_success=true
      PROCESSED_FILES+=("$file")
    else
      FAILED_FILES+=("$file")
    fi
    
    # Update changelog regardless of conversion success
    update_changelog "$file" "$conversion_success"
    
  done <<< "$CHANGED_FILES"
  
  generate_summary
  
  echo ""
  echo "✨ Processing complete!"
}

# Run main function
main "$@"
