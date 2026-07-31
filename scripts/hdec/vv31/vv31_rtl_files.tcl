# Single source of truth for VV31 RTL and verification package ordering.

proc vv31_common_packages {repo_root} {
    set common_dir [file join $repo_root "verif" "hdec" "vv31" "common"]
    set preferred [list \
        "hdec_vv31_ref_pkg.sv" \
        "hdec_vv31_vectors_pkg.sv" \
        "hdec_vv31_driver_pkg.sv" \
        "hdec_vv31_check_pkg.sv" \
        "hdec_vv31_bfm_if.sv" \
        "hdec_vv31_system_harness.sv" \
    ]
    set files [list]
    foreach name $preferred {
        set path [file join $common_dir $name]
        if {[file exists $path]} {
            lappend files $path
        }
    }
    return $files
}

proc vv31_rtl_files {repo_root} {
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

proc vv31_require_sources {files} {
    foreach path $files {
        if {![file exists $path]} {
            error "Required VV31 source does not exist: $path"
        }
    }
}
