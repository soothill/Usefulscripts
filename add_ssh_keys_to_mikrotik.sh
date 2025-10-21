#!/bin/bash

# Script to add SSH public key to MikroTik router
# Copyright (c) 2025 Darren Soothill
# Usage: ./add_mikrotik_ssh_key.sh <router_ip> <username> <public_key_file>

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo -e "${YELLOW}=== MikroTik SSH Key Installation ===${NC}"
    echo ""
    echo "Usage: $0 <router_ip> [username] [public_key_file]"
    echo ""
    echo "Arguments:"
    echo "  router_ip        IP address of the MikroTik router (required)"
    echo "  username         Router username (default: admin)"
    echo "  public_key_file  Path to SSH public key (default: ~/.ssh/id_rsa.pub)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.88.1"
    echo "  $0 192.168.88.1 admin"
    echo "  $0 192.168.88.1 admin ~/.ssh/id_ed25519.pub"
    echo ""
    exit 1
}

# Check if router IP is provided
if [ $# -eq 0 ]; then
    usage
fi

# Configuration
ROUTER_IP="$1"
USERNAME="${2:-admin}"
PUBLIC_KEY_FILE="${3:-~/.ssh/id_rsa.pub}"

echo "=== MikroTik SSH Key Installation ==="
echo "Router IP: $ROUTER_IP"
echo "Username: $USERNAME"
echo "Public Key: $PUBLIC_KEY_FILE"
echo ""

# Check if public key file exists
if [ ! -f "$PUBLIC_KEY_FILE" ]; then
    echo -e "${RED}Error: Public key file not found: $PUBLIC_KEY_FILE${NC}"
    echo "Generate one with: ssh-keygen -t rsa -b 4096"
    exit 1
fi

# Read the public key
PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")

echo "Public key loaded successfully"
echo ""

# Upload the key to MikroTik
echo "Adding SSH key to MikroTik router..."
echo "You will be prompted for your router password twice:"
echo "  1. To upload the key file via SCP"
echo "  2. To import the key via SSH"
echo ""

# Extract filename from path
KEY_FILENAME=$(basename "$PUBLIC_KEY_FILE")

# Step 1: Upload the public key file to the router via SCP
echo "Step 1: Uploading public key file to router..."
scp "$PUBLIC_KEY_FILE" "${USERNAME}@${ROUTER_IP}:${KEY_FILENAME}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to upload key file to router.${NC}"
    echo "Please check:"
    echo "  - Router IP address is correct: ${ROUTER_IP}"
    echo "  - Username is correct: ${USERNAME}"
    echo "  - You have network connectivity to the router"
    echo "  - SCP/SFTP service is enabled on the router"
    exit 1
fi

echo -e "${GREEN}Key file uploaded successfully.${NC}"
echo ""

# Step 2: Import the uploaded key via SSH
echo "Step 2: Importing SSH key on router..."
ssh "${USERNAME}@${ROUTER_IP}" "/user ssh-keys import public-key-file=${KEY_FILENAME} user=${USERNAME}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Success! SSH key imported to router.${NC}"
    echo ""

    # Step 3: Clean up the uploaded file
    echo "Step 3: Cleaning up temporary file on router..."
    ssh "${USERNAME}@${ROUTER_IP}" "/file remove ${KEY_FILENAME}" 2>/dev/null

    # Step 4: Disable password authentication for this user
    echo "Step 4: Disabling password authentication for user ${USERNAME}..."
    ssh "${USERNAME}@${ROUTER_IP}" "/user set ${USERNAME} password=\"\""

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Password authentication disabled for ${USERNAME}.${NC}"
        echo -e "${YELLOW}WARNING: This user can now ONLY login via SSH key!${NC}"
    else
        echo -e "${YELLOW}Note: Could not disable password authentication.${NC}"
        echo "To disable it manually, run on the router:"
        echo "  /user set ${USERNAME} password=\"\""
    fi

    echo ""
    echo -e "${GREEN}=== Installation Complete ===${NC}"
    echo "Test your connection with:"
    echo "  ssh ${USERNAME}@${ROUTER_IP}"
    echo ""
    echo "IMPORTANT: Password login is now disabled for ${USERNAME}."
    echo "Make sure your SSH key works before closing this session!"
else
    echo -e "${RED}Failed to import key on router.${NC}"
    echo ""
    echo "Manual steps:"
    echo "1. Log into your router and run:"
    echo "   /user ssh-keys import public-key-file=${KEY_FILENAME} user=${USERNAME}"
    echo ""
    echo "2. Then clean up the file:"
    echo "   /file remove ${KEY_FILENAME}"
    exit 1
fi

# Additional info
echo ""
echo "=== Additional Notes ==="
echo "1. To list SSH keys: /user ssh-keys print"
echo "2. To remove a key: /user ssh-keys remove [id]"
echo "3. To disable password auth: /ip ssh set strong-crypto=yes"
echo "4. Ensure SSH service is enabled: /ip service print"