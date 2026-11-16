#!/usr/bin/env python3
"""mips_trace.py -- run a small MIPS32 program and record its branch trace.

Owner: Mayank  |  Project 5: Dynamic Branch Prediction Unit

The program sums the non-zero elements of an array. It contains one BEQ
(skip zero elements) and one BNE (loop back). This script
  1. assembles each instruction into its 32-bit machine code (R/I format),
  2. executes the program on a tiny MIPS interpreter,
  3. writes every executed BEQ/BNE to traces/array_sum.csv.

usage: python3 python/mips_trace.py [out_dir]
"""
import os
import sys

from trace_io import Branch, write_trace

REG = {"$zero": 0, "$t0": 8, "$t1": 9, "$t2": 10, "$t3": 11, "$s0": 16}
TEXT_BASE = 0x00400000
ARRAY = [3, 0, 5, 7, 0, 0, 2, 9]

# (label, mnemonic, operands)
PROGRAM = [
    (None,   "addi", ("$t0", "$zero", 0)),       # i = 0
    (None,   "addi", ("$t1", "$zero", 8)),       # n = 8
    (None,   "addi", ("$s0", "$zero", 0)),       # sum = 0
    (None,   "addi", ("$t2", "$zero", 0x100)),   # p = &a[0]
    ("loop", "lw",   ("$t3", 0, "$t2")),         # t3 = *p
    (None,   "beq",  ("$t3", "$zero", "skip")),  # if (a[i] == 0) skip
    (None,   "add",  ("$s0", "$s0", "$t3")),     # sum += a[i]
    ("skip", "addi", ("$t2", "$t2", 4)),         # p++
    (None,   "addi", ("$t0", "$t0", 1)),         # i++
    (None,   "bne",  ("$t0", "$t1", "loop")),    # while (i != n)
    (None,   "sw",   ("$s0", 0x200, "$zero")),   # store sum
]
OPCODE = {"addi": 0x08, "lw": 0x23, "sw": 0x2B, "beq": 0x04, "bne": 0x05}


def asm_text(op, args):
    """Readable assembly, e.g. 'lw $t3, 0($t2)'."""
    if op in ("lw", "sw"):
        return f"{op:4s} {args[0]}, {args[1]:#x}({args[2]})"
    return f"{op:4s} " + ", ".join(str(a) for a in args)


def labels():
    return {lab: TEXT_BASE + 4 * i for i, (lab, _, _) in enumerate(PROGRAM) if lab}


def encode(pc, op, args, lab):
    """Return the 32-bit machine code of one instruction."""
    if op == "add":                                   # R-format: funct 0x20
        rd, rs, rt = (REG[a] for a in args)
        return (rs << 21) | (rt << 16) | (rd << 11) | 0x20
    if op in ("beq", "bne"):                          # I-format, PC-relative
        rs, rt, target = REG[args[0]], REG[args[1]], lab[args[2]]
        imm = ((target - (pc + 4)) >> 2) & 0xFFFF
        return (OPCODE[op] << 26) | (rs << 21) | (rt << 16) | imm
    if op in ("lw", "sw"):                            # I-format: rt, offset(rs)
        rt, off, rs = REG[args[0]], args[1], REG[args[2]]
        return (OPCODE[op] << 26) | (rs << 21) | (rt << 16) | (off & 0xFFFF)
    rt, rs, imm = REG[args[0]], REG[args[1]], args[2]  # addi
    return (OPCODE[op] << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF)


def run():
    """Execute the program; return (branch trace, final registers, memory)."""
    lab = labels()
    regs = [0] * 32
    mem = {0x100 + 4 * i: v for i, v in enumerate(ARRAY)}
    trace = []
    pc = TEXT_BASE
    end = TEXT_BASE + 4 * len(PROGRAM)
    while pc < end:
        _, op, a = PROGRAM[(pc - TEXT_BASE) // 4]
        next_pc = pc + 4
        if op == "addi":
            regs[REG[a[0]]] = regs[REG[a[1]]] + a[2]
        elif op == "add":
            regs[REG[a[0]]] = regs[REG[a[1]]] + regs[REG[a[2]]]
        elif op == "lw":
            regs[REG[a[0]]] = mem.get(regs[REG[a[2]]] + a[1], 0)
        elif op == "sw":
            mem[regs[REG[a[2]]] + a[1]] = regs[REG[a[0]]]
        else:                                         # beq / bne
            equal = regs[REG[a[0]]] == regs[REG[a[1]]]
            taken = equal if op == "beq" else not equal
            target = lab[a[2]]
            trace.append(Branch(pc, op.upper(), int(taken), target))
            if taken:
                next_pc = target
        regs[0] = 0
        pc = next_pc
    return trace, regs, mem


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "traces"
    os.makedirs(out_dir, exist_ok=True)
    lab = labels()
    print("Address   Machine code  Instruction")
    for i, (l, op, a) in enumerate(PROGRAM):
        pc = TEXT_BASE + 4 * i
        print(f"{pc:08x}  {encode(pc, op, a, lab):08x}      {(l + ':') if l else '':6s}{asm_text(op, a)}")
    trace, regs, mem = run()
    path = os.path.join(out_dir, "array_sum.csv")
    write_trace(path, trace)
    print(f"sum = {mem[0x200]} (expected {sum(ARRAY)}); {len(trace)} branches -> {path}")
    assert mem[0x200] == sum(ARRAY)


if __name__ == "__main__":
    main()
