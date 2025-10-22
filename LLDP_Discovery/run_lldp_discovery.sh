#!/bin/bash
#
# LLDP Network Discovery Runner Script
# Automates the discovery and visualization process
#
# Copyright (c) 2025 Darren Soothill
#

set -e

# Configuration
CONFIG_FILE="${1:-switches_config.yaml}"
OUTPUT_JSON="${2:-network_topology.json}"
OUTPUT_IMAGE="${3:-network_topology.png}"
LAYOUT="${4:-spring}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "LLDP Network Discovery Tool"
echo "=========================================="
echo ""

# Check if Python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    exit 1
fi

# Check if required Python packages are installed
echo -e "${YELLOW}Checking Python dependencies...${NC}"
python3 -c "import paramiko, yaml, networkx, matplotlib" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Required Python packages not installed${NC}"
    echo "Install them with: pip install -r requirements_lldp.txt"
    exit 1
fi
echo -e "${GREEN}Dependencies OK${NC}"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
    echo "Usage: $0 [config_file] [output_json] [output_image] [layout]"
    exit 1
fi

# Step 1: Run network discovery
echo -e "${YELLOW}Step 1: Discovering network topology...${NC}"
python3 "$SCRIPT_DIR/lldp_network_discovery.py" -c "$CONFIG_FILE" -o "$OUTPUT_JSON"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Discovery failed${NC}"
    exit 1
fi
echo -e "${GREEN}Discovery completed successfully${NC}"
echo ""

# Check if JSON file was created
if [ ! -f "$OUTPUT_JSON" ]; then
    echo -e "${RED}Error: Topology JSON file was not created${NC}"
    exit 1
fi

# Step 2: Generate visualization
echo -e "${YELLOW}Step 2: Generating network visualization...${NC}"
python3 "$SCRIPT_DIR/lldp_visualize.py" -i "$OUTPUT_JSON" -o "$OUTPUT_IMAGE" -l "$LAYOUT" --text-report --dot-file

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Visualization failed${NC}"
    exit 1
fi
echo -e "${GREEN}Visualization completed successfully${NC}"
echo ""

# Summary
echo "=========================================="
echo -e "${GREEN}Discovery Complete!${NC}"
echo "=========================================="
echo ""
echo "Generated files:"
echo "  - Topology data: $OUTPUT_JSON"
echo "  - Network map:   $OUTPUT_IMAGE"
echo "  - Text report:   ${OUTPUT_IMAGE%.png}.txt"
echo "  - DOT file:      ${OUTPUT_IMAGE%.png}.dot"
echo ""
echo "View the network map:"
echo "  open $OUTPUT_IMAGE"
echo ""
