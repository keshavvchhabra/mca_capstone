#!/usr/bin/env python3
"""synth_report.py -- synthesize bpu_top with Yosys for every scheme.

Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit

Two flows per scheme:
  generic : technology-independent gates  (synth -flatten; check -assert; ltp)
  xilinx  : Xilinx 7-series FPGA mapping  (synth_xilinx -flatten) -> LUTs, FFs, carry
Writes results/synthesis/<flow>_scheme<k>.log and results/synthesis/synthesis_summary.md.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "results", "synthesis")
BUILD = os.path.join(ROOT, "build")
NAMES = {0: "Static NT", 1: "1-bit BHT", 2: "2-bit BHT"}
FLOWS = {
    "generic": "synth -flatten -top bpu_top\ncheck -assert\nstat\nltp -noff",
    "xilinx": "synth_xilinx -flatten -top bpu_top\ncheck -assert\nstat",
}


def run(flow, scheme):
    with open(os.path.join(ROOT, "synth", "synth.ys")) as f:
        script = f.read().replace("SCHEME_VALUE", str(scheme)).replace("TARGET_COMMANDS", FLOWS[flow])
    ys = os.path.join(BUILD, f"synth_{flow}_{scheme}.ys")
    with open(ys, "w") as f:
        f.write(script)
    out = subprocess.run(["yosys", "-s", ys], cwd=ROOT, capture_output=True, text=True)
    with open(os.path.join(OUT, f"{flow}_scheme{scheme}.log"), "w") as f:
        f.write(out.stdout + out.stderr)
    if out.returncode != 0:
        sys.exit(f"yosys failed ({flow}, scheme {scheme}); see results/synthesis/")
    # keep only the final statistics block
    stat = out.stdout[out.stdout.rfind("Printing statistics"):]
    cells = {m.group(2): int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+(\$?\w+)\s*$", stat, re.M)}
    total = re.search(r"^\s+(\d+)\s+cells\s*$", stat, re.M)
    depth = re.search(r"Longest topological path in \S+ \(length=(\d+)\)", out.stdout)
    latches = sum(v for k, v in cells.items() if "DLATCH" in k.upper() or k.upper().startswith("LD"))
    return dict(total=int(total.group(1)) if total else 0, cells=cells,
                depth=int(depth.group(1)) if depth else None, latches=latches)


def main():
    if not shutil.which("yosys"):
        sys.exit("yosys not found (macOS: brew install yosys)")
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    gen = {s: run("generic", s) for s in NAMES}
    xil = {s: run("xilinx", s) for s in NAMES}

    def ffs(c):
        return sum(v for k, v in c.items() if "DFF" in k.upper() or k in ("FDRE", "FDSE", "FDCE", "FDPE"))

    def luts(c):
        return sum(v for k, v in c.items() if re.fullmatch(r"LUT\d", k))

    L = ["# Synthesis Results (Yosys)", "",
         f"Design: `bpu_top` (predictor + BTB + update/selection logic + flush control), "
         "32-bit PC, 16-entry BHT, 16-entry BTB, 32-bit performance counters.", "",
         "## Generic gate-level synthesis (`synth -flatten`)", "",
         "| Scheme | Total cells | Flip-flops | Latches | Logic depth (gates) | check -assert |",
         "|---|---:|---:|---:|---:|---|"]
    for s in NAMES:
        g = gen[s]
        L.append(f"| {NAMES[s]} | {g['total']} | {ffs(g['cells'])} | {g['latches']} | {g['depth']} | passed |")
    L += ["", "## Xilinx 7-series FPGA mapping (`synth_xilinx -flatten`)", "",
          "| Scheme | LUTs | Flip-flops (FDRE/FDSE) | CARRY4 | LUTRAM (RAM32M) | I/O buffers (IBUF/OBUF) |",
          "|---|---:|---:|---:|---:|---:|"]
    for s in NAMES:
        c = xil[s]["cells"]
        lutram = sum(v for k, v in c.items() if k.startswith("RAM"))
        io = c.get("IBUF", 0) + c.get("OBUF", 0)
        L.append(f"| {NAMES[s]} | {luts(c)} | {ffs(c)} | {c.get('CARRY4', 0)} | {lutram} | {io} |")
    L += ["", "Notes: the BTB tag/target arrays map to distributed LUTRAM (RAM32M), so they do not",
          "appear as flip-flops in the FPGA mapping. The I/O buffer count reflects the wide",
          "debug/counter ports of the standalone unit; inside a CPU these would be internal wires.",
          "Per-cell breakdowns are in the `*.log` files in this folder.",
          "Maximum frequency requires place-and-route with timing (e.g. Vivado); "
          "Yosys reports logic depth only."]
    with open(os.path.join(OUT, "synthesis_summary.md"), "w") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
