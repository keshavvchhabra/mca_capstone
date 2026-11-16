#!/usr/bin/env python3
"""ref_model.py -- golden reference model of the branch prediction unit.

Owner: Rohit  |  Project 5: Dynamic Branch Prediction Unit

Mirrors the RTL bit for bit: PC indexing pc[INDEX+1:2], reset states
(1-bit = 0, 2-bit = 01), saturating update, tagged direct-mapped BTB written
only on taken branches, pred_target selection and the misprediction rule.

For each branch it writes one line of the expectation file:
    <pred_taken> <btb_hit> <pred_target-hex> <mispredict> <next_pc-hex>

usage: ref_model.py <trace.csv> <scheme 0|1|2> <out.exp> [bht_index_bits] [btb_index_bits]
"""
import sys

from trace_io import read_trace

MASK32 = 0xFFFFFFFF
SCHEMES = {0: "Static NT", 1: "1-bit BHT", 2: "2-bit BHT"}


class BranchPredictor:
    def __init__(self, scheme, bht_bits=4, btb_bits=4, ctr_width=2):
        self.scheme = scheme
        self.bht_bits, self.btb_bits = bht_bits, btb_bits
        self.ctr_max = (1 << ctr_width) - 1
        self.ctr_msb = 1 << (ctr_width - 1)
        init = 0 if scheme == 1 else self.ctr_msb - 1   # 1-bit: 0, 2-bit: 01
        self.bht = [init] * (1 << bht_bits)
        self.btb = [None] * (1 << btb_bits)             # (tag, target) or None

    def bht_index(self, pc):
        return (pc >> 2) & ((1 << self.bht_bits) - 1)

    def btb_split(self, pc):
        return (pc >> 2) & ((1 << self.btb_bits) - 1), pc >> (self.btb_bits + 2)

    def state(self, pc):
        return 0 if self.scheme == 0 else self.bht[self.bht_index(pc)]

    def predict(self, pc):
        """Return (pred_taken, btb_hit, pred_target)."""
        if self.scheme == 0:
            direction = 0
        elif self.scheme == 1:
            direction = self.bht[self.bht_index(pc)]
        else:
            direction = int(bool(self.bht[self.bht_index(pc)] & self.ctr_msb))
        idx, tag = self.btb_split(pc)
        entry = self.btb[idx]
        hit = int(entry is not None and entry[0] == tag)
        target = entry[1] if (direction and hit) else (pc + 4) & MASK32
        return direction, hit, target

    def update(self, pc, taken, target):
        i = self.bht_index(pc)
        if self.scheme == 1:
            self.bht[i] = taken
        elif self.scheme == 2:
            c = self.bht[i]
            self.bht[i] = min(c + 1, self.ctr_max) if taken else max(c - 1, 0)
        if taken:
            idx, tag = self.btb_split(pc)
            self.btb[idx] = (tag, target)


def simulate(trace, scheme, bht_bits=4, btb_bits=4):
    """Run a trace; return one dict per branch (prediction + outcome)."""
    p = BranchPredictor(scheme, bht_bits, btb_bits)
    rows = []
    for b in trace:
        state = p.state(b.pc)
        pt, hit, ptgt = p.predict(b.pc)
        mis = int(pt != b.taken or (pt and b.taken and ptgt != b.target))
        correct_pc = b.target if b.taken else (b.pc + 4) & MASK32
        next_pc = correct_pc if mis else ptgt
        rows.append(dict(pc=b.pc, taken=b.taken, state=state, pred=pt, hit=hit,
                         pred_target=ptgt, mispredict=mis, next_pc=next_pc))
        p.update(b.pc, b.taken, b.target)
    return rows


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    trace_path, scheme, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    bht_bits = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    btb_bits = int(sys.argv[5]) if len(sys.argv) > 5 else 4
    trace = read_trace(trace_path)
    rows = simulate(trace, scheme, bht_bits, btb_bits)
    with open(out, "w") as f:
        for r in rows:
            f.write(f"{r['pred']} {r['hit']} {r['pred_target']:08x} {r['mispredict']} "
                    f"{r['next_pc']:08x}\n")
    n = len(rows)
    correct = sum(r["pred"] == r["taken"] for r in rows)
    print(f"MODEL {SCHEMES[scheme]}: branches={n} correct={correct} "
          f"mispred={sum(r['mispredict'] for r in rows)} btb_hits={sum(r['hit'] for r in rows)}")


if __name__ == "__main__":
    main()
