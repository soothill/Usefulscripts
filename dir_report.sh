#!/bin/bash

################################################################################
# Directory Capacity Report Script
#
# Copyright (c) 2025 Darren Soothill. All rights reserved.
#
# Description:
#   This script crawls the filesystem starting from the current working
#   directory and generates a comprehensive report of disk space usage.
#   It analyzes each immediate subdirectory and displays the capacity
#   consumed by each one in a sorted, human-readable format.
#
# Usage:
#   ./dir_report.sh [directory]
#
# Parameters:
#   directory - Optional path to directory to analyze (default: current directory)
#
# Output:
#   - Lists all directories under the current directory
#   - Shows disk usage for each directory in human-readable format
#   - Sorts directories by size (largest first)
#   - Displays total disk usage summary
#
################################################################################

# Parse command line arguments
TARGET_DIR="${1:-.}"

# Validate the target directory
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: '$TARGET_DIR' is not a valid directory"
    echo "Usage: $0 [directory]"
    exit 1
fi

# Convert to absolute path for clearer output
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

echo "========================================"
echo "Directory Capacity Report"
echo "Target Directory: $TARGET_DIR"
echo "========================================"
echo ""

# Check if du command is available
if ! command -v du &> /dev/null; then
    echo "Error: 'du' command not found"
    exit 1
fi

# Function to format bytes to human-readable format
format_size() {
    local size=$1
    if [ $size -lt 1024 ]; then
        echo "${size}B"
    elif [ $size -lt 1048576 ]; then
        echo "$(( size / 1024 ))KB"
    elif [ $size -lt 1073741824 ]; then
        echo "$(( size / 1048576 ))MB"
    else
        echo "$(( size / 1073741824 ))GB"
    fi
}

# Get disk usage for each directory (one level deep)
# -s: summarize (don't show subdirectories)
# -B1: block size of 1 byte for precise calculations
echo "Analyzing directories..."
echo ""

# Store results in an array for sorting
declare -a results

# Get all directories in target directory
for dir in "$TARGET_DIR"/*/; do
    # Remove trailing slash and get just the directory name
    dir_path="${dir%/}"
    
    # Skip if not a directory
    [ ! -d "$dir_path" ] && continue
    
    # Get size in bytes
    size=$(du -sb "$dir_path" 2>/dev/null | cut -f1)
    
    if [ -n "$size" ]; then
        # Store basename for display
        dir_name=$(basename "$dir_path")
        results+=("$size|$dir_name|$dir_path")
    fi
done

# Sort by size (largest first) and display
printf "%-15s %s\n" "SIZE" "DIRECTORY"
printf "%-15s %s\n" "---------------" "--------------------------------"

if [ ${#results[@]} -eq 0 ]; then
    echo "No directories found or permission denied"
else
    # Sort numerically in reverse order (largest first)
    IFS=$'\n' sorted=($(sort -t'|' -k1 -rn <<<"${results[*]}"))
    unset IFS
    
    total_size=0
    
    for entry in "${sorted[@]}"; do
        size=$(echo "$entry" | cut -d'|' -f1)
        dir_name=$(echo "$entry" | cut -d'|' -f2)
        dir_path=$(echo "$entry" | cut -d'|' -f3)
        
        # Convert size to human-readable format
        human_size=$(du -sh "$dir_path" 2>/dev/null | cut -f1)
        
        printf "%-15s %s\n" "$human_size" "$dir_name"
        
        total_size=$((total_size + size))
    done
    
    echo ""
    echo "========================================"
    total_human=$(du -sh "$TARGET_DIR" 2>/dev/null | cut -f1)
    echo "Total (target directory): $total_human"
    echo "========================================"
fi
