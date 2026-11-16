"""trace_io.py -- read and write branch traces in CSV format.

Owner: Rohit  |  Project 5: Dynamic Branch Prediction Unit

CSV columns (header line is required):
    pc,type,taken,target
    00400010,BNE,1,00400000
pc / target : 8 hex digits (no 0x prefix, so Verilog $sscanf can read them)
type        : BEQ or BNE
taken       : 1 = branch taken, 0 = not taken
"""
import csv
from collections import namedtuple

Branch = namedtuple("Branch", "pc kind taken target")
HEADER = ["pc", "type", "taken", "target"]


def read_trace(path):
    """Return a list of Branch records from a CSV trace."""
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    out = []
    for i, r in enumerate(rows, start=2):
        kind = r["type"].strip().upper()
        if kind not in ("BEQ", "BNE"):
            raise ValueError(f"{path}:{i}: unknown branch type {kind!r}")
        out.append(Branch(int(r["pc"], 16), kind, int(r["taken"]), int(r["target"], 16)))
    return out


def write_trace(path, records):
    """Write Branch records (or 4-tuples) to a CSV trace."""
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(HEADER)
        for pc, kind, taken, target in records:
            w.writerow([f"{pc:08x}", kind, int(taken), f"{target:08x}"])
