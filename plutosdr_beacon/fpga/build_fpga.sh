#!/bin/bash
# FPGA Build Script for PlutoSDR/Zynq 7010 OpenWiFi
# Generates Vivado project, runs synthesis, implementation, and bitstream generation
#
# Usage: ./build_fpga.sh [clean|synth|impl|bit|all]
#
# Requirements:
# - Vivado 2019.1 or later installed
# - OpenWiFi IP cores cloned to ../../openwifi-hw/ip/
# - Source Vivado settings: source /opt/Xilinx/Vivado/2019.1/settings64.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="openwifi_z7010"
PROJECT_DIR="./openwifi_z7010"
BOARD_PART="xc7z010clg400-1"
IP_REPO_PATH="../../openwifi-hw/ip"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Vivado is available
check_vivado() {
    echo -e "${YELLOW}[Check] Verifying Vivado installation...${NC}"
    if ! command -v vivado &> /dev/null; then
        echo -e "${RED}Error: Vivado not found in PATH${NC}"
        echo "Please source Vivado settings first:"
        echo "  source /opt/Xilinx/Vivado/2019.1/settings64.sh"
        exit 1
    fi
    VIVADO_VERSION=$(vivado -version | grep Vivado | awk '{print $2}')
    echo -e "${GREEN}✓ Vivado ${VIVADO_VERSION} found${NC}"
}

# Check if IP repository exists
check_ip_repo() {
    echo -e "${YELLOW}[Check] Verifying OpenWiFi IP repository...${NC}"
    if [ ! -d "$IP_REPO_PATH" ]; then
        echo -e "${RED}Error: IP repository not found at $IP_REPO_PATH${NC}"
        echo "Please clone openwifi-hw first:"
        echo "  cd ../.."
        echo "  git clone https://github.com/open-sdr/openwifi-hw.git"
        exit 1
    fi

    # Check for required IP cores
    REQUIRED_IPS=("openofdm_rx" "openofdm_tx" "rx_intf" "tx_intf" "xpu" "side_ch")
    for ip in "${REQUIRED_IPS[@]}"; do
        if [ ! -d "$IP_REPO_PATH/$ip" ]; then
            echo -e "${RED}Error: Missing IP core: $ip${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓ All required IP cores found${NC}"
}

# Clean project
clean_project() {
    echo -e "${YELLOW}[Clean] Removing previous project...${NC}"
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
        echo -e "${GREEN}✓ Project cleaned${NC}"
    else
        echo -e "${BLUE}→ No previous project to clean${NC}"
    fi
}

# Create Vivado project
create_project() {
    echo -e "${YELLOW}[Create] Creating Vivado project...${NC}"

    # Run block design creation script
    vivado -mode batch -source create_zynq7010_block_design.tcl -notrace

    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${RED}Error: Project creation failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Project created successfully${NC}"
}

# Add constraints file
add_constraints() {
    echo -e "${YELLOW}[Constraints] Adding timing and pin constraints...${NC}"

    # Check if constraints file exists
    if [ -f "constraints_zynq7010.xdc" ]; then
        # Add to project using TCL
        cat > add_constraints.tcl << 'EOF'
open_project ./openwifi_z7010/openwifi_z7010.xpr
add_files -fileset constrs_1 -norecurse constraints_zynq7010.xdc
set_property used_in_synthesis true [get_files constraints_zynq7010.xdc]
set_property used_in_implementation true [get_files constraints_zynq7010.xdc]
save_project
close_project
EOF
        vivado -mode batch -source add_constraints.tcl -notrace
        rm add_constraints.tcl
        echo -e "${GREEN}✓ Constraints added${NC}"
    else
        echo -e "${YELLOW}⚠ No constraints file found (constraints_zynq7010.xdc)${NC}"
        echo "  Design will use default constraints"
    fi
}

# Run synthesis
run_synthesis() {
    echo -e "${YELLOW}[Synthesis] Running synthesis (this may take 10-20 minutes)...${NC}"

    cat > run_synth.tcl << 'EOF'
open_project ./openwifi_z7010/openwifi_z7010.xpr

# Set synthesis strategy for area optimization (Zynq 7010 is resource-constrained)
set_property strategy {Flow_AreaOptimized_high} [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Launch synthesis
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: Synthesis failed!"
}

# Report utilization
open_run synth_1 -name synth_1
report_utilization -file ./openwifi_z7010/utilization_post_synth.rpt
report_timing_summary -file ./openwifi_z7010/timing_post_synth.rpt

close_project
EOF

    vivado -mode batch -source run_synth.tcl -notrace

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Synthesis failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Synthesis completed successfully${NC}"

    # Display resource utilization
    if [ -f "$PROJECT_DIR/utilization_post_synth.rpt" ]; then
        echo -e "${BLUE}Resource Utilization (Post-Synthesis):${NC}"
        grep -A 10 "Slice Logic Distribution" "$PROJECT_DIR/utilization_post_synth.rpt" | head -15
    fi
}

# Run implementation
run_implementation() {
    echo -e "${YELLOW}[Implementation] Running place and route (this may take 15-30 minutes)...${NC}"

    cat > run_impl.tcl << 'EOF'
open_project ./openwifi_z7010/openwifi_z7010.xpr

# Set implementation strategy for area optimization
set_property strategy {Area_Explore} [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

# Launch implementation
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation failed!"
}

# Report results
open_run impl_1
report_utilization -file ./openwifi_z7010/utilization_post_impl.rpt
report_timing_summary -file ./openwifi_z7010/timing_post_impl.rpt
report_power -file ./openwifi_z7010/power_post_impl.rpt

close_project
EOF

    vivado -mode batch -source run_impl.tcl -notrace

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Implementation failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Implementation completed successfully${NC}"

    # Display final utilization
    if [ -f "$PROJECT_DIR/utilization_post_impl.rpt" ]; then
        echo -e "${BLUE}Final Resource Utilization:${NC}"
        grep -A 10 "Slice Logic Distribution" "$PROJECT_DIR/utilization_post_impl.rpt" | head -15
    fi

    # Display timing summary
    if [ -f "$PROJECT_DIR/timing_post_impl.rpt" ]; then
        echo -e "${BLUE}Timing Summary:${NC}"
        grep -A 5 "Design Timing Summary" "$PROJECT_DIR/timing_post_impl.rpt" | head -10
    fi
}

# Generate bitstream
generate_bitstream() {
    echo -e "${YELLOW}[Bitstream] Generating bitstream...${NC}"

    cat > gen_bit.tcl << 'EOF'
open_project ./openwifi_z7010/openwifi_z7010.xpr

# Launch bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

close_project
EOF

    vivado -mode batch -source gen_bit.tcl -notrace

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Bitstream generation failed${NC}"
        exit 1
    fi

    # Find and copy bitstream
    BITSTREAM=$(find $PROJECT_DIR -name "*.bit" | grep impl_1 | head -1)
    if [ -f "$BITSTREAM" ]; then
        cp "$BITSTREAM" ./system_top.bit
        echo -e "${GREEN}✓ Bitstream generated: system_top.bit${NC}"
        ls -lh system_top.bit
    else
        echo -e "${RED}Error: Bitstream file not found${NC}"
        exit 1
    fi

    # Export hardware definition
    echo -e "${YELLOW}[Export] Exporting hardware definition (XSA)...${NC}"
    cat > export_hw.tcl << 'EOF'
open_project ./openwifi_z7010/openwifi_z7010.xpr
open_run impl_1
write_hw_platform -fixed -force -file ./system_top.xsa
close_project
EOF

    vivado -mode batch -source export_hw.tcl -notrace

    if [ -f "./system_top.xsa" ]; then
        echo -e "${GREEN}✓ Hardware definition exported: system_top.xsa${NC}"
    fi
}

# Display summary
show_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}FPGA Build Summary${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Project: $PROJECT_NAME"
    echo "Part: $BOARD_PART"
    echo ""

    if [ -f "system_top.bit" ]; then
        echo -e "${GREEN}✓ Bitstream: system_top.bit ($(ls -lh system_top.bit | awk '{print $5}'))${NC}"
    fi

    if [ -f "system_top.xsa" ]; then
        echo -e "${GREEN}✓ Hardware Definition: system_top.xsa${NC}"
    fi

    echo ""
    echo "Reports available in: $PROJECT_DIR/"
    echo "  - utilization_post_synth.rpt"
    echo "  - utilization_post_impl.rpt"
    echo "  - timing_post_impl.rpt"
    echo "  - power_post_impl.rpt"
    echo ""
    echo "Next steps:"
    echo "  1. Review timing report to ensure design meets timing"
    echo "  2. Use system_top.xsa to generate BOOT.BIN"
    echo "  3. Create device tree using exported hardware"
    echo ""
}

# Main build flow
main() {
    local command=${1:-all}

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}FPGA Build for Zynq 7010 PlutoSDR${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    check_vivado
    check_ip_repo

    case "$command" in
        clean)
            clean_project
            ;;
        create)
            create_project
            add_constraints
            ;;
        synth)
            if [ ! -d "$PROJECT_DIR" ]; then
                create_project
                add_constraints
            fi
            run_synthesis
            ;;
        impl)
            if [ ! -d "$PROJECT_DIR" ]; then
                create_project
                add_constraints
                run_synthesis
            fi
            run_implementation
            ;;
        bit)
            if [ ! -d "$PROJECT_DIR" ]; then
                create_project
                add_constraints
                run_synthesis
                run_implementation
            fi
            generate_bitstream
            show_summary
            ;;
        all)
            clean_project
            create_project
            add_constraints
            run_synthesis
            run_implementation
            generate_bitstream
            show_summary
            ;;
        *)
            echo "Usage: $0 [clean|create|synth|impl|bit|all]"
            echo ""
            echo "Commands:"
            echo "  clean  - Remove previous project"
            echo "  create - Create Vivado project"
            echo "  synth  - Run synthesis"
            echo "  impl   - Run implementation"
            echo "  bit    - Generate bitstream"
            echo "  all    - Complete build flow (default)"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}Build step '$command' completed successfully!${NC}"
}

# Run main
main "$@"
