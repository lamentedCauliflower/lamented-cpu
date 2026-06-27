# See LICENSE for license details.
# See LICENSE for license details.
#*****************************************************************************
# csr.S
#-----------------------------------------------------------------------------
# Test CSRRx and CSRRxI instructions.
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
  # For RV64, make sure UXL encodes RV64. (UXL does not exist for RV32.)
  test_20: li gp, 20; csrw mscratch, zero; csrr a0, mscratch; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_21: li gp, 21; csrrwi a0, mscratch, 0; csrrwi a0, mscratch, 0xF; li x7, ((0) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_22: li gp, 22; csrrsi x0, mscratch, 0x10; csrr a0, mscratch; li x7, ((0x1f) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  csrwi mscratch, 3
  test_2: li gp, 2; csrr a0, mscratch; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_3: li gp, 3; csrrci a1, mscratch, 1; li x7, ((3) & ((1 << (32 - 1) << 1) - 1)); bne a1, x7, fail;;
  test_4: li gp, 4; csrrsi a2, mscratch, 4; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne a2, x7, fail;;
  test_5: li gp, 5; csrrwi a3, mscratch, 2; li x7, ((6) & ((1 << (32 - 1) << 1) - 1)); bne a3, x7, fail;;
  test_6: li gp, 6; li a0, 0xbad1dea; csrrw a1, mscratch, a0; li x7, ((2) & ((1 << (32 - 1) << 1) - 1)); bne a1, x7, fail;;
  test_7: li gp, 7; li a0, 0x0001dea; csrrc a1, mscratch, a0; li x7, ((0xbad1dea) & ((1 << (32 - 1) << 1) - 1)); bne a1, x7, fail;;
  test_8: li gp, 8; li a0, 0x000beef; csrrs a1, mscratch, a0; li x7, ((0xbad0000) & ((1 << (32 - 1) << 1) - 1)); bne a1, x7, fail;;
  test_9: li gp, 9; li a0, 0xbad1dea; csrrw a0, mscratch, a0; li x7, ((0xbadbeef) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_10: li gp, 10; li a0, 0x0001dea; csrrc a0, mscratch, a0; li x7, ((0xbad1dea) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_11: li gp, 11; li a0, 0x000beef; csrrs a0, mscratch, a0; li x7, ((0xbad0000) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  test_12: li gp, 12; csrr a0, mscratch; li x7, ((0xbadbeef) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  # Is F extension present?
  csrr a0, misa
  andi a0, a0, (1 << ('F' - 'A'))
  beqz a0, 1f
  # If so, make sure FP stores have no effect when mstatus.FS is off.
  li a1, 0x00006000
  csrs mstatus, a1
  # Fail if this test is compiled without F but executed on a core with F.
  test_13: li gp, 13; ; li x7, ((1) & ((1 << (32 - 1) << 1) - 1)); bne zero, x7, fail;
1:
  # Figure out if 'U' is set in misa
  csrr a0, misa # a0 = csr(misa)
  srli a0, a0, 20 # a0 = a0 >> 20
  andi a0, a0, 1 # a0 = a0 & 1
  beqz a0, finish # if no user mode, skip the rest of these checks
  # Enable access to the cycle counter
  csrwi mcounteren, 1
  # Figure out if 'S' is set in misa
  csrr a0, misa # a0 = csr(misa)
  srli a0, a0, 18 # a0 = a0 >> 20
  andi a0, a0, 1 # a0 = a0 & 1
  beqz a0, 1f
  # Enable access to the cycle counter
  csrwi scounteren, 1
1:
  # jump to user land
  li t0, 0x00001800
  csrc mstatus, t0
  la t0, 1f
  csrw mepc, t0
  mret
  1:
  # Make sure writing the cycle counter causes an exception.
  # Don't run in supervisor, as we don't delegate illegal instruction traps.
  test_14: li gp, 14; li a0, 255; csrrw a0, cycle, x0; li x7, ((255) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;;
  # Make sure reading status in user mode causes an exception.
  # Don't run in supervisor, as we don't delegate illegal instruction traps.
  test_15: li gp, 15; li a0, 255; csrr a0, mstatus; li x7, ((255) & ((1 << (32 - 1) << 1) - 1)); bne a0, x7, fail;
finish:
  fence; li gp, 1; ecall
  # We should only fall through to this if scall failed.
  bne x0, gp, pass; fail: fence; 1: beqz gp, 1b; sll gp, gp, 1; or gp, gp, 1; ecall; pass: fence; li gp, 1; ecall
  .align 2
  .global mtvec_handler
mtvec_handler:
  # Trapping on tests 13-15 is good news.
  li t0, 13
  bltu gp, t0, 1f
  li t0, 15
  bleu gp, t0, privileged
1:
  # catch fence; li gp, 1; ecall and kick it up to M-mode
  csrr t0, mcause
  li t1, 0x8
  bne t0, t1, fail
  fence; li gp, 1; ecall
privileged:
  # Make sure mcause indicates a lack of privilege.
  csrr t0, mcause
  li t1, 0x2
  bne t0, t1, fail
  # Return to user mode, but skip the trapping instruction.
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret
unimp
  .data
.pushsection .tohost, "aw", @progbits; .align 6; .global tohost; tohost: .dword 0; .align 6; .global fromhost; fromhost: .dword 0; .popsection; .align 4; .global begin_signature; begin_signature:
fsw_data: .word 1
.align 4; .global end_signature; end_signature:
