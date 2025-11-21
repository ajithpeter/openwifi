#!/bin/bash
# Quick Test Script for PlutoSDR Beacon Scanner
# Tests basic functionality and hardware connectivity

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PLUTO_IP="${PLUTO_IP:-192.168.2.1}"
TEST_CHANNEL="${TEST_CHANNEL:-6}"
TEST_SSID="${TEST_SSID:-PlutoTest}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PlutoSDR Beacon Scanner Quick Test${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Test 1: Check if binary exists
echo -e "${YELLOW}[Test 1/5] Checking binary...${NC}"
if [ ! -f "beacon_scanner" ]; then
    echo -e "${RED}✗ beacon_scanner binary not found${NC}"
    echo "  Build it first with: make"
    exit 1
fi
echo -e "${GREEN}✓ Binary found${NC}"

# Test 2: Check libiio installation
echo -e "${YELLOW}[Test 2/5] Checking libiio...${NC}"
if ! ldconfig -p | grep -q libiio; then
    echo -e "${RED}✗ libiio not found${NC}"
    echo "  Install it with: sudo apt-get install libiio-dev libiio-utils"
    exit 1
fi
echo -e "${GREEN}✓ libiio installed${NC}"

# Test 3: Check PlutoSDR connectivity
echo -e "${YELLOW}[Test 3/5] Checking PlutoSDR connectivity...${NC}"
if ! command -v iio_info &> /dev/null; then
    echo -e "${YELLOW}⚠ iio_info not available, skipping hardware check${NC}"
else
    if iio_info -n ${PLUTO_IP} &> /dev/null; then
        echo -e "${GREEN}✓ PlutoSDR reachable at ${PLUTO_IP}${NC}"

        # Show PlutoSDR info
        echo "  Device info:"
        iio_info -n ${PLUTO_IP} | grep -E "(IIO context created|ad9361)" | sed 's/^/    /'
    else
        echo -e "${YELLOW}⚠ PlutoSDR not reachable at ${PLUTO_IP}${NC}"
        echo "  Hardware tests will be skipped"
        echo "  To test with hardware, ensure PlutoSDR is connected"
    fi
fi

# Test 4: Test help function
echo -e "${YELLOW}[Test 4/5] Testing help function...${NC}"
if ./beacon_scanner -h &> /dev/null; then
    echo -e "${GREEN}✓ Help function works${NC}"
else
    echo -e "${RED}✗ Help function failed${NC}"
    exit 1
fi

# Test 5: Quick hardware test (if available)
echo -e "${YELLOW}[Test 5/5] Hardware functionality test...${NC}"
if iio_info -n ${PLUTO_IP} &> /dev/null 2>&1; then
    echo "  Testing channel ${TEST_CHANNEL} scan (5 second dwell)..."
    echo "  This will attempt to detect WiFi beacons..."
    echo ""

    timeout 10 ./beacon_scanner -m scan -c ${TEST_CHANNEL} -t 5000 || true

    echo ""
    echo -e "${GREEN}✓ Hardware test completed${NC}"
    echo "  (Check output above for detected beacons)"
else
    echo -e "${YELLOW}⚠ Hardware not available, skipping${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Quick Test Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Basic tests: PASSED"
echo ""
echo "To run full tests:"
echo "  ./beacon_scanner -a              # Automated scan (all channels)"
echo "  ./beacon_scanner -m scan -c 6    # Scan specific channel"
echo "  ./beacon_scanner -m tx -c 6 -s \"${TEST_SSID}\"  # Transmit test beacon"
echo ""
echo "For deployment to PlutoSDR:"
echo "  ./build_and_deploy.sh            # Build and deploy automatically"
echo ""
echo "For Zynq 7010 SD card:"
echo "  sudo ./prepare_sdcard.sh         # Prepare bootable SD card"
echo ""
