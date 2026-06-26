# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# ld_st.S
#-----------------------------------------------------------------------------
# Test load and store instructions
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
  # Bypassing Tests
  #-------------------------------------------------------------
  # Test sb and lb (signed byte)
  test_2: li gp, 2; la x2, tdat; li x1, 0xffffffffffffffdd; sb x1, 0(x2); lb x14, 0(x2); sb x14, 0(x2); lb x2, 0(x2); li x7, 0xffffffffffffffdd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 0(x4); bne x4, x2, fail; lb x14, 0(x4); bne x14, x7, fail;;
  test_3: li gp, 3; la x2, tdat; li x1, 0xffffffffffffffcd; sb x1, 1(x2); lb x14, 1(x2); sb x14, 1(x2); lb x2, 1(x2); li x7, 0xffffffffffffffcd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 1(x4); bne x4, x2, fail; lb x14, 1(x4); bne x14, x7, fail;;
  test_4: li gp, 4; la x2, tdat; li x1, 0xffffffffffffffcc; sb x1, 2(x2); lb x14, 2(x2); sb x14, 2(x2); lb x2, 2(x2); li x7, 0xffffffffffffffcc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 2(x4); bne x4, x2, fail; lb x14, 2(x4); bne x14, x7, fail;;
  test_5: li gp, 5; la x2, tdat; li x1, 0xffffffffffffffbc; sb x1, 3(x2); lb x14, 3(x2); sb x14, 3(x2); lb x2, 3(x2); li x7, 0xffffffffffffffbc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 3(x4); bne x4, x2, fail; lb x14, 3(x4); bne x14, x7, fail;;
  test_6: li gp, 6; la x2, tdat; li x1, 0xffffffffffffffbb; sb x1, 4(x2); lb x14, 4(x2); sb x14, 4(x2); lb x2, 4(x2); li x7, 0xffffffffffffffbb; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 4(x4); bne x4, x2, fail; lb x14, 4(x4); bne x14, x7, fail;;
  test_7: li gp, 7; la x2, tdat; li x1, 0xffffffffffffffab; sb x1, 5(x2); lb x14, 5(x2); sb x14, 5(x2); lb x2, 5(x2); li x7, 0xffffffffffffffab; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 5(x4); bne x4, x2, fail; lb x14, 5(x4); bne x14, x7, fail;;
  test_8: li gp, 8; la x2, tdat; li x1, 0x33; sb x1, 0(x2); lb x14, 0(x2); sb x14, 0(x2); lb x2, 0(x2); li x7, 0x33; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 0(x4); bne x4, x2, fail; lb x14, 0(x4); bne x14, x7, fail;;
  test_9: li gp, 9; la x2, tdat; li x1, 0x23; sb x1, 1(x2); lb x14, 1(x2); sb x14, 1(x2); lb x2, 1(x2); li x7, 0x23; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 1(x4); bne x4, x2, fail; lb x14, 1(x4); bne x14, x7, fail;;
  test_10: li gp, 10; la x2, tdat; li x1, 0x22; sb x1, 2(x2); lb x14, 2(x2); sb x14, 2(x2); lb x2, 2(x2); li x7, 0x22; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 2(x4); bne x4, x2, fail; lb x14, 2(x4); bne x14, x7, fail;;
  test_11: li gp, 11; la x2, tdat; li x1, 0x12; sb x1, 3(x2); lb x14, 3(x2); sb x14, 3(x2); lb x2, 3(x2); li x7, 0x12; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 3(x4); bne x4, x2, fail; lb x14, 3(x4); bne x14, x7, fail;;
  test_12: li gp, 12; la x2, tdat; li x1, 0x11; sb x1, 4(x2); lb x14, 4(x2); sb x14, 4(x2); lb x2, 4(x2); li x7, 0x11; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 4(x4); bne x4, x2, fail; lb x14, 4(x4); bne x14, x7, fail;;
  test_13: li gp, 13; la x2, tdat; li x1, 0x01; sb x1, 5(x2); lb x14, 5(x2); sb x14, 5(x2); lb x2, 5(x2); li x7, 0x01; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 5(x4); bne x4, x2, fail; lb x14, 5(x4); bne x14, x7, fail;;
  # Test sb and lbu (unsigned byte)
  test_14: li gp, 14; la x2, tdat; li x1, 0x33; sb x1, 0(x2); lbu x14, 0(x2); sb x14, 0(x2); lbu x2, 0(x2); li x7, 0x33; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 0(x4); bne x4, x2, fail; lbu x14, 0(x4); bne x14, x7, fail;;
  test_15: li gp, 15; la x2, tdat; li x1, 0x23; sb x1, 1(x2); lbu x14, 1(x2); sb x14, 1(x2); lbu x2, 1(x2); li x7, 0x23; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 1(x4); bne x4, x2, fail; lbu x14, 1(x4); bne x14, x7, fail;;
  test_16: li gp, 16; la x2, tdat; li x1, 0x22; sb x1, 2(x2); lbu x14, 2(x2); sb x14, 2(x2); lbu x2, 2(x2); li x7, 0x22; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 2(x4); bne x4, x2, fail; lbu x14, 2(x4); bne x14, x7, fail;;
  test_17: li gp, 17; la x2, tdat; li x1, 0x12; sb x1, 3(x2); lbu x14, 3(x2); sb x14, 3(x2); lbu x2, 3(x2); li x7, 0x12; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 3(x4); bne x4, x2, fail; lbu x14, 3(x4); bne x14, x7, fail;;
  test_18: li gp, 18; la x2, tdat; li x1, 0x11; sb x1, 4(x2); lbu x14, 4(x2); sb x14, 4(x2); lbu x2, 4(x2); li x7, 0x11; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 4(x4); bne x4, x2, fail; lbu x14, 4(x4); bne x14, x7, fail;;
  test_19: li gp, 19; la x2, tdat; li x1, 0x01; sb x1, 5(x2); lbu x14, 5(x2); sb x14, 5(x2); lbu x2, 5(x2); li x7, 0x01; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sb x1, 5(x4); bne x4, x2, fail; lbu x14, 5(x4); bne x14, x7, fail;;
  # Test sw and lw (signed word)
  test_20: li gp, 20; la x2, tdat; li x1, 0xffffffffaabbccdd; sw x1, 0(x2); lw x14, 0(x2); sw x14, 0(x2); lw x2, 0(x2); li x7, 0xffffffffaabbccdd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 0(x4); bne x4, x2, fail; lw x14, 0(x4); bne x14, x7, fail;;
  test_21: li gp, 21; la x2, tdat; li x1, 0xffffffffdaabbccd; sw x1, 4(x2); lw x14, 4(x2); sw x14, 4(x2); lw x2, 4(x2); li x7, 0xffffffffdaabbccd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 4(x4); bne x4, x2, fail; lw x14, 4(x4); bne x14, x7, fail;;
  test_22: li gp, 22; la x2, tdat; li x1, 0xffffffffddaabbcc; sw x1, 8(x2); lw x14, 8(x2); sw x14, 8(x2); lw x2, 8(x2); li x7, 0xffffffffddaabbcc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 8(x4); bne x4, x2, fail; lw x14, 8(x4); bne x14, x7, fail;;
  test_23: li gp, 23; la x2, tdat; li x1, 0xffffffffcddaabbc; sw x1, 12(x2); lw x14, 12(x2); sw x14, 12(x2); lw x2, 12(x2); li x7, 0xffffffffcddaabbc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 12(x4); bne x4, x2, fail; lw x14, 12(x4); bne x14, x7, fail;;
  test_24: li gp, 24; la x2, tdat; li x1, 0xffffffffccddaabb; sw x1, 16(x2); lw x14, 16(x2); sw x14, 16(x2); lw x2, 16(x2); li x7, 0xffffffffccddaabb; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 16(x4); bne x4, x2, fail; lw x14, 16(x4); bne x14, x7, fail;;
  test_25: li gp, 25; la x2, tdat; li x1, 0xffffffffbccddaab; sw x1, 20(x2); lw x14, 20(x2); sw x14, 20(x2); lw x2, 20(x2); li x7, 0xffffffffbccddaab; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 20(x4); bne x4, x2, fail; lw x14, 20(x4); bne x14, x7, fail;;
  test_26: li gp, 26; la x2, tdat; li x1, 0x00112233; sw x1, 0(x2); lw x14, 0(x2); sw x14, 0(x2); lw x2, 0(x2); li x7, 0x00112233; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 0(x4); bne x4, x2, fail; lw x14, 0(x4); bne x14, x7, fail;;
  test_27: li gp, 27; la x2, tdat; li x1, 0x30011223; sw x1, 4(x2); lw x14, 4(x2); sw x14, 4(x2); lw x2, 4(x2); li x7, 0x30011223; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 4(x4); bne x4, x2, fail; lw x14, 4(x4); bne x14, x7, fail;;
  test_28: li gp, 28; la x2, tdat; li x1, 0x33001122; sw x1, 8(x2); lw x14, 8(x2); sw x14, 8(x2); lw x2, 8(x2); li x7, 0x33001122; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 8(x4); bne x4, x2, fail; lw x14, 8(x4); bne x14, x7, fail;;
  test_29: li gp, 29; la x2, tdat; li x1, 0x23300112; sw x1, 12(x2); lw x14, 12(x2); sw x14, 12(x2); lw x2, 12(x2); li x7, 0x23300112; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 12(x4); bne x4, x2, fail; lw x14, 12(x4); bne x14, x7, fail;;
  test_30: li gp, 30; la x2, tdat; li x1, 0x22330011; sw x1, 16(x2); lw x14, 16(x2); sw x14, 16(x2); lw x2, 16(x2); li x7, 0x22330011; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 16(x4); bne x4, x2, fail; lw x14, 16(x4); bne x14, x7, fail;;
  test_31: li gp, 31; la x2, tdat; li x1, 0x12233001; sw x1, 20(x2); lw x14, 20(x2); sw x14, 20(x2); lw x2, 20(x2); li x7, 0x12233001; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sw x1, 20(x4); bne x4, x2, fail; lw x14, 20(x4); bne x14, x7, fail;;
  # Test sh and lh (signed halfword)
  test_32: li gp, 32; la x2, tdat; li x1, 0xffffffffffffccdd; sh x1, 0(x2); lh x14, 0(x2); sh x14, 0(x2); lh x2, 0(x2); li x7, 0xffffffffffffccdd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 0(x4); bne x4, x2, fail; lh x14, 0(x4); bne x14, x7, fail;;
  test_33: li gp, 33; la x2, tdat; li x1, 0xffffffffffffbccd; sh x1, 2(x2); lh x14, 2(x2); sh x14, 2(x2); lh x2, 2(x2); li x7, 0xffffffffffffbccd; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 2(x4); bne x4, x2, fail; lh x14, 2(x4); bne x14, x7, fail;;
  test_34: li gp, 34; la x2, tdat; li x1, 0xffffffffffffbbcc; sh x1, 4(x2); lh x14, 4(x2); sh x14, 4(x2); lh x2, 4(x2); li x7, 0xffffffffffffbbcc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 4(x4); bne x4, x2, fail; lh x14, 4(x4); bne x14, x7, fail;;
  test_35: li gp, 35; la x2, tdat; li x1, 0xffffffffffffabbc; sh x1, 6(x2); lh x14, 6(x2); sh x14, 6(x2); lh x2, 6(x2); li x7, 0xffffffffffffabbc; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 6(x4); bne x4, x2, fail; lh x14, 6(x4); bne x14, x7, fail;;
  test_36: li gp, 36; la x2, tdat; li x1, 0xffffffffffffaabb; sh x1, 8(x2); lh x14, 8(x2); sh x14, 8(x2); lh x2, 8(x2); li x7, 0xffffffffffffaabb; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 8(x4); bne x4, x2, fail; lh x14, 8(x4); bne x14, x7, fail;;
  test_37: li gp, 37; la x2, tdat; li x1, 0xffffffffffffdaab; sh x1, 10(x2); lh x14, 10(x2); sh x14, 10(x2); lh x2, 10(x2); li x7, 0xffffffffffffdaab; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 10(x4); bne x4, x2, fail; lh x14, 10(x4); bne x14, x7, fail;;
  test_38: li gp, 38; la x2, tdat; li x1, 0x2233; sh x1, 0(x2); lh x14, 0(x2); sh x14, 0(x2); lh x2, 0(x2); li x7, 0x2233; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 0(x4); bne x4, x2, fail; lh x14, 0(x4); bne x14, x7, fail;;
  test_39: li gp, 39; la x2, tdat; li x1, 0x1223; sh x1, 2(x2); lh x14, 2(x2); sh x14, 2(x2); lh x2, 2(x2); li x7, 0x1223; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 2(x4); bne x4, x2, fail; lh x14, 2(x4); bne x14, x7, fail;;
  test_40: li gp, 40; la x2, tdat; li x1, 0x1122; sh x1, 4(x2); lh x14, 4(x2); sh x14, 4(x2); lh x2, 4(x2); li x7, 0x1122; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 4(x4); bne x4, x2, fail; lh x14, 4(x4); bne x14, x7, fail;;
  test_41: li gp, 41; la x2, tdat; li x1, 0x0112; sh x1, 6(x2); lh x14, 6(x2); sh x14, 6(x2); lh x2, 6(x2); li x7, 0x0112; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 6(x4); bne x4, x2, fail; lh x14, 6(x4); bne x14, x7, fail;;
  test_42: li gp, 42; la x2, tdat; li x1, 0x0011; sh x1, 8(x2); lh x14, 8(x2); sh x14, 8(x2); lh x2, 8(x2); li x7, 0x0011; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 8(x4); bne x4, x2, fail; lh x14, 8(x4); bne x14, x7, fail;;
  test_43: li gp, 43; la x2, tdat; li x1, 0x3001; sh x1, 10(x2); lh x14, 10(x2); sh x14, 10(x2); lh x2, 10(x2); li x7, 0x3001; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 10(x4); bne x4, x2, fail; lh x14, 10(x4); bne x14, x7, fail;;
  # Test sh and lhu (unsigned halfword)
  test_44: li gp, 44; la x2, tdat; li x1, 0x2233; sh x1, 0(x2); lhu x14, 0(x2); sh x14, 0(x2); lhu x2, 0(x2); li x7, 0x2233; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 0(x4); bne x4, x2, fail; lhu x14, 0(x4); bne x14, x7, fail;;
  test_45: li gp, 45; la x2, tdat; li x1, 0x1223; sh x1, 2(x2); lhu x14, 2(x2); sh x14, 2(x2); lhu x2, 2(x2); li x7, 0x1223; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 2(x4); bne x4, x2, fail; lhu x14, 2(x4); bne x14, x7, fail;;
  test_46: li gp, 46; la x2, tdat; li x1, 0x1122; sh x1, 4(x2); lhu x14, 4(x2); sh x14, 4(x2); lhu x2, 4(x2); li x7, 0x1122; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 4(x4); bne x4, x2, fail; lhu x14, 4(x4); bne x14, x7, fail;;
  test_47: li gp, 47; la x2, tdat; li x1, 0x0112; sh x1, 6(x2); lhu x14, 6(x2); sh x14, 6(x2); lhu x2, 6(x2); li x7, 0x0112; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 6(x4); bne x4, x2, fail; lhu x14, 6(x4); bne x14, x7, fail;;
  test_48: li gp, 48; la x2, tdat; li x1, 0x0011; sh x1, 8(x2); lhu x14, 8(x2); sh x14, 8(x2); lhu x2, 8(x2); li x7, 0x0011; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 8(x4); bne x4, x2, fail; lhu x14, 8(x4); bne x14, x7, fail;;
  test_49: li gp, 49; la x2, tdat; li x1, 0x3001; sh x1, 10(x2); lhu x14, 10(x2); sh x14, 10(x2); lhu x2, 10(x2); li x7, 0x3001; bne x2, x7, fail; la x2, tdat; sw x2,8(x2); lw x4,8(x2); sh x1, 10(x4); bne x4, x2, fail; lhu x14, 10(x4); bne x14, x7, fail;;
  # RV64-specific tests for ld, sd, and lwu
  li a0, 0xef # Immediate load for manual store test
  la a1, tdat # Load address of tdat
  sb a0, 3(a1) # Store byte at offset 3 of tdat
  lb a2, 3(a1) # Load byte back for verification
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
 
tdat:
    .rept 20
    .word 0xdeadbeef
    .endr
.align 4; .global end_signature; end_signature:
