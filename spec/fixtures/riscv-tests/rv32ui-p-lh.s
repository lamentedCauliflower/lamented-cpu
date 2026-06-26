# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# lh.S
#-----------------------------------------------------------------------------
# Test lh instruction.
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
  # Basic tests
  #-------------------------------------------------------------
  test_2: li gp, 2; li x15, 0x00000000000000ff; la x2, tdat; lh x14, 0(x2);; li x7, ((0x00000000000000ff) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_3: li gp, 3; li x15, 0xffffffffffffff00; la x2, tdat; lh x14, 2(x2);; li x7, ((0xffffffffffffff00) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_4: li gp, 4; li x15, 0x0000000000000ff0; la x2, tdat; lh x14, 4(x2);; li x7, ((0x0000000000000ff0) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_5: li gp, 5; li x15, 0xfffffffffffff00f; la x2, tdat; lh x14, 6(x2);; li x7, ((0xfffffffffffff00f) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  # Test with negative offset
  test_6: li gp, 6; li x15, 0x00000000000000ff; la x2, tdat4; lh x14, -6(x2);; li x7, ((0x00000000000000ff) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_7: li gp, 7; li x15, 0xffffffffffffff00; la x2, tdat4; lh x14, -4(x2);; li x7, ((0xffffffffffffff00) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_8: li gp, 8; li x15, 0x0000000000000ff0; la x2, tdat4; lh x14, -2(x2);; li x7, ((0x0000000000000ff0) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  test_9: li gp, 9; li x15, 0xfffffffffffff00f; la x2, tdat4; lh x14, 0(x2);; li x7, ((0xfffffffffffff00f) & ((1 << (32 - 1) << 1) - 1)); bne x14, x7, fail;;
  # Test with a negative base
  test_10: li gp, 10; la x1, tdat; addi x1, x1, -32; lh x5, 32(x1);; li x7, ((0x00000000000000ff) & ((1 << (32 - 1) << 1) - 1)); bne x5, x7, fail;
  # Test with unaligned base
  test_11: li gp, 11; la x1, tdat; addi x1, x1, -5; lh x5, 7(x1);; li x7, ((0xffffffffffffff00) & ((1 << (32 - 1) << 1) - 1)); bne x5, x7, fail;
  #-------------------------------------------------------------
  # Bypassing tests
  #-------------------------------------------------------------
  test_12: li gp, 12; li x4, 0; 1: la x13, tdat2; lh x14, 2(x13); addi x6, x14, 0; li x7, 0x0000000000000ff0; bne x6, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;;
  test_13: li gp, 13; li x4, 0; 1: la x13, tdat3; lh x14, 2(x13); nop; addi x6, x14, 0; li x7, 0xfffffffffffff00f; bne x6, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;;
  test_14: li gp, 14; li x4, 0; 1: la x13, tdat1; lh x14, 2(x13); nop; nop; addi x6, x14, 0; li x7, 0xffffffffffffff00; bne x6, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;;
  test_15: li gp, 15; li x4, 0; 1: la x13, tdat2; lh x14, 2(x13); li x7, 0x0000000000000ff0; bne x14, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  test_16: li gp, 16; li x4, 0; 1: la x13, tdat3; nop; lh x14, 2(x13); li x7, 0xfffffffffffff00f; bne x14, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  test_17: li gp, 17; li x4, 0; 1: la x13, tdat1; nop; nop; lh x14, 2(x13); li x7, 0xffffffffffffff00; bne x14, x7, fail; addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  #-------------------------------------------------------------
  # Test write-after-write hazard
  #-------------------------------------------------------------
  test_18: li gp, 18; la x5, tdat; lh x2, 0(x5); li x2, 2;; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x2, x7, fail;
  test_19: li gp, 19; la x5, tdat; lh x2, 0(x5); nop; li x2, 2;; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne x2, x7, fail;
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
 
tdat:
tdat1: .half 0x00ff
tdat2: .half 0xff00
tdat3: .half 0x0ff0
tdat4: .half 0xf00f
.align 4; .global end_signature; end_signature:
