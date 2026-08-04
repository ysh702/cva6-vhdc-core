#!/usr/bin/env bash
# Copy to env.local.sh and fill paths for the laboratory installation.

export HDEC_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export HDEC_ASIC_OUT="$HDEC_REPO_ROOT/out/hdec_vv35_asic"

# Synopsys executables. Override if the installation uses wrapper names.
export DC_SHELL_BIN=dc_shell
export VCS_BIN=vcs
export VCD2SAIF_BIN=vcd2saif

# A Tcl list of standard-cell .db files used for mapping. SRAM macro .db files
# normally belong in HDEC_LINK_LIBS but not HDEC_TARGET_LIBS. Example only:
export HDEC_TARGET_LIBS="/pdk/lib/slow.db"
export HDEC_LINK_LIBS="/pdk/lib/slow.db"
export HDEC_CELL_MODELS="/pdk/verilog/slow_cells.v"
export HDEC_OPERATING_CONDITION=""

export HDEC_PERIOD_NS=5.000
export HDEC_CLOCK_UNCERTAINTY_NS=0.100
export HDEC_INPUT_DELAY_NS=0.500
export HDEC_OUTPUT_DELAY_NS=0.500
export HDEC_INPUT_TRANSITION_NS=0.100
# Value is interpreted in the capacitance unit reported by DC report_units.
export HDEC_OUTPUT_LOAD=0.010
export HDEC_MAX_TRANSITION_NS=0.500
export HDEC_MAX_FANOUT=32

# Required only for SRAM_MACRO_VRF. The adapter must define hdec_vrf_64x256.
export HDEC_SRAM_ADAPTER_RTL=""
export HDEC_SRAM_MACRO_NAME=""

# The frozen bundle is shared with FPGA and board tests.
export HDEC_VECTOR_DIR="$HDEC_REPO_ROOT/verif/hdec/vv35_eval/common/vectors/frozen_lab_20260803"
# Normally auto-detected from the converted SAIF. Set only if the installed
# converter uses an unusual hierarchy.
export HDEC_SAIF_INSTANCE_OVERRIDE=""
