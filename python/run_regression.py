#!/usr/bin/env python3
"""run_regression.py -- run every trace on every scheme in Icarus Verilog.

Owner: Sarvesh  |  Project 5: Dynamic Branch Prediction Unit

For each (trace, scheme[, BHT size]):
  1. the golden model writes build/<run>.exp
  2. the RTL testbench (tb_predictor.v + all of rtl/) runs the same trace and
     compares every output with the expectation file
  3. the RESULT line is parsed and stored

Outputs:
  results/simulation_results.csv   one row per trace x scheme (16-entry BHT)
  results/bht_sweep.csv            BHT-size sweep (with --sweep)
  results/logs/<trace>_s<k>.log    raw simulator output

usage: python3 python/run_regression.py [--sweep]
Exit status is non-zero if any run fails.
"""
import csv
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
RESULTS = os.path.join(ROOT, "results")
LOGS = os.path.join(RESULTS, "logs")
SCHEMES = (0, 1, 2)
SWEEP_BITS = (2, 3, 4, 5, 6)                       # 4 .. 64 entries
SWEEP_TRACES = ("multi_alias", "mixed", "nested", "random")
RESULT_RE = re.compile(r"RESULT name=(\S+) scheme=(\d+) bht=(\d+) branches=(\d+) "
                       r"correct=(\d+) mispred=(\d+) btb_hits=(\d+) penalty=(\d+)")


def sh(cmd):
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def traces():
    return sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(ROOT, "traces", "*.csv")))


def compile_tb(scheme, bht_bits):
    vvp = os.path.join(BUILD, f"tb_s{scheme}_b{bht_bits}.vvp")
    rtl = sorted(glob.glob(os.path.join(ROOT, "rtl", "*.v")))
    sh(["iverilog", "-Wall", "-g2005", f"-Ptb_predictor.SCHEME={scheme}",
        f"-Ptb_predictor.BHT_INDEX_BITS={bht_bits}", "-o", vvp,
        os.path.join(ROOT, "testbench", "tb_predictor.v"), *rtl])
    return vvp


def run_one(trace, scheme, bht_bits=4, log_dir=None):
    vvp = os.path.join(BUILD, f"tb_s{scheme}_b{bht_bits}.vvp")
    exp = os.path.join(BUILD, f"{trace}_s{scheme}_b{bht_bits}.exp")
    sh(["python3", "python/ref_model.py", f"traces/{trace}.csv", str(scheme), exp, str(bht_bits)])
    out = sh(["vvp", "-n", vvp, f"+TRACE=traces/{trace}.csv", f"+EXP={exp}", f"+NAME={trace}"])
    if log_dir:
        with open(os.path.join(log_dir, f"{trace}_s{scheme}.log"), "w") as f:
            f.write(out)
    m = RESULT_RE.search(out)
    passed = bool(m) and re.search(r"^PASS ", out, re.M) is not None
    if not passed:
        print(out)
    n, correct, mis, hits, pen = (int(m.group(i)) for i in (4, 5, 6, 7, 8)) if m else (0,) * 5
    return dict(trace=trace, scheme=scheme, bht_entries=1 << bht_bits, branches=n,
                correct=correct, mispredictions=mis, btb_hits=hits, penalty_cycles=pen,
                status="PASS" if passed else "FAIL")


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def main():
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(LOGS, exist_ok=True)
    names = traces()
    if not names:
        sys.exit("no traces found: run 'make traces' first")

    for s in SCHEMES:
        compile_tb(s, 4)
    rows = []
    print(f"{'trace':12s} {'scheme':10s} {'branches':>8s} {'correct':>8s} {'mispred':>8s}  status")
    for t in names:
        for s in SCHEMES:
            r = run_one(t, s, 4, LOGS)
            rows.append(r)
            print(f"{t:12s} {['Static NT', '1-bit BHT', '2-bit BHT'][s]:10s} {r['branches']:8d} "
                  f"{r['correct']:8d} {r['mispredictions']:8d}  {r['status']}")
    write_csv(os.path.join(RESULTS, "simulation_results.csv"), rows)
    failed = [r for r in rows if r["status"] != "PASS"]

    if "--sweep" in sys.argv:
        sweep = []
        for b in SWEEP_BITS:
            for s in (1, 2):
                compile_tb(s, b)
                for t in SWEEP_TRACES:
                    sweep.append(run_one(t, s, b))
        write_csv(os.path.join(RESULTS, "bht_sweep.csv"), sweep)
        failed += [r for r in sweep if r["status"] != "PASS"]
        print(f"BHT sweep: {len(sweep)} runs ({', '.join(str(1 << b) for b in SWEEP_BITS)} entries)")

    total = len(rows) + (len(sweep) if "--sweep" in sys.argv else 0)
    if failed:
        print(f"REGRESSION FAILED: {len(failed)} of {total} runs")
        sys.exit(1)
    print(f"REGRESSION PASSED: {total} of {total} runs match the golden model")


if __name__ == "__main__":
    main()
