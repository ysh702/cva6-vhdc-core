proc vv30_common_packages {repo_root} {
    set common_dir [file join $repo_root "verif" "hdec" "vv30" "common"]
    return [list \
        [file join $common_dir "hdec_vv30_ref_pkg.sv"] \
        [file join $common_dir "hdec_vv30_check_pkg.sv"] \
        [file join $common_dir "hdec_vv30_vectors_pkg.sv"] \
        [file join $common_dir "hdec_vv30_driver_pkg.sv"] \
    ]
}

proc vv30_rtl_files {repo_root} {
    set rtl_dir [file join $repo_root "core" "hdec" "rtl"]
    return [list \
        [file join $rtl_dir "hdec_pkg.sv"] \
        [file join $rtl_dir "hdec_resource_pkg.sv"] \
        [file join $rtl_dir "hdec_vrf_64x256.sv"] \
        [file join $rtl_dir "hdec_lane_boolean_mask.sv"] \
        [file join $rtl_dir "hdec_lane_popcount_compressor.sv"] \
        [file join $rtl_dir "hdec_p2_pop_slice.sv"] \
        [file join $rtl_dir "hdec_cnt_array.sv"] \
        [file join $rtl_dir "hdec_lane_shift_align.sv"] \
        [file join $rtl_dir "hdec_lane_clip.sv"] \
        [file join $rtl_dir "hdec_lane_4x64.sv"] \
        [file join $rtl_dir "hdec_top.sv"] \
    ]
}

proc vv30_test_top {test_name} {
    switch -- $test_name {
        "shift_align_basis" { return "tb_vv30_shift_align_unit" }
        "fused_map_unit"    { return "tb_vv30_fused_map_unit" }
        "diag_native_map"   { return "tb_vv30_diag_native_map_unit" }
        "square_basis"      { return "tb_vv30_square_basis_unit" }
        "gfmac_tail_fusion" { return "tb_vv30_gfmac_tail_fusion" }
        "inv_redirect_contract" {
            return "tb_vv30_inv_redirect_contract"
        }
        "pmul_random_k"       { return "tb_vv30_pmul_random_k" }
        "pmul_graph_baseline" { return "tb_vv30_pmul_graph_baseline" }
        "pmul_graph_dbl_only" { return "tb_vv30_pmul_graph_dbl_only" }
        "pmul_graph_add_only" { return "tb_vv30_pmul_graph_add_only" }
        "pmul_method_base"    { return "tb_vv30_pmul_method_base" }
        "pmul_method_seed"    { return "tb_vv30_pmul_method_seed" }
        "pmul_method_factor"  { return "tb_vv30_pmul_method_factor" }
        "pmul_method_inv"     { return "tb_vv30_pmul_method_inv" }
        default { error "Unknown VV30 generic test: $test_name" }
    }
}

proc vv30_test_file {repo_root test_name} {
    set unit_dir [file join $repo_root "verif" "hdec" "vv30" "unit"]
    switch -- $test_name {
        "shift_align_basis" {
            return [file join $unit_dir "tb_vv30_shift_align_unit.sv"]
        }
        "fused_map_unit" {
            return [file join $unit_dir "tb_vv30_fused_map_unit.sv"]
        }
        "diag_native_map" {
            return [file join $unit_dir "tb_vv30_diag_native_map_unit.sv"]
        }
        "square_basis" {
            return [file join $unit_dir "tb_vv30_square_basis_unit.sv"]
        }
        "gfmac_tail_fusion" {
            return [file join $repo_root "verif" "hdec" "vv30" \
                "integration" "tb_vv30_gfmac_tail_fusion.sv"]
        }
        "inv_redirect_contract" {
            return [file join $repo_root "verif" "hdec" "vv30" \
                "integration" "tb_vv30_inv_redirect_contract.sv"]
        }
        "pmul_random_k" -
        "pmul_graph_baseline" -
        "pmul_graph_dbl_only" -
        "pmul_graph_add_only" -
        "pmul_method_base" -
        "pmul_method_seed" -
        "pmul_method_factor" -
        "pmul_method_inv" {
            return [file join $repo_root "verif" "hdec" "vv30" \
                "system" "tb_vv30_pmul_random_k.sv"]
        }
        default { error "Unknown VV30 generic test: $test_name" }
    }
}
