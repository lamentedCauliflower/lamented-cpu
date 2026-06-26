// Minimal machine-mode test env for lamented-cpu (ADR-0004).
// A stripped replacement for riscv-tests' env/p: it sets mtvec and runs the
// test body directly in M-mode (no mret to U/S, no PMP / satp / medeleg), using
// only the M-mode CSRs the Hart implements. The test bodies (rv*ui/um/mi) are
// privilege-agnostic integer/CSR sequences, so M-mode execution is faithful to
// the ISA behaviour under test.
#ifndef _ENV_LAMENTED_M_H
#define _ENV_LAMENTED_M_H

#define TESTNUM gp

// trap causes we care about (from the RISC-V priv spec)
#define CAUSE_USER_ECALL 0x8
#define CAUSE_SUPERVISOR_ECALL 0x9
#define CAUSE_MACHINE_ECALL 0xb

// TVM selectors only define the (empty) `init` macro; we are always in M-mode,
// so there is nothing to enable.
#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV32M .macro init; .endm
#define RVTEST_RV32S .macro init; .endm
#define RVTEST_RV64U .macro init; .endm
#define RVTEST_RV64M .macro init; .endm
#define RVTEST_RV64S .macro init; .endm

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                           \
        .align 6;                                                      \
        .weak mtvec_handler;                                           \
        .globl _start;                                                 \
_start:                                                                \
        j reset_vector;                                                \
        .align 2;                                                      \
trap_vector:                                                           \
        csrr t5, mcause;                                               \
        li t6, CAUSE_MACHINE_ECALL;    beq t5, t6, write_tohost;       \
        li t6, CAUSE_USER_ECALL;       beq t5, t6, write_tohost;       \
        li t6, CAUSE_SUPERVISOR_ECALL; beq t5, t6, write_tohost;       \
        /* a test may install its own machine trap handler */          \
        la t5, mtvec_handler;                                          \
        beqz t5, 1f;                                                   \
        jr t5;                                                         \
  1:    ori TESTNUM, TESTNUM, 1337; /* unexpected trap => fail */       \
write_tohost:                                                          \
        sw TESTNUM, tohost, t5;                                        \
        sw zero, tohost + 4, t5;                                       \
        j write_tohost;                                                \
reset_vector:                                                          \
        li TESTNUM, 0;                                                 \
        la t0, trap_vector;                                            \
        csrw mtvec, t0;                                                \
        init; /* fall straight into the test body, in M-mode */

#define RVTEST_CODE_END unimp

#define RVTEST_PASS                                                    \
        fence;                                                         \
        li TESTNUM, 1;                                                 \
        ecall

#define RVTEST_FAIL                                                    \
        fence;                                                         \
  1:    beqz TESTNUM, 1b;                                              \
        sll TESTNUM, TESTNUM, 1;                                       \
        or TESTNUM, TESTNUM, 1;                                        \
        ecall

#define RVTEST_DATA_BEGIN                                              \
        .pushsection .tohost, "aw", @progbits;                        \
        .align 6; .global tohost;   tohost:   .dword 0;                \
        .align 6; .global fromhost; fromhost: .dword 0;               \
        .popsection;                                                  \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
