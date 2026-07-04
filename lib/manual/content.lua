-- Manual content (ADR-0008): the chapter list, authored inline. Each entry is a
-- chapter { id, title, blocks }; the first is the Overview (the Informatron root
-- page). Later issues append chapters here.
--
-- Everything documented is the HONEST SUBSET: only what the Assembler/Hart actually
-- accept, derived from lib/asm.lua and lib/hart.lua, not the ISA name.
local ir = require("lib.manual")
local h1, h2, p, code, tbl, rows = ir.h1, ir.h2, ir.p, ir.code, ir.table, ir.rows

-- x0..x31: ABI name, who preserves it across a call, and its role. The RISC-V
-- integer calling convention; ABI names match lib/asm.lua's register table.
local function gpr(num, abi, saver, role)
  return { reg = "x" .. num, abi = abi, saver = saver, role = role }
end
local GPRS = {
  gpr(0, "zero", "—", "Hardwired constant 0 (writes ignored)"),
  gpr(1, "ra", "Caller", "Return address"),
  gpr(2, "sp", "Callee", "Stack pointer"),
  gpr(3, "gp", "—", "Global pointer (set by the environment; leave alone)"),
  gpr(4, "tp", "—", "Thread pointer (set by the environment; leave alone)"),
  gpr(5, "t0", "Caller", "Temporary"),
  gpr(6, "t1", "Caller", "Temporary"),
  gpr(7, "t2", "Caller", "Temporary"),
  gpr(8, "s0", "Callee", "Saved / frame pointer (also named fp)"),
  gpr(9, "s1", "Callee", "Saved"),
  gpr(10, "a0", "Caller", "Argument / return value"),
  gpr(11, "a1", "Caller", "Argument / return value"),
  gpr(12, "a2", "Caller", "Argument"),
  gpr(13, "a3", "Caller", "Argument"),
  gpr(14, "a4", "Caller", "Argument"),
  gpr(15, "a5", "Caller", "Argument"),
  gpr(16, "a6", "Caller", "Argument"),
  gpr(17, "a7", "Caller", "Argument"),
  gpr(18, "s2", "Callee", "Saved"),
  gpr(19, "s3", "Callee", "Saved"),
  gpr(20, "s4", "Callee", "Saved"),
  gpr(21, "s5", "Callee", "Saved"),
  gpr(22, "s6", "Callee", "Saved"),
  gpr(23, "s7", "Callee", "Saved"),
  gpr(24, "s8", "Callee", "Saved"),
  gpr(25, "s9", "Callee", "Saved"),
  gpr(26, "s10", "Callee", "Saved"),
  gpr(27, "s11", "Callee", "Saved"),
  gpr(28, "t3", "Caller", "Temporary"),
  gpr(29, "t4", "Caller", "Temporary"),
  gpr(30, "t5", "Caller", "Temporary"),
  gpr(31, "t6", "Caller", "Temporary"),
}

-- The machine-mode CSRs the Hart actually holds state for (lib/inspector registers,
-- lib/hart CSR numbers). The Assembler's CSR table names more, but only these five
-- carry architectural state the Hart reads back.
local CSRS = {
  { "0x301", "misa", "ISA + extensions; reads as RV32IM" },
  { "0x305", "mtvec", "Trap-handler base address" },
  { "0x341", "mepc", "PC saved on trap entry" },
  { "0x342", "mcause", "Cause of the most recent trap" },
  { "0x343", "mtval", "Faulting address / instruction on a trap" },
}

local SUM_EXAMPLE = [[
  li   a0, 0          # sum
  li   t0, 1          # i
  li   t1, 10         # n
loop:
  add  a0, a0, t0     # sum += i
  addi t0, t0, 1      # i++
  ble  t0, t1, loop   # while i <= n  ->  a0 = 55
]]

local overview = {
  id = "overview",
  title = "Overview",
  blocks = {
    h1("The RISC-V Combinator"),
    p(
      "The RISC-V Combinator hosts one Hart — a single RISC-V hardware thread that "
        .. "emulates RV32IM_Zicsr in machine mode. You write assembly directly in the "
        .. "Combinator's Inspector and run it; there is no binary to compile and no "
        .. "external toolchain. The loadable artifact is always assembly text."
    ),
    h2("What runs"),
    p(
      "The Hart implements the 32-bit base integer set, the M extension "
        .. "(multiply/divide), and Zicsr (CSR access), machine-mode only. There is no "
        .. "floating point, no atomics, no compressed encoding, and no supervisor or "
        .. "user mode. Misaligned loads and stores are allowed, not trapped."
    ),
    tbl({ "Extension", "Accepted" }, {
      { "RV32I (base integer)", "Yes" },
      { "M (multiply / divide)", "Yes" },
      { "Zicsr (CSR access)", "Yes" },
      { "A (atomics)", "No" },
      { "F / D (floating point)", "No" },
      { "C (compressed)", "No" },
      { "Supervisor / User mode", "No" },
      { "Misaligned load / store", "Allowed (not trapped)" },
    }),
    h2("Halting"),
    p(
      "A program signals completion by writing a non-zero value to the tohost symbol; "
        .. "the Hart then stops. A write of 1 reports a clean pass. Until tohost is "
        .. "written the Hart runs one instruction per tick."
    ),
    h2("A first program"),
    p("Sum 1 through 10 into a0, then loop. Every mnemonic here is one the Assembler accepts:"),
    code(SUM_EXAMPLE),
    h2("Using this Manual"),
    p(
      "Each chapter documents only what the Assembler and Hart actually accept. The "
        .. "Register Reference lists every register; later chapters cover the instruction "
        .. "set, calling convention, memory model, CSRs and traps, and Circuit I/O."
    ),
  },
}

local BASIC_PROGRAM = [[
# A basic program: sum 1..10 into a0, then halt.
_start:                 # execution begins at the top (pc = 0x80000000)
  li   a0, 0            # a0 = running sum
  li   t0, 1            # t0 = counter i
  li   t1, 10           # t1 = limit n
loop:
  add  a0, a0, t0       # sum += i
  addi t0, t0, 1        # i++
  ble  t0, t1, loop     # repeat while i <= n
  la   t2, tohost       # address of the halt symbol
  sw   a0, 0(t2)        # write the result -> the Hart halts
1:
  j    1b               # park here (1b = jump back to the 1: above)

.section .data          # data sits below the code in one flat image
.align 6
.global tohost
tohost: .dword 0        # 8 bytes the program writes to signal "done"
]]

local program_layout = {
  id = "program-layout",
  title = "Anatomy of a Program",
  blocks = {
    h1("Anatomy of a Program"),
    p(
      "A program is plain RV32IM assembly text. Execution starts at the very first "
        .. "instruction (the pc resets to 0x80000000) and runs one instruction per tick "
        .. "until the program halts or faults. Here is a complete one, annotated:"
    ),
    code(BASIC_PROGRAM),
    h2("Comments and labels"),
    p(
      "A # begins a comment to the end of the line. A label such as loop: names the "
        .. "current address; you reference it in branches and jumps. _start is just a "
        .. "conventional name for the first line -- the Hart starts at the top regardless."
    ),
    h2("Halting"),
    p(
      "The Hart has no exit instruction. To stop cleanly, write a non-zero value to the "
        .. "tohost symbol; the Hart halts and the Inspector shows 'halted' (a write of 1 "
        .. "reports a clean pass). la loads tohost's address, and sw stores to it."
    ),
    h2("Numeric labels and the park loop"),
    p(
      "Numeric labels like 1: are local and reusable: refer to one as 1f (the next 1: "
        .. "forward) or 1b (the previous 1: backward). The program ends with 1: j 1b -- a "
        .. "one-instruction infinite loop that parks the Hart after it has signalled done, "
        .. "so execution never runs off the end into unwritten memory."
    ),
    h2("The data section"),
    p(
      "Code and data share one flat image in source order; .section, .data and .text are "
        .. "ignored except for alignment (see Memory & Execution Model). .align 6 advances "
        .. "to a 64-byte boundary, .global tohost exports the symbol, and tohost: .dword 0 "
        .. "reserves eight zero bytes for the program to write. The Assembler Reference "
        .. "lists every directive."
    ),
  },
}

local registers = {
  id = "registers",
  title = "Register Reference",
  blocks = {
    h1("Register Reference"),
    p(
      "The Hart has 32 general-purpose registers x0–x31, each 32 bits, plus the "
        .. "program counter pc. x0 is hardwired to 0: writes are discarded and reads "
        .. "always yield 0. Every register has an ABI name, used interchangeably with "
        .. "its x-number in source. The Saver column gives the calling-convention "
        .. "owner (see Register Types)."
    ),
    rows({
      { key = "reg", header = "Register" },
      { key = "abi", header = "ABI" },
      { key = "saver", header = "Saver" },
      { key = "role", header = "Role" },
    }, GPRS),
    h2("Program counter and CSRs"),
    p(
      "The pc holds the address of the next instruction to execute and is not a "
        .. "general register; it resets to 0x80000000. Beyond the GPRs the Hart holds "
        .. "state for these machine-mode control and status registers:"
    ),
    tbl({ "Number", "Name", "Purpose" }, CSRS),
  },
}

local register_types = {
  id = "register-types",
  title = "Register Types",
  blocks = {
    h1("Register Types"),
    p(
      "The 32 general registers are identical hardware; what differs is the convention "
        .. "for who preserves each one across a function call. Following it lets your "
        .. "code call (and be called by) other routines without clobbering their state."
    ),
    h2("Callee-saved (saved registers)"),
    p(
      "sp, s0–s11. A function that uses one of these must save it on entry and restore "
        .. "it before returning, so a caller can rely on its value surviving the call. "
        .. "s0 doubles as the frame pointer (fp)."
    ),
    h2("Caller-saved (temporaries and arguments)"),
    p(
      "ra, t0–t6, a0–a7. These may be overwritten by any call, so a caller that needs "
        .. "a value afterwards must save it first. a0–a7 pass arguments; a0 and a1 also "
        .. "return results. ra holds the return address that ret jumps to."
    ),
    h2("Fixed-role registers"),
    p(
      "zero (x0) is the constant 0. gp (global pointer) and tp (thread pointer) are set "
        .. "up by the environment — read them if you must, but do not repurpose them."
    ),
    h2("Machine-mode CSRs"),
    p(
      "Separate from the GPRs, the CSRs carry trap and identification state: misa "
        .. "identifies the ISA, mtvec points at the trap handler, and on a trap the Hart "
        .. "records the return point in mepc, the reason in mcause, and the offending "
        .. "value in mtval. The CSRs and Traps chapter covers how a trap uses them."
    ),
  },
}

-- Instruction set (#25). Each row carries a concrete `ex` one-liner that the
-- coverage spec assembles, so the Manual can never list a mnemonic the Assembler
-- rejects (ADR-0008). `operands` is the display syntax; `ex` is real and runnable.
local INSN_COLS = {
  { key = "mnemonic", header = "Mnemonic" },
  { key = "operands", header = "Operands" },
  { key = "semantics", header = "Semantics" },
}
local function r(m, o, s, ex)
  return { mnemonic = m, operands = o, semantics = s, kind = "real", ex = ex }
end
local function ps(m, o, s, ex)
  return { mnemonic = m, operands = o, semantics = s, kind = "pseudo", ex = ex }
end

local ARITH = {
  r("add", "rd, rs1, rs2", "rd = rs1 + rs2", "add a0, a1, a2"),
  r("sub", "rd, rs1, rs2", "rd = rs1 - rs2", "sub a0, a1, a2"),
  r("and", "rd, rs1, rs2", "rd = rs1 & rs2", "and a0, a1, a2"),
  r("or", "rd, rs1, rs2", "rd = rs1 | rs2", "or a0, a1, a2"),
  r("xor", "rd, rs1, rs2", "rd = rs1 ^ rs2", "xor a0, a1, a2"),
  r("sll", "rd, rs1, rs2", "rd = rs1 << (rs2 & 31)", "sll a0, a1, a2"),
  r("srl", "rd, rs1, rs2", "rd = rs1 >> (rs2 & 31), logical", "srl a0, a1, a2"),
  r("sra", "rd, rs1, rs2", "rd = rs1 >> (rs2 & 31), arithmetic", "sra a0, a1, a2"),
  r("slt", "rd, rs1, rs2", "rd = (rs1 < rs2) ? 1 : 0, signed", "slt a0, a1, a2"),
  r("sltu", "rd, rs1, rs2", "rd = (rs1 < rs2) ? 1 : 0, unsigned", "sltu a0, a1, a2"),
  r("addi", "rd, rs1, imm", "rd = rs1 + imm", "addi a0, a1, 1"),
  r("andi", "rd, rs1, imm", "rd = rs1 & imm", "andi a0, a1, 1"),
  r("ori", "rd, rs1, imm", "rd = rs1 | imm", "ori a0, a1, 1"),
  r("xori", "rd, rs1, imm", "rd = rs1 ^ imm", "xori a0, a1, 1"),
  r("slti", "rd, rs1, imm", "rd = (rs1 < imm) ? 1 : 0, signed", "slti a0, a1, 1"),
  r("sltiu", "rd, rs1, imm", "rd = (rs1 < imm) ? 1 : 0, unsigned", "sltiu a0, a1, 1"),
  r("slli", "rd, rs1, shamt", "rd = rs1 << shamt", "slli a0, a1, 1"),
  r("srli", "rd, rs1, shamt", "rd = rs1 >> shamt, logical", "srli a0, a1, 1"),
  r("srai", "rd, rs1, shamt", "rd = rs1 >> shamt, arithmetic", "srai a0, a1, 1"),
}
local MULDIV = {
  r("mul", "rd, rs1, rs2", "rd = low 32 bits of rs1 * rs2", "mul a0, a1, a2"),
  r("mulh", "rd, rs1, rs2", "rd = high 32 bits, signed * signed", "mulh a0, a1, a2"),
  r("mulhu", "rd, rs1, rs2", "rd = high 32 bits, unsigned * unsigned", "mulhu a0, a1, a2"),
  r("mulhsu", "rd, rs1, rs2", "rd = high 32 bits, signed * unsigned", "mulhsu a0, a1, a2"),
  r("div", "rd, rs1, rs2", "rd = rs1 / rs2, signed (÷0 = -1)", "div a0, a1, a2"),
  r("divu", "rd, rs1, rs2", "rd = rs1 / rs2, unsigned (÷0 = all-ones)", "divu a0, a1, a2"),
  r("rem", "rd, rs1, rs2", "rd = rs1 % rs2, signed (sign of rs1)", "rem a0, a1, a2"),
  r("remu", "rd, rs1, rs2", "rd = rs1 % rs2, unsigned", "remu a0, a1, a2"),
}
local MEMOPS = {
  r("lw", "rd, off(rs1)", "rd = mem[rs1+off], 32-bit", "lw a0, 0(sp)"),
  r("lh", "rd, off(rs1)", "rd = mem[rs1+off], 16-bit sign-extended", "lh a0, 0(sp)"),
  r("lhu", "rd, off(rs1)", "rd = mem[rs1+off], 16-bit zero-extended", "lhu a0, 0(sp)"),
  r("lb", "rd, off(rs1)", "rd = mem[rs1+off], 8-bit sign-extended", "lb a0, 0(sp)"),
  r("lbu", "rd, off(rs1)", "rd = mem[rs1+off], 8-bit zero-extended", "lbu a0, 0(sp)"),
  r("sw", "rs2, off(rs1)", "mem[rs1+off] = rs2, 32-bit", "sw a0, 0(sp)"),
  r("sh", "rs2, off(rs1)", "mem[rs1+off] = rs2, low 16 bits", "sh a0, 0(sp)"),
  r("sb", "rs2, off(rs1)", "mem[rs1+off] = rs2, low 8 bits", "sb a0, 0(sp)"),
}
local CONTROL = {
  r("beq", "rs1, rs2, label", "branch if rs1 == rs2", "beq a0, a1, 1f"),
  r("bne", "rs1, rs2, label", "branch if rs1 != rs2", "bne a0, a1, 1f"),
  r("blt", "rs1, rs2, label", "branch if rs1 < rs2, signed", "blt a0, a1, 1f"),
  r("bge", "rs1, rs2, label", "branch if rs1 >= rs2, signed", "bge a0, a1, 1f"),
  r("bltu", "rs1, rs2, label", "branch if rs1 < rs2, unsigned", "bltu a0, a1, 1f"),
  r("bgeu", "rs1, rs2, label", "branch if rs1 >= rs2, unsigned", "bgeu a0, a1, 1f"),
  r("jal", "rd, label", "rd = pc+4; jump to label", "jal ra, 1f"),
  r("jalr", "rd, off(rs1)", "rd = pc+4; jump to rs1+off", "jalr ra, 0(a1)"),
}
local UPPER = {
  r("lui", "rd, imm20", "rd = imm20 << 12", "lui a0, 1"),
  r("auipc", "rd, imm20", "rd = pc + (imm20 << 12)", "auipc a0, 1"),
}
local SYSTEM = {
  r("csrrw", "rd, csr, rs1", "rd = csr; csr = rs1", "csrrw a0, mtvec, a1"),
  r("csrrs", "rd, csr, rs1", "rd = csr; csr |= rs1", "csrrs a0, mtvec, a1"),
  r("csrrc", "rd, csr, rs1", "rd = csr; csr &= ~rs1", "csrrc a0, mtvec, a1"),
  r("csrrwi", "rd, csr, zimm", "rd = csr; csr = zimm", "csrrwi a0, mtvec, 1"),
  r("csrrsi", "rd, csr, zimm", "rd = csr; csr |= zimm", "csrrsi a0, mtvec, 1"),
  r("csrrci", "rd, csr, zimm", "rd = csr; csr &= ~zimm", "csrrci a0, mtvec, 1"),
  r("ecall", "—", "trap to mtvec (machine ecall, mcause=11)", "ecall"),
  r("ebreak", "—", "breakpoint trap (mcause=3)", "ebreak"),
  r("mret", "—", "return from trap to mepc", "mret"),
  r("fence", "—", "memory ordering; a no-op on the single Hart", "fence"),
  r("fence.i", "—", "instruction-stream fence; a no-op here", "fence.i"),
  r("wfi", "—", "wait for interrupt; a no-op (no async interrupts)", "wfi"),
}

local instruction_set = {
  id = "instructions",
  title = "Instruction Set",
  blocks = {
    h1("Instruction Set"),
    p(
      "Every real instruction the Assembler encodes, by category. rd is the "
        .. "destination, rs1/rs2 the sources; imm is a 12-bit signed immediate, shamt a "
        .. "5-bit shift amount, zimm a 5-bit unsigned immediate, and csr a CSR name or "
        .. "number. Anything not listed here is rejected."
    ),
    h2("Arithmetic & logical"),
    rows(INSN_COLS, ARITH),
    h2("Multiply & divide (M)"),
    rows(INSN_COLS, MULDIV),
    h2("Loads & stores"),
    p("Memory is little-endian; misaligned access is allowed, not trapped."),
    rows(INSN_COLS, MEMOPS),
    h2("Control flow"),
    p("Branch and jump targets are written as labels; the Assembler resolves the offset."),
    rows(INSN_COLS, CONTROL),
    h2("Upper immediate & address"),
    rows(INSN_COLS, UPPER),
    h2("System & CSR (Zicsr)"),
    rows(INSN_COLS, SYSTEM),
  },
}

-- Pseudo-instructions (#25): the finite set the Assembler expands to real ops.
local PSEUDO = {
  ps("li", "rd, imm", "load a 32-bit immediate (addi, or lui+addi)", "li a0, 0x12345"),
  ps("la", "rd, symbol", "load address, pc-relative (auipc+addi)", "la a0, 0x80000100"),
  ps("lla", "rd, symbol", "load local address (same as la here)", "lla a0, 0x80000100"),
  ps("mv", "rd, rs", "rd = rs  (addi rd, rs, 0)", "mv a0, a1"),
  ps("nop", "—", "do nothing  (addi x0, x0, 0)", "nop"),
  ps("j", "label", "unconditional jump  (jal x0)", "j 1f"),
  ps("jr", "rs", "jump to rs  (jalr x0, 0(rs))", "jr a0"),
  ps("ret", "—", "return  (jalr x0, 0(ra))", "ret"),
  ps("beqz", "rs, label", "branch if rs == 0", "beqz a0, 1f"),
  ps("bnez", "rs, label", "branch if rs != 0", "bnez a0, 1f"),
  ps("ble", "rs1, rs2, label", "branch if rs1 <= rs2, signed", "ble a0, a1, 1f"),
  ps("bgt", "rs1, rs2, label", "branch if rs1 > rs2, signed", "bgt a0, a1, 1f"),
  ps("bleu", "rs1, rs2, label", "branch if rs1 <= rs2, unsigned", "bleu a0, a1, 1f"),
  ps("bgtu", "rs1, rs2, label", "branch if rs1 > rs2, unsigned", "bgtu a0, a1, 1f"),
  ps("csrr", "rd, csr", "read CSR  (csrrs rd, csr, x0)", "csrr a0, mtvec"),
  ps("csrw", "csr, rs", "write CSR  (csrrw x0, csr, rs)", "csrw mtvec, a0"),
  ps("csrwi", "csr, zimm", "write CSR immediate", "csrwi mtvec, 1"),
  ps("csrs", "csr, rs", "set CSR bits  (csrrs x0, csr, rs)", "csrs mtvec, a0"),
  ps("csrc", "csr, rs", "clear CSR bits  (csrrc x0, csr, rs)", "csrc mtvec, a0"),
  ps("csrsi", "csr, zimm", "set CSR bits, immediate", "csrsi mtvec, 1"),
  ps("csrci", "csr, zimm", "clear CSR bits, immediate", "csrci mtvec, 1"),
}

local pseudo_instructions = {
  id = "pseudo-instructions",
  title = "Pseudo-instructions",
  blocks = {
    h1("Pseudo-instructions"),
    p(
      "These are conveniences the Assembler expands into the real instructions above. "
        .. "They assemble to one or two real instructions; the expansion is shown in the "
        .. "Semantics column. This is the complete accepted set."
    ),
    rows(INSN_COLS, PSEUDO),
  },
}

-- Functions & Calling Convention (#26). Standard RISC-V integer ABI, transferable.
local FRAME_EXAMPLE = [[
caller:
  addi sp, sp, -16     # allocate a 16-byte stack frame
  sw   ra, 12(sp)      # save the return address (ra is caller-saved)
  sw   s0, 8(sp)       # save s0 (callee-saved) before reusing it
  mv   s0, a0          # keep the argument across the call
  jal  ra, callee      # call; may clobber a0-a7, t0-t6, ra
  add  a0, a0, s0      # combine the result with the preserved argument
  lw   ra, 12(sp)      # restore
  lw   s0, 8(sp)
  addi sp, sp, 16      # free the frame
  ret                  # jalr x0, 0(ra)
callee:
  ret
]]

local calling_convention = {
  id = "calling-convention",
  title = "Calling Convention",
  blocks = {
    h1("Functions & Calling Convention"),
    p(
      "This is the standard RISC-V integer calling convention — the same one a "
        .. "hardware RV32 toolchain uses, so the discipline transfers directly. A call "
        .. "is jal ra, target (which stores the return address in ra); the callee returns "
        .. "with ret (jalr x0, 0(ra)). Use jalr for a computed target."
    ),
    h2("Arguments and return values"),
    p(
      "Integer arguments go in a0–a7, left to right; further arguments spill to the "
        .. "stack. Results come back in a0 (and a1 for a 64-bit pair). a0–a7 are caller-"
        .. "saved: a callee may freely overwrite them."
    ),
    h2("Who saves what"),
    p(
      "Across a call, callee-saved registers keep their value and caller-saved ones may "
        .. "not. Save anything you need afterwards before calling, and restore any callee-"
        .. "saved register you reuse."
    ),
    tbl({ "Class", "Registers", "Preserved across a call?" }, {
      { "Callee-saved", "sp, s0–s11", "Yes — the callee restores them" },
      { "Caller-saved", "ra, t0–t6, a0–a7", "No — save them yourself first" },
      { "Arguments / return", "a0–a7 (a0, a1 return)", "No" },
      { "Fixed", "zero, gp, tp", "Not used for passing values" },
    }),
    h2("Stack frame, prologue and epilogue"),
    p(
      "The stack grows downward; sp stays 16-byte aligned. A non-leaf function opens "
        .. "with a prologue that allocates a frame and saves ra plus any callee-saved "
        .. "registers it touches, and closes with the mirror-image epilogue:"
    ),
    code(FRAME_EXAMPLE),
  },
}

-- Memory & Execution Model (#26). Accurate to lib/mem.lua and lib/asm.lua.
local memory_model = {
  id = "memory-model",
  title = "Memory & Execution Model",
  blocks = {
    h1("Memory & Execution Model"),
    p(
      "The Hart resets with pc = 0x80000000 and begins executing there; that address is "
        .. "the entry point of every assembled program. It runs one instruction per game "
        .. "tick until it writes tohost or faults."
    ),
    h2("Address space"),
    p(
      "Memory is flat, byte-addressable, sparse, and little-endian. It is zero-filled: "
        .. "any address never written reads back as 0, so there is no separate data "
        .. "section to reserve. lw/lh/lb (and the unsigned lhu/lbu) read 32/16/8 bits; "
        .. "sw/sh/sb write them. The low region around 0x10000000 is the Circuit-network "
        .. "controller (see Circuit I/O)."
    ),
    h2("Alignment — a deliberate deviation"),
    p(
      "Real RV32 traps a misaligned load or store. This Hart allows them: a word access "
        .. "at any address just composes the bytes. This matches the rv32ui-p-ma_data "
        .. "conformance fixture and means you never need alignment shims, but code that "
        .. "relies on it will not run on stock hardware."
    ),
    h2("Where code and data land"),
    p(
      "The Assembler flattens everything into one image in source order. .text, .data, "
        .. ".section and .pushsection are no-ops except for any .align they carry; only "
        .. ".align/.p2align move the location counter (padding code gaps with nop). So a "
        .. ".data label sits immediately after the statement before it, and labels simply "
        .. "get distinct, aligned addresses counting up from 0x80000000."
    ),
  },
}

-- CSRs & Traps (#26). Only the CSRs the Hart gives meaning to; the rest assemble
-- but are inert (lib/asm.lua's CSR table is broad; lib/hart.lua honours five).
local csrs_traps = {
  id = "csrs-traps",
  title = "CSRs & Traps",
  blocks = {
    h1("CSRs & Traps"),
    p(
      "The Hart is machine-mode only with no asynchronous interrupts, so the control and "
        .. "status registers that matter are the handful the trap path uses. Many more "
        .. "CSR names assemble (mstatus, mscratch, mie, …), but the Hart attaches no "
        .. "behaviour to them — they read back whatever was written, or 0. These five "
        .. "drive real behaviour:"
    ),
    tbl({ "CSR", "Role", "Active?" }, {
      { "misa", "Identifies the ISA; reads as RV32IM", "Read (identification)" },
      { "mtvec", "Trap-handler base address (direct mode; low bits ignored)", "Active" },
      { "mepc", "PC saved on trap entry; mret returns here", "Active" },
      { "mcause", "Cause code of the most recent trap", "Active" },
      { "mtval", "Faulting value: bad instruction word, else 0", "Active" },
    }),
    h2("The trap path"),
    p(
      "ecall, ebreak, and an illegal instruction all trap. On a trap the Hart records "
        .. "the cause in mcause, the current pc in mepc, and the offending value in mtval, "
        .. "then jumps to mtvec. mret returns to mepc. The cause codes are: 2 = illegal "
        .. "instruction, 3 = breakpoint (ebreak), 11 = environment call (ecall). There is "
        .. "no delegation and no interrupt handling — every trap goes straight to mtvec."
    ),
  },
}

-- Circuit I/O (#27): the mod-specific content. Accurate to lib/iocontroller.lua
-- (the MMIO map, doorbell offsets, CAP, STATUS bits) and lib/signalmap.lua.
local IO_EXAMPLE = [[
# Read both input wires, echo the largest signal back at double its value.
  li   s0, 0x10000000   # controller base: STATUS / SAMPLE / COMMIT / SNAPSHOT
  li   t0, 3
  sw   t0, 0x004(s0)    # SAMPLE both colours (red | green)
  lw   t1, 0x100(s0)    # t1 = number of signals sampled
  beqz t1, done         # nothing on the wires? skip
  lw   t2, 0x104(s0)    # id    of the largest sampled signal (pairs sort by value)
  lw   t3, 0x108(s0)    # value of the largest sampled signal
  add  t3, t3, t3       # double it
  li   s1, 0x10000800   # STAGING base: too far from s0 for one lw/sw offset
  li   t0, 1
  sw   t0, 0(s1)        # STAGING count = 1
  sw   t2, 4(s1)        # staged id
  sw   t3, 8(s1)        # staged value
  sw   zero, 0x008(s0)  # COMMIT -> flush staging onto the output wire
done:
  ret
]]

local circuit_io = {
  id = "circuit-io",
  title = "Circuit I/O",
  blocks = {
    h1("Circuit I/O"),
    p(
      "This is how a program talks to Factorio's circuit network — the one thing this "
        .. "Hart does that real RISC-V hardware cannot. The Circuit-network controller is "
        .. "a memory-mapped device at base 0x10000000 that you drive with ordinary loads "
        .. "and stores. You never wire it up in assembly; you read its snapshot and write "
        .. "its staging buffer."
    ),
    h2("Memory map"),
    p("All offsets are from the controller base 0x10000000:"),
    tbl({ "Offset", "Name", "Access", "Meaning" }, {
      {
        "0x000",
        "STATUS",
        "read",
        "bit0 = last Sample overflowed; bit1 = last Commit dropped an id",
      },
      {
        "0x004",
        "SAMPLE",
        "write",
        "doorbell; bit0 = red, bit1 = green (1=red, 2=green, 3=both), bit2 = query sample",
      },
      { "0x008", "COMMIT", "write", "doorbell; flush the staging buffer (value ignored)" },
      { "0x010", "Q1–Q16", "both", "Query registers: one signal id per word — you fill these" },
      { "0x100", "SNAPSHOT", "read", "word0 = count, then (id, value) pairs, largest value first" },
      { "0x800", "STAGING", "write", "word0 = count, then (id, value) pairs — you fill this" },
    }),
    p(
      "Each buffer holds up to 256 (id, value) pairs. SNAPSHOT and STAGING are 0x700 "
        .. "bytes apart, too far for a single load/store offset, so keep a base register "
        .. "per buffer rather than one for both."
    ),
    h2("Sample and Commit"),
    p(
      "A store to SAMPLE is a doorbell: between instructions the controller latches the "
        .. "chosen wires into an Input snapshot — a frozen copy. The circuit network "
        .. "changing afterwards cannot perturb a computation already in flight. With the "
        .. "'both' mask the two wires are summed per id, matching Factorio's own merge. "
        .. "You then read SNAPSHOT: word0 is the count, followed by that many id/value "
        .. "pairs sorted descending by signed value — the largest signal is always the "
        .. "first pair — with equal values ordered by id. If more than 256 signals were "
        .. "present, the largest 256 are kept and STATUS bit0 is set."
    ),
    h2("Query sample"),
    p(
      "Scanning a full snapshot for one signal costs a loop per entry; a query sample "
        .. "answers up to 16 signals you name in advance, at fixed offsets, in one Sample. "
        .. "Store each signal's id into a Query register (Q1 at 0x010 … Q16 at 0x04C, "
        .. "0 = slot unused) — they are ordinary memory you own, written once and kept "
        .. "across Samples. Then store the colour mask plus 4 to SAMPLE (5 = query red, "
        .. "6 = query green, 7 = query both). Instead of the full dump, SNAPSHOT word0 "
        .. "becomes the number of queries that found their signal on the wires, and pair "
        .. "n answers Qn: the id echoed back, then the value. A signal absent from the "
        .. "wires reads as value 0, like everywhere else in the circuit network; if the "
        .. "hit count is short, scan your pairs for the value-0 entries. A query sample "
        .. "writes only word0 and the 16 pairs — anything beyond is stale — and clears "
        .. "STATUS bit0, since a query never overflows."
    ),
    p(
      "Output works in reverse. You build a set in the Output staging buffer — count "
        .. "first, then id/value pairs — entirely in RAM, invisible on the wire. A store "
        .. "to COMMIT flushes the whole set atomically, so partial output never appears. "
        .. "Any staged id the Signal map cannot resolve is dropped and STATUS bit1 is set."
    ),
    code(IO_EXAMPLE),
    h2("Signals and the Signal map"),
    p(
      "Snapshot and staging entries are identified by small integer Signal IDs, not "
        .. "Factorio signal names. Source names a signal by its rich-text tag — "
        .. "[item=processing-unit], [fluid=water], [virtual-signal=signal-D] — and the "
        .. "Assembler resolves each tag to the save's integer ID, baking the number into "
        .. "the program. Only item, fluid and virtual-signal tags are accepted; quality "
        .. "clauses and other signal types are rejected."
    ),
    p(
      "The Signal map is per-save and append-only: an ID is assigned the first time a "
        .. "signal is named or seen, and never renumbered, so a running program's baked "
        .. "IDs stay valid for the life of the save. Because those IDs are baked in, an "
        .. "assembled program is not portable between saves — share the assembly source, "
        .. "which re-resolves its tags on assembly, not the image."
    ),
  },
}

-- Assembler Reference (#28). The directive/operator/label surface the Assembler
-- accepts, from lib/asm.lua. Honest subset: what is a no-op and what is rejected.
local assembler_reference = {
  id = "assembler-reference",
  title = "Assembler Reference",
  blocks = {
    h1("Assembler Reference"),
    p(
      "The Assembler turns your text into a program image in two passes. It is gas-like "
        .. "but small: this is the whole accepted surface. A line is split on ; into "
        .. "statements; # begins a comment to end of line; a statement is a label, a "
        .. "directive, an instruction, or a macro call."
    ),
    h2("Labels"),
    p(
      "A named label is foo: and marks the current address; use its name anywhere an "
        .. "expression is expected. A numeric label like 1: is local and reusable — refer "
        .. "to it as 1f for the next one forward or 1b for the previous one backward, which "
        .. "is how loops and short branches avoid inventing names."
    ),
    h2("Expressions"),
    p(
      "Immediates and addresses are constant expressions over unsigned 32-bit arithmetic "
        .. "(it wraps). Operands are decimal, 0x hex, a character constant like 'A', a "
        .. "label, or a combination. Operators, highest precedence first:"
    ),
    tbl({ "Operators", "Meaning" }, {
      { "( )", "grouping" },
      { "- ~ + (unary)", "negate, bitwise NOT, identity" },
      { "* / %", "multiply, divide, remainder" },
      { "+ -", "add, subtract" },
      { "<< >>", "shift left, shift right (logical)" },
      { "&", "bitwise AND" },
      { "^", "bitwise XOR" },
      { "|", "bitwise OR" },
    }),
    h2("Directives"),
    tbl({ "Directive", "Effect" }, {
      { ".align n / .p2align n", "advance to a 2^n boundary (pads code gaps with nop)" },
      { ".byte / .half / .word v, …", "emit 1 / 2 / 4-byte little-endian values" },
      { ".dword v, …", "emit 8 bytes (only the low 32 bits are non-zero)" },
      { ".fill rep, size, val", "emit rep copies of a size-byte value" },
      { ".zero n / .skip n", "emit n zero bytes" },
      { ".weak sym", "declare sym weak; an undefined weak symbol evaluates to 0" },
      { ".macro / .endm", "define a macro; call it by name" },
      { ".rept n / .endr", "repeat the enclosed block n times" },
      { ".globl, .section, .data, .text, …", "accepted but ignored (one flat section)" },
    }),
    p(
      "The ignored directives include .global, .pushsection, .popsection, .size, .type, "
        .. ".string, .file and .option — they parse without error but emit nothing, so "
        .. ".string does not place any bytes. Use .byte/.word for data."
    ),
    h2("Signal tags"),
    p(
      "A rich-text signal tag — [item=…], [fluid=…], [virtual-signal=…] — resolves to its "
        .. "integer Signal ID and can be used wherever a number can (see Circuit I/O)."
    ),
    h2("What is rejected"),
    p(
      "An unknown instruction, directive, register or CSR is an error, as is a quality "
        .. "clause on a signal tag ([item=iron-plate,quality=uncommon]) or any signal type "
        .. "other than item, fluid and virtual-signal. The Assembler refuses rather than "
        .. "guess, so a typo fails loudly instead of mis-assembling."
    ),
  },
}

-- Examples (#28): worked programs, each assembled by spec/manual_examples_spec.lua.
local TRAP_EXAMPLE = [[
# Install a trap handler, trigger it with ecall, then return.
_start:
  la   t0, handler
  csrw mtvec, t0        # point traps at our handler
  ecall                 # machine ecall -> mcause = 11 -> jump to mtvec
  j    done
handler:
  csrr t1, mcause       # why did we trap? (11 = ecall)
  csrr t2, mepc         # the faulting pc
  addi t2, t2, 4        # step past the ecall so we don't re-trap
  csrw mepc, t2
  mret                  # return to mepc
done:
  ret
]]

local examples = {
  id = "examples",
  title = "Examples",
  blocks = {
    h1("Examples"),
    p("Worked programs. Each one assembles as written; paste any into the Inspector and run it."),
    h2("Sum a range"),
    p("The default program: add 1 through 10, leaving 55 in a0."),
    code(SUM_EXAMPLE),
    h2("A function with a stack frame"),
    p("Prologue/epilogue discipline: save ra and a callee-saved register, call, restore, return."),
    code(FRAME_EXAMPLE),
    h2("Read, compute, commit"),
    p("Sample the input wires, transform a signal, and commit it to the output."),
    code(IO_EXAMPLE),
    h2("A trap handler"),
    p("Point mtvec at a handler, take an ecall, inspect mcause/mepc, and mret back."),
    code(TRAP_EXAMPLE),
  },
}

-- Vector extension chapter (#46): Zve32x, one chapter per extension. Every
-- accepted vector mnemonic gets a row with an assemblable example for the
-- coverage gate; rows are generated per suffix so the source stays sublinear
-- in the ~240 mnemonics. The open-ended memory families (segment and
-- whole-register forms) are documented as <n>/<eew> pattern rows, each still
-- carrying one concrete assemblable example.
local VSFX = {
  vv = { "vd, vs2, vs1", "v1, v2, v3" },
  vx = { "vd, vs2, rs1", "v1, v2, a0" },
  vi = { "vd, vs2, imm", "v1, v2, 5" },
  vvm = { "vd, vs2, vs1, v0", "v1, v2, v3, v0" },
  vxm = { "vd, vs2, rs1, v0", "v1, v2, a0, v0" },
  vim = { "vd, vs2, imm, v0", "v1, v2, 5, v0" },
  wv = { "vd, vs2w, vs1", "v2, v4, v3" },
  wx = { "vd, vs2w, rs1", "v2, v4, a0" },
  wi = { "vd, vs2w, uimm", "v2, v4, 5" },
  vs = { "vd, vs2, vs1", "v1, v2, v3" },
  mm = { "vd, vs2, vs1", "v1, v2, v3" },
  -- the multiply-accumulates put the multiplier first
  mv = { "vd, vs1, vs2", "v1, v2, v3" },
  mx = { "vd, rs1, vs2", "v1, a0, v2" },
}
local function vr(m, o, s, ex)
  return { mnemonic = m, operands = o, semantics = s, kind = "real", ex = ex }
end
-- one row per suffix in `sfxs` (space-separated), sharing one semantics text
local function vf(base, sfxs, sem)
  local out = {}
  for s in sfxs:gmatch("%S+") do
    local mm = base .. "." .. (s == "mv" and "vv" or s == "mx" and "vx" or s)
    local sh = VSFX[s]
    out[#out + 1] = vr(mm, sh[1], sem, mm .. " " .. sh[2])
  end
  return out
end
local function vcat(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, row in ipairs(list) do
      out[#out + 1] = row
    end
  end
  return out
end

local VCONFIG = {
  vr(
    "vsetvli",
    "rd, rs1, e<sew>, m<lmul>, t<a|u>, m<a|u>",
    "set vtype from the operand list and vl = min(rs1, VLMAX); rd = vl",
    "vsetvli t0, a0, e32, m1, ta, ma"
  ),
  vr(
    "vsetivli",
    "rd, uimm, e<sew>, m<lmul>, ...",
    "vsetvli with a 5-bit immediate AVL",
    "vsetivli t0, 4, e8, m2, ta, ma"
  ),
  vr(
    "vsetvl",
    "rd, rs1, rs2",
    "set vtype = rs2 (a saved vtype word) and vl from rs1",
    "vsetvl t0, a0, a1"
  ),
}

local VMEM = vcat({
  vr(
    "vle<eew>.v",
    "vd, (rs1) [, v0.t]",
    "unit-stride load at element width 8, 16, or 32",
    "vle32.v v1, (a0)"
  ),
  vr("vse<eew>.v", "vs3, (rs1) [, v0.t]", "unit-stride store", "vse32.v v1, (a0)"),
  vr(
    "vle<eew>ff.v",
    "vd, (rs1) [, v0.t]",
    "fault-only-first load: a fault past element 0 truncates vl instead of trapping",
    "vle8ff.v v1, (a0)"
  ),
  vr("vlm.v", "vd, (rs1)", "mask load: ceil(vl/8) bytes, always unmasked", "vlm.v v0, (a0)"),
  vr("vsm.v", "vs3, (rs1)", "mask store", "vsm.v v0, (a0)"),
  vr(
    "vlse<eew>.v",
    "vd, (rs1), rs2 [, v0.t]",
    "strided load: element e at rs1 + e*rs2",
    "vlse32.v v1, (a0), a1"
  ),
  vr("vsse<eew>.v", "vs3, (rs1), rs2 [, v0.t]", "strided store", "vsse32.v v1, (a0), a1"),
  vr(
    "vluxei<eew>.v",
    "vd, (rs1), vs2 [, v0.t]",
    "indexed (unordered) load: element e at rs1 + vs2[e]; the index EEW is the mnemonic's, data moves at SEW",
    "vluxei16.v v1, (a0), v2"
  ),
  vr(
    "vloxei<eew>.v",
    "vd, (rs1), vs2 [, v0.t]",
    "indexed (ordered) load",
    "vloxei16.v v1, (a0), v2"
  ),
  vr(
    "vsuxei<eew>.v",
    "vs3, (rs1), vs2 [, v0.t]",
    "indexed (unordered) store",
    "vsuxei16.v v1, (a0), v2"
  ),
  vr(
    "vsoxei<eew>.v",
    "vs3, (rs1), vs2 [, v0.t]",
    "indexed (ordered) store",
    "vsoxei16.v v1, (a0), v2"
  ),
  vr(
    "vl<n>re<eew>.v",
    "vd, (rs1)",
    "whole-register load of n = 1/2/4/8 registers, vl-independent",
    "vl2re32.v v2, (a0)"
  ),
  vr("vs<n>r.v", "vs3, (rs1)", "whole-register store of n registers", "vs2r.v v2, (a0)"),
  vr(
    "vlseg<n>e<eew>.v",
    "vd, (rs1) [, v0.t]",
    "unit-stride segment load: de-interleaves n fields into n register groups",
    "vlseg3e16.v v4, (a0)"
  ),
  vr(
    "vlseg<n>e<eew>ff.v",
    "vd, (rs1) [, v0.t]",
    "fault-only-first segment load",
    "vlseg3e16ff.v v4, (a0)"
  ),
  vr(
    "vsseg<n>e<eew>.v",
    "vs3, (rs1) [, v0.t]",
    "unit-stride segment store: interleaves n register groups",
    "vsseg3e16.v v4, (a0)"
  ),
  vr(
    "vlsseg<n>e<eew>.v",
    "vd, (rs1), rs2 [, v0.t]",
    "strided segment load",
    "vlsseg2e32.v v4, (a0), a1"
  ),
  vr(
    "vssseg<n>e<eew>.v",
    "vs3, (rs1), rs2 [, v0.t]",
    "strided segment store",
    "vssseg2e32.v v4, (a0), a1"
  ),
  vr(
    "vluxseg<n>ei<eew>.v",
    "vd, (rs1), vs2 [, v0.t]",
    "indexed (unordered) segment load",
    "vluxseg2ei16.v v4, (a0), v2"
  ),
  vr(
    "vloxseg<n>ei<eew>.v",
    "vd, (rs1), vs2 [, v0.t]",
    "indexed (ordered) segment load",
    "vloxseg2ei16.v v4, (a0), v2"
  ),
  vr(
    "vsuxseg<n>ei<eew>.v",
    "vs3, (rs1), vs2 [, v0.t]",
    "indexed (unordered) segment store",
    "vsuxseg2ei16.v v4, (a0), v2"
  ),
  vr(
    "vsoxseg<n>ei<eew>.v",
    "vs3, (rs1), vs2 [, v0.t]",
    "indexed (ordered) segment store",
    "vsoxseg2ei16.v v4, (a0), v2"
  ),
})

local VARITH = vcat(
  vf("vadd", "vv vx vi", "vd = vs2 + operand"),
  vf("vsub", "vv vx", "vd = vs2 - operand"),
  vf("vrsub", "vx vi", "vd = operand - vs2"),
  vf("vand", "vv vx vi", "bitwise and"),
  vf("vor", "vv vx vi", "bitwise or"),
  vf("vxor", "vv vx vi", "bitwise xor"),
  vf("vsll", "vv vx vi", "shift left; the shift uses the low lg2(SEW) bits"),
  vf("vsrl", "vv vx vi", "shift right logical"),
  vf("vsra", "vv vx vi", "shift right arithmetic"),
  vf("vminu", "vv vx", "unsigned minimum"),
  vf("vmin", "vv vx", "signed minimum"),
  vf("vmaxu", "vv vx", "unsigned maximum"),
  vf("vmax", "vv vx", "signed maximum"),
  {
    vr("vzext.vf2", "vd, vs2 [, v0.t]", "zero-extend SEW/2 source elements", "vzext.vf2 v1, v2"),
    vr("vsext.vf2", "vd, vs2 [, v0.t]", "sign-extend SEW/2 source elements", "vsext.vf2 v1, v2"),
    vr("vzext.vf4", "vd, vs2 [, v0.t]", "zero-extend SEW/4 source elements", "vzext.vf4 v1, v2"),
    vr("vsext.vf4", "vd, vs2 [, v0.t]", "sign-extend SEW/4 source elements", "vsext.vf4 v1, v2"),
  },
  vf("vadc", "vvm vxm vim", "vd = vs2 + operand + v0 carry-in (always unmasked)"),
  vf("vmadc", "vv vx vi vvm vxm vim", "carry-out of the add into mask register vd"),
  vf("vsbc", "vvm vxm", "vd = vs2 - operand - v0 borrow-in"),
  vf("vmsbc", "vv vx vvm vxm", "borrow-out of the subtract into mask register vd"),
  vf("vmerge", "vvm vxm vim", "vd[e] = v0[e] ? operand : vs2[e]"),
  {
    vr("vmv.v.v", "vd, vs1", "copy a vector", "vmv.v.v v1, v2"),
    vr("vmv.v.x", "vd, rs1", "splat a scalar", "vmv.v.x v1, a0"),
    vr("vmv.v.i", "vd, imm", "splat an immediate", "vmv.v.i v1, 5"),
  }
)

local VCMPS = vcat(
  vf("vmseq", "vv vx vi", "mask bit = (vs2 == operand)"),
  vf("vmsne", "vv vx vi", "mask bit = (vs2 != operand)"),
  vf("vmsltu", "vv vx", "mask bit = (vs2 < operand), unsigned"),
  vf("vmslt", "vv vx", "mask bit = (vs2 < operand), signed"),
  vf("vmsleu", "vv vx vi", "mask bit = (vs2 <= operand), unsigned"),
  vf("vmsle", "vv vx vi", "mask bit = (vs2 <= operand), signed"),
  vf("vmsgtu", "vx vi", "mask bit = (vs2 > operand), unsigned"),
  vf("vmsgt", "vx vi", "mask bit = (vs2 > operand), signed"),
  {
    {
      mnemonic = "vmsgt.vv",
      operands = "vd, vs1, vs2",
      semantics = "pseudo: vmslt.vv with the sources swapped",
      kind = "pseudo",
      ex = "vmsgt.vv v1, v2, v3",
    },
    {
      mnemonic = "vmsgtu.vv",
      operands = "vd, vs1, vs2",
      semantics = "pseudo: vmsltu.vv with the sources swapped",
      kind = "pseudo",
      ex = "vmsgtu.vv v1, v2, v3",
    },
  }
)

local VMULDIV = vcat(
  vf("vmul", "vv vx", "low half of the product"),
  vf("vmulh", "vv vx", "high half, signed x signed"),
  vf("vmulhu", "vv vx", "high half, unsigned x unsigned"),
  vf("vmulhsu", "vv vx", "high half, signed vs2 x unsigned operand"),
  vf("vdivu", "vv vx", "unsigned divide; /0 gives all-ones"),
  vf("vdiv", "vv vx", "signed divide; /0 gives -1, overflow wraps"),
  vf("vremu", "vv vx", "unsigned remainder; %0 gives the dividend"),
  vf("vrem", "vv vx", "signed remainder"),
  vf("vmacc", "mv mx", "vd += vs1 * vs2"),
  vf("vnmsac", "mv mx", "vd -= vs1 * vs2"),
  vf("vmadd", "mv mx", "vd = vs1 * vd + vs2"),
  vf("vnmsub", "mv mx", "vd = -(vs1 * vd) + vs2")
)

local VWIDE = vcat(
  vf(
    "vwaddu",
    "vv vx wv wx",
    "widening add, unsigned (destination at 2*SEW; .w forms read vs2 already wide)"
  ),
  vf("vwadd", "vv vx wv wx", "widening add, signed"),
  vf("vwsubu", "vv vx wv wx", "widening subtract, unsigned"),
  vf("vwsub", "vv vx wv wx", "widening subtract, signed"),
  vf("vwmulu", "vv vx", "widening multiply, unsigned"),
  vf("vwmulsu", "vv vx", "widening multiply, signed vs2 x unsigned operand"),
  vf("vwmul", "vv vx", "widening multiply, signed"),
  vf("vwmaccu", "mv mx", "widening vd += vs1 * vs2, unsigned"),
  vf("vwmacc", "mv mx", "widening MAC, signed"),
  vf("vwmaccsu", "mv mx", "widening MAC, signed vs1 x unsigned vs2"),
  {
    vr(
      "vwmaccus.vx",
      "vd, rs1, vs2",
      "widening MAC, unsigned rs1 x signed vs2",
      "vwmaccus.vx v1, a0, v2"
    ),
  }
)

local VFIXED = vcat(
  vf("vsaddu", "vv vx vi", "saturating add, unsigned (clamps and sets vxsat)"),
  vf("vsadd", "vv vx vi", "saturating add, signed"),
  vf("vssubu", "vv vx", "saturating subtract, unsigned (clamps at 0)"),
  vf("vssub", "vv vx", "saturating subtract, signed"),
  vf("vaaddu", "vv vx", "averaging add, unsigned: (vs2 + operand) >> 1 with vxrm rounding"),
  vf("vaadd", "vv vx", "averaging add, signed"),
  vf("vasubu", "vv vx", "averaging subtract, unsigned"),
  vf("vasub", "vv vx", "averaging subtract, signed"),
  vf("vsmul", "vv vx", "fractional multiply: (vs2 * operand) >> (SEW-1), rounded, saturating"),
  vf("vssrl", "vv vx vi", "scaling shift right logical, rounded per vxrm"),
  vf("vssra", "vv vx vi", "scaling shift right arithmetic, rounded"),
  vf("vnsrl", "wv wx wi", "narrowing shift right logical: vs2 at 2*SEW, result at SEW"),
  vf("vnsra", "wv wx wi", "narrowing shift right arithmetic"),
  vf("vnclipu", "wv wx wi", "narrowing clip, unsigned: round per vxrm, clamp to SEW, set vxsat"),
  vf("vnclip", "wv wx wi", "narrowing clip, signed")
)

local VRED = vcat(
  vf("vredsum", "vs", "vd[0] = sum(vs1[0], active vs2 elements)"),
  vf("vredand", "vs", "and-reduction"),
  vf("vredor", "vs", "or-reduction"),
  vf("vredxor", "vs", "xor-reduction"),
  vf("vredminu", "vs", "unsigned-min reduction"),
  vf("vredmin", "vs", "signed-min reduction"),
  vf("vredmaxu", "vs", "unsigned-max reduction"),
  vf("vredmax", "vs", "signed-max reduction"),
  vf("vwredsumu", "vs", "widening sum at 2*SEW, unsigned elements"),
  vf("vwredsum", "vs", "widening sum at 2*SEW, sign-extended elements")
)

local VMASK = vcat(
  vf("vmand", "mm", "mask and"),
  vf("vmnand", "mm", "mask nand"),
  vf("vmandn", "mm", "vs2 and not vs1"),
  vf("vmxor", "mm", "mask xor"),
  vf("vmor", "mm", "mask or"),
  vf("vmnor", "mm", "mask nor"),
  vf("vmorn", "mm", "vs2 or not vs1"),
  vf("vmxnor", "mm", "mask xnor"),
  {
    vr(
      "vcpop.m",
      "rd, vs2 [, v0.t]",
      "count the set (active) mask bits into x[rd]",
      "vcpop.m a0, v2"
    ),
    vr("vfirst.m", "rd, vs2 [, v0.t]", "index of the first set mask bit, or -1", "vfirst.m a0, v2"),
    vr(
      "vmsbf.m",
      "vd, vs2 [, v0.t]",
      "set bits strictly before the first set bit",
      "vmsbf.m v1, v2"
    ),
    vr("vmsif.m", "vd, vs2 [, v0.t]", "set bits up to and including the first", "vmsif.m v1, v2"),
    vr("vmsof.m", "vd, vs2 [, v0.t]", "set only the first set bit", "vmsof.m v1, v2"),
    vr("viota.m", "vd, vs2 [, v0.t]", "prefix count of set bits, written at SEW", "viota.m v1, v2"),
    vr("vid.v", "vd [, v0.t]", "element indices 0, 1, 2, ...", "vid.v v1"),
  }
)

local VPERM = vcat(
  {
    vr("vmv.x.s", "rd, vs2", "x[rd] = element 0, sign-extended", "vmv.x.s a0, v2"),
    vr("vmv.s.x", "vd, rs1", "element 0 of vd = rs1 (tail untouched)", "vmv.s.x v1, a0"),
  },
  vf("vslideup", "vx vi", "vd[e + offset] = vs2[e]; elements below the offset are untouched"),
  vf("vslidedown", "vx vi", "vd[e] = vs2[e + offset], 0 past VLMAX"),
  {
    vr(
      "vslide1up.vx",
      "vd, vs2, rs1 [, v0.t]",
      "slide up one; rs1 enters at element 0",
      "vslide1up.vx v1, v2, a0"
    ),
    vr(
      "vslide1down.vx",
      "vd, vs2, rs1 [, v0.t]",
      "slide down one; rs1 enters at element vl-1",
      "vslide1down.vx v1, v2, a0"
    ),
  },
  vf("vrgather", "vv vx vi", "vd[e] = vs2[index]; out-of-range indices read 0"),
  {
    vr(
      "vrgatherei16.vv",
      "vd, vs2, vs1 [, v0.t]",
      "gather with 16-bit indices regardless of SEW",
      "vrgatherei16.vv v1, v2, v4"
    ),
    vr(
      "vcompress.vm",
      "vd, vs2, vs1",
      "pack the vs1-selected elements of vs2 densely into vd",
      "vcompress.vm v1, v2, v0"
    ),
    vr(
      "vmv<n>r.v",
      "vd, vs2",
      "copy n = 1/2/4/8 whole registers, vtype-independent",
      "vmv2r.v v2, v4"
    ),
  }
)

local STRIP_EXAMPLE = [[
loop:                              # a0 = dst, a1 = src, a2 = words left
  vsetvli t0, a2, e32, m1, ta, ma  # grant vl = min(a2, 4) at VLEN=128
  vle32.v v1, (a1)                 # load up to four words
  vse32.v v1, (a0)                 # store them
  slli t1, t0, 2                   # bytes consumed = vl * 4
  add  a1, a1, t1
  add  a0, a0, t1
  sub  a2, a2, t0                  # words left -= vl
  bnez a2, loop                    # until the tail is drained
]]

local vector_ext = {
  id = "vector",
  title = "Vector Extension (Zve32x)",
  blocks = {
    h1("Vector Extension (Zve32x)"),
    p(
      "The Hart implements Zve32x, the integer-only embedded vector subset of RVV 1.0, "
        .. "at a fixed VLEN of 128 bits. A vector register holds sixteen 8-bit, eight "
        .. "16-bit, or four 32-bit elements; one vector instruction processes them all in "
        .. "a single tick, so bulk work over circuit data runs an order of magnitude "
        .. "faster than a scalar loop. Everything below is the complete accepted set — "
        .. "portable RVV idioms from tutorials and real hardware run unchanged."
    ),
    h2("Configuration"),
    p(
      "vsetvli picks the element width (e8/e16/e32), the register-group length LMUL "
        .. "(m1..m8 or the fractional mf2/mf4/mf8), the tail and mask policies (ta/tu, "
        .. "ma/mu), and grants vl = min(requested, VLMAX). VLMAX = VLEN * LMUL / SEW — "
        .. "16 bytes of elements per register in the group. The strip-mining idiom asks "
        .. "for everything and takes what it gets:"
    ),
    code(STRIP_EXAMPLE),
    rows(INSN_COLS, VCONFIG),
    h2("Vector CSRs"),
    tbl({ "CSR", "Name", "Role" }, {
      {
        "0x008",
        "vstart",
        "First element the next vector instruction executes (reset to 0 after each)",
      },
      { "0x009", "vxsat", "Sticky fixed-point saturation flag" },
      { "0x00A", "vxrm", "Fixed-point rounding mode: 0 rnu, 1 rne, 2 rdn, 3 rod" },
      { "0x00F", "vcsr", "vxrm and vxsat packed as vxrm[1:0]<<1 | vxsat" },
      { "0xC20", "vl", "Elements the current configuration operates on (read-only)" },
      { "0xC21", "vtype", "SEW / LMUL / policy word set by vset* (read-only)" },
      { "0xC22", "vlenb", "VLEN in bytes: always 16 (read-only)" },
    }),
    h2("Memory"),
    p(
      "Loads and stores move elements between vector registers and memory. <eew> in a "
        .. "mnemonic is the element width in bits (8, 16, or 32); <n> is the whole-register "
        .. "or segment count (1-8; n * LMUL stays within the file). A trailing `, v0.t` "
        .. "makes any maskable form skip inactive elements. Segment forms de-interleave "
        .. "records — vlseg2e32.v splits (id, value) pairs into two registers in one "
        .. "instruction."
    ),
    rows(INSN_COLS, VMEM),
    h2("Integer arithmetic"),
    p(
      "Elementwise over the active elements at the live SEW. The .vv form takes the "
        .. "second source from vs1, .vx from a scalar register (truncated to SEW), and "
        .. ".vi from a 5-bit immediate. A trailing `, v0.t` masks any of them."
    ),
    rows(INSN_COLS, VARITH),
    h2("Compares"),
    p(
      "Compares write one mask bit per element — feed the result to v0.t or the mask instructions."
    ),
    rows(INSN_COLS, VCMPS),
    h2("Multiply & divide"),
    rows(INSN_COLS, VMULDIV),
    h2("Widening"),
    p(
      "Widening forms write destination elements at 2*SEW (so e32 sources are reserved "
        .. "— ELEN is 32). The destination register group must be aligned to 2*LMUL."
    ),
    rows(INSN_COLS, VWIDE),
    h2("Fixed-point"),
    p(
      "Saturating forms clamp instead of wrapping and set the sticky vxsat flag. "
        .. "Averaging, scaling, and clip forms round the shifted-out bits per vxrm: "
        .. "rnu rounds half up, rne half to even, rdn truncates, rod jams the low bit."
    ),
    rows(INSN_COLS, VFIXED),
    h2("Reductions"),
    p(
      "Reductions collapse the active elements of vs2 into element 0 of vd, seeded "
        .. "from element 0 of vs1. vl = 0 leaves vd untouched."
    ),
    rows(INSN_COLS, VRED),
    h2("Mask instructions"),
    p(
      "Masks live one bit per element in any vector register; v0 is the one the "
        .. "`, v0.t` suffix reads. The logicals operate on the low vl bits."
    ),
    rows(INSN_COLS, VMASK),
    h2("Permutation"),
    rows(INSN_COLS, VPERM),
    h2("Circuit I/O interaction"),
    p(
      "The controller's data regions — the Query registers, the Input snapshot, and "
        .. "the Output staging — are ordinary memory to vector code: bulk-filling the "
        .. "staging with vector stores is the intended fast path. The trigger registers "
        .. "(Sample and Commit) are the exception: they are rung with scalar stores "
        .. "only, and any vector element store landing in that 16-byte window raises a "
        .. "store access-fault instead of a doorbell, so a slip in vector address "
        .. "arithmetic cannot fire a Sample or Commit you did not intend. Vector loads "
        .. "never fault."
    ),
  },
}

-- Extensions (#28): append-only placeholder establishing the one-chapter-per-
-- extension pattern. Nothing here is implemented yet.
local extensions = {
  id = "extensions",
  title = "Extensions",
  blocks = {
    h1("Extensions"),
    p(
      "The Manual grows by one chapter per extension the Hart gains. The base is "
        .. "RV32IM_Zicsr in machine mode, and every chapter before this one documents all "
        .. "of it. When an extension lands it appears here as its own chapter, leaving the "
        .. "existing chapters untouched. Nothing below is implemented yet:"
    ),
    tbl({ "Extension", "Status" }, {
      { "A — atomics", "Not implemented" },
      { "F / D — floating point", "Not implemented" },
      { "C — compressed encoding", "Not implemented" },
      { "Supervisor (S) mode", "Not implemented" },
      { "User (U) mode", "Not implemented" },
    }),
  },
}

return {
  overview,
  program_layout,
  registers,
  register_types,
  instruction_set,
  pseudo_instructions,
  calling_convention,
  memory_model,
  csrs_traps,
  circuit_io,
  assembler_reference,
  examples,
  vector_ext,
  extensions,
}
