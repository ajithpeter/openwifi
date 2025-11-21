#!/bin/bash
# Zynq 7010 SD Card Preparation Script
# Creates bootable SD card for minimal beacon scanner deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Zynq 7010 SD Card Preparation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will ERASE all data on the target SD card!${NC}"
echo ""

# List available block devices
echo "Available devices:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
echo ""

# Get SD card device
read -p "Enter SD card device (e.g., sdb): " SD_DEVICE
SD_DEV="/dev/${SD_DEVICE}"

if [ ! -b "${SD_DEV}" ]; then
    echo -e "${RED}Error: ${SD_DEV} is not a valid block device${NC}"
    exit 1
fi

# Confirm
echo ""
echo -e "${YELLOW}This will completely erase ${SD_DEV}${NC}"
lsblk ${SD_DEV}
echo ""
read -p "Are you sure? Type 'yes' to continue: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Unmount any existing partitions
echo -e "${YELLOW}[1/7] Unmounting existing partitions...${NC}"
umount ${SD_DEV}* 2>/dev/null || true
echo -e "${GREEN}✓ Unmounted${NC}"

# Create partitions
echo -e "${YELLOW}[2/7] Creating partition table...${NC}"
parted -s ${SD_DEV} mklabel msdos
parted -s ${SD_DEV} mkpart primary fat32 1MiB 100MiB
parted -s ${SD_DEV} mkpart primary ext4 100MiB 100%
parted -s ${SD_DEV} set 1 boot on
echo -e "${GREEN}✓ Partitions created${NC}"

# Wait for kernel to update
sleep 2

# Format partitions
echo -e "${YELLOW}[3/7] Formatting partitions...${NC}"
mkfs.vfat -F 32 -n BOOT ${SD_DEV}1
mkfs.ext4 -L ROOT ${SD_DEV}2
echo -e "${GREEN}✓ Formatting complete${NC}"

# Mount partitions
echo -e "${YELLOW}[4/7] Mounting partitions...${NC}"
MOUNT_BOOT="/tmp/sdcard_boot"
MOUNT_ROOT="/tmp/sdcard_root"
mkdir -p ${MOUNT_BOOT} ${MOUNT_ROOT}
mount ${SD_DEV}1 ${MOUNT_BOOT}
mount ${SD_DEV}2 ${MOUNT_ROOT}
echo -e "${GREEN}✓ Mounted${NC}"

# Check for boot files
echo -e "${YELLOW}[5/7] Copying boot files...${NC}"
BOOT_FILES_DIR="${BOOT_FILES_DIR:-./boot_files}"

if [ -d "${BOOT_FILES_DIR}" ]; then
    if [ -f "${BOOT_FILES_DIR}/BOOT.BIN" ]; then
        cp ${BOOT_FILES_DIR}/BOOT.BIN ${MOUNT_BOOT}/
        echo "  ✓ BOOT.BIN"
    fi

    if [ -f "${BOOT_FILES_DIR}/uImage" ] || [ -f "${BOOT_FILES_DIR}/Image" ]; then
        cp ${BOOT_FILES_DIR}/uImage ${MOUNT_BOOT}/ 2>/dev/null || \
        cp ${BOOT_FILES_DIR}/Image ${MOUNT_BOOT}/ 2>/dev/null || true
        echo "  ✓ Kernel image"
    fi

    if [ -f "${BOOT_FILES_DIR}/devicetree.dtb" ]; then
        cp ${BOOT_FILES_DIR}/devicetree.dtb ${MOUNT_BOOT}/
        echo "  ✓ Device tree"
    fi

    echo -e "${GREEN}✓ Boot files copied${NC}"
else
    echo -e "${YELLOW}⚠ Boot files directory not found at ${BOOT_FILES_DIR}${NC}"
    echo "  Please place boot files (BOOT.BIN, uImage, devicetree.dtb) manually in ${MOUNT_BOOT}/"
fi

# Copy rootfs
echo -e "${YELLOW}[6/7] Copying root filesystem...${NC}"
ROOTFS_TAR="${ROOTFS_TAR:-./rootfs.tar.gz}"

if [ -f "${ROOTFS_TAR}" ]; then
    tar -xzf ${ROOTFS_TAR} -C ${MOUNT_ROOT}/
    echo -e "${GREEN}✓ Root filesystem extracted${NC}"
else
    echo -e "${YELLOW}⚠ Root filesystem not found at ${ROOTFS_TAR}${NC}"
    echo "  Creating minimal directory structure..."
    mkdir -p ${MOUNT_ROOT}/{bin,sbin,lib,usr,etc,root,dev,proc,sys,tmp}
    chmod 1777 ${MOUNT_ROOT}/tmp
fi

# Copy beacon scanner application
echo -e "${YELLOW}[7/7] Copying beacon scanner application...${NC}"
if [ -f "beacon_scanner" ]; then
    mkdir -p ${MOUNT_ROOT}/root
    cp beacon_scanner ${MOUNT_ROOT}/root/
    chmod +x ${MOUNT_ROOT}/root/beacon_scanner
    echo -e "${GREEN}✓ Beacon scanner copied to /root/beacon_scanner${NC}"
else
    echo -e "${YELLOW}⚠ beacon_scanner binary not found${NC}"
    echo "  Build it first with: make cross CROSS_COMPILE=arm-linux-gnueabihf-"
fi

# Create startup script
cat > ${MOUNT_ROOT}/root/run_scanner.sh << 'EOF'
#!/bin/sh
# Zynq 7010 Beacon Scanner Startup Script

echo "========================================="
echo "WiFi Beacon Scanner for Zynq 7010"
echo "========================================="
echo ""

# Check AD9361
if [ -e /sys/bus/iio/devices/iio:device1/name ]; then
    echo "✓ AD9361 detected:"
    cat /sys/bus/iio/devices/iio:device1/name
else
    echo "✗ AD9361 not found!"
    echo "Please check hardware connections"
    exit 1
fi

echo ""
echo "Available commands:"
echo "  ./beacon_scanner -h          # Show help"
echo "  ./beacon_scanner -a          # Automated scan"
echo "  ./beacon_scanner -m scan -c 6  # Scan channel 6"
echo ""
EOF
chmod +x ${MOUNT_ROOT}/root/run_scanner.sh

# Sync and unmount
sync
umount ${MOUNT_BOOT}
umount ${MOUNT_ROOT}

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SD Card Preparation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "SD card is ready for Zynq 7010."
echo ""
echo "Next steps:"
echo "  1. Insert SD card into Zynq 7010 board"
echo "  2. Connect serial console (115200 8N1)"
echo "  3. Power on the board"
echo "  4. Login and run: /root/run_scanner.sh"
echo ""
echo "If you need to add boot files manually:"
echo "  1. Mount ${SD_DEV}1 (BOOT partition)"
echo "  2. Copy BOOT.BIN, uImage, devicetree.dtb"
echo ""
echo "If you need to add root filesystem manually:"
echo "  1. Mount ${SD_DEV}2 (ROOT partition)"
echo "  2. Extract your rootfs.tar.gz there"
echo ""
