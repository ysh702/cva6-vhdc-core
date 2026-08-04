#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  run_vv35_asic.sh synth <REG_VRF|BLACKBOX_VRF|SRAM_MACRO_VRF>
  run_vv35_asic.sh gate <SERIAL|INTERLEAVED> <ZERO|SDF> <VRF_MODE>
  run_vv35_asic.sh power <SERIAL|INTERLEAVED> <VRF_MODE>
  run_vv35_asic.sh all <VRF_MODE>

Source env.local.sh (based on env.example.sh) before running this script.
SERIAL and INTERLEAVED always use the same mapped DDC and netlist.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
require_var() { [[ -n "${!1:-}" ]] || die "environment variable $1 is not set"; }
require_file() { [[ -f "$1" ]] || die "required file not found: $1"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "command not found: $1"; }
sha256_file() { sha256sum "$1" | awk '{print $1}'; }

action="${1:-}"
[[ -n "$action" ]] || { usage; exit 2; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${HDEC_REPO_ROOT:-$(cd "$script_dir/../../../.." && pwd)}"
out_root="${HDEC_ASIC_OUT:-$repo_root/out/hdec_vv35_asic}"
vector_dir="${HDEC_VECTOR_DIR:-$repo_root/verif/hdec/vv35_eval/common/vectors/frozen_lab_20260803}"
contract="$repo_root/verif/hdec/vv35_eval/common/workload_contract.json"
tb="$repo_root/verif/hdec/vv35_eval/asic/tb_vv35_schedule_asic.sv"
dc_synth_tcl="$script_dir/dc_synth.tcl"
dc_power_tcl="$script_dir/dc_power.tcl"

require_file "$contract"
require_file "$tb"
require_file "$vector_dir/vector_manifest.json"

normalize_vrf_mode() {
    local mode="${1^^}"
    case "$mode" in
        REG_VRF|BLACKBOX_VRF|SRAM_MACRO_VRF) printf '%s' "$mode" ;;
        *) die "invalid VRF mode: $1" ;;
    esac
}

scenario_cycles() {
    case "$1" in
        SERIAL) printf '337853' ;;
        INTERLEAVED) printf '200144' ;;
        *) die "invalid scenario: $1" ;;
    esac
}

synth_dir() { printf '%s/%s/synth' "$out_root" "${1,,}"; }
gate_dir() { printf '%s/%s/gate_%s_%s' "$out_root" "${3,,}" "${1,,}" "${2,,}"; }
power_dir() { printf '%s/%s/power_%s' "$out_root" "${2,,}" "${1,,}"; }

write_common_manifest() {
    local target="$1" scenario="${2:-NA}" mode="${3:-NA}"
    local rtl_filelist="$repo_root/verif/hdec/vv35_eval/asic/hdec_vv35_rtl.f"
    local rtl_digest
    rtl_digest="$({
        while IFS= read -r relative; do
            [[ -z "$relative" || "$relative" == \#* ]] && continue
            printf '%s\0%s\n' "$relative" "$(sha256_file "$repo_root/$relative")"
        done < "$rtl_filelist"
    } | sha256sum | awk '{print $1}')"
    mkdir -p "$target"
    {
        printf 'branch=%s\n' "$(git -C "$repo_root" branch --show-current)"
        printf 'commit=%s\n' "$(git -C "$repo_root" rev-parse HEAD)"
        printf 'tracked_dirty=%s\n' "$(test -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" && echo true || echo false)"
        printf 'untracked_count=%s\n' "$(git -C "$repo_root" ls-files --others --exclude-standard | wc -l | tr -d ' ')"
        printf 'scenario=%s\n' "$scenario"
        printf 'vrf_mode=%s\n' "$mode"
        printf 'contract_sha256=%s\n' "$(sha256_file "$contract")"
        printf 'vector_manifest_sha256=%s\n' "$(sha256_file "$vector_dir/vector_manifest.json")"
        printf 'rtl_filelist_sha256=%s\n' "$(sha256_file "$rtl_filelist")"
        printf 'rtl_bundle_sha256=%s\n' "$rtl_digest"
        printf 'gate_testbench_sha256=%s\n' "$(sha256_file "$tb")"
        printf 'runner_sha256=%s\n' "$(sha256_file "$script_dir/run_vv35_asic.sh")"
        printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$target/run_manifest.txt"
}

run_synth() {
    local mode; mode="$(normalize_vrf_mode "$1")"
    require_var HDEC_TARGET_LIBS
    require_cmd "${DC_SHELL_BIN:-dc_shell}"
    if [[ "$mode" == SRAM_MACRO_VRF ]]; then
        require_var HDEC_SRAM_ADAPTER_RTL
        require_file "$HDEC_SRAM_ADAPTER_RTL"
    fi
    local dir; dir="$(synth_dir "$mode")"
    mkdir -p "$dir"
    write_common_manifest "$dir" NA "$mode"
    export HDEC_REPO_ROOT="$repo_root"
    export HDEC_OUT_DIR="$dir"
    export HDEC_VRF_MODE="$mode"
    "${DC_SHELL_BIN:-dc_shell}" -64bit -f "$dc_synth_tcl" |& tee "$dir/dc_synth.log"
    require_file "$dir/netlist/hdec_top.ddc"
    require_file "$dir/netlist/hdec_top_mapped.v"
    require_file "$dir/netlist/hdec_top_mapped.sdf"
    printf 'ddc_sha256=%s\n' "$(sha256_file "$dir/netlist/hdec_top.ddc")" >> "$dir/run_manifest.txt"
    printf 'netlist_sha256=%s\n' "$(sha256_file "$dir/netlist/hdec_top_mapped.v")" >> "$dir/run_manifest.txt"
    printf 'sdf_sha256=%s\n' "$(sha256_file "$dir/netlist/hdec_top_mapped.sdf")" >> "$dir/run_manifest.txt"
}

run_gate() {
    local scenario="${1^^}" delay="${2^^}" mode
    mode="$(normalize_vrf_mode "$3")"
    [[ "$mode" != BLACKBOX_VRF ]] || die "BLACKBOX_VRF is area/timing only; use REG_VRF or a real SRAM macro for functional gate simulation"
    local cycles; cycles="$(scenario_cycles "$scenario")"
    [[ "$delay" == ZERO || "$delay" == SDF ]] || die "delay must be ZERO or SDF"
    require_cmd "${VCS_BIN:-vcs}"
    local synth; synth="$(synth_dir "$mode")"
    local netlist="$synth/netlist/hdec_top_mapped.v"
    local sdf="$synth/netlist/hdec_top_mapped.sdf"
    require_file "$netlist"
    [[ "$delay" == ZERO ]] || require_file "$sdf"
    local dir; dir="$(gate_dir "$scenario" "$delay" "$mode")"
    mkdir -p "$dir"
    write_common_manifest "$dir" "$scenario" "$mode"

    local -a cell_models=()
    if [[ -n "${HDEC_CELL_MODELS:-}" ]]; then
        # HDEC_CELL_MODELS is intentionally a whitespace-separated shell list.
        # Use paths without spaces, as is customary for PDK installations.
        read -r -a cell_models <<< "$HDEC_CELL_MODELS"
    fi
    ((${#cell_models[@]} > 0)) || die "HDEC_CELL_MODELS must list gate simulation models"
    local model
    for model in "${cell_models[@]}"; do require_file "$model"; done

    local -a sources=(
        "$repo_root/core/hdec/rtl/hdec_pkg.sv"
        "$repo_root/verif/hdec/vv31/common/hdec_vv31_vectors_pkg.sv"
        "$repo_root/verif/hdec/vv31/common/hdec_vv31_ref_pkg.sv"
        "$repo_root/verif/hdec/vv31/common/hdec_vv31_driver_pkg.sv"
        "$repo_root/verif/hdec/vv31/common/hdec_vv31_check_pkg.sv"
        "$netlist"
        "$tb"
    )
    for model in "${cell_models[@]}"; do sources+=("$model"); done

    pushd "$dir" >/dev/null
    local -a vcs_args=(
        -full64 -sverilog -timescale=1ns/1ps
        -top tb_vv35_schedule_gate -o simv
    )
    if [[ "$delay" == SDF ]]; then
        vcs_args+=("-sdf" "max:tb_vv35_schedule_gate.dut:$sdf")
    fi
    "${VCS_BIN:-vcs}" "${vcs_args[@]}" "${sources[@]}" |& tee vcs_compile.log
    local vcd="$dir/${scenario,,}_${delay,,}.vcd"
    local -a sim_args=(
        "+SCENARIO=$scenario"
        "+TASK_COUNT=1632"
        "+WINDOW_CYCLES=$cycles"
        "+PMUL_WAIT_CYCLES=146908"
        "+VV31_VECTOR_DIR=$vector_dir"
        "+ACTIVITY_VCD=$vcd"
    )
    ./simv "${sim_args[@]}" |& tee gate.log
    grep -Fq "[VV35:GATE_SCHEDULE] PASS scenario=$scenario" gate.log \
        || die "gate simulation did not emit the required PASS marker"
    popd >/dev/null
    require_file "$vcd"

    require_cmd "${VCD2SAIF_BIN:-vcd2saif}"
    local saif="$dir/${scenario,,}_${delay,,}.saif"
    "${VCD2SAIF_BIN:-vcd2saif}" -input "$vcd" -output "$saif" \
        |& tee "$dir/vcd2saif.log"
    require_file "$saif"
    require_cmd "${PYTHON_BIN:-python3}"
    local saif_instance
    saif_instance="$("${PYTHON_BIN:-python3}" - "$saif" <<'PY'
import re, sys
stack = []
for line in open(sys.argv[1], errors='replace'):
    m = re.search(r'\(INSTANCE\s+([^\s\)]+)', line)
    if m:
        stack.append(m.group(1))
        if m.group(1) == 'dut':
            print('/'.join(stack))
            break
else:
    raise SystemExit('unable to find dut INSTANCE in SAIF')
PY
)"
    [[ -n "$saif_instance" ]] || die "unable to determine SAIF DUT instance path"
    printf 'netlist_sha256=%s\n' "$(sha256_file "$netlist")" >> "$dir/run_manifest.txt"
    printf 'activity_vcd_sha256=%s\n' "$(sha256_file "$vcd")" >> "$dir/run_manifest.txt"
    printf 'activity_saif_sha256=%s\n' "$(sha256_file "$saif")" >> "$dir/run_manifest.txt"
    printf 'saif_instance_path=%s\n' "$saif_instance" >> "$dir/run_manifest.txt"
    printf 'cycles=%s\n' "$cycles" >> "$dir/run_manifest.txt"
}

run_power() {
    local scenario="${1^^}" mode
    mode="$(normalize_vrf_mode "$2")"
    scenario_cycles "$scenario" >/dev/null
    [[ "$mode" != BLACKBOX_VRF ]] || die "BLACKBOX_VRF excludes functional memory activity and cannot produce a complete power result"
    require_cmd "${DC_SHELL_BIN:-dc_shell}"
    local synth; synth="$(synth_dir "$mode")"
    local ddc="$synth/netlist/hdec_top.ddc"
    require_file "$ddc"
    local gate; gate="$(gate_dir "$scenario" SDF "$mode")"
    local saif="$gate/${scenario,,}_sdf.saif"
    require_file "$saif"
    local saif_instance
    saif_instance="$(awk -F= '$1=="saif_instance_path" {print $2}' "$gate/run_manifest.txt")"
    [[ -n "$saif_instance" ]] || die "SAIF instance path missing from gate manifest"
    local dir; dir="$(power_dir "$scenario" "$mode")"
    mkdir -p "$dir"
    write_common_manifest "$dir" "$scenario" "$mode"
    export HDEC_DDC="$ddc"
    export HDEC_SAIF="$saif"
    export HDEC_POWER_OUT="$dir"
    export HDEC_SCENARIO="$scenario"
    export HDEC_VRF_MODE="$mode"
    export HDEC_SAIF_INSTANCE="${HDEC_SAIF_INSTANCE_OVERRIDE:-$saif_instance}"
    "${DC_SHELL_BIN:-dc_shell}" -64bit -f "$dc_power_tcl" |& tee "$dir/dc_power.log"
    require_file "$dir/power.rpt"
    if ! grep -Fq 'audit_status=PASS' "$dir/saif_annotation_audit.rpt"; then
        die "SAIF coverage audit is unavailable; review the laboratory tool syntax before accepting power data"
    fi
    printf 'ddc_sha256=%s\n' "$(sha256_file "$ddc")" >> "$dir/run_manifest.txt"
    printf 'saif_sha256=%s\n' "$(sha256_file "$saif")" >> "$dir/run_manifest.txt"
    printf 'saif_instance_path=%s\n' "$HDEC_SAIF_INSTANCE" >> "$dir/run_manifest.txt"
}

case "$action" in
    synth)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_synth "$2"
        ;;
    gate)
        [[ $# -eq 4 ]] || { usage; exit 2; }
        run_gate "$2" "$3" "$4"
        ;;
    power)
        [[ $# -eq 3 ]] || { usage; exit 2; }
        run_power "$2" "$3"
        ;;
    all)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        mode="$(normalize_vrf_mode "$2")"
        run_synth "$mode"
        run_gate SERIAL ZERO "$mode"
        run_gate INTERLEAVED ZERO "$mode"
        run_gate SERIAL SDF "$mode"
        run_gate INTERLEAVED SDF "$mode"
        run_power SERIAL "$mode"
        run_power INTERLEAVED "$mode"
        ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
esac
