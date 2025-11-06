#!/bin/bash
#
# Advanced script to configure rsyslog to send logs to a remote syslog server
# Author: Darren Soothill
# Usage: sudo ./configure_remote_syslog_advanced.sh [OPTIONS]
#

set -e

# Default configuration variables
SYSLOG_SERVER="syslog"
SYSLOG_PORT="514"
PROTOCOL="udp"
CONFIG_FILE="/etc/rsyslog.d/50-remote-syslog.conf"
FACILITIES="*.*"  # All facilities and priorities by default
TLS_ENABLED=false
SKIP_TESTS=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure rsyslog to send logs to a remote syslog server.

OPTIONS:
    -s, --server SERVER     Syslog server hostname or IP (default: syslog)
    -p, --port PORT         Syslog server port (default: 514)
    -t, --protocol PROTO    Protocol: udp, tcp, or tls (default: udp)
    -f, --facilities SPEC   Facility specification (default: *.*)
                           Examples: kern.*, auth.*, mail.info
    -c, --config FILE       Config file path (default: /etc/rsyslog.d/50-remote-syslog.conf)
    --skip-tests           Skip connectivity tests
    --remove               Remove remote syslog configuration
    -h, --help             Display this help message

EXAMPLES:
    # Basic configuration
    sudo $0 -s syslog.example.com

    # Use TCP protocol with custom port
    sudo $0 -s syslog.example.com -t tcp -p 1514

    # Forward only kernel and auth logs
    sudo $0 -s syslog -f "kern.*;auth.*"

    # Remove configuration
    sudo $0 --remove

EOF
    exit 0
}

# Parse command line arguments
REMOVE_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            SYSLOG_SERVER="$2"
            shift 2
            ;;
        -p|--port)
            SYSLOG_PORT="$2"
            shift 2
            ;;
        -t|--protocol)
            PROTOCOL="${2,,}"  # Convert to lowercase
            shift 2
            ;;
        -f|--facilities)
            FACILITIES="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --remove)
            REMOVE_CONFIG=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate protocol
if [[ ! "$PROTOCOL" =~ ^(udp|tcp|tls)$ ]]; then
    print_error "Invalid protocol: $PROTOCOL. Must be udp, tcp, or tls"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Handle removal
if [[ "$REMOVE_CONFIG" == true ]]; then
    print_info "Removing remote syslog configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        BACKUP_FILE="${CONFIG_FILE}.removed.$(date +%Y%m%d_%H%M%S)"
        mv "$CONFIG_FILE" "$BACKUP_FILE"
        print_info "Configuration moved to: $BACKUP_FILE"
    else
        print_warn "Configuration file not found: $CONFIG_FILE"
    fi
    
    print_info "Restarting rsyslog..."
    systemctl restart rsyslog
    print_info "Remote syslog configuration removed successfully"
    exit 0
fi

# Display configuration
cat << EOF

================================================
Remote Syslog Configuration Script
================================================
Server:      $SYSLOG_SERVER
Port:        $SYSLOG_PORT
Protocol:    $PROTOCOL
Facilities:  $FACILITIES
Config File: $CONFIG_FILE
================================================

EOF

# Check if rsyslog is installed
if ! command -v rsyslogd &> /dev/null; then
    print_error "rsyslog is not installed"
    print_info "Installing rsyslog..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y rsyslog
    elif command -v yum &> /dev/null; then
        yum install -y rsyslog
    elif command -v zypper &> /dev/null; then
        zypper install -y rsyslog
    elif command -v dnf &> /dev/null; then
        dnf install -y rsyslog
    else
        print_error "Could not detect package manager. Please install rsyslog manually."
        exit 1
    fi
fi

# Backup existing config
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"
if [[ -f "$CONFIG_FILE" ]]; then
    print_info "Backing up existing configuration"
    cp "$CONFIG_FILE" "${CONFIG_FILE}${BACKUP_SUFFIX}"
fi

# Create the rsyslog configuration
print_info "Creating rsyslog configuration..."

cat > "$CONFIG_FILE" << EOF
# Remote syslog configuration
# Generated on $(date)
# Server: $SYSLOG_SERVER:$SYSLOG_PORT ($PROTOCOL)

# Queue configuration for reliability
\$ActionQueueType LinkedList
\$ActionQueueFileName remote_fwd
\$ActionResumeRetryCount -1
\$ActionQueueSaveOnShutdown on
\$ActionQueueMaxDiskSpace 1g

EOF

# Add protocol-specific configuration
case "$PROTOCOL" in
    tcp)
        echo "# Forward logs via TCP (reliable)" >> "$CONFIG_FILE"
        echo "$FACILITIES @@${SYSLOG_SERVER}:${SYSLOG_PORT}" >> "$CONFIG_FILE"
        ;;
    tls)
        print_warn "TLS configuration requires additional setup (certificates)"
        cat >> "$CONFIG_FILE" << 'EOF'
# TLS configuration (requires certificates)
$DefaultNetstreamDriver gtls
$ActionSendStreamDriverMode 1
$ActionSendStreamDriverAuthMode x509/name

EOF
        echo "$FACILITIES @@${SYSLOG_SERVER}:${SYSLOG_PORT}" >> "$CONFIG_FILE"
        ;;
    *)
        echo "# Forward logs via UDP (standard)" >> "$CONFIG_FILE"
        echo "$FACILITIES @${SYSLOG_SERVER}:${SYSLOG_PORT}" >> "$CONFIG_FILE"
        ;;
esac

print_info "Configuration created: $CONFIG_FILE"

# Test configuration
print_info "Testing rsyslog configuration..."
if rsyslogd -N1 2>&1 | grep -q "error"; then
    print_error "Configuration has errors:"
    rsyslogd -N1
    exit 1
else
    print_info "Configuration syntax is valid"
fi

# Connectivity tests
if [[ "$SKIP_TESTS" == false ]]; then
    print_info "Testing connectivity to $SYSLOG_SERVER..."
    
    if host "$SYSLOG_SERVER" &> /dev/null || getent hosts "$SYSLOG_SERVER" &> /dev/null; then
        SYSLOG_IP=$(getent hosts "$SYSLOG_SERVER" | awk '{ print $1 }' | head -n1)
        print_info "Resolved $SYSLOG_SERVER to $SYSLOG_IP"
        
        if command -v nc &> /dev/null && [[ "$PROTOCOL" == "tcp" ]]; then
            if timeout 5 nc -zv "$SYSLOG_SERVER" "$SYSLOG_PORT" 2>&1 | grep -q succeeded; then
                print_info "TCP connection successful"
            else
                print_warn "Could not establish TCP connection"
            fi
        fi
    else
        print_warn "Could not resolve $SYSLOG_SERVER"
    fi
fi

# Restart rsyslog
print_info "Restarting rsyslog service..."
if systemctl restart rsyslog && systemctl is-active --quiet rsyslog; then
    print_info "rsyslog restarted successfully"
else
    print_error "Failed to restart rsyslog"
    systemctl status rsyslog
    exit 1
fi

# Send test message
print_info "Sending test message..."
logger -t "syslog_config_test" "Remote syslog configured for $SYSLOG_SERVER:$SYSLOG_PORT via $PROTOCOL at $(date)"

# Summary
cat << EOF

================================================
Configuration Complete
================================================
✓ Configuration: $CONFIG_FILE
✓ Service restarted
✓ Test message sent

Verify on server:
  tail -f /var/log/messages | grep syslog_config_test

Monitor locally:
  journalctl -u rsyslog -f
  tail -f /var/log/messages

To remove:
  sudo $0 --remove
================================================

EOF

print_info "Done!"
exit 0
