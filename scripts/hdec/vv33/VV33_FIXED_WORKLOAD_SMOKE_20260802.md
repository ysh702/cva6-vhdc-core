# VV33 fixed-workload smoke evidence

## Scope

This is a two-episode compile and functional smoke test of the fixed-workload
infrastructure.  It is neither the traceable 46-episode result nor the formal
168-episode equal-work result and must not be used as the final Chapter V
performance claim.

## Work-normalization correction

The smoke run measures 1748 standalone HDC cycles for two episodes, exactly
874 cycles per episode.  Therefore the originally requested 46 episodes are
40204 HDC cycles and are not equal to a 146908-cycle PMUL.  The 46-episode
`full` suite is retained only for traceability.  The new `equalized` suite uses
168 episodes, the nearest integer to `146908 / 874 = 168.087`, corresponding to
146832 nominal HDC cycles.  Every formal compare manifest recomputes these
values from that run's measured standalone HDC and PMUL cycles.

The matched input is one replayable legal K-233 scalar:

```text
K = 0000000969da65ff09180fbadde7e12df457f88ab12db156c503ca75243293a3
Hamming weight = 118
```

The timed HDC workload performs 16 compute instructions per episode:

```text
HCNTCLR
4 x (HPERM, HBIND, HCNTADD)
HCNTCLIP
HSIM
HMATCH
```

One random base hypervector is preloaded before timing.  Four distinct legal
four-bit-aligned rotations create the encoded training samples in each episode.
No host VRF load or result read occurs in the timed interval.  The two smoke
episodes produced different expected similarity scores, 450 and 452.

## Matched result

| Metric | Strict serial | Interleaved |
|---|---:|---:|
| HDC episodes | 2 | 2 |
| HDC compute instructions | 32 | 32 |
| Standalone HDC cycles | 1748 | 1748 |
| PMUL wall cycles | 146908 | 148568 |
| Mixed wall cycles | 148660 | 148572 |
| Data-bearing overlap cycles | 0 | 44 |
| Control-overlap cycles | 0 | 758 |
| Matrix/XOR0/payload conflicts | 0 | 0 |
| VRF read/write conflicts | 0 | 0 |
| Unknown writes or responses | 0 | 0 |
| Function result | PASS | PASS |

The interleaved run saves 88 mixed wall cycles, 0.0592% of the strict serial
wall time.  It closes 5.02% of the 1752-cycle serial-to-ideal gap for this small
smoke workload.  However, PMUL wall time increases by 1660 cycles.  Therefore
the engineering smoke passes, while the scheduling-method evidence gate is
`NOT_MET`.

## Correctness issue exposed and repaired

An earlier smoke run showed the first concurrent episode returning 455 instead
of the golden score 450.  The pre-existing background protocol could accept
HCNTCLR before PMUL completed.  When PMUL ended during the episode, the live
counter address basis changed.  The RTL now latches the background epoch when
HCNTCLR is accepted.  Recompilation with this fix restored both episode scores
without introducing a resource conflict.

The strict serial test also waits for PMUL completion before presenting the
first HDC request.  Disabling `VV33_FINE_INTERLEAVE` alone is not a strict
serial reference because the older background protocol still contains coarse
yield points.

## Evidence files

- Strict serial manifest:
  `tmp/hdec_logs/vv33/fixed_smoke_serial_agent_c/run_manifest.json`
- Strict serial XSim log:
  `tmp/hdec_logs/vv33/fixed_smoke_serial_agent_c/xsim_fixed_workload_serial/xsim.log`
- Interleaved manifest:
  `tmp/hdec_logs/vv33/fixed_smoke_interleaved_agent/run_manifest.json`
- Interleaved XSim log:
  `tmp/hdec_logs/vv33/fixed_smoke_interleaved_agent/xsim_fixed_workload_interleaved/xsim.log`

The recompilation used the following `hdec_top.sv` SHA-256:

```text
de33f8413d311c6e1c5e1d3f5ae863583f1c62dee67014067261839d9e8e59ce
```

## Formal-run rule

Both the traceable 46-episode `full` run and the 168-episode `equalized` run
must use one frozen RTL hash for their serial and interleaved elaborations.
The runner records the hash before and after the pair and fails if it changes.
The Chapter V evidence gate requires all of the following:

- correct PMUL and all 46 HDC episodes;
- zero matrix, XOR0, payload, and VRF conflicts;
- at least one data-bearing overlap event;
- no standalone HDC cycle change;
- no PMUL cycle increase;
- at least 5% reduction in fixed-workload mixed wall cycles.

Functional PASS without these measured conditions remains engineering evidence,
not a validated scheduling-method result.
