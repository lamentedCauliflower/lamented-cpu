-- Manual content (ADR-0008): the chapter list, authored inline. Each entry is a
-- chapter { id, title, blocks }; the first is the Overview (the Informatron root /
-- the Booktorio book's first topic). Later issues append chapters here.
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

return {
  overview,
  registers,
  register_types,
  instruction_set,
  pseudo_instructions,
  calling_convention,
  memory_model,
  csrs_traps,
}
