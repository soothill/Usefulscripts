#!/bin/bash

################################################################################
# Syslog-ng Installation and Configuration Script
#
# Copyright (c) 2025 Darren Soothill. All rights reserved.
#
# This script automates the installation and configuration of syslog-ng to
# create a centralized logging server. It performs the following tasks:
#
# - Installs syslog-ng and logrotate packages (supports Ubuntu/Debian/RHEL/CentOS)
# - Configures syslog-ng to accept incoming syslog messages on both TCP and UDP
#   port 514 (standard syslog port)
# - Sets up organized log storage with separate directories for local and remote logs
# - Configures daily log rotation with automatic compression
# - Maintains logs for 30 days before automatic deletion
# - Configures firewall rules (firewalld or UFW) to allow syslog traffic
# - Creates proper directory structure with appropriate permissions
# - Validates configuration before applying changes
# - Backs up existing configurations before making changes
#
# Usage: Run this script as root or with sudo privileges
#   sudo ./syslog-ng-setup.sh
#
# Log Storage Locations:
#   Local logs:  /var/log/syslog-ng/local/YYYY-MM-DD.log
#   Remote logs: /var/log/syslog-ng/remote/<hostname>/YYYY-MM-DD.log
#
################################################################################

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "========================================="
echo "Syslog-ng Installation & Configuration"
echo "========================================="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

# Install syslog-ng
echo "Installing syslog-ng..."
case $OS in
    ubuntu|debian)
        apt-get update
        apt-get install -y syslog-ng logrotate
        ;;
    centos|rhel|fedora)
        yum install -y syslog-ng logrotate
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Backup existing configuration
if [ -f /etc/syslog-ng/syslog-ng.conf ]; then
    cp /etc/syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf.backup.$(date +%Y%m%d_%H%M%S)
    echo "Backed up existing configuration"
fi

# Create syslog-ng configuration
echo "Creating syslog-ng configuration..."
cat > /etc/syslog-ng/syslog-ng.conf << 'EOF'
@version: 3.38
@include "scl.conf"

# Options
options {
    chain_hostnames(off);
    flush_lines(0);
    use_dns(no);
    use_fqdn(no);
    owner("root");
    group("adm");
    perm(0640);
    stats_freq(0);
    bad_hostname("^gconfd$");
    time_reopen(10);
    log_fifo_size(2048);
    create_dirs(yes);
    keep_hostname(yes);
};

# Source for local system logs
source s_local {
    system();
    internal();
};

# Source for network logs - UDP
source s_network_udp {
    network(
        transport("udp")
        port(514)
        flags(no-parse)
    );
};

# Source for network logs - TCP
source s_network_tcp {
    network(
        transport("tcp")
        port(514)
        flags(no-parse)
        max-connections(256)
    );
};

# Destination for local logs
destination d_local {
    file("/var/log/syslog-ng/local/$YEAR-$MONTH-$DAY.log"
        create_dirs(yes)
        dir_perm(0755)
        perm(0644)
    );
};

# Destination for network logs (organized by host)
destination d_network {
    file("/var/log/syslog-ng/remote/$HOST/$YEAR-$MONTH-$DAY.log"
        create_dirs(yes)
        dir_perm(0755)
        perm(0644)
    );
};

# Log paths
log {
    source(s_local);
    destination(d_local);
};

log {
    source(s_network_udp);
    source(s_network_tcp);
    destination(d_network);
};
EOF

echo "Syslog-ng configuration created"

# Create logrotate configuration
echo "Creating logrotate configuration..."
cat > /etc/logrotate.d/syslog-ng << 'EOF'
/var/log/syslog-ng/local/*.log /var/log/syslog-ng/remote/*/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/bin/killall -HUP syslog-ng
    endscript
}
EOF

echo "Logrotate configuration created"

# Create log directories
mkdir -p /var/log/syslog-ng/local
mkdir -p /var/log/syslog-ng/remote
chown -R root:adm /var/log/syslog-ng
chmod -R 755 /var/log/syslog-ng

# Configure firewall if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "Configuring firewall..."
    firewall-cmd --permanent --add-port=514/tcp
    firewall-cmd --permanent --add-port=514/udp
    firewall-cmd --reload
    echo "Firewall rules added"
fi

# Configure UFW if it's running
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo "Configuring UFW..."
    ufw allow 514/tcp
    ufw allow 514/udp
    echo "UFW rules added"
fi

# Validate syslog-ng configuration
echo "Validating syslog-ng configuration..."
if syslog-ng -s; then
    echo "Configuration is valid"
else
    echo "Configuration validation failed!"
    exit 1
fi

# Enable and start syslog-ng
echo "Enabling and starting syslog-ng service..."
systemctl enable syslog-ng
systemctl restart syslog-ng

# Check service status
if systemctl is-active --quiet syslog-ng; then
    echo "========================================="
    echo "Installation completed successfully!"
    echo "========================================="
    echo "Syslog-ng is now:"
    echo "  - Accepting UDP logs on port 514"
    echo "  - Accepting TCP logs on port 514"
    echo "  - Storing local logs in: /var/log/syslog-ng/local/"
    echo "  - Storing remote logs in: /var/log/syslog-ng/remote/<hostname>/"
    echo "  - Rotating logs daily"
    echo "  - Keeping logs for 30 days"
    echo ""
    echo "Service status:"
    systemctl status syslog-ng --no-pager -l
else
    echo "========================================="
    echo "Installation completed but service failed to start!"
    echo "Check logs with: journalctl -xeu syslog-ng"
    echo "========================================="
    exit 1
fi
