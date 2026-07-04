-- Zve32x vector walking skeleton (#37): configuration, unit-stride memory,
-- vadd, VS gating, and the store watch, observed at the architectural seam
-- (assemble -> run -> registers/CSRs/memory), the same hart-level style as
-- circuit_io_spec. Conformance against riscv-vector-tests fixtures lives in
-- conformance_spec; these specs drive the element loop at development
-- granularity. VLEN=128 is frozen (ADR-0012).
local asm = require("asm")
local Mem = require("mem")
local Hart = require("hart")

local VSTART, VXRM = 0x008, 0x00A
local VL, VTYPE, VLENB = 0xC20, 0xC21, 0xC22
local MCAUSE = 0x342

-- assemble and run until the pc leaves the listing (or a step budget), so a
-- program simply ends by falling past its last instruction. Returns the hart
-- and the image (for symbol addresses).
local function run(src, steps)
  local image = asm.assemble(src)
  local h = Hart.new(Mem.new())
  h:load(image)
  for _ = 1, steps or 1000 do
    if not image.words[h.pc] then
      break
    end
    h:step()
  end
  return h, image
end

describe("vector configuration (vsetvli/vsetivli/vsetvl)", function()
  it("grants vl = AVL when AVL <= VLMAX and records vtype", function()
    local h = run([[
      li a0, 3
      vsetvli t0, a0, e32, m1, ta, ma
    ]])
    assert.are.equal(3, h.x[5]) -- t0 = granted vl
    assert.are.equal(3, h.csr[VL])
    -- e32 -> vsew=2 (bits 5:3), m1 -> vlmul=0, ta -> bit 6, ma -> bit 7
    assert.are.equal(0xD0, h.csr[VTYPE])
  end)

  it("caps vl at VLMAX (VLEN=128: e32 m1 -> 4)", function()
    local h = run([[
      li a0, 99
      vsetvli t0, a0, e32, m1, ta, ma
    ]])
    assert.are.equal(4, h.x[5])
    assert.are.equal(4, h.csr[VL])
  end)

  it("rs1=x0, rd!=x0 selects VLMAX (e8 m8 -> 128)", function()
    local h = run([[ vsetvli t0, x0, e8, m8, tu, mu ]])
    assert.are.equal(128, h.x[5])
    assert.are.equal(128, h.csr[VL])
    -- e8 m8 tu mu -> vsew=0, vlmul=3, vta=0, vma=0
    assert.are.equal(0x03, h.csr[VTYPE])
  end)

  it("supports fractional LMUL (e8 mf4 -> VLMAX 4)", function()
    local h = run([[ vsetvli t0, x0, e8, mf4, tu, mu ]])
    assert.are.equal(4, h.x[5])
  end)

  it("sets vill (and vl=0) for an unsupported vtype (e8 mf8 on ELEN=32)", function()
    local h = run([[ vsetvli t0, x0, e8, mf8, tu, mu ]])
    assert.are.equal(0x80000000, h.csr[VTYPE])
    assert.are.equal(0, h.csr[VL])
    assert.are.equal(0, h.x[5])
  end)

  it("vsetivli takes AVL from the immediate", function()
    local h = run([[ vsetivli t0, 7, e16, m2, ta, ma ]])
    assert.are.equal(7, h.x[5])
    assert.are.equal(7, h.csr[VL])
    -- e16 -> vsew=1, m2 -> vlmul=1
    assert.are.equal(0xC9, h.csr[VTYPE])
  end)

  it("vsetvl takes vtype from a register", function()
    local h = run([[
      li a0, 5
      li a1, 0xD0    # e32, m1, ta, ma
      vsetvl t0, a0, a1
    ]])
    assert.are.equal(4, h.x[5]) -- VLMAX e32 m1 = 4
    assert.are.equal(0xD0, h.csr[VTYPE])
  end)
end)

describe("vector CSRs", function()
  it("vlenb reads 16 and the state CSRs read back", function()
    local h = run([[
      csrr t0, vlenb
      csrwi vxrm, 2
      csrr t1, vxrm
      csrr t2, vcsr
      csrwi vcsr, 0
      csrr t3, vxrm
      csrr t4, vstart
    ]])
    assert.are.equal(16, h.x[5]) -- t0: vlenb = VLEN/8
    assert.are.equal(2, h.x[6]) -- t1: vxrm as written
    assert.are.equal(4, h.x[7]) -- t2: vcsr mirrors vxrm<<1|vxsat
    assert.are.equal(0, h.x[28]) -- t3: vcsr write cleared vxrm
    assert.are.equal(0, h.x[29]) -- t4: vstart resets to 0
    assert.are.equal(16, h.csr[VLENB])
    assert.are.equal(0, h.csr[VSTART])
    assert.are.equal(0, h.csr[VXRM])
  end)
end)

describe("mstatus.VS gate", function()
  it("vector instructions trap illegal while VS is Off", function()
    local h = run([[
      li t1, 0x600
      csrc mstatus, t1     # force VS = Off
      vsetvli t0, x0, e32, m1, ta, ma
    ]])
    assert.are.equal(2, h.csr[MCAUSE]) -- illegal instruction
    assert.are.equal(0, h.x[5]) -- t0 untouched
  end)

  it("resets with VS enabled so vector instructions execute", function()
    local h = run([[ vsetvli t0, x0, e32, m1, ta, ma ]])
    assert.are.equal(4, h.x[5])
  end)
end)

describe("unit-stride load/store and vadd", function()
  it("vle32/vadd.vv/vse32 computes elementwise sums", function()
    local h, image = run([[
      la a0, src1
      la a1, src2
      la a2, out
      vsetvli t0, x0, e32, m1, ta, ma
      vle32.v v1, (a0)
      vle32.v v2, (a1)
      vadd.vv v3, v1, v2
      vse32.v v3, (a2)
    src1: .word 1, 2, 3, 4
    src2: .word 10, 20, 30, 40
    out:  .word 0, 0, 0, 0
    ]])
    local out = image.symbols.out
    assert.are.equal(11, h.mem:r32(out))
    assert.are.equal(22, h.mem:r32(out + 4))
    assert.are.equal(33, h.mem:r32(out + 8))
    assert.are.equal(44, h.mem:r32(out + 12))
  end)

  it("v0.t masks inactive elements (mu: destination undisturbed)", function()
    local h, image = run([[
      la a0, mask
      la a1, src1
      la a2, src2
      la a3, out
      vsetvli t0, x0, e32, m1, tu, mu
      vle32.v v0, (a0)     # mask bits: 0101 -> elements 0 and 2 active
      vle32.v v1, (a1)
      vle32.v v2, (a2)
      vle32.v v3, (a3)     # preload destination with sentinels
      vadd.vv v3, v1, v2, v0.t
      vse32.v v3, (a3)
    mask: .word 5, 0, 0, 0
    src1: .word 1, 2, 3, 4
    src2: .word 10, 20, 30, 40
    out:  .word 100, 200, 300, 400
    ]])
    local out = image.symbols.out
    assert.are.equal(11, h.mem:r32(out)) -- active
    assert.are.equal(200, h.mem:r32(out + 4)) -- masked off: undisturbed
    assert.are.equal(33, h.mem:r32(out + 8)) -- active
    assert.are.equal(400, h.mem:r32(out + 12)) -- masked off: undisturbed
  end)

  it("vle8/vse8 and vle16/vse16 move bytes and halfwords", function()
    local h, image = run([[
      la a0, bytes
      la a1, out8
      la a2, halves
      la a3, out16
      vsetvli t0, x0, e8, m1, tu, mu
      vle8.v v1, (a0)
      vse8.v v1, (a1)
      vsetvli t0, x0, e16, m1, tu, mu
      vle16.v v2, (a2)
      vse16.v v2, (a3)
    bytes:  .byte 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
    out8:   .zero 16
    halves: .half 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000
    out16:  .zero 16
    ]])
    assert.are.equal(1, h.mem:rb(image.symbols.out8))
    assert.are.equal(16, h.mem:rb(image.symbols.out8 + 15))
    assert.are.equal(1000, h.mem:r16(image.symbols.out16))
    assert.are.equal(8000, h.mem:r16(image.symbols.out16 + 14))
  end)

  it("vmv.v.i splats the immediate", function()
    local h, image = run([[
      la a0, out
      vsetvli t0, x0, e32, m1, tu, mu
      vmv.v.i v4, 6
      vse32.v v4, (a0)
    out: .word 9, 9, 9, 9
    ]])
    assert.are.equal(6, h.mem:r32(image.symbols.out))
    assert.are.equal(6, h.mem:r32(image.symbols.out + 12))
  end)
end)

describe("vector element stores and the watch", function()
  it("a vse32 element store into tohost halts like a scalar sw", function()
    local image = asm.assemble([[
      la a0, vals
      la a1, tohost
      vsetvli t0, x0, e32, m1, tu, mu
      vle32.v v1, (a0)
      vse32.v v1, (a1)
    1: j 1b
    vals:   .word 1, 0, 0, 0
    .align 6
    tohost: .dword 0
    ]])
    local h = Hart.new(Mem.new())
    h:load(image)
    local r = h:run({ max_steps = 100 })
    assert.are.equal(1, r.tohost)
  end)
end)

describe("vector state is plain data", function()
  it("v registers hold only numbers after vector execution", function()
    local h = run([[
      vsetvli t0, x0, e32, m8, tu, mu
      vmv.v.i v8, 3
    ]])
    for i = 0, 31 do
      local reg = h.v[i]
      assert.are.equal("table", type(reg))
      assert.are.equal(4, #reg) -- VLEN=128 = 4 words
      for w = 1, 4 do
        assert.are.equal("number", type(reg[w]))
      end
    end
    -- splat landed across the whole v8..v15 group
    assert.are.equal(3, h.v[8][1])
    assert.are.equal(3, h.v[15][4])
  end)
end)
