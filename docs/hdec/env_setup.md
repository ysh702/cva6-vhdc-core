# HDEC Development Environment Setup

## Project Overview

This project is based on CVA6 V5.2.0 with HDEC Phase 1 extensions.

Current HDEC stable baseline:

```text
1c359689 HDEC Phase1: add Add/Sub/Counter core and real badd
```

Recommended working branch:

```text
hdec-phase1
```

Remote repository:

```text
HTTPS: https://github.com/ysh702/cva6-hdec-v2.git
SSH:   git@github.com:ysh702/cva6-hdec-v2.git
```

## Toolchain Policy

Do not upload the toolchain binaries, installation directories, generated build
trees, or simulator outputs to GitHub. The repository should only record how to
install tools and how to check versions.

The RISC-V bare-metal toolchain must be available through `PATH` as:

```text
riscv64-unknown-elf-gcc
```

## Current Host Tool Versions

Recorded on the current development host:

```text
verilator --version
Verilator 5.008 2023-03-04 rev v5.008 (mod)

riscv64-unknown-elf-gcc --version
riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0

which riscv64-unknown-elf-gcc
/home/ysh/riscv_toolchain/bin/riscv64-unknown-elf-gcc

gcc --version
gcc (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0

make --version
GNU Make 4.3

python3 --version
Python 3.10.12

cmake --version
cmake version 3.22.1

ninja --version
1.10.1
```

If a command is missing on another host, install the matching package or update
`PATH` before building CVA6.

## Setup Requirements For Another Computer

Prepare an Ubuntu/Linux environment with:

- `git`
- `make`
- `gcc` and `g++`
- Python3
- Verilator, preferably matching the current host version
- RISC-V bare-metal toolchain, with `riscv64-unknown-elf-gcc` found in `PATH`
- CVA6 build dependencies required by the upstream project

If possible, keep the RISC-V toolchain path consistent with the current host:

```text
/home/ysh/riscv_toolchain/bin/riscv64-unknown-elf-gcc
```

If that exact path is not practical, ensure `PATH` prioritizes the intended
RISC-V toolchain version.

## Clone Steps

```sh
git clone git@github.com:ysh702/cva6-hdec-v2.git cva6
cd cva6
git checkout hdec-phase1
git submodule update --init --recursive
```

## Build Steps

```sh
rm -rf work-ver
make verilate NUM_JOBS=16
```

## HDEC Regression Checklist

Current HDEC tests to verify:

- `multi_index_test`
- `hclr_test`
- `bclr_test`
- `hbind_test`
- `hsim_test`
- `hperm_test`
- `badd_test`

Write build and simulation logs under:

```text
tmp/hdec_logs/
```

PASS judgment must inspect the full log. A passing run must contain a clear
success marker such as:

- `*** SUCCESS ***`
- Python `All tests PASSED`

Do not use `timeout ... | grep ...` as the only test judgment. `RUN_EXIT=124`
is acceptable only when the log already contains a clear SUCCESS marker.

## Two-Computer Collaboration Flow

Before starting work:

```sh
git checkout hdec-phase1
git pull
```

After completing a stable feature:

```sh
git add <related files>
git commit -m "clear commit message"
git push
```

On the other computer:

```sh
git pull
rm -rf work-ver
make verilate NUM_JOBS=16
```

## Do Not Commit

Do not commit generated artifacts or local-only files:

- `work-ver/`
- `tmp/hdec_logs/`
- `*.elf`
- `*.log`
- core dump files
- `verif/core-v-verif`
- temporary debug files
- unreviewed `docs/hdec/phase1_plan.md`
