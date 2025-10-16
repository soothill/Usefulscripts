#!/bin/bash

################################################################################
# Ubuntu Static IP Configuration Script
# 
# Description:
#   This script configures a static IP address on Ubuntu systems using Netplan.
#   It automatically backs up existing network configuration, creates a new
#   Netplan configuration file with the specified static IP settings, and
#   applies the changes with a safety timeout that allows automatic rollback
#   if the network configuration fails.
#
# Copyright (c) 2025 Darren Soothill
# All rights reserved.
################################################################################

# Configuration variables - CHANGE THESE TO MATCH YOUR NETWORK
STATIC_IP="x.x.x.x"        # Your desired static IP address
GATEWAY="y.y.y.y"          # Your network gateway
NETMASK="24"               # /24 subnet (255.255.255.0)
DNS_SERVERS="y.y.y.y"      # DNS server address

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Set the network interface
INTERFACE="ens18"

echo "Configuring static IP for interface: $INTERFACE"
echo "IP Address: $STATIC_IP/$NETMASK"
echo "Gateway: $GATEWAY"
echo "DNS: $DNS_SERVERS"

# Backup existing netplan configuration
NETPLAN_DIR="/etc/netplan"
BACKUP_DIR="/etc/netplan/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -n "$(ls -A $NETPLAN_DIR/*.yaml 2>/dev/null)" ]; then
    echo "Backing up existing Netplan configuration to $BACKUP_DIR"
    cp $NETPLAN_DIR/*.yaml "$BACKUP_DIR/" 2>/dev/null
fi

# Create new netplan configuration
NETPLAN_FILE="$NETPLAN_DIR/01-static-config.yaml"

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $STATIC_IP/$NETMASK
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$(echo $DNS_SERVERS | tr ',' ' ')]
EOF

echo "Netplan configuration created at $NETPLAN_FILE"
echo "Configuration contents:"
cat "$NETPLAN_FILE"

# Set correct permissions
chmod 600 "$NETPLAN_FILE"

# Test the configuration
echo ""
echo "Testing Netplan configuration..."
netplan try --timeout 30

if [ $? -eq 0 ]; then
    echo ""
    echo "Configuration applied successfully!"
    echo "Verifying network settings..."
    echo ""
    ip addr show "$INTERFACE"
    echo ""
    ip route show
    echo ""
    echo "Static IP configuration complete!"
else
    echo "Configuration failed. Rolling back..."
    if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A $BACKUP_DIR)" ]; then
        cp "$BACKUP_DIR"/*.yaml "$NETPLAN_DIR/"
        netplan apply
    fi
    exit 1
fi
