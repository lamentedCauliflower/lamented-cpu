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

return { overview, registers, register_types }
