#!/bin/bash

# Script to expand LVM root filesystem to maximum available space
# Handles disk rescanning and extends PV, LV, and filesystem

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}=== LVM Root Filesystem Expansion Script ===${NC}\n"

# Find the root filesystem mount point
ROOT_MOUNT=$(df / | tail -1 | awk '{print $1}')
echo -e "Root filesystem device: ${YELLOW}$ROOT_MOUNT${NC}"

# Check if root is on LVM
if [[ ! $ROOT_MOUNT =~ /dev/mapper/ ]] && [[ ! $ROOT_MOUNT =~ /dev/.*/.* ]]; then
    echo -e "${RED}Error: Root filesystem does not appear to be on LVM${NC}"
    exit 1
fi

# Get LV information
LV_PATH=$ROOT_MOUNT
VG_NAME=$(lvs --noheadings -o vg_name $LV_PATH | tr -d ' ')
LV_NAME=$(lvs --noheadings -o lv_name $LV_PATH | tr -d ' ')

echo -e "Volume Group: ${YELLOW}$VG_NAME${NC}"
echo -e "Logical Volume: ${YELLOW}$LV_NAME${NC}\n"

# Find the physical volume(s) for this VG
PV_DEVICES=$(pvs --noheadings -o pv_name -S vg_name=$VG_NAME | tr -d ' ')
echo -e "Physical Volume(s): ${YELLOW}$PV_DEVICES${NC}\n"

# Rescan all disks for size changes
echo -e "${GREEN}Step 1: Rescanning disks for size changes...${NC}"
for disk in /sys/class/block/sd*/device/rescan; do
    if [ -f "$disk" ]; then
        echo 1 > "$disk" 2>/dev/null || true
        disk_name=$(echo $disk | cut -d'/' -f5)
        echo "  Rescanned: $disk_name"
    fi
done

for disk in /sys/class/block/vd*/device/rescan; do
    if [ -f "$disk" ]; then
        echo 1 > "$disk" 2>/dev/null || true
        disk_name=$(echo $disk | cut -d'/' -f5)
        echo "  Rescanned: $disk_name"
    fi
done

# Also try partprobe
if command -v partprobe &> /dev/null; then
    echo "  Running partprobe..."
    partprobe 2>/dev/null || true
fi

echo ""

# Show current sizes
echo -e "${GREEN}Current Status:${NC}"
pvs | grep $VG_NAME
echo ""
vgs $VG_NAME
echo ""
lvs $VG_NAME/$LV_NAME
echo ""

# Extend each physical volume to use all available space
echo -e "${GREEN}Step 2: Extending Physical Volume(s)...${NC}"
for PV in $PV_DEVICES; do
    echo "  Extending PV: $PV"
    pvresize $PV
done
echo ""

# Show PV status after resize
echo -e "Physical Volumes after resize:"
pvs | grep $VG_NAME
echo ""

# Extend the logical volume to use all free space in VG
echo -e "${GREEN}Step 3: Extending Logical Volume...${NC}"
FREE_SPACE=$(vgs --noheadings --units g -o vg_free $VG_NAME | tr -d ' ' | sed 's/g//')
echo "  Available free space: ${FREE_SPACE}G"

if (( $(echo "$FREE_SPACE > 0.5" | bc -l) )); then
    echo "  Extending LV to use all free space..."
    lvextend -l +100%FREE /dev/$VG_NAME/$LV_NAME
else
    echo -e "${YELLOW}  No significant free space available to extend${NC}"
fi
echo ""

# Show LV status after extension
echo -e "Logical Volume after extension:"
lvs $VG_NAME/$LV_NAME
echo ""

# Resize the filesystem
echo -e "${GREEN}Step 4: Resizing filesystem...${NC}"
FS_TYPE=$(df -T / | tail -1 | awk '{print $2}')
echo "  Filesystem type: $FS_TYPE"

case $FS_TYPE in
    ext[234])
        echo "  Running resize2fs..."
        resize2fs $LV_PATH
        ;;
    xfs)
        echo "  Running xfs_growfs..."
        xfs_growfs /
        ;;
    *)
        echo -e "${RED}  Warning: Unsupported filesystem type: $FS_TYPE${NC}"
        echo "  You may need to resize manually"
        ;;
esac
echo ""

# Show final results
echo -e "${GREEN}=== Final Status ===${NC}"
df -h / | grep -E '(Filesystem|/)'
echo ""
echo -e "${GREEN}Filesystem expansion complete!${NC}"
