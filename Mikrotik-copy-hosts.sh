#!/bin/bash

################################################################################
# MikroTik Static DNS Host Entry Copy Script
################################################################################
#
# Description:
#   This script copies all static DNS host entries from one MikroTik RouterOS
#   device to another. It connects to the source router via SSH, exports all
#   static DNS entries configured under /ip dns static, and then imports them
#   to the destination router. The script supports both SSH key-based and
#   password-based authentication.
#
#   Features:
#   - Export static DNS host entries from source MikroTik router
#   - Import entries to destination MikroTik router
#   - Support for SSH key authentication or password authentication
#   - Connection validation before operations
#   - Preview entries before copying with confirmation prompt
#   - Detailed success/failure reporting
#   - Handles duplicate entries gracefully
#
# Usage:
#   ./mikrotik_copy_hosts.sh -s <source_ip> -d <dest_ip> -u <username> [-p <password>] [-k]
#
#   Debug Mode:
#   DEBUG=1 ./mikrotik_copy_hosts.sh -s <source_ip> -d <dest_ip> -u <username> -k
#
# Requirements:
#   - SSH access to both MikroTik routers
#   - sshpass (only required for password authentication)
#
# Author:
#   Darren Soothill
#
# Contact:
#   darren [at] soothill [dot] com
#
# Copyright:
#   Copyright (c) 2025 Darren Soothill. All rights reserved.
#
# License:
#   This script is provided as-is without any warranty. Use at your own risk.
#
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -s <source_ip> -d <dest_ip> -u <username> [-p <password>] [-k]

Options:
    -s <source_ip>    Source MikroTik router IP address
    -d <dest_ip>      Destination MikroTik router IP address
    -u <username>     Username for SSH authentication (used for both routers)
    -p <password>     Password for SSH authentication (optional)
    -k                Use SSH key authentication (no password required)
    -h                Display this help message

Environment Variables:
    DEBUG=1           Enable debug mode to show verbose output and command execution
                      Example: DEBUG=1 $0 -s 192.168.1.1 -d 192.168.1.2 -u admin -k

Examples:
    # Using SSH key authentication
    $0 -s 192.168.1.1 -d 192.168.1.2 -u admin -k
    
    # Using password (will prompt)
    $0 -s 192.168.1.1 -d 192.168.1.2 -u admin
    
    # Using password (provided)
    $0 -s 192.168.1.1 -d 192.168.1.2 -u admin -p mypassword
    
    # Debug mode with SSH keys
    DEBUG=1 $0 -s 192.168.1.1 -d 192.168.1.2 -u admin -k

Note: sshpass is only required when using password authentication
EOF
    exit 1
}

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if sshpass is installed (only needed for password auth)
check_sshpass() {
    if [[ "$USE_SSH_KEY" != "true" ]]; then
        if ! command -v sshpass &> /dev/null; then
            print_error "sshpass is not installed. Please install it first:"
            echo "  Ubuntu/Debian: sudo apt-get install sshpass"
            echo "  RHEL/CentOS: sudo yum install sshpass"
            echo "  macOS: brew install hudochenkov/sshpass/sshpass"
            echo ""
            echo "Alternatively, use SSH key authentication with the -k flag"
            exit 1
        fi
    fi
}

# Parse command line arguments
SOURCE_IP=""
DEST_IP=""
USERNAME=""
PASSWORD=""
USE_SSH_KEY="false"

while getopts "s:d:u:p:kh" opt; do
    case $opt in
        s) SOURCE_IP="$OPTARG" ;;
        d) DEST_IP="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        k) USE_SSH_KEY="true" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [[ -z "$SOURCE_IP" ]] || [[ -z "$DEST_IP" ]] || [[ -z "$USERNAME" ]]; then
    print_error "Missing required parameters"
    usage
fi

# Prompt for password if not provided and not using SSH key
if [[ -z "$PASSWORD" ]] && [[ "$USE_SSH_KEY" != "true" ]]; then
    read -sp "Enter password for user '$USERNAME': " PASSWORD
    echo
fi

# Check if sshpass is available when using password
if [[ "$USE_SSH_KEY" != "true" ]]; then
    check_sshpass
fi

# Temporary file to store host entries
TEMP_FILE=$(mktemp /tmp/mikrotik_hosts.XXXXXX)
SCRIPT_FILE=$(mktemp /tmp/mikrotik_script.XXXXXX)

# Cleanup function
cleanup() {
    rm -f "$TEMP_FILE" "$SCRIPT_FILE"
}
trap cleanup EXIT

print_info "Starting static DNS host copy process..."
print_info "Source: $SOURCE_IP"
print_info "Destination: $DEST_IP"

# Add debug mode if DEBUG environment variable is set
if [[ "${DEBUG:-0}" == "1" ]]; then
    print_info "Debug mode enabled"
    set -x
fi

echo

# SSH command wrapper
ssh_cmd() {
    local host=$1
    local cmd=$2
    
    if [[ "$USE_SSH_KEY" == "true" ]]; then
        # Use SSH key authentication
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 "${USERNAME}@${host}" "$cmd" 2>/dev/null
    else
        # Use password authentication with sshpass
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 "${USERNAME}@${host}" "$cmd" 2>/dev/null
    fi
}

# Test connection to source router
print_info "Testing connection to source router..."
if ! ssh_cmd "$SOURCE_IP" "/system identity print" > /dev/null; then
    print_error "Failed to connect to source router at $SOURCE_IP"
    exit 1
fi
print_info "Successfully connected to source router"

# Test connection to destination router
print_info "Testing connection to destination router..."
if ! ssh_cmd "$DEST_IP" "/system identity print" > /dev/null; then
    print_error "Failed to connect to destination router at $DEST_IP"
    exit 1
fi
print_info "Successfully connected to destination router"
echo

# Export static DNS entries from source
print_info "Exporting static DNS host entries from source router..."
RAW_EXPORT=$(ssh_cmd "$SOURCE_IP" "/ip dns static export" 2>&1)

# Check if the command failed
if [[ $? -ne 0 ]]; then
    print_error "Failed to export DNS entries from source router"
    echo "Error output: $RAW_EXPORT"
    exit 1
fi

# Show raw output in debug mode
if [[ "${DEBUG:-0}" == "1" ]]; then
    print_info "Raw export output:"
    echo "---"
    echo "$RAW_EXPORT"
    echo "---"
fi

# Filter for add commands - handle both old format (/ip dns static add) and new format (add under /ip dns static)
# Skip comments and empty lines
HOST_EXPORT=$(echo "$RAW_EXPORT" | grep -v "^#" | grep "^add " || true)

# If we found entries in the new format, prepend the command path
if [[ -n "$HOST_EXPORT" ]]; then
    # Convert "add ..." to "/ip dns static add ..."
    HOST_EXPORT=$(echo "$HOST_EXPORT" | sed 's/^add /\/ip dns static add /')
else
    # Try old format
    HOST_EXPORT=$(echo "$RAW_EXPORT" | grep -v "^#" | grep "^/ip dns static add" || true)
fi

if [[ -z "$HOST_EXPORT" ]]; then
    print_warn "No static DNS host entries found on source router"
    print_info "Checking if there are any static DNS entries..."
    ENTRY_CHECK=$(ssh_cmd "$SOURCE_IP" "/ip dns static print count-only" 2>&1)
    echo "Entry count: $ENTRY_CHECK"
    
    # Show what we got from export for debugging
    if [[ -n "$RAW_EXPORT" ]]; then
        echo ""
        print_info "Export command returned:"
        echo "$RAW_EXPORT" | head -20
    fi
    exit 0
fi

# Count entries
ENTRY_COUNT=$(echo "$HOST_EXPORT" | wc -l)
print_info "Found $ENTRY_COUNT static DNS host entries on source router"

# Save to temp file
echo "$HOST_EXPORT" > "$TEMP_FILE"

# Display entries to be copied
echo
print_info "Entries to be copied:"
echo "----------------------------------------"
cat "$TEMP_FILE"
echo "----------------------------------------"
echo

# Prompt for confirmation
read -p "Do you want to proceed with copying these entries? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Operation cancelled by user"
    exit 0
fi

# Create RouterOS script
echo "# Static DNS Host Import Script" > "$SCRIPT_FILE"
echo "# Generated on $(date)" >> "$SCRIPT_FILE"
echo "" >> "$SCRIPT_FILE"
cat "$TEMP_FILE" >> "$SCRIPT_FILE"

# Upload and execute script on destination router
print_info "Copying entries to destination router..."
echo

# Method 1: Direct execution (preferred)
COPY_COUNT=0
FAIL_COUNT=0
ENTRY_NUM=0

while IFS= read -r line; do
    if [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]]; then
        ((ENTRY_NUM++))
        
        # Extract hostname/name from the command for better logging
        HOSTNAME=$(echo "$line" | grep -oP 'name=\K[^ ]+' | head -1)
        ADDRESS=$(echo "$line" | grep -oP 'address=\K[^ ]+' | head -1)
        
        if [[ -n "$HOSTNAME" ]]; then
            print_info "[$ENTRY_NUM/$ENTRY_COUNT] Processing: $HOSTNAME -> $ADDRESS"
        else
            print_info "[$ENTRY_NUM/$ENTRY_COUNT] Processing entry..."
        fi
        
        ERROR_OUTPUT=$(ssh_cmd "$DEST_IP" "$line" 2>&1)
        
        if echo "$ERROR_OUTPUT" | grep -q "failure:"; then
            ((FAIL_COUNT++))
            print_warn "  ✗ Failed to add entry (possibly duplicate or invalid)"
            if [[ -n "$HOSTNAME" ]]; then
                echo "    Entry: $HOSTNAME"
            fi
        else
            ((COPY_COUNT++))
            echo -e "  ${GREEN}✓${NC} Successfully added"
        fi
    fi
done < "$TEMP_FILE"

echo
print_info "Copy operation completed!"
print_info "Successfully copied: $COPY_COUNT entries"
if [[ $FAIL_COUNT -gt 0 ]]; then
    print_warn "Failed to copy: $FAIL_COUNT entries (possibly duplicates)"
fi

# Display current static DNS entries on destination
echo
print_info "Current static DNS entries on destination router:"
echo "----------------------------------------"
ssh_cmd "$DEST_IP" "/ip dns static print detail" | head -30
if [[ $(ssh_cmd "$DEST_IP" "/ip dns static print count-only") -gt 10 ]]; then
    echo "... (showing first 30 lines, use MikroTik terminal for full list)"
fi
echo "----------------------------------------"

print_info "Script completed successfully!"
