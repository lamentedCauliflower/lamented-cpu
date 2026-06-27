# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# scall.S
#-----------------------------------------------------------------------------
# Test syscall trap.
#-----------------------------------------------------------------------
# Helper macros
#-----------------------------------------------------------------------
# We use a macro hack to simpify code generation for various numbers
# of bubble cycles.
#-----------------------------------------------------------------------
# RV64UI MACROS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Tests for instructions with immediate operand
#-----------------------------------------------------------------------
# RV32 P-extension register-pair immediate-op tests.
# rs1 pair = {x13, x12} (even base), rd pair = {x15, x14}.
# Both halves of result are checked; on mismatch we jump to the same fail
# label as TEST_CASE, so the reported testnum matches.
#-----------------------------------------------------------------------
# Tests for an instruction with register operands
#-----------------------------------------------------------------------
# P-extension vxsat helpers.
# vxsat is a sticky CSR (0x009): set to 1 whenever an instruction saturates,
# never auto-cleared. To verify it deterministically per test we clear it
# before the instruction and check the expected post-value after.
# Using the literal CSR address keeps these macros toolchain-independent.
#-----------------------------------------------------------------------
# Tests for an instruction with register-register operands
#-----------------------------------------------------------------------
# RV32 P-extension register-pair register-register tests.
# rs1 pair = {x13, x12} (even base), rd pair = {x15, x14}, rs2 = x11.
# Both halves of result are checked; on mismatch we jump to the same fail
# label as TEST_CASE, so the reported testnum matches.
#-----------------------------------------------------------------------
# Test memory instructions
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Test jump instructions
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# RV64UF MACROS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Tests floating-point instructions
#-----------------------------------------------------------------------
# 16-bit half precision (float16)
# 32-bit single precision (float)
# 64-bit double precision (double)
#-----------------------------------------------------------------------
# Pass and fail code (assumes test num is in gp)
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# Test data section
#-----------------------------------------------------------------------
.macro init; .endm
.section .text.init; .align 6; .weak mtvec_handler; .globl _start; _start: j reset_vector; .align 2; trap_vector: csrr t5, mcause; li t6, 0xb; beq t5, t6, write_tohost; li t6, 0x8; beq t5, t6, write_tohost; li t6, 0x9; beq t5, t6, write_tohost; la t5, mtvec_handler; beqz t5, 1f; jr t5; 1: ori gp, gp, 1337; write_tohost: sw gp, tohost, t5; sw zero, tohost + 4, t5; j write_tohost; reset_vector: li gp, 0; la t0, trap_vector; csrw mtvec, t0; init;
  li gp, 2
  # This is the expected trap code.
  li t1, 0x8
  # If running in M mode, use mstatus.MPP to check existence of U mode.
  # Otherwise, if in S mode, then U mode must exist and we don't need to check.
  li t0, 0x00001800
  csrc mstatus, t0
  csrr t2, mstatus
  and t0, t0, t2
  beqz t0, 1f
  # If U mode doesn't exist, mcause should indicate ECALL from M mode.
  li t1, 0xb
1:
  li t0, 0x00001800
  csrc mstatus, t0
  la t0, 1f
  csrw mepc, t0
  mret
1:
  li gp, 1
do_scall:
  scall
  j fail
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
 # Depending on the test environment, the M-mode version of this test might
# not actually invoke the following handler. Instead, the usual ECALL
# handler in the test environment might detect the 0x8 or
# 0xb exception and mark the test as having passed.
# Either way, we'll get the coverage we desire: such a handler must check
# both mcause and gp, just like the following handler.
  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t0, mcause
  # Check if CLIC mode
  csrr t2, mtvec
  andi t2, t2, 2
  # Skip masking if non-CLIC mode
  beqz t2, skip_mask
  andi t0, t0, 255
skip_mask:
  bne t0, t1, fail
  la t2, do_scall
  csrr t0, mepc
  bne t0, t2, fail
  j pass
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
 
.align 4; .global end_signature; end_signature:
