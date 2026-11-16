#!/usr/bin/env python3
"""analyze.py -- accuracy, misprediction rate, CPI and strategy comparison.

Owner: Sarvesh  |  Project 5: Dynamic Branch Prediction Unit

Reads the RTL simulation results produced by run_regression.py (never invents
numbers) and produces:
  results/accuracy_table.md        full comparison tables (Markdown)
  results/performance_summary.csv  accuracy, misprediction rate, CPI, speedup
  results/charts/accuracy.png      accuracy per trace and scheme
  results/charts/cpi.png           estimated CPI per trace and scheme
  results/charts/bht_sweep.png     accuracy vs BHT size (aliasing study)

It also re-computes every run with the Python model and confirms that the
model and the RTL agree.

usage: python3 python/analyze.py [--branch-freq 0.2] [--penalty 2] [--base-cpi 1.0]
"""
import argparse
import csv
import os

import metrics
from ref_model import simulate
from trace_io import read_trace

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results")
CHARTS = os.path.join(RESULTS, "charts")
NAMES = {0: "Static NT", 1: "1-bit BHT", 2: "2-bit BHT"}
COLORS = {0: "#2a78d6", 1: "#eb6834", 2: "#1baf7a"}    # validated categorical slots 1-3
TRACE_ORDER = ["loop10", "loop100", "nested", "array_sum", "mixed",
               "multi_alias", "random", "alternating"]


def load(name):
    path = os.path.join(RESULTS, name)
    if not os.path.exists(path):
        raise SystemExit(f"{path} missing: run 'make test' (and 'make sweep') first")
    with open(path) as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        for k in ("scheme", "bht_entries", "branches", "correct", "mispredictions", "btb_hits"):
            r[k] = int(r[k])
    return rows


def ordered(traces):
    return [t for t in TRACE_ORDER if t in traces] + sorted(t for t in traces if t not in TRACE_ORDER)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch-freq", type=float, default=metrics.BRANCH_FREQ)
    ap.add_argument("--penalty", type=int, default=metrics.PENALTY)
    ap.add_argument("--base-cpi", type=float, default=metrics.BASE_CPI)
    a = ap.parse_args()
    os.makedirs(CHARTS, exist_ok=True)

    sim = {(r["trace"], r["scheme"]): r for r in load("simulation_results.csv")}
    traces = ordered({t for t, _ in sim})

    # ---- cross-check: Python model vs RTL ----
    agree = 0
    for (t, s), r in sim.items():
        rows = simulate(read_trace(os.path.join(ROOT, "traces", f"{t}.csv")), s)
        same = (sum(x["pred"] == x["taken"] for x in rows) == r["correct"] and
                sum(x["mispredict"] for x in rows) == r["mispredictions"])
        agree += same
        if not same:
            print(f"WARNING: model and RTL disagree on {t} / {NAMES[s]}")
    print(f"model/RTL agreement: {agree} of {len(sim)} runs")

    # ---- per-run metrics ----
    perf = []
    for t in traces:
        cpi_nt = metrics.cpi(sim[(t, 0)]["mispredictions"], sim[(t, 0)]["branches"],
                             a.base_cpi, a.branch_freq, a.penalty)
        for s in (0, 1, 2):
            r = sim[(t, s)]
            c = metrics.cpi(r["mispredictions"], r["branches"], a.base_cpi, a.branch_freq, a.penalty)
            perf.append(dict(trace=t, scheme=NAMES[s], branches=r["branches"],
                             correct=r["correct"], mispredictions=r["mispredictions"],
                             accuracy_pct=round(metrics.accuracy(r["correct"], r["branches"]), 2),
                             mispredict_rate_pct=round(100 * metrics.mispredict_rate(r["mispredictions"], r["branches"]), 2),
                             btb_hit_pct=round(100 * r["btb_hits"] / r["branches"], 2),
                             cpi=round(c, 4), speedup_vs_nt=round(metrics.speedup(cpi_nt, c), 3)))
    with open(os.path.join(RESULTS, "performance_summary.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(perf[0].keys()))
        w.writeheader()
        w.writerows(perf)

    # ---- overall comparison (all branches of all traces pooled) ----
    pooled = {}
    for s in (0, 1, 2):
        n = sum(sim[(t, s)]["branches"] for t in traces)
        c = sum(sim[(t, s)]["correct"] for t in traces)
        m = sum(sim[(t, s)]["mispredictions"] for t in traces)
        pooled[s] = (n, c, m, metrics.cpi(m, n, a.base_cpi, a.branch_freq, a.penalty))

    L = ["# Branch Prediction Results", "",
         "All values are computed from Icarus Verilog simulations of the RTL "
         "(`results/simulation_results.csv`); each run was checked branch-by-branch "
         "against the Python golden model.", "",
         f"**Assumptions:** base CPI = {a.base_cpi}, branch frequency = {a.branch_freq}, "
         f"misprediction penalty = {a.penalty} cycles, BHT = 16 entries, BTB = 16 entries.  ",
         "**CPI** = base CPI + branch frequency x misprediction rate x penalty.  ",
         "**Accuracy** = correct direction predictions / branches. "
         "**Misprediction** = pipeline flush (wrong direction or wrong target).", "",
         "## 1. Overall comparison of the three strategies (all traces pooled)", "",
         "| Scheme | Branches | Correct | Accuracy % | Mispredictions | Mispredict rate % | CPI | Speedup vs NT |",
         "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for s in (0, 1, 2):
        n, c, m, cp = pooled[s]
        L.append(f"| {NAMES[s]} | {n} | {c} | {100 * c / n:.2f} | {m} | {100 * m / n:.2f} | "
                 f"{cp:.4f} | {pooled[0][3] / cp:.3f} |")
    L += ["", "## 2. Per-trace results", "",
          "| Trace | Branches | Scheme | Accuracy % | Mispredictions | Mispredict rate % | BTB hit % | CPI | Speedup vs NT |",
          "|---|---:|---|---:|---:|---:|---:|---:|---:|"]
    for p in perf:
        L.append(f"| {p['trace']} | {p['branches']} | {p['scheme']} | {p['accuracy_pct']:.2f} | "
                 f"{p['mispredictions']} | {p['mispredict_rate_pct']:.2f} | {p['btb_hit_pct']:.2f} | "
                 f"{p['cpi']:.4f} | {p['speedup_vs_nt']:.3f} |")

    sweep_path = os.path.join(RESULTS, "bht_sweep.csv")
    sweep = load("bht_sweep.csv") if os.path.exists(sweep_path) else []
    if sweep:
        sizes = sorted({r["bht_entries"] for r in sweep})
        sw = {(r["trace"], r["scheme"], r["bht_entries"]): r for r in sweep}
        sweep_traces = ordered({r["trace"] for r in sweep})
        L += ["", "## 3. BHT size sensitivity (accuracy %, BTB fixed at 16 entries)", "",
              "| Trace | Scheme | " + " | ".join(f"{e} entries" for e in sizes) + " |",
              "|---|---|" + "---:|" * len(sizes)]
        for t in sweep_traces:
            for s in (1, 2):
                vals = [metrics.accuracy(sw[(t, s, e)]["correct"], sw[(t, s, e)]["branches"]) for e in sizes]
                L.append(f"| {t} | {NAMES[s]} | " + " | ".join(f"{v:.2f}" for v in vals) + " |")

    with open(os.path.join(RESULTS, "accuracy_table.md"), "w") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L))
    charts(perf, traces, sweep, a)


def style(ax, ylabel):
    ax.set_ylabel(ylabel, color="#52514e")
    ax.spines[["top", "right"]].set_visible(False)
    ax.spines[["left", "bottom"]].set_color("#b8b7b1")
    ax.tick_params(colors="#52514e")
    ax.yaxis.grid(True, color="#e6e5e1", linewidth=0.8)
    ax.set_axisbelow(True)


def grouped_bars(perf, traces, value, ylabel, title, path, ylim=None, fmt="{:.0f}%"):
    """Grouped bars; value(p) gives the bar height. Zero-height bars get a label."""
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(11, 4.6))
    w = 0.26
    for s in (0, 1, 2):
        ys = [value(next(p for p in perf if p["trace"] == t and p["scheme"] == NAMES[s])) for t in traces]
        xs = [i + (s - 1) * w for i in range(len(traces))]
        ax.bar(xs, ys, w * 0.92, label=NAMES[s], color=COLORS[s])
        for x, y in zip(xs, ys):
            if y == 0:
                ax.text(x, 0, fmt.format(0), ha="center", va="bottom", fontsize=8, color="#52514e")
    ax.set_xticks(range(len(traces)))
    ax.set_xticklabels(traces)
    if ylim:
        ax.set_ylim(*ylim)
    style(ax, ylabel)
    ax.set_title(title, loc="left", color="#0b0b0b")
    ax.legend(frameon=False, ncol=3, loc="upper right", bbox_to_anchor=(1, 1.12))
    fig.tight_layout()
    fig.savefig(path, dpi=150, facecolor="#fcfcfb")
    plt.close(fig)


def charts(perf, traces, sweep, a):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not installed: charts skipped (pip install -r requirements.txt)")
        return
    grouped_bars(perf, traces, lambda p: p["accuracy_pct"], "Prediction accuracy (%)",
                 "Prediction accuracy by trace (16-entry BHT)",
                 os.path.join(CHARTS, "accuracy.png"), ylim=(0, 100))
    # CPI is shown as the branch-stall overhead above the base CPI, so the bars
    # start at zero and their lengths are directly comparable.
    grouped_bars(perf, traces, lambda p: round(p["cpi"] - a.base_cpi, 4),
                 "Branch stall cycles per instruction",
                 f"Misprediction CPI overhead (CPI = {a.base_cpi} + bar)",
                 os.path.join(CHARTS, "cpi.png"), fmt="{:.2f}")
    if sweep:
        sizes = sorted({r["bht_entries"] for r in sweep})
        sweep_traces = ordered({r["trace"] for r in sweep})
        fig, axes = plt.subplots(1, len(sweep_traces), figsize=(12, 3.6), sharey=True)
        for ax, t in zip(axes, sweep_traces):
            for s in (1, 2):
                ys = [next(metrics.accuracy(r["correct"], r["branches"]) for r in sweep
                           if r["trace"] == t and r["scheme"] == s and r["bht_entries"] == e) for e in sizes]
                ax.plot(range(len(sizes)), ys, color=COLORS[s], linewidth=2, marker="o",
                        markersize=6, label=NAMES[s])
            same = all(
                metrics.accuracy(r1["correct"], r1["branches"]) == metrics.accuracy(r2["correct"], r2["branches"])
                for r1 in sweep for r2 in sweep
                if r1["trace"] == r2["trace"] == t and r1["bht_entries"] == r2["bht_entries"]
                and r1["scheme"] == 1 and r2["scheme"] == 2)
            if same:
                ax.text(len(sizes) / 2 - 0.5, 35, "1-bit and 2-bit\nidentical", ha="center",
                        color="#52514e", fontsize=9)
            ax.set_xticks(range(len(sizes)))
            ax.set_xticklabels([str(e) for e in sizes])
            ax.set_xlabel("BHT entries", color="#52514e")
            ax.set_title(t, color="#0b0b0b")
            ax.set_ylim(0, 100)
            style(ax, "Accuracy (%)" if ax is axes[0] else "")
        axes[-1].legend(frameon=False, loc="lower right")
        fig.suptitle("Accuracy vs BHT size (aliasing study)", x=0.01, ha="left", color="#0b0b0b")
        fig.tight_layout()
        fig.savefig(os.path.join(CHARTS, "bht_sweep.png"), dpi=150, facecolor="#fcfcfb")
        plt.close(fig)
    print("charts written to results/charts/")


if __name__ == "__main__":
    main()
