#include "encoding.h"
#include "vv35_board_vectors.inc"

/*
 * CVA6+HDEC board workload matching tb_vv35_schedule_gate.sv.
 *
 * Runtime controls can be patched through JTAG before entering main:
 *   vv35_run_mode     0=SERIAL, 1=INTERLEAVED, 2=CLOCKED_IDLE_SPIN
 *   vv35_batch_count  precision run=1, power run>=1
 *   vv35_marker_mmio  0 disables marker, otherwise 32-bit MMIO address
 *   vv35_pmul_wait_cycles  PMUL interval in CPU rdcycle ticks
 *
 * The marker covers only the named workload. Vector preload and final result
 * checking are outside. For batch_count>1, the first PMUL start response is
 * excluded while later batch-start responses are included; report this fixed
 * boundary overhead and divide cycles/energy by batch_count.
 */

    .macro HDEC_VADDR rd, rs1
    .insn r 0x0B, 2, 3, \rd, \rs1, zero
    .endm
    .macro HDEC_VWR64 rd, rs1
    .insn r 0x0B, 0, 2, \rd, \rs1, zero
    .endm
    .macro HDEC_VRD64 rd
    .insn r 0x0B, 1, 2, \rd, zero, zero
    .endm
    .macro HDEC_HMATCH rd, rs1
    .insn r 0x0B, 1, 3, \rd, \rs1, zero
    .endm
    .macro HDEC_ECC_STATUS rd, rs1
    .insn r 0x0B, 4, 3, \rd, \rs1, zero
    .endm

    .section .text.init
    .globl main
main:
    /* Preload the exact frozen vector bundle. */
    la s0, vv35_preload_pairs
    li s1, VV35_PRELOAD_PAIR_COUNT
1:
    ld a0, 0(s0)
    HDEC_VADDR t0, a0
    ld a0, 8(s0)
    HDEC_VWR64 t0, a0
    addi s0, s0, 16
    addi s1, s1, -1
    bnez s1, 1b

    la t0, vv35_run_mode
    ld s6, 0(t0)
    li t1, 2
    bgtu s6, t1, vv35_bad_config
    la t0, vv35_batch_count
    ld s7, 0(t0)
    beqz s7, vv35_bad_config

    li s5, 0                  /* accumulated error count */
    li s4, 0                  /* completed HMATCH count */
    li s3, 0                  /* completed batch count */
    li s10, 0                 /* last HMATCH result */

    li t0, 2
    beq s6, t0, vv35_idle_spin

    /* Start the first PMUL before opening the measurement marker. */
    li a0, VV35_PMUL_OPERAND
    HDEC_ECC_STATUS t0, a0
    andi t1, t0, 7
    li t2, 4                  /* STATUS_OK and active=1 */
    beq t1, t2, 2f
    addi s5, s5, 1
2:
    rdcycle s8
    li a0, 1
    jal vv35_set_marker

vv35_batch_work:
    mv s11, s8                /* first-batch PMUL reference cycle */
    bnez s3, vv35_start_next_pmul_done
    j vv35_pmul_started
vv35_start_next_pmul_done:
    li a0, VV35_PMUL_OPERAND
    HDEC_ECC_STATUS t0, a0
    andi t1, t0, 7
    li t2, 4
    beq t1, t2, 3f
    addi s5, s5, 1
3:
    rdcycle s11

vv35_pmul_started:
    /* SERIAL releases HMATCH only after the frozen PMUL service interval. */
    bnez s6, vv35_hmatch_begin
4:
    rdcycle t0
    sub t1, t0, s11
    la t2, vv35_pmul_wait_cycles
    ld t2, 0(t2)
    bltu t1, t2, 4b

vv35_hmatch_begin:
    li s0, 1632
    li s1, VV35_HMATCH_OPERAND
    li s2, VV35_EXPECTED_HMATCH
5:
    mv a0, s1
    HDEC_HMATCH t0, a0
    mv s10, t0
    beq t0, s2, 6f
    addi s5, s5, 1
6:
    addi s4, s4, 1
    addi s0, s0, -1
    bnez s0, 5b

    /* End only after both the foreground stream and PMUL can be complete. */
7:
    rdcycle t0
    sub t1, t0, s11
    la t2, vv35_pmul_wait_cycles
    ld t2, 0(t2)
    bltu t1, t2, 7b

    addi s3, s3, 1
    bgeu s3, s7, vv35_metric_done
    j vv35_batch_work

vv35_metric_done:
    rdcycle s9
    li a0, 0
    jal vv35_set_marker

    /* One completion query and all correctness checks remain outside marker. */
    li a0, 0
    HDEC_ECC_STATUS t0, a0
    mv s11, t0
    andi t1, t0, 0xf
    li t2, 8                  /* STATUS_OK, active=0, done=1 */
    beq t1, t2, 8f
    addi s5, s5, 1
8:
    li a0, 4
    la a1, vv35_expected_x
    jal vv35_check_row
    add s5, s5, a0
    li a0, 5
    la a1, vv35_expected_y
    jal vv35_check_row
    add s5, s5, a0
    li a0, 3
    la a1, vv35_expected_guard3
    jal vv35_check_row
    add s5, s5, a0
    li a0, 6
    la a1, vv35_expected_guard6
    jal vv35_check_row
    add s5, s5, a0
    li a0, 7
    la a1, vv35_expected_guard7
    jal vv35_check_row
    add s5, s5, a0

    la t0, vv35_result_block
    li t1, 0x565633354c414231 /* "VV35LAB1" */
    sd t1, 0(t0)
    sd s5, 8(t0)
    sd s6, 16(t0)
    sd s7, 24(t0)
    sd s8, 32(t0)
    sd s9, 40(t0)
    sub t1, s9, s8
    sd t1, 48(t0)
    sd s4, 56(t0)
    sd s10, 64(t0)
    sd s11, 72(t0)
    la t2, vv35_pmul_wait_cycles
    ld t1, 0(t2)
    sd t1, 80(t0)
    mv a0, s5
    j _exit

vv35_idle_spin:
    rdcycle s8
    li a0, 1
    jal vv35_set_marker
    la t0, vv35_idle_window_cycles
    ld t2, 0(t0)
12:
    rdcycle t0
    sub t1, t0, s8
    bltu t1, t2, 12b
    rdcycle s9
    li a0, 0
    jal vv35_set_marker
    la t0, vv35_result_block
    li t1, 0x565633354c414231
    sd t1, 0(t0)
    sd zero, 8(t0)
    sd s6, 16(t0)
    sd s7, 24(t0)
    sd s8, 32(t0)
    sd s9, 40(t0)
    sub t1, s9, s8
    sd t1, 48(t0)
    sd zero, 56(t0)
    sd zero, 64(t0)
    sd zero, 72(t0)
    la t2, vv35_pmul_wait_cycles
    ld t1, 0(t2)
    sd t1, 80(t0)
    li a0, 0
    j _exit

vv35_bad_config:
    li a0, 0
    jal vv35_set_marker
    la t0, vv35_result_block
    li t1, 0x565633354c414231
    sd t1, 0(t0)
    li t1, 0xffffffffffffffff
    sd t1, 8(t0)
    li a0, 1
    j _exit

/* a0=value. A zero marker address makes this a no-op. */
vv35_set_marker:
    la t0, vv35_marker_mmio
    ld t0, 0(t0)
    beqz t0, 9f
    sw a0, 0(t0)
    fence iorw, iorw
9:
    ret

/* a0=row, a1=expected four-qword array. Returns mismatch count in a0. */
vv35_check_row:
    addi sp, sp, -48
    sd ra, 0(sp)
    sd s0, 8(sp)
    sd s1, 16(sp)
    sd s2, 24(sp)
    sd s3, 32(sp)
    mv s0, a0
    mv s1, a1
    li s2, 0
    li s3, 0
10:
    slli a0, s3, 6
    add a0, a0, s0
    HDEC_VADDR t0, a0
    HDEC_VRD64 t0
    ld t1, 0(s1)
    beq t0, t1, 11f
    addi s2, s2, 1
11:
    addi s1, s1, 8
    addi s3, s3, 1
    li t1, 4
    bltu s3, t1, 10b
    mv a0, s2
    ld ra, 0(sp)
    ld s0, 8(sp)
    ld s1, 16(sp)
    ld s2, 24(sp)
    ld s3, 32(sp)
    addi sp, sp, 48
    ret

    .section .data.vv35_control, "aw", @progbits
    .balign 8
    .globl vv35_run_mode
vv35_run_mode:
    .quad 1                   /* 0=SERIAL, 1=INTERLEAVED */
    .globl vv35_batch_count
vv35_batch_count:
    .quad 1
    .globl vv35_marker_mmio
vv35_marker_mmio:
    .quad 0
    .globl vv35_pmul_wait_cycles
vv35_pmul_wait_cycles:
    .quad 146908
    .globl vv35_idle_window_cycles
vv35_idle_window_cycles:
    .quad 2000000

    .section .bss.vv35_result, "aw", @nobits
    .balign 64
    .globl vv35_result_block
vv35_result_block:
    .zero 88
