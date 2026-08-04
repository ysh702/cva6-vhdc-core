# VV35 standalone HDEC post-route implementation report

## Scope

- Branch and RTL checkpoint: `VV35@ba053f51f26c2be318626ab27a3d830cc5d32a44`.
- Tool: Vivado 2024.2.
- Device: `xc7z020clg400-2`.
- Top: standalone `hdec_top`, out of context.
- Clock constraint: 5.000 ns, 200 MHz.
- The RTL under `core/hdec/rtl/**` was not modified.

This report measures the physical implementation of the same HDEC shared
execution structure.  Placement, routing and power-estimation strategy are
implementation evidence, not additional HDEC innovations.

## Matched implementation probes

| Probe | Clock methodology | Physical strategy | Logic LUT | FF | BRAM | DSP | Internal reg-to-reg WNS | Estimated Fmax |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Default OOC route | `HD.CLK_SRC` absent | default place and route | 4688 | 1513 | 4 | 0 | -0.254 ns | 190.331 MHz |
| Corrected route | `BUFGCTRL_X0Y0`, verified legal on the target part | default place, `phys_opt Explore`, `route Explore` | 4694 | 1513 | 4 | 0 | -0.054 ns | 197.863 MHz |
| Bounded timing repair | same corrected clock model | post-route `phys_opt AggressiveExplore`, `route AggressiveExplore` | 4694 | 1513 | 4 | 0 | **+0.042 ns** | **201.694 MHz** |

The default result is retained as an implementation-strategy control, but it is
not the preferred timing result because the missing OOC clock source prevents
clock-delay and skew estimation.  The bounded post-route repair closes the
5 ns internal timing requirement without changing RTL or resource counts.

The final routed checkpoint is:

`reports/hdec/vv35_eval_postroute_repair_20260803/dcp/02_postroute_repaired.dcp`

The route-status report records 5642 fully routed nets and zero nets with
routing errors.

## Vectorless post-route power estimate

| Activity source | Total on-chip | Dynamic | Device static | Vivado confidence |
|---|---:|---:|---:|---|
| Vectorless propagation | 0.312 W | 0.206 W | 0.106 W | Medium |

This is only a tool-driven, vectorless estimate.  It is suitable for checking
that the routed checkpoint can be analyzed, but it is not evidence for the
serial-versus-interleaved workload power or energy claim.  That comparison must
reuse this exact DCP with matched serial and interleaved SAIF windows.

## OOC interpretation boundary

The standalone core intentionally has no package pin allocation.  Vivado
therefore reports missing `HD.PARTPIN_LOCS` and missing input/output delay
methodology warnings.  Port-to-register and register-to-port delays are not
package-accurate.  The timing claim in this report is limited to internal
sequential-to-sequential paths.

The final DRC report contains warnings rather than errors:

- 20 `REQP-1839` warnings because asynchronously reset registers drive RAMB36
  address or control pins.  This is a real implementation warning to review in
  a future RTL-optimization decision, not something hidden by the flow.
- one `ZPS7-1` warning because the standalone OOC HDEC core is not a complete
  Zynq processing-system design.
- `TIMING-18` warnings for top-level input/output delays, which remain outside
  the standalone core boundary.

No arbitrary physical I/O placement was added to suppress these warnings.

## Reproduction

Initial route:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv35_eval/run_vv35_impl.ps1 `
  -OutRoot reports/hdec/vv35_eval_route_probe_20260803
```

Methodology-corrected implementation:

```powershell
E:\Vivado\Vivado\2024.2\bin\vivado.bat -mode batch -notrace `
  -source scripts/hdec/vv35_eval/vv35_impl_route_timing.tcl -tclargs `
  <repo_root> reports/hdec/vv35_eval_route_timing_20260803 `
  5.0 vv35_postroute_timing BUFGCTRL_X0Y0
```

Bounded timing repair:

```powershell
E:\Vivado\Vivado\2024.2\bin\vivado.bat -mode batch -notrace `
  -source scripts/hdec/vv35_eval/vv35_postroute_timing_repair.tcl -tclargs `
  reports/hdec/vv35_eval_route_timing_20260803/dcp/05_route.dcp `
  reports/hdec/vv35_eval_postroute_repair_20260803 `
  5.0 vv35_postroute_repair
```
