# VV35 strict name-based primitive attribution from a FULL hdec_top DCP.
#
# This is a measurement-only audit.  The ECC-private result is deliberately
# labelled a lower bound: logic that Vivado merges into shared or unnamed
# top-level equations remains in shared/unattributed buckets and is never
# charged to ECC by inference.
#
# Usage:
#   vivado -mode batch \
#     -source scripts/hdec/vv35_eval/area/vv35_ecc_private_bucket_from_dcp.tcl \
#     -tclargs <full_dcp> <out_dir> ?sample_limit?
#
# A routed DCP is strongly preferred.  It enables the physical-LUT lower bound
# used by the paper.  A synthesis DCP remains supported for the primitive-name
# census, but cannot establish physical packing ownership.
#
# Outputs:
#   leaf_cells.csv       every primitive cell, including its audit reason
#   bucket_summary.csv   primitive counts for the four ownership buckets
#   physical_lut_sites.csv routed LOC/BEL packing and ownership decision
#   physical_lut_summary.csv strict ECC-only physical-LUT lower bound
#   bucket_samples.txt   representative cells for manual inspection
#   classification_rules.txt exact whitelist precedence and claim boundary
#   attribution_meta.txt checkpoint/design metadata and claim boundary

if {$argc < 2 || $argc > 3} {
    error "Expected: <full_dcp> <out_dir> ?sample_limit?"
}

set full_dcp     [file normalize [lindex $argv 0]]
set out_dir      [file normalize [lindex $argv 1]]
set sample_limit 16
if {$argc == 3} {
    set sample_limit [lindex $argv 2]
    if {![string is integer -strict $sample_limit] || $sample_limit < 1} {
        error "sample_limit must be a positive integer"
    }
}

if {![file isfile $full_dcp]} {
    error "FULL checkpoint does not exist: $full_dcp"
}
file mkdir $out_dir

proc csv_quote {value} {
    set escaped [string map [list "\"" "\"\""] $value]
    return "\"$escaped\""
}

proc safe_property {property object {default ""}} {
    if {[catch {set value [get_property $property $object]}]} {
        return $default
    }
    if {$value eq ""} {
        return $default
    }
    return $value
}

proc write_text {path value} {
    set fh [open $path w]
    puts -nonewline $fh $value
    close $fh
}

# Return {ownership_bucket detail_bucket reason}.
# Precedence matters.  The HDC-only counter/clip children inside i_vec are
# removed before the remaining i_vec fabric is assigned to the shared bucket.
proc classify_primitive {cell_name ref_name} {
    set n [string tolower "$cell_name $ref_name"]

    # Explicit HDC-private children embedded in the otherwise shared payload.
    if {[regexp {(^|/)i_vec/.*/i_cnt_array(/|$)|(^|/)i_vec/.*/i_clip(/|$)} $n]} {
        return [list hdc_private hdc_counter_clip "named HDC-only counter or clip child under i_vec"]
    }

    # Physical structures used by both HDC and ECC.  Shared hierarchy takes
    # precedence over signal names such as ecc_* on its input/output nets.
    if {[regexp {(^|/)i_vrf(/|$)|hdec_vrf_64x256} $n]} {
        return [list shared shared_vrf "shared 4-bank vector register file hierarchy"]
    }
    if {[regexp {(^|/)i_vec(/|$)|hdec_vector_payload_4x64|hdec_gf2_contribution_row_tile_8x32|hdec_xor1_shared_8x32} $n]} {
        return [list shared shared_matrix_reduction_payload "shared bit-matrix, POPCOUNT, XOR, or payload hierarchy"]
    }
    if {[regexp {hdc_src0|vec_payload|vec_popcount|xor0_field_packet|vv33_|pair_active|pair_ready|pair_resp} $n]} {
        return [list shared shared_cross_task_state_control "named shared state, payload, or cross-task scheduling logic"]
    }
    if {[regexp {vrf_(ra|rd|we|wa|wd)|vaddr|bank_ra|bank_we|bank_wa|bank_wdata} $n]} {
        return [list shared shared_vrf_top_control "top-level shared VRF address or access control"]
    }
    if {[regexp {(^|/)(st_q|op_q|a_q|res_q|ready_o|valid_o|busy_o|state_o)(_|\[|/|$)} $n]} {
        return [list shared shared_host_control "common request, response, or main-state control"]
    }

    # Strict ECC-private names in the VV35 hdec_top.  These cover the PMUL job
    # controller, field-operation state, private operands/scratch, square and
    # fused diagonal-to-modular-contribution logic.  They intentionally do not
    # absorb unnamed equations or anything already assigned to shared logic.
    if {[regexp {ecc_pmul|ecc_job|ecc_inv|ecc_sqr|ecc_square} $n]} {
        return [list ecc_private_strict ecc_pmul_inv_square "named ECC PMUL, inversion, or square logic"]
    }
    if {[regexp {ecc_leaf|ecc_diag|ecc_kpd|ecc_fold|ecc_reduce|ecc_direct_reduce|ecc_product|ecc_bitmatrix|lane_ecc} $n]} {
        return [list ecc_private_strict ecc_mul_fold_mapping "named ECC leaf, diagonal, product, fold, or contribution mapping logic"]
    }
    if {[regexp {ecc_src|ecc_dst|ecc_acc|ecc_autoreduce|ecc_raw_product|ecc_mac|ecc_kernel|ecc_partial|ecc_pipe} $n]} {
        return [list ecc_private_strict ecc_field_state_control "named ECC field-operation state or control"]
    }
    if {[regexp {xor0_contribution_packet} $n]} {
        return [list ecc_private_strict ecc_mod_contribution_mapper "ECC modular-contribution generation before shared XOR0"]
    }
    if {[regexp {(^|/)ecc_} $n]} {
        return [list unattributed unattributed_ecc_named_not_whitelisted "ECC-like name not admitted by the strict private whitelist"]
    }

    # HDC-private paths.  hdc_src0 is excluded above because VV35 also uses it
    # at the shared HDC/ECC boundary.
    if {[regexp {hmatch|hsim|hbind|hperm|hcnt|hclip|cnt_|clip_|clr_|group_dist} $n]} {
        return [list hdc_private hdc_named_operation "named HDC operation or private state"]
    }
    if {[regexp {uop_p[0-9]|p[0-9]_lane|hperm_stage|hperm_word|hperm_lane} $n]} {
        return [list hdc_private hdc_pipeline_control "named HDC micro-operation or permutation pipeline"]
    }

    return [list unattributed unattributed_synthesized "no ownership inferred from retained VV35 primitive name"]
}

# Map each primitive into the resource classes requested for this audit.  SRL
# primitives are reported separately as well as included in lutram_cells,
# matching Vivado's broader "LUT as Memory" interpretation without hiding the
# distinction from distributed RAM.
proc primitive_resource {ref_name} {
    set r [string toupper $ref_name]
    if {[regexp {^LUT[1-6](_2)?$} $r]} {
        return logic_lut
    }
    if {[regexp {^FD} $r]} {
        return ff
    }
    if {[regexp {^RAMB(18|36)} $r]} {
        return bram
    }
    if {[regexp {^RAM(16|32|64|128|256|512)|^RAMD|^RAMS} $r]} {
        return lutram
    }
    if {[regexp {^SRL} $r]} {
        return srl
    }
    if {[regexp {^CARRY[48]$} $r]} {
        return carry
    }
    if {[regexp {^MUXF[7-9]$} $r]} {
        return mux
    }
    if {[regexp {^DSP} $r]} {
        return dsp
    }
    return other
}

proc increment {array_name key {amount 1}} {
    upvar $array_name values
    if {![info exists values($key)]} {
        set values($key) 0
    }
    incr values($key) $amount
}

open_checkpoint $full_dcp

set design_name [safe_property NAME [current_design] "unknown"]
set top_name    [safe_property TOP [current_design] $design_name]
set part_name   [safe_property PART [current_design] "unknown"]
set design_mode [safe_property DESIGN_MODE [current_design] "unknown"]

if {![regexp -nocase {hdec_top} "$design_name $top_name"]} {
    close_design
    error "Checkpoint is not a FULL hdec_top design: design=$design_name top=$top_name"
}

report_utilization -file [file join $out_dir "full_utilization.rpt"]
report_utilization -hierarchical -file [file join $out_dir "full_utilization_hierarchical.rpt"]

set rules_text ""
append rules_text "CLAIM_SCOPE=strict_name_based_ecc_private_lower_bound\n"
append rules_text "ECC_PRIVATE_RESULT_IS_A_LOWER_BOUND=1\n"
append rules_text "METRIC=LUT/FF/LUTRAM/BRAM/DSP/CARRY/MUX primitive-cell census\n"
append rules_text "DENOMINATOR_RULE=Use full_utilization.rpt for physical Logic-LUT area; do not call primitive counts placed Logic LUTs.\n"
append rules_text "ROUTE_PHYSICAL_RULE=Group A5LUT/A6LUT, B5LUT/B6LUT, and equivalent BEL pairs by LOC plus BEL letter. Count one ECC-private physical LUT only when every logic-LUT cell in that group is strict ECC-private.\n"
append rules_text "ROUTE_MIXED_EXCLUSION=A physical LUT co-located with shared, HDC-private, or unattributed logic is excluded from the ECC-private physical count.\n"
append rules_text "PRECEDENCE_1=Named HDC-only i_vec counter/clip children -> hdc_private.\n"
append rules_text "PRECEDENCE_2=Shared VRF, bit-matrix/reduction/payload hierarchy, hdc_src0, common payload/state, VV33 cross-task control, VRF control, and host control -> shared, even if an absorbed cell retains an ecc-like signal name.\n"
append rules_text "ECC_WHITE_1=ecc_pmul|ecc_job|ecc_inv|ecc_sqr|ecc_square -> ECC PMUL/inversion/square private logic.\n"
append rules_text "ECC_WHITE_2=ecc_leaf|ecc_diag|ecc_kpd|ecc_fold|ecc_reduce|ecc_direct_reduce|ecc_product|ecc_bitmatrix|lane_ecc -> ECC multiply/fold/mapping private logic.\n"
append rules_text "ECC_WHITE_3=ecc_src|ecc_dst|ecc_acc|ecc_autoreduce|ecc_raw_product|ecc_mac|ecc_kernel|ecc_partial|ecc_pipe -> ECC field state/control.\n"
append rules_text "ECC_WHITE_4=xor0_contribution_packet outside shared hierarchy -> ECC modular-contribution mapper.\n"
append rules_text "ECC_EXCLUSION=Any other ecc-like name is unattributed; unnamed or synthesis-merged equations are never inferred as ECC-private.\n"
append rules_text "UNATTRIBUTED=All primitives not proved shared, HDC-private, or ECC-private by the ordered rules.\n"
write_text [file join $out_dir "classification_rules.txt"] $rules_text

array set ownership_counts {}
array set detail_counts {}
array set ref_counts {}
array set samples {}
array set physical_cells {}
array set physical_owners {}
array set physical_loc {}
array set physical_letter {}
set unplaced_logic_lut_cells 0

set leaf_path [file join $out_dir "leaf_cells.csv"]
set leaf_fh [open $leaf_path w]
puts $leaf_fh "claim_scope,ownership_bucket,detail_bucket,resource_class,ref_name,cell_name,parent_name,classification_reason"

set primitive_cells [lsort -dictionary [get_cells -hierarchical -quiet -filter {IS_PRIMITIVE == 1}]]
foreach cell $primitive_cells {
    set cell_name [safe_property NAME $cell $cell]
    set ref_name  [safe_property REF_NAME $cell "UNKNOWN"]
    set parent_name [file dirname $cell_name]

    lassign [classify_primitive $cell_name $ref_name] ownership detail reason
    set resource [primitive_resource $ref_name]

    increment ownership_counts "$ownership,total_primitives"
    increment ownership_counts "$ownership,$resource"
    if {$resource eq "srl"} {
        increment ownership_counts "$ownership,lutram_including_srl"
    } elseif {$resource eq "lutram"} {
        increment ownership_counts "$ownership,lutram_including_srl"
    }
    increment detail_counts "$ownership,$detail,$resource"
    increment detail_counts "$ownership,$detail,total_primitives"
    increment ref_counts "$ownership,$ref_name"

    # Routed 7-series LUT packing audit.  A5LUT/A6LUT occupy the same physical
    # A LUT, and likewise for B/C/D.  Count the physical resource only after all
    # logical LUT cells sharing that LOC+letter have been classified.
    if {$resource eq "logic_lut"} {
        set loc [safe_property LOC $cell ""]
        set bel [safe_property BEL $cell ""]
        if {$loc ne "" && [regexp {([A-H])[56]LUT$} $bel -> lut_letter]} {
            set physical_key "$loc/$lut_letter"
            if {![info exists physical_cells($physical_key)]} {
                set physical_cells($physical_key) {}
                set physical_loc($physical_key) $loc
                set physical_letter($physical_key) $lut_letter
            }
            lappend physical_cells($physical_key) $cell_name
            set physical_owners($physical_key,$ownership) 1
        } else {
            incr unplaced_logic_lut_cells
        }
    }

    set sample_count_key "$ownership,$detail,sample_count"
    if {![info exists detail_counts($sample_count_key)]} {
        set detail_counts($sample_count_key) 0
    }
    if {$detail_counts($sample_count_key) < $sample_limit} {
        incr detail_counts($sample_count_key)
        set sample_index $detail_counts($sample_count_key)
        set samples($ownership,$detail,$sample_index) "$ref_name,$cell_name"
    }

    set row [list \
        "strict_name_based_ecc_private_lower_bound" \
        $ownership $detail $resource $ref_name $cell_name $parent_name $reason]
    set quoted {}
    foreach value $row {
        lappend quoted [csv_quote $value]
    }
    puts $leaf_fh [join $quoted ","]
}
close $leaf_fh

# A physical LUT is strict ECC-private only if every logical LUT cell packed
# into that LOC+letter group is classified ecc_private_strict.  Mixed packing
# is excluded rather than proportionally allocated.
array set physical_summary_counts {}
set physical_fh [open [file join $out_dir "physical_lut_sites.csv"] w]
puts $physical_fh "claim_scope,physical_lut_key,loc,lut_letter,logical_lut_cell_count,ownership_set,physical_class,counted_ecc_private_lower_bound,logical_cell_names"
foreach physical_key [lsort -dictionary [array names physical_cells]] {
    set owners {}
    foreach ownership {ecc_private_strict shared hdc_private unattributed} {
        if {[info exists physical_owners($physical_key,$ownership)]} {
            lappend owners $ownership
        }
    }
    if {[llength $owners] == 1} {
        set physical_class "[lindex $owners 0]_only"
    } else {
        set physical_class "mixed_ownership"
    }
    set counted [expr {$physical_class eq "ecc_private_strict_only" ? 1 : 0}]
    increment physical_summary_counts total_occupied_physical_luts
    increment physical_summary_counts $physical_class
    if {$counted} {
        increment physical_summary_counts ecc_private_strict_physical_luts_lower_bound
    }
    set row [list \
        "route_physical_ecc_private_lower_bound" \
        $physical_key $physical_loc($physical_key) $physical_letter($physical_key) \
        [llength $physical_cells($physical_key)] [join $owners ";"] \
        $physical_class $counted [join $physical_cells($physical_key) ";"]]
    set quoted {}
    foreach value $row {
        lappend quoted [csv_quote $value]
    }
    puts $physical_fh [join $quoted ","]
}
close $physical_fh

set physical_available [expr {[array size physical_cells] > 0 ? 1 : 0}]
set physical_summary_fh [open [file join $out_dir "physical_lut_summary.csv"] w]
puts $physical_summary_fh "claim_scope,route_physical_available,total_occupied_physical_luts,ecc_private_strict_physical_luts_lower_bound,shared_only_physical_luts,hdc_private_only_physical_luts,unattributed_only_physical_luts,mixed_ownership_physical_luts,unplaced_logic_lut_cells"
set physical_row [list "route_physical_ecc_private_lower_bound" $physical_available]
foreach key {total_occupied_physical_luts ecc_private_strict_physical_luts_lower_bound shared_only hdc_private_only unattributed_only mixed_ownership} {
    if {[info exists physical_summary_counts($key)]} {
        lappend physical_row $physical_summary_counts($key)
    } else {
        lappend physical_row 0
    }
}
lappend physical_row $unplaced_logic_lut_cells
set quoted {}
foreach value $physical_row {
    lappend quoted [csv_quote $value]
}
puts $physical_summary_fh [join $quoted ","]
close $physical_summary_fh

set ownership_order {ecc_private_strict shared hdc_private unattributed}
set resource_order {logic_lut ff lutram srl lutram_including_srl bram dsp carry mux other total_primitives}

set summary_fh [open [file join $out_dir "bucket_summary.csv"] w]
puts $summary_fh "claim_scope,ownership_bucket,logic_lut_cells,ff_cells,lutram_cells,srl_cells,lutram_including_srl_cells,bram_cells,dsp_cells,carry_cells,mux_cells,other_primitives,total_primitives"
foreach ownership $ownership_order {
    set row [list "strict_name_based_ecc_private_lower_bound" $ownership]
    foreach resource $resource_order {
        set key "$ownership,$resource"
        if {[info exists ownership_counts($key)]} {
            lappend row $ownership_counts($key)
        } else {
            lappend row 0
        }
    }
    set quoted {}
    foreach value $row {
        lappend quoted [csv_quote $value]
    }
    puts $summary_fh [join $quoted ","]
}
close $summary_fh

set detail_fh [open [file join $out_dir "detail_bucket_summary.csv"] w]
puts $detail_fh "claim_scope,ownership_bucket,detail_bucket,logic_lut_cells,ff_cells,lutram_cells,srl_cells,bram_cells,dsp_cells,carry_cells,mux_cells,other_primitives,total_primitives"
set detail_keys {}
foreach key [array names detail_counts "*,*,total_primitives"] {
    set fields [split $key ","]
    lappend detail_keys "[lindex $fields 0],[lindex $fields 1]"
}
foreach owner_detail [lsort -unique $detail_keys] {
    lassign [split $owner_detail ","] ownership detail
    set row [list "strict_name_based_ecc_private_lower_bound" $ownership $detail]
    foreach resource {logic_lut ff lutram srl bram dsp carry mux other total_primitives} {
        set key "$ownership,$detail,$resource"
        if {[info exists detail_counts($key)]} {
            lappend row $detail_counts($key)
        } else {
            lappend row 0
        }
    }
    set quoted {}
    foreach value $row {
        lappend quoted [csv_quote $value]
    }
    puts $detail_fh [join $quoted ","]
}
close $detail_fh

set refs_fh [open [file join $out_dir "primitive_ref_summary.csv"] w]
puts $refs_fh "claim_scope,ownership_bucket,ref_name,count"
foreach key [lsort -dictionary [array names ref_counts]] {
    set comma [string first "," $key]
    set ownership [string range $key 0 [expr {$comma - 1}]]
    set ref_name [string range $key [expr {$comma + 1}] end]
    puts $refs_fh "[csv_quote strict_name_based_ecc_private_lower_bound],[csv_quote $ownership],[csv_quote $ref_name],$ref_counts($key)"
}
close $refs_fh

set samples_fh [open [file join $out_dir "bucket_samples.txt"] w]
puts $samples_fh "CLAIM_SCOPE=strict_name_based_ecc_private_lower_bound"
puts $samples_fh "ECC_PRIVATE_RESULT_IS_A_LOWER_BOUND=1"
puts $samples_fh ""
foreach ownership $ownership_order {
    puts $samples_fh "\[$ownership\]"
    set details {}
    foreach key [array names detail_counts "$ownership,*,sample_count"] {
        lappend details [lindex [split $key ","] 1]
    }
    foreach detail [lsort -unique $details] {
        puts $samples_fh "  <$detail>"
        set count_key "$ownership,$detail,sample_count"
        for {set idx 1} {$idx <= $detail_counts($count_key)} {incr idx} {
            set sample_key "$ownership,$detail,$idx"
            if {[info exists samples($sample_key)]} {
                puts $samples_fh "    $samples($sample_key)"
            }
        }
    }
    puts $samples_fh ""
}
close $samples_fh

set ecc_lut 0
set ecc_ff 0
set ecc_bram 0
set ecc_dsp 0
if {[info exists ownership_counts(ecc_private_strict,logic_lut)]} {
    set ecc_lut $ownership_counts(ecc_private_strict,logic_lut)
}
if {[info exists ownership_counts(ecc_private_strict,ff)]} {
    set ecc_ff $ownership_counts(ecc_private_strict,ff)
}
if {[info exists ownership_counts(ecc_private_strict,bram)]} {
    set ecc_bram $ownership_counts(ecc_private_strict,bram)
}
if {[info exists ownership_counts(ecc_private_strict,dsp)]} {
    set ecc_dsp $ownership_counts(ecc_private_strict,dsp)
}
set ecc_physical_lut 0
if {[info exists physical_summary_counts(ecc_private_strict_physical_luts_lower_bound)]} {
    set ecc_physical_lut $physical_summary_counts(ecc_private_strict_physical_luts_lower_bound)
}

set metadata ""
append metadata "claim_scope=strict_name_based_ecc_private_lower_bound\n"
append metadata "ecc_private_result_is_lower_bound=1\n"
append metadata "interpretation=Only primitives retaining explicit VV35 ECC-private names are charged to ECC. Shared or synthesis-merged equations are not inferred as ECC-private.\n"
append metadata "metric_scope=Primitive-cell ownership census; not placed physical Logic-LUT attribution.\n"
append metadata "physical_denominator=See full_utilization.rpt generated from the same checkpoint.\n"
append metadata "route_physical_available=$physical_available\n"
append metadata "route_physical_rule=LOC plus BEL letter; a physical LUT counts only when every packed logic-LUT cell is strict ECC-private.\n"
append metadata "checkpoint=[file normalize $full_dcp]\n"
append metadata "checkpoint_sha256=NOT_COMPUTED_BY_VIVADO_TCL\n"
append metadata "design=$design_name\n"
append metadata "top=$top_name\n"
append metadata "part=$part_name\n"
append metadata "design_mode=$design_mode\n"
append metadata "vivado_version=[version -short]\n"
append metadata "primitive_count=[llength $primitive_cells]\n"
append metadata "ecc_private_strict_logic_lut_cells=$ecc_lut\n"
append metadata "ecc_private_strict_ff_cells=$ecc_ff\n"
append metadata "ecc_private_strict_physical_luts_lower_bound=$ecc_physical_lut\n"
append metadata "ecc_private_strict_bram_cells=$ecc_bram\n"
append metadata "ecc_private_strict_dsp_cells=$ecc_dsp\n"
append metadata "ecc_private_bram_dsp_expected_zero=[expr {$ecc_bram == 0 && $ecc_dsp == 0 ? 1 : 0}]\n"
append metadata "unplaced_logic_lut_cells=$unplaced_logic_lut_cells\n"
append metadata "leaf_csv=$leaf_path\n"
write_text [file join $out_dir "attribution_meta.txt"] $metadata

close_design
puts "VV35_ECC_PRIVATE_BUCKET_PASS"
puts "CLAIM_SCOPE=strict_name_based_ecc_private_lower_bound"
puts "ROUTE_PHYSICAL_AVAILABLE=$physical_available"
puts "ECC_PRIVATE_PHYSICAL_LUT_LOWER_BOUND=$ecc_physical_lut"
puts "ECC_PRIVATE_FF_LOGICAL_CELLS=$ecc_ff"
puts "ECC_PRIVATE_BRAM_CELLS=$ecc_bram"
puts "ECC_PRIVATE_DSP_CELLS=$ecc_dsp"
puts "OUTPUT_DIR=$out_dir"
