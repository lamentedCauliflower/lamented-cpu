# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# jalr.S
#-----------------------------------------------------------------------------
# Test jalr instruction.
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
  # Test 2: Basic test
  #-------------------------------------------------------------
test_2:
  li gp, 2
  li t0, 0
  la t1, target_2
  jalr t0, t1, 0
linkaddr_2:
  j fail
target_2:
  la t1, linkaddr_2
  bne t0, t1, fail
  #-------------------------------------------------------------
  # Test 3: Basic test2, rs = rd
  #-------------------------------------------------------------
test_3:
  li gp, 3
  la t0, target_3
  jalr t0, t0, 0
linkaddr_3:
  j fail
target_3:
  la t1, linkaddr_3
  bne t0, t1, fail
  #-------------------------------------------------------------
  # Bypassing tests
  #-------------------------------------------------------------
  test_4: li gp, 4; li x4, 0; 1: la x6, 2f; jalr x13, x6, 0; bne x0, gp, fail; 2: addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  test_5: li gp, 5; li x4, 0; 1: la x6, 2f; nop; jalr x13, x6, 0; bne x0, gp, fail; 2: addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  test_6: li gp, 6; li x4, 0; 1: la x6, 2f; nop; nop; jalr x13, x6, 0; bne x0, gp, fail; 2: addi x4, x4, 1; li x5, 2; bne x4, x5, 1b;
  #-------------------------------------------------------------
  # Test delay slot instructions not executed nor bypassed
  #-------------------------------------------------------------
  .option push
  .align 2
  .option norvc
  test_7: li gp, 7; li t0, 1; la t1, 1f; jr t1, -4; addi t0, t0, 1; addi t0, t0, 1; addi t0, t0, 1; addi t0, t0, 1; 1: addi t0, t0, 1; addi t0, t0, 1;; li x7, ((4) & ((1 << (32 - 1) << 1) - 1)); bne t0, x7, fail;
  .option pop
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
 
.align 4; .global end_signature; end_signature:
