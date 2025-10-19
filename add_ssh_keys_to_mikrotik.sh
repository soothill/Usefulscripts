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
echo "You will be prompted for your router password."
echo ""

# Method 1: Direct SSH command (works for RouterOS 6.45+)
ssh "${USERNAME}@${ROUTER_IP}" "/user ssh-keys import public-key-file=stdin user=${USERNAME}" < "$PUBLIC_KEY_FILE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Success! SSH key added to router.${NC}"
    echo ""
    echo "Test your connection with:"
    echo "ssh ${USERNAME}@${ROUTER_IP}"
else
    echo -e "${RED}Failed to add key via direct import.${NC}"
    echo "Trying alternative method..."
    echo ""
    
    # Method 2: Manual command
    echo "Run this command manually on your MikroTik router:"
    echo ""
    echo "/user ssh-keys import user=${USERNAME} public-key-file=<filename>.pub"
    echo ""
    echo "Or add the key directly:"
    echo "/user ssh-keys add user=${USERNAME} key-data=\"${PUBLIC_KEY}\""
fi

# Additional info
echo ""
echo "=== Additional Notes ==="
echo "1. To list SSH keys: /user ssh-keys print"
echo "2. To remove a key: /user ssh-keys remove [id]"
echo "3. To disable password auth: /ip ssh set strong-crypto=yes"
echo "4. Ensure SSH service is enabled: /ip service print"