# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# sub.S
#-----------------------------------------------------------------------------
# Test sub instruction.
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
  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------
  test_2: li gp, 2; li x11, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_3: li gp, 3; li x11, ((0x0000000000000001) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000001) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_4: li gp, 4; li x11, ((0x0000000000000003) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000007) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xfffffffffffffffc) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_5: li gp, 5; li x11, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0xffffffffffff8000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000000008000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_6: li gp, 6; li x11, ((0xffffffff80000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xffffffff80000000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_7: li gp, 7; li x11, ((0xffffffff80000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0xffffffffffff8000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xffffffff80008000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_8: li gp, 8; li x11, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000007fff) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xffffffffffff8001) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_9: li gp, 9; li x11, ((0x000000007fffffff) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x000000007fffffff) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_10: li gp, 10; li x11, ((0x000000007fffffff) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000007fff) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x000000007fff8000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_11: li gp, 11; li x11, ((0xffffffff80000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000007fff) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xffffffff7fff8001) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_12: li gp, 12; li x11, ((0x000000007fffffff) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0xffffffffffff8000) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000080007fff) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_13: li gp, 13; li x11, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0xffffffffffffffff) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000000000001) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_14: li gp, 14; li x11, ((0xffffffffffffffff) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0x0000000000000001) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0xfffffffffffffffe) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_15: li gp, 15; li x11, ((0xffffffffffffffff) & ((1 << (32 - 1) << 1) - 1)); li x12, ((0xffffffffffffffff) & ((1 << (32 - 1) << 1) - 1)); sub x14, x11, x12;; li x7, ((0x0000000000000000) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  #-------------------------------------------------------------
  # Source/Destination tests
  #-------------------------------------------------------------
  test_16: li gp, 16; li x11, ((13) & ((1 << (32 - 1) << 1) - 1)); li x12, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x11, x11, x12;; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x11, x7, fail;;
  test_17: li gp, 17; li x11, ((14) & ((1 << (32 - 1) << 1) - 1)); li x12, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x12, x11, x12;; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x12, x7, fail;;
  test_18: li gp, 18; li x11, ((13) & ((1 << (32 - 1) << 1) - 1)); sub x11, x11, x11;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x11, x7, fail;;
  #-------------------------------------------------------------
  # Bypassing tests
  #-------------------------------------------------------------
  test_19: li gp, 19; li x4, 0; 1: li x1, ((13) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x6, x14, 0; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x6, x7, fail;;
  test_20: li gp, 20; li x4, 0; 1: li x1, ((14) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; nop; addi x6, x14, 0; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x6, x7, fail;;
  test_21: li gp, 21; li x4, 0; 1: li x1, ((15) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; nop; nop; addi x6, x14, 0; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne x6, x7, fail;;
  test_22: li gp, 22; li x4, 0; 1: li x1, ((13) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_23: li gp, 23; li x4, 0; 1: li x1, ((14) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_24: li gp, 24; li x4, 0; 1: li x1, ((15) & ((1 << (32 - 1) << 1) - 1)); li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_25: li gp, 25; li x4, 0; 1: li x1, ((13) & ((1 << (32 - 1) << 1) - 1)); nop; li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_26: li gp, 26; li x4, 0; 1: li x1, ((14) & ((1 << (32 - 1) << 1) - 1)); nop; li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_27: li gp, 27; li x4, 0; 1: li x1, ((15) & ((1 << (32 - 1) << 1) - 1)); nop; nop; li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_28: li gp, 28; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); li x1, ((13) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_29: li gp, 29; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); li x1, ((14) & ((1 << (32 - 1) << 1) - 1)); nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_30: li gp, 30; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); li x1, ((15) & ((1 << (32 - 1) << 1) - 1)); nop; nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_31: li gp, 31; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; li x1, ((13) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_32: li gp, 32; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; li x1, ((14) & ((1 << (32 - 1) << 1) - 1)); nop; sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_33: li gp, 33; li x4, 0; 1: li x2, ((11) & ((1 << (32 - 1) << 1) - 1)); nop; nop; li x1, ((15) & ((1 << (32 - 1) << 1) - 1)); sub x14, x1, x2; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_34: li gp, 34; li x1, ((-15) & ((1 << (32 - 1) << 1) - 1)); sub x2, x0, x1;; li x7, ((15) & ((1 << (32 - 1) << 1) - 1)); bne x2, x7, fail;;
  test_35: li gp, 35; li x1, ((32) & ((1 << (32 - 1) << 1) - 1)); sub x2, x1, x0;; li x7, ((32) & ((1 << (32 - 1) << 1) - 1)); bne x2, x7, fail;;
  test_36: li gp, 36; sub x1, x0, x0;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x1, x7, fail;;
  test_37: li gp, 37; li x1, ((16) & ((1 << (32 - 1) << 1) - 1)); li x2, ((30) & ((1 << (32 - 1) << 1) - 1)); sub x0, x1, x2;; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne x0, x7, fail;;
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
 
.align 4; .global end_signature; end_signature:
