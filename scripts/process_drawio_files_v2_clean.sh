#!/bin/bash
# Clean Draw.io Files Processing Script V2
# Simplified and robust implementation based on workflow_v2_specification.md

set -euo pipefail

# Configuration
readonly DRAWIO_FILES_DIR="drawio_files"
readonly PNG_FILES_DIR="png_files"
readonly COUNTER_FILE="${DIAGRAMS_COUNTER_FILE:-${DRAWIO_FILES_DIR}/.counter}"
readonly CHANGELOG_FILE="${DIAGRAMS_CHANGELOG_FILE:-${PNG_FILES_DIR}/CHANGELOG.csv}"
readonly VERSION_FILE="${PNG_FILES_DIR}/.versions"
readonly PNG_SCALE="${DIAGRAMS_PNG_SCALE:-2.0}"
readonly PNG_QUALITY="${DIAGRAMS_PNG_QUALITY:-100}"

# Statistics
declare -i PROCESSED_COUNT=0
declare -i FAILED_COUNT=0
declare -a PROCESSED_FILES=()
declare -a FAILED_FILES=()

# ===========================
# UTILITY FUNCTIONS
# ===========================

log() {
    echo "$(date '+%H:%M:%S') $*" >&2
}

log_info() {
    log "ℹ️  $*"
}

log_success() {
    log "✅ $*"
}

log_warning() {
    log "⚠️  $*"
}

log_error() {
    log "❌ $*"
}

# ===========================
# SETUP FUNCTIONS
# ===========================

setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p "$PNG_FILES_DIR" "$DRAWIO_FILES_DIR"
    
    # Initialize counter if it doesn't exist
    if [[ ! -f "$COUNTER_FILE" ]]; then
        echo "000" > "$COUNTER_FILE"
        log_info "Initialized counter file"
    fi
    
    # Initialize version file if it doesn't exist
    if [[ ! -f "$VERSION_FILE" ]]; then
        touch "$VERSION_FILE"
        log_info "Initialized version file"
    fi
    
    # Initialize changelog if it doesn't exist
    if [[ ! -f "$CHANGELOG_FILE" ]]; then
        echo "Date,Time,Diagram,File,Action,Commit Message,Version,Commit Hash,Author Name" > "$CHANGELOG_FILE"
        log_info "Initialized changelog file"
    fi
}

# ===========================
# FILE DETECTION
# ===========================

detect_changed_files() {
    log_info "Detecting changed Draw.io files..."
    
    local changed_files=""
    
    # Use specific file if provided
    if [[ -n "${SPECIFIC_FILE:-}" ]]; then
        if [[ -f "$SPECIFIC_FILE" ]]; then
            changed_files="$SPECIFIC_FILE"
            log_info "Processing specific file: $SPECIFIC_FILE"
        else
            log_error "Specific file not found: $SPECIFIC_FILE"
            exit 1
        fi
    # Use environment variable if set (from GitHub Actions)
    elif [[ -n "${CHANGED_FILES:-}" ]]; then
        changed_files="$CHANGED_FILES"
        log_info "Using pre-detected files from environment"
    else
        # Detect files using Git
        if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
            # Normal commit - compare with previous commit
            changed_files=$(git diff --name-only --diff-filter=AM HEAD^ HEAD -- "${DRAWIO_FILES_DIR}/*.drawio" 2>/dev/null || true)
        else
            # Initial commit or no previous commit - get all files
            changed_files=$(find "$DRAWIO_FILES_DIR" -name "*.drawio" -type f 2>/dev/null || true)
        fi
    fi
    
    if [[ -z "$changed_files" ]]; then
        log_info "No Draw.io files to process"
        exit 0
    fi
    
    echo "$changed_files"
}

# ===========================
# ID ASSIGNMENT
# ===========================

extract_id() {
    local file="$1"
    local basename=$(basename "$file" .drawio)
    
    # Check for ID in parentheses format: "filename (123)"
    if [[ "$basename" =~ ^(.+)\ \(([0-9]{3})\)$ ]]; then
        echo "${BASH_REMATCH[2]}"
        return 0
    fi
    
    # Check for pure numeric format: "123"
    if [[ "$basename" =~ ^([0-9]+)$ ]]; then
        printf "%03d" "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # No ID found
    echo ""
}

assign_id() {
    local file="$1"
    local basename=$(basename "$file" .drawio)
    local existing_id=$(extract_id "$file")
    
    # File already has an ID
    if [[ -n "$existing_id" ]]; then
        log_info "File $basename already has ID $existing_id"
        echo "$file"
        return 0
    fi
    
    # Read and increment counter
    local counter=$(<"$COUNTER_FILE")
    local new_counter=$(printf "%03d" $((10#$counter + 1)))
    
    # Create new filename
    local new_filename="${basename} (${new_counter}).drawio"
    local new_filepath="${DRAWIO_FILES_DIR}/${new_filename}"
    
    # Rename file
    log_info "Assigning ID $new_counter to $basename"
    mv "$file" "$new_filepath"
    
    # Update counter
    echo "$new_counter" > "$COUNTER_FILE"
    
    echo "$new_filepath"
}

# ===========================
# PNG CONVERSION
# ===========================

convert_to_png() {
    local input_file="$1"
    local basename=$(basename "$input_file" .drawio)
    local output_png="${PNG_FILES_DIR}/${basename}.png"
    
    log_info "Converting $basename to PNG..."
    
    # Ensure input file exists and is readable
    if [[ ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file"
        return 1
    fi
    
    if [[ ! -r "$input_file" ]]; then
        log_error "Input file not readable: $input_file"
        return 1
    fi
    
    # Remove any existing output file
    rm -f "$output_png"
    
    # Convert using Draw.io with xvfb
    if xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" \
       drawio -x -f png --scale "$PNG_SCALE" -o "$output_png" "$input_file" >/dev/null 2>&1; then
        
        # Verify the output file
        if [[ -f "$output_png" && -s "$output_png" ]]; then
            local file_size=$(stat -f%z "$output_png" 2>/dev/null || stat -c%s "$output_png" 2>/dev/null || echo "0")
            
            if [[ $file_size -gt 1000 ]]; then  # At least 1KB
                log_success "Successfully created $basename.png (${file_size} bytes)"
                return 0
            else
                log_warning "Output file too small, removing: $basename.png"
                rm -f "$output_png"
            fi
        fi
    fi
    
    # Conversion failed - create placeholder with ImageMagick
    log_warning "Draw.io conversion failed, creating placeholder for $basename"
    if command -v convert >/dev/null 2>&1; then
        convert -size 800x600 xc:white \
          -fill red -gravity Center -pointsize 24 \
          -annotate 0 "Conversion Failed\n\n$(basename "$input_file")\n\nPlease check the diagram file" \
          "$output_png" 2>/dev/null && {
            log_info "Created error placeholder for $basename.png"
            return 1
        }
    fi
    
    # If all else fails, create a simple text file as placeholder
    echo "Conversion failed for $(basename "$input_file") at $(date)" > "${output_png}.error"
    log_error "Could not create PNG or placeholder for $basename"
    return 1
}

# ===========================
# VERSIONING
# ===========================

determine_version() {
    local file="$1"
    local id=$(extract_id "$file")
    
    if [[ -z "$id" ]]; then
        log_warning "No ID found for file $file, using default version 1.0"
        echo "1.0"
        return 0
    fi
    
    # Get current version from version file
    local current_version
    if [[ -f "$VERSION_FILE" ]] && grep -q "^$id:" "$VERSION_FILE"; then
        current_version=$(grep "^$id:" "$VERSION_FILE" | cut -d: -f2)
    else
        current_version="0.0"
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
        grep -v "^$id:" "$VERSION_FILE" > "${VERSION_FILE}.tmp" 2>/dev/null || true
        echo "$id:$new_version" >> "${VERSION_FILE}.tmp"
        mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
    else
        echo "$id:$new_version" > "$VERSION_FILE"
    fi
    
    echo "$new_version"
}

# ===========================
# CHANGELOG MANAGEMENT
# ===========================

update_changelog() {
    local file="$1"
    local success="$2"
    
    local basename=$(basename "$file")
    local diagram_name="${basename%.drawio}"
    
    # Get commit information
    local commit_hash commit_msg author_name
    commit_hash=$(git log -1 --format="%h" -- "$file" 2>/dev/null || echo "")
    commit_msg=$(git log -1 --format="%s" -- "$file" 2>/dev/null || echo "")
    author_name=$(git log -1 --format="%an" -- "$file" 2>/dev/null || echo "")
    
    # Get current date and time
    local current_date current_time
    current_date=$(date +"%d.%m.%Y")
    current_time=$(date +"%H:%M:%S")
    
    # Determine version and action
    local version action
    version=$(determine_version "$file")
    if [[ "$success" == "true" ]]; then
        action="Converted to PNG"
    else
        action="Conversion failed - placeholder created"
    fi
    
    # Create changelog entry
    local entry="${current_date},${current_time},\"${diagram_name}\",\"${file}\",\"${action}\",\"${commit_msg}\",\"${version}\",\"${commit_hash}\",\"${author_name}\""
    
    # Add entry to changelog
    echo "$entry" >> "$CHANGELOG_FILE"
    log_info "Added changelog entry for $diagram_name (v$version)"
}

# ===========================
# MAIN PROCESSING
# ===========================

process_files() {
    local changed_files="$1"
    
    log_info "Starting file processing..."
    
    # Process each file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        log_info "Processing: $file"
        
        # Verify file exists
        if [[ ! -f "$file" ]]; then
            log_warning "File not found, skipping: $file"
            continue
        fi
        
        # Assign ID if needed (this may change the file path)
        file=$(assign_id "$file")
        
        # Convert to PNG
        local conversion_success=false
        if convert_to_png "$file"; then
            conversion_success=true
            PROCESSED_FILES+=("$file")
            ((PROCESSED_COUNT++))
        else
            FAILED_FILES+=("$file")
            ((FAILED_COUNT++))
        fi
        
        # Update changelog regardless of conversion success
        update_changelog "$file" "$conversion_success"
        
    done <<< "$changed_files"
}

# ===========================
# CLEANUP & SUMMARY
# ===========================

cleanup_duplicates() {
    log_info "Cleaning up duplicate files..."
    
    # Remove duplicate drawio files (keep the one with highest ID)
    local -A file_groups
    
    while IFS= read -r -d '' file; do
        local basename=$(basename "$file" .drawio)
        local base_name_clean
        
        # Extract base name without ID
        if [[ "$basename" =~ ^(.+)\ \([0-9]{3}\)$ ]]; then
            base_name_clean="${BASH_REMATCH[1]}"
        elif [[ "$basename" =~ ^[0-9]+$ ]]; then
            continue  # Keep pure numeric files
        else
            base_name_clean="$basename"
        fi
        
        # Group files by clean base name
        if [[ -n "${file_groups[$base_name_clean]:-}" ]]; then
            file_groups[$base_name_clean]+=$'\n'"$file"
        else
            file_groups[$base_name_clean]="$file"
        fi
    done < <(find "$DRAWIO_FILES_DIR" -name "*.drawio" -print0)
    
    # For each group with multiple files, keep only the one with the highest ID
    for base_name in "${!file_groups[@]}"; do
        local files="${file_groups[$base_name]}"
        local file_count=$(echo "$files" | wc -l)
        
        if [[ $file_count -gt 1 ]]; then
            log_info "Found $file_count duplicates for '$base_name', keeping highest ID..."
            
            # Sort files by ID (descending) and keep the first one
            local files_sorted
            files_sorted=$(echo "$files" | sort -t'(' -k2 -nr)
            local keep_file=$(echo "$files_sorted" | head -n1)
            
            # Remove the others
            while IFS= read -r file_to_remove; do
                if [[ "$file_to_remove" != "$keep_file" ]]; then
                    log_info "Removing duplicate: $(basename "$file_to_remove")"
                    rm -f "$file_to_remove"
                    
                    # Also remove corresponding PNG if it exists
                    local png_to_remove="${PNG_FILES_DIR}/$(basename "$file_to_remove" .drawio).png"
                    if [[ -f "$png_to_remove" ]]; then
                        rm -f "$png_to_remove"
                        log_info "Removed corresponding PNG: $(basename "$png_to_remove")"
                    fi
                fi
            done <<< "$files_sorted"
        fi
    done
}

generate_missing_pngs() {
    log_info "Checking for missing PNG files..."
    
    while IFS= read -r -d '' drawio_file; do
        local basename=$(basename "$drawio_file" .drawio)
        local png_file="${PNG_FILES_DIR}/${basename}.png"
        
        if [[ ! -f "$png_file" ]]; then
            log_info "Missing PNG for $basename, generating..."
            
            if convert_to_png "$drawio_file"; then
                log_success "Generated missing PNG: $basename.png"
                update_changelog "$drawio_file" "true"
            else
                log_warning "Failed to generate PNG for $basename"
                update_changelog "$drawio_file" "false"
            fi
        fi
    done < <(find "$DRAWIO_FILES_DIR" -name "*.drawio" -print0)
}

print_summary() {
    echo ""
    echo "================================================================"
    echo "                    PROCESSING SUMMARY"
    echo "================================================================"
    echo "📊 Files processed: $PROCESSED_COUNT"
    echo "❌ Files failed: $FAILED_COUNT"
    echo "📁 PNG files directory: $PNG_FILES_DIR"
    echo "📋 Changelog: $CHANGELOG_FILE"
    
    if [[ ${#PROCESSED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "✅ Successfully processed:"
        for file in "${PROCESSED_FILES[@]}"; do
            echo "   - $(basename "$file")"
        done
    fi
    
    if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "❌ Failed to process:"
        for file in "${FAILED_FILES[@]}"; do
            echo "   - $(basename "$file")"
        done
    fi
    
    echo "================================================================"
}

# ===========================
# MAIN FUNCTION
# ===========================

main() {
    log_info "Starting Draw.io Files Processing V2 (Clean)"
    
    # Setup
    setup_directories
    
    # Cleanup existing issues
    cleanup_duplicates
    
    # Generate missing PNGs
    generate_missing_pngs
    
    # Detect and process changed files
    local changed_files
    changed_files=$(detect_changed_files)
    
    if [[ -n "$changed_files" ]]; then
        process_files "$changed_files"
    fi
    
    # Summary
    print_summary
    
    log_success "Processing completed"
}

# Run main function
main "$@"
