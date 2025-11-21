#!/bin/bash
# PlutoSDR Beacon Scanner - Build and Deploy Script
# Automates cross-compilation and deployment to PlutoSDR

set -e  # Exit on error

# Configuration
PLUTO_IP="${PLUTO_IP:-192.168.2.1}"
PLUTO_USER="${PLUTO_USER:-root}"
PLUTO_PASS="${PLUTO_PASS:-analog}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
TARGET_DIR="/root"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PlutoSDR Beacon Scanner Build & Deploy${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if cross-compiler is installed
echo -e "${YELLOW}[1/5] Checking cross-compiler...${NC}"
if ! command -v ${CROSS_COMPILE}gcc &> /dev/null; then
    echo -e "${RED}Error: Cross-compiler not found!${NC}"
    echo "Please install: sudo apt-get install gcc-arm-linux-gnueabihf"
    exit 1
fi
echo -e "${GREEN}✓ Cross-compiler found${NC}"

# Clean previous build
echo -e "${YELLOW}[2/5] Cleaning previous build...${NC}"
make clean 2>/dev/null || true
echo -e "${GREEN}✓ Clean complete${NC}"

# Build for ARM
echo -e "${YELLOW}[3/5] Cross-compiling for ARM...${NC}"
make cross CROSS_COMPILE=${CROSS_COMPILE}
if [ ! -f "beacon_scanner" ]; then
    echo -e "${RED}Error: Build failed!${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build successful${NC}"

# Check PlutoSDR connection
echo -e "${YELLOW}[4/5] Checking PlutoSDR connection...${NC}"
if ! ping -c 1 -W 2 ${PLUTO_IP} &> /dev/null; then
    echo -e "${RED}Error: Cannot reach PlutoSDR at ${PLUTO_IP}${NC}"
    echo "Please check:"
    echo "  1. PlutoSDR is connected via USB or Ethernet"
    echo "  2. PlutoSDR IP is ${PLUTO_IP} (set PLUTO_IP if different)"
    exit 1
fi
echo -e "${GREEN}✓ PlutoSDR reachable at ${PLUTO_IP}${NC}"

# Deploy to PlutoSDR
echo -e "${YELLOW}[5/5] Deploying to PlutoSDR...${NC}"
echo "Password is: ${PLUTO_PASS}"

# Use sshpass if available, otherwise remind user to enter password
if command -v sshpass &> /dev/null; then
    sshpass -p ${PLUTO_PASS} scp -o StrictHostKeyChecking=no beacon_scanner ${PLUTO_USER}@${PLUTO_IP}:${TARGET_DIR}/
    sshpass -p ${PLUTO_PASS} ssh -o StrictHostKeyChecking=no ${PLUTO_USER}@${PLUTO_IP} "chmod +x ${TARGET_DIR}/beacon_scanner"
else
    echo "Note: Install 'sshpass' for automated deployment without password prompt"
    scp -o StrictHostKeyChecking=no beacon_scanner ${PLUTO_USER}@${PLUTO_IP}:${TARGET_DIR}/
    ssh -o StrictHostKeyChecking=no ${PLUTO_USER}@${PLUTO_IP} "chmod +x ${TARGET_DIR}/beacon_scanner"
fi

echo -e "${GREEN}✓ Deployment complete${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Success! Beacon scanner deployed to PlutoSDR${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To run the scanner, SSH to PlutoSDR:"
echo "  ssh ${PLUTO_USER}@${PLUTO_IP}  (password: ${PLUTO_PASS})"
echo ""
echo "Then run:"
echo "  ${TARGET_DIR}/beacon_scanner -h               # Show help"
echo "  ${TARGET_DIR}/beacon_scanner -a               # Automated scan"
echo "  ${TARGET_DIR}/beacon_scanner -m scan -c 6     # Scan channel 6"
echo "  ${TARGET_DIR}/beacon_scanner -m tx -c 6 -s \"TestAP\"  # Transmit beacon"
echo ""
