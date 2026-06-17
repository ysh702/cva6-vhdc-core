# V47 ECC area share recheck

Date: 2026-06-17

This note rechecks whether V47 accidentally charged HDC/shared hardware to ECC-exclusive area.

## Main correction

The earlier V47 number, about 1246 LUT-equivalent resources, should be read as:

> ECC-named top-level private logic plus ECC product scratch.

It should not be described as pure ECC compute-operator area.

After checking the synthesized cells, there is no large HDC datapath block inside the `ecc_exclusive_*` buckets. The bigger issue is wording: some ECC-named logic is address/control glue that drives shared VRF/lane resources. That glue is ECC-owned control, but it is not an ECC-only compute operator.

## Hardware that HDC uses and must not be charged to ECC

These resources are shared by design and should stay outside ECC-exclusive accounting:

| Resource | Why it is not ECC-exclusive | V47 bucket treatment |
| --- | --- | --- |
| BRAM VRF `i_vrf` | HDC and ECC both read/write vector rows through it | shared VRF |
| lane container `gen_lane[*].i_lane` | HDC uses lane XOR/popcount/shift/clip/counter paths; ECC also uses lane-resident paths | shared lane |
| HDC uop pipeline `uop_p0/uop_p2/uop_p3` | ECC point-add schedules HBIND-like work through the same HDC pipeline | HDC/host control, not ECC |
| `lane_result_q` writeback path | HDC HBIND/HPERM/HCNTADD and ECC-triggered shared ops write through it | HDC/shared, not ECC |
| `hperm_spread` / `hspread` path | HDC HPERM/HSPREAD and ECC square/reduce both use spread behavior | shared shift/spread |
| VRF request and write-enable path | HDC and ECC both arbitrate into the same VRF address/write ports | shared VRF top control |
| HDC source staging such as `hdc_src0_q` | used by HDC pipeline and also referenced by ECC reduce input packing | HDC/host or unattributed, not ECC |
| popcount/clip/shift/counter blocks | HDC operators, not ECC-private | shared/HDC buckets |

A direct keyword check over the current `ecc_exclusive_*` buckets for shared/HDC names (`uop`, `hperm`, `hspread`, `hdc`, `vrf`, `lane_result`, `pop`, `bool`, `hcnt`, `hbind`, `hsim`, `hmatch`, `clip`, `shift`) found no matching cells. So the current bucket script is not obviously charging these shared datapaths to ECC.

## ECC-named logic that should be described more carefully

Within `ecc_exclusive_mul_reduce_datapath`, the cells split roughly as follows:

| Subcategory | LUT cells | FF cells | Better wording |
| --- | ---: | ---: | --- |
| `ecc_diag32_pipe` | 551 | 32 | ECC-only diagonal result staging |
| `ecc_leaf*` | 345 | 322 | ECC-only leaf/partial-product state |
| `ecc_src/ecc_dst/ecc_acc` | 76 | 18 | ECC address/control glue into shared VRF/lane |
| `ecc_fold/ecc_autoreduce/kpd` | 16 | 5 | ECC fold/reduce mode control |
| other ECC-named mul/reduce | 12 | 5 | small ECC control residue |

The `ecc_src/ecc_dst/ecc_fold/ecc_autoreduce/kpd` group is not HDC-used hardware, but it is also not a standalone ECC arithmetic operator. It should be separated when telling the story:

- ECC private compute/storage: diagonal pipe, leaf/product state, product scratch, point-multiply/inversion scheduler.
- ECC interface/control glue: ECC addresses and mode bits that steer shared VRF/lane resources.
- Shared infrastructure: VRF, lanes, HDC uop pipeline, HSPREAD/HPERM path.

## Revised reading of the number

Original strict ECC-named estimate:

- ECC named LUT cells: 1343
- normalized ECC logic LUT: about 1118
- plus physical product scratch LUTRAM: 128
- total: about 1246 LUT-equivalent, about 21.5% of total LUT

If the small ECC interface/control glue is not counted as "ECC private compute operator" area:

- subtract `ecc_src/ecc_dst/ecc_fold/ecc_autoreduce/kpd` glue: 92 LUT cells and 23 FF
- normalized ECC private compute/storage LUT-equivalent becomes about 1170
- ratio becomes about 20.2% of total LUT
- FF becomes 433, about 25.3% of total FF

So the corrected conclusion is:

> The earlier 21.5% is a conservative ECC-named top-level burden, not pure ECC compute area. The HDC/shared datapaths are already mostly excluded. A better story is that ECC's remaining non-shared burden is about 20% LUT-equivalent, dominated by ECC diagonal/leaf/product scratch and point-multiply scheduling, while shared VRF/lane/HDC uop resources should not be charged to ECC.

## Implication for the next optimization

The next area target should not be VRF or lane ownership. Those are already shared in the accounting.

The next target should be:

1. shrink or remove `ecc_product_pair`;
2. reduce `ecc_diag32_pipe` and `ecc_leaf*` staging;
3. compress point-multiply/inversion schedule state;
4. keep ECC address/mode glue small, but do not confuse it with arithmetic operator area.
