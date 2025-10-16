#!/bin/bash

################################################################################
# LVM Root Filesystem Expansion Script
#
# Copyright (c) 2025 Darren Soothill
# All rights reserved.
#
# DESCRIPTION:
#   This script automatically expands the root filesystem on Ubuntu systems
#   using LVM (Logical Volume Manager) to utilize all available physical disk
#   space. It is particularly useful after expanding a virtual disk in
#   hypervisors (VMware, VirtualBox, KVM, etc.) or cloud environments (AWS,
#   Azure, GCP, etc.).
#
#   The script performs the complete expansion chain:
#   1. Rescans physical disks to detect size changes
#   2. Expands the partition(s) to use all available disk space
#   3. Extends the Physical Volume(s) to use the full partition
#   4. Extends the Logical Volume to use all free space in the Volume Group
#   5. Resizes the filesystem to fill the Logical Volume
#
# USAGE:
#   sudo bash ./expand-root-lvm.sh
#
# REQUIREMENTS:
#   - Must be run as root or with sudo
#   - Root filesystem must be on LVM
#   - Supported filesystems: ext2, ext3, ext4, XFS
#   - Required packages: lvm2, util-linux
#   - Recommended packages: cloud-guest-utils (for growpart), parted
#
# SUPPORTED DISK TYPES:
#   - SCSI/SATA disks (sda, sdb, etc.)
#   - VirtIO disks (vda, vdb, etc.)
#   - NVMe disks (nvme0n1, nvme1n1, etc.)
#
# NOTES:
#   - This script is safe to run even if no expansion is needed
#   - All operations are performed online (no reboot required)
#   - The script includes safety checks and informative output
#   - Compatible with standard Ubuntu LVM installations
#
# EXAMPLES:
#   # After expanding a VM's disk from 20GB to 50GB:
#   sudo bash ./expand-root-lvm.sh
#
#   # The script will automatically:
#   # - Detect the additional 30GB of space
#   # - Expand all necessary components
#   # - Resize the filesystem to use the new space
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then 
    printf "${RED}Error: This script must be run as root or with sudo${NC}\n"
    exit 1
fi

printf "${GREEN}=== LVM Root Filesystem Expansion Script ===${NC}\n\n"

# Find the root filesystem mount point
ROOT_MOUNT=$(df / | tail -1 | awk '{print $1}')
printf "Root filesystem device: ${YELLOW}%s${NC}\n" "$ROOT_MOUNT"

# Check if root is on LVM
case "$ROOT_MOUNT" in
    /dev/mapper/*|/dev/*/*)
        # Looks like LVM
        ;;
    *)
        printf "${RED}Error: Root filesystem does not appear to be on LVM${NC}\n"
        exit 1
        ;;
esac

# Get LV information
LV_PATH=$ROOT_MOUNT
VG_NAME=$(lvs --noheadings -o vg_name "$LV_PATH" | tr -d ' ')
LV_NAME=$(lvs --noheadings -o lv_name "$LV_PATH" | tr -d ' ')

printf "Volume Group: ${YELLOW}%s${NC}\n" "$VG_NAME"
printf "Logical Volume: ${YELLOW}%s${NC}\n\n" "$LV_NAME"

# Find the physical volume(s) for this VG
PV_DEVICES=$(pvs --noheadings -o pv_name -S vg_name="$VG_NAME" | tr -d ' ')
printf "Physical Volume(s): ${YELLOW}%s${NC}\n\n" "$PV_DEVICES"

# Rescan all disks for size changes
printf "${GREEN}Step 1: Rescanning disks for size changes...${NC}\n"
for disk in /sys/class/block/sd*/device/rescan; do
    if [ -f "$disk" ]; then
        echo 1 > "$disk" 2>/dev/null || true
        disk_name=$(echo "$disk" | cut -d'/' -f5)
        printf "  Rescanned: %s\n" "$disk_name"
    fi
done

for disk in /sys/class/block/vd*/device/rescan; do
    if [ -f "$disk" ]; then
        echo 1 > "$disk" 2>/dev/null || true
        disk_name=$(echo "$disk" | cut -d'/' -f5)
        printf "  Rescanned: %s\n" "$disk_name"
    fi
done

# Also try partprobe
if command -v partprobe >/dev/null 2>&1; then
    printf "  Running partprobe...\n"
    partprobe 2>/dev/null || true
fi

printf "\n"

# Show current sizes
printf "${GREEN}Current Status:${NC}\n"
pvs | grep "$VG_NAME"
printf "\n"
vgs "$VG_NAME"
printf "\n"
lvs "$VG_NAME/$LV_NAME"
printf "\n"

# Extend partitions and physical volumes
printf "${GREEN}Step 2: Extending Partitions and Physical Volumes...${NC}\n"
for PV in $PV_DEVICES; do
    printf "  Processing PV: %s\n" "$PV"
    
    # Determine if PV is a partition or whole disk
    # Check if device name ends with a number (indicating a partition)
    if echo "$PV" | grep -qE '[0-9]$'; then
        # This is a partition, we need to grow it first
        
        # Determine disk type and extract disk/partition number
        if echo "$PV" | grep -q "nvme"; then
            # NVMe device (e.g., /dev/nvme0n1p1)
            DISK=$(echo "$PV" | sed 's/p[0-9]*$//')
            PART_NUM=$(echo "$PV" | grep -oE '[0-9]+$')
        else
            # Standard disk (e.g., /dev/sda1, /dev/vda3)
            DISK=$(echo "$PV" | sed 's/[0-9]*$//')
            PART_NUM=$(echo "$PV" | grep -oE '[0-9]+$')
        fi
        
        printf "    Disk: %s, Partition: %s\n" "$DISK" "$PART_NUM"
        
        # Try to grow the partition using growpart
        if command -v growpart >/dev/null 2>&1; then
            printf "    Growing partition with growpart...\n"
            if ! growpart "$DISK" "$PART_NUM" 2>/dev/null; then
                printf "    ${YELLOW}growpart: partition may already be at maximum size${NC}\n"
            fi
        else
            # Fallback to parted if growpart not available
            printf "    Growing partition with parted (growpart not found)...\n"
            if ! parted "$DISK" resizepart "$PART_NUM" 100% 2>/dev/null; then
                printf "    ${YELLOW}parted: partition may already be at maximum size${NC}\n"
            fi
        fi
        
        # Inform kernel of partition table changes
        partprobe "$DISK" 2>/dev/null || partx -u "$DISK" 2>/dev/null || true
        sleep 1
    fi
    
    # Now extend the physical volume
    printf "    Extending PV to use full partition space...\n"
    pvresize "$PV"
done
printf "\n"

# Show PV status after resize
printf "Physical Volumes after resize:\n"
pvs | grep "$VG_NAME"
printf "\n"

# Extend the logical volume to use all free space in VG
printf "${GREEN}Step 3: Extending Logical Volume...${NC}\n"
FREE_SPACE=$(vgs --noheadings --units m -o vg_free "$VG_NAME" | tr -d ' ' | sed 's/[^0-9.]//g')
printf "  Available free space: %sM\n" "$FREE_SPACE"

# Convert to integer for comparison (bash only handles integers)
FREE_SPACE_INT=$(echo "$FREE_SPACE" | cut -d'.' -f1)

if [ -n "$FREE_SPACE_INT" ] && [ "$FREE_SPACE_INT" -gt 100 ]; then
    printf "  Extending LV to use all free space...\n"
    lvextend -l +100%FREE "/dev/$VG_NAME/$LV_NAME"
else
    printf "  ${YELLOW}No significant free space available to extend (less than 100M)${NC}\n"
fi
printf "\n"

# Show LV status after extension
printf "Logical Volume after extension:\n"
lvs "$VG_NAME/$LV_NAME"
printf "\n"

# Resize the filesystem
printf "${GREEN}Step 4: Resizing filesystem...${NC}\n"
FS_TYPE=$(df -T / | tail -1 | awk '{print $2}')
printf "  Filesystem type: %s\n" "$FS_TYPE"

case $FS_TYPE in
    ext[234])
        printf "  Running resize2fs...\n"
        resize2fs "$LV_PATH"
        ;;
    xfs)
        printf "  Running xfs_growfs...\n"
        xfs_growfs /
        ;;
    *)
        printf "  ${RED}Warning: Unsupported filesystem type: %s${NC}\n" "$FS_TYPE"
        printf "  You may need to resize manually\n"
        ;;
esac
printf "\n"

# Show final results
printf "${GREEN}=== Final Status ===${NC}\n"
df -h / | grep -E '(Filesystem|/)'
printf "\n"
printf "${GREEN}Filesystem expansion complete!${NC}\n"