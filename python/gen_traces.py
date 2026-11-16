#!/usr/bin/env python3
"""gen_traces.py -- generate loop-oriented BEQ/BNE branch traces (CSV).

Owner: Rohit  |  Project 5: Dynamic Branch Prediction Unit

Traces produced in traces/:
  loop10       single loop, 10 iterations (9 T + 1 NT), run 10 times
  loop100      single loop, 100 iterations, run 3 times
  nested       nested loops: inner 4 iterations, outer 10 iterations
  alternating  T, NT, T, NT ...  (worst case for 1-bit and 2-bit)
  random       one data-dependent branch, 50 % taken (seeded)
  multi_alias  5 branches, two of them alias in a 16-entry BHT
  mixed        loop + if/else + periodic if, data-dependent (seeded)
(array_sum.csv is produced separately by mips_trace.py from a real MIPS program.)

usage: python3 python/gen_traces.py [out_dir]
"""
import os
import random
import sys

from trace_io import Branch, write_trace


def loop(pc, target, iters, kind="BNE"):
    """A loop-closing branch: taken (iters-1) times, then not taken once."""
    return [Branch(pc, kind, int(i < iters - 1), target) for i in range(iters)]


def t_loop10():
    # for (r = 0; r < 10; r++) for (i = 0; i < 10; i++) {...}   -> inner branch only
    out = []
    for _ in range(10):
        out += loop(0x00400010, 0x00400000, 10)
    return out


def t_loop100():
    out = []
    for _ in range(3):
        out += loop(0x00400110, 0x00400100, 100)
    return out


def t_nested():
    out = []
    for o in range(10):
        out += loop(0x00400208, 0x00400204, 4)                       # inner BNE
        out.append(Branch(0x00400210, "BNE", int(o < 9), 0x00400200))  # outer BNE
    return out


def t_alternating():
    # if (i % 2 == 0) ...
    return [Branch(0x00400300, "BEQ", int(i % 2 == 0), 0x00400318) for i in range(100)]


def t_random(seed=7):
    # if (a[i] > threshold) ...  with random data: no pattern to learn
    rng = random.Random(seed)
    return [Branch(0x00400604, "BEQ", int(rng.random() < 0.5), 0x00400620) for _ in range(200)]


def t_multi_alias():
    # BHT index (16 entries) = pc[5:2]:
    #   0x00400404 -> 1, 0x00400408 -> 2, 0x0040040C -> 3
    #   0x00400410 -> 4 and 0x00400450 -> 4   <-- alias pair (differ by 16*4 = 0x40)
    out = []
    for i in range(50):
        out.append(Branch(0x00400404, "BEQ", 1, 0x00400480))              # always taken
        out.append(Branch(0x00400408, "BNE", 0, 0x004004A0))              # never taken
        out.append(Branch(0x0040040C, "BNE", int(i % 5 != 4), 0x00400400))  # loop of 5
        out.append(Branch(0x00400410, "BEQ", 1, 0x004004C0))              # alias A: always T
        out.append(Branch(0x00400450, "BNE", 0, 0x004004E0))              # alias B: always NT
    return out


def t_mixed(seed=2026):
    # for (i = 0; i < 40; i++) {
    #     if (a[i] < 0) {...}          BEQ, data dependent (30 % taken)
    #     for (j = 0; j < 3; j++) {}   inner BNE
    #     if (i % 4 == 3) {...}        BEQ, periodic
    # }                                outer BNE
    rng = random.Random(seed)
    out = []
    for i in range(40):
        out.append(Branch(0x00400504, "BEQ", int(rng.random() < 0.3), 0x00400514))
        out += loop(0x0040051C, 0x00400518, 3)
        out.append(Branch(0x00400524, "BEQ", int(i % 4 == 3), 0x0040052C))
        out.append(Branch(0x00400530, "BNE", int(i < 39), 0x00400500))
    return out


TRACES = {
    "loop10": t_loop10,
    "loop100": t_loop100,
    "nested": t_nested,
    "alternating": t_alternating,
    "random": t_random,
    "multi_alias": t_multi_alias,
    "mixed": t_mixed,
}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "traces"
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in TRACES.items():
        recs = fn()
        path = os.path.join(out_dir, name + ".csv")
        write_trace(path, recs)
        print(f"{path:26s} {len(recs):4d} branches, {sum(r.taken for r in recs):4d} taken")


if __name__ == "__main__":
    main()
