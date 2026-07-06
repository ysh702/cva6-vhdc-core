# VV13 Diagonal Pipeline Reference Checkpoint

Date: 2026-07-06

This checkpoint is a reference implementation, not the final low-area retained version.

What is included:

- True diagonal-group on-the-fly modular reduction in `hdec_top.sv`.
- A generated fixed-coordinate diagonal reduction map.
- Two-stage scheduling that prefetches the next leaf during the current leaf tail.
- Local ECC accumulator bypass so ECC reduction packets do not route through the general `i_vec` XOR payload merge.
- Explicit pruning of the old leaf-end direct-reduce packet when `ECC_DIAG_GROUP_REDUCE=1`.

Validation already run for this checkpoint:

- `xsim_hdec_ecc_diag_reduce_map_v1`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS

Known status:

- PMUL wall cycles remain `354544`, down from the no-prefetch diagonal stage value of `392560`.
- Area is still under active optimization. The previous measured final OOC before the explicit direct-reduce prune was `5339 LUT`, `WNS=0.265 ns`, `Fmax=211.193 MHz`.
- The next step is to rerun OOC after the direct-reduce pruning and continue reducing logic until the design is below the user's area threshold.
