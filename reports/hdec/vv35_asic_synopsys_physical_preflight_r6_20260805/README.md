# VV35 ASIC Synopsys physical-flow preflight (R6)

This directory preserves the small, decision-relevant evidence from remote LSF job `10910` on host `js09` (`2026-08-04T17:26:32Z` to `2026-08-04T17:28:24Z`). The diagnostic workflow itself completed successfully:

- `workflow_status=PASS`
- `workflow_exit_code=0`
- `diagnostic_execution_status=PASS`
- remote server assets remained unchanged (`server_roots_modified=0`)

The PASS result applies only to the scoped tool/environment audit. It is **not**
a placement-and-routing or post-layout result. The terminal physical-flow
fields are:

- `place_and_route_execution=NONE`
- `physical_flow_status=BLOCKED_NO_NATIVE_PHYSICAL_IMPLEMENTATION_SHELL`
- `place_and_route_executed=0`
- `gpdk045_used=0`

Within the defined `/data/synopsys` search and safe-probe scope, the inventory
found the Synopsys Design Compiler wrapper but no physical-implementation shell
that passed the probe. No `pt_shell` analysis runtime or StarRC extraction
runtime passed the scoped search/probe either. The `dc_shell` marker probe
returned `rc=124` (`TIMEOUT`), but that R6 marker result does not negate the
independently completed R13 DC synthesis and R16 DC power workflow. The
preceding R5 binding reported `server_writable_path_count=4`, so the safety gate
set `safe_native_parse=0`; native DB/Milkyway/NDM parsing was therefore not
executed. The resulting counts were `all_db_parse_pass_count=0`,
`milkyway_native_parse_pass_count=0`, and `lm_db_matches_setup_db=0`.

These results do not assert that no tool could exist anywhere outside the
defined search/probe scope. They establish that this audited workflow did not
identify a safely usable ICC/ICC2/Fusion Compiler/Astro/Physical
Compiler/Milkyway physical-implementation path, nor a usable PrimeTime/StarRC
analysis or extraction path. Consequently, R6 performed no native physical
implementation, routing, parasitic extraction, or post-layout timing/power
analysis.

## Evidence map

- `job_status_synopsys_r6.txt`: job identity, diagnostic scope, mutation policy, and workflow PASS.
- `synopsys_physical_conclusion_r6.txt`: final physical-flow status and the explicit no-P&R/no-GPDK45 flags.
- `selected_tools_r6.tsv`, `tool_inventory_r6.tsv`, and `shell_capability_summary_r6.tsv`: executable discovery and capability results.
- `native_db_parse_summary_r6.tsv`, `native_milkyway_parse_summary_r6.tsv`, and `native_ndm_readonly_summary_r6.tsv`: native-format parse probes.
- `starrc_runtime_summary_r6.tsv` and `rc_technology_candidates_r6.tsv`: extraction-tool and RC-technology probes.
- `r5_candidate_binding_r6.txt`: binding to the preceding R5 environment inventory.
- `server_root_immutability_r6.txt`: before/after server-root content-hash equality.
- `launcher_status_synopsys_r6.txt` and `bsub_submit_synopsys_r6.log`: submission trace.
- `synopsys_physical_key_evidence_r6.sha256`: hashes of the remote key-evidence files.
- `source_archive_files_r6.sha256`: the original full R6 archive manifest; this curated directory intentionally omits bulky low-level snapshots not required for the conclusion.
- `EVIDENCE_SHA256.txt`: locally checkable relative-path hashes for this curated
  evidence set. The downloaded source archive was independently verified as
  SHA-256
  `1fc37dce954dfa616f4ad43ceeba15882cbc8c0e1a5fe12c07cb59e6bfe8d49a`.

For ASIC quantitative reporting, R6 therefore establishes only the
physical-tool boundary observed within the defined `/data/synopsys` search and
safe-probe scope. Area, timing, and activity-based power results must be labeled
by their actual analysis stage; R6 contributes no post-layout metrics.
