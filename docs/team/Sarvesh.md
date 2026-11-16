# Part 5 of 5 — System Verification, Performance Analysis and Final Report

**Project:** Dynamic Branch Prediction Unit (Project 5, *Modern Computer Architecture – Verilog Projects*)
**Member:** Sarvesh
**Role:** Verification and analysis lead (workflow step 5: "calculate prediction accuracy and estimate CPI impact"), report editor

---

## 1. Team Division at a Glance

| Part | Member | Responsibility | Source files in the repository |
|---|---|---|---|
| 1 | Arun | Direction predictors: static baseline, 1-bit BHT, 2-bit BHT, FSM verification | `rtl/static_not_taken.v`, `rtl/bht_1bit.v`, `rtl/bht_2bit.v`, `testbench/tb_bht_fsm.v` |
| 2 | Keshav | BTB, update/selection logic, predictor top level, build system, synthesis | `rtl/btb.v`, `rtl/bp_update_logic.v`, `rtl/bp_select_logic.v`, `rtl/branch_predictor_top.v`, `testbench/tb_btb.v`, `synth/synth.ys`, `python/synth_report.py`, `Makefile`, `README.md` |
| 3 | Mayank | Pipeline flush/control, integrated unit `bpu_top`, MIPS workload | `rtl/flush_ctrl.v`, `rtl/bpu_top.v`, `testbench/tb_flush_ctrl.v`, `testbench/tb_bpu_top.v`, `python/mips_trace.py` |
| 4 | Rohit | Branch traces and the Python golden reference model | `python/trace_io.py`, `python/gen_traces.py`, `python/ref_model.py`, `traces/*.csv` |
| 5 | Sarvesh | System testbench, regression, accuracy/CPI analysis, final report | `testbench/tb_predictor.v`, `python/metrics.py`, `python/run_regression.py`, `python/analyze.py`, `results/`, `docs/report.md` |

> **The repository files are authoritative.** Code listings in this guide explain the design; where they differ from the file in the repository, the repository version is the one that was simulated and verified. Every file you own starts with a `// Owner:` or `Owner:` header line.

## 2. Your Responsibilities

1. Write the **trace-driven, self-checking testbench** `testbench/tb_predictor.v`:
   - reads a trace and the matching golden-model expectation file,
   - drives the predict and update interfaces for each branch,
   - prints PASS/FAIL and reports the **first mismatch with its cycle number**,
   - computes branches, correct predictions, accuracy %, mispredictions and BTB hit rate.
2. Produce the **waveform**: a VCD with `clk, pc, pred_taken, actual_taken, counter state, mispredict, flush`, a GTKWave command and a `.gtkw` save file.
3. Write `python/analyze.py`: run all simulations, then build the accuracy/CPI tables, the speedup over the baseline, the **BHT size sweep (4, 8, 16, 32, 64 entries)** and a matplotlib bar chart.
4. Write report **Sections 6, 7 and 8** (results, comparison and analysis, conclusion).
5. **Assemble `docs/report.md`** from all members' sections, and run the final `make test` / `make report` before submission.

**Evaluation criteria you directly satisfy:** *"accuracy analysis"*, *"clear performance comparison"*, *"waveform verification"*, *"accuracy tables"*.

---

## 3. Verification Strategy

```
 traces/*.csv ──┬──► python/ref_model.py ──► build/<t>_s<k>.exp  (expected per branch)
   (Rohit)        │                                   │
                  └──► tb_predictor.v ◄───────────────┘
                         │  drives branch_predictor_top (Keshav, with Arun's BHT)
                         │  and flush_ctrl (Mayank)
                         ▼
                compare pred_taken, btb_hit, pred_target, mispredict  ──► PASS / FAIL + first mismatch
                         ▼
                RESULT line (branches, correct, mispred, btb_hits, penalty) ──► analyze.py ──► tables + chart
```

**Timing of one branch (one clock cycle per branch):**

| When | Action |
|---|---|
| `negedge clk` | drive `pc`, `is_branch = 1`, and the same branch's `update_en`, `actual_taken`, `actual_target` |
| `#1` later | sample the combinational outputs (`pred_*`, `btb_hit`, `mispredict`) and compare them with the `.exp` line |
| `posedge clk` | BHT, BTB and flush-controller counters update |

So each branch is predicted with the state left by all previous branches. This is the "update before the next prediction" assumption that the whole team agreed on.

---

## 4. `testbench/tb_predictor.v`

Open the file for the full source. It instantiates **`bpu_top`** (Mayank), which contains Keshav's predictor and Mayank's flush controller, and works as follows:

| Step | What the testbench does |
|---|---|
| Read | the CSV trace line by line with `$fgets` + `$sscanf(line, "%h,%c%c%c,%d,%h", ...)`; the header row is skipped automatically |
| Drive | one branch per cycle on both the IF port (`fetch_pc`) and the EX port (`ex_*`); the IF prediction is fed back as `ex_pred_*` |
| Check 1 | `next_pc` must equal the architecturally correct next PC (`actual_taken ? target : pc + 4`) for **every** branch |
| Check 2 | `pred_taken`, `btb_hit`, `pred_target`, `mispredict`, `next_pc` must equal the golden model's `.exp` line |
| Check 3 | hardware `branch_count` = number of trace lines; `penalty_cycles` = `PENALTY × mispredict_count` |
| Report | `MISMATCH (...) at branch N, cycle C`, then `RESULT ...` and `PASS` / `FAIL` |

Plusargs: `+TRACE=<csv> +EXP=<file> +NAME=<label> +VCD=<file>`. Parameters: `SCHEME`, `BHT_INDEX_BITS`, `BTB_INDEX_BITS`, `PENALTY`.

**Lesson learnt during development:** a bare `$fscanf` loop hung forever on comment lines, because a failed match consumes nothing. Reading whole lines with `$fgets` and parsing them with `$sscanf` fixed it.

**Example run** (`make demo` shows this for all three schemes):

```
RESULT name=loop10 scheme=2 bht=16 branches=100 correct=89 mispred=11 btb_hits=99 penalty=22
  accuracy = 89.00 %   btb hit rate = 99.00 %
PASS loop10 scheme=2
```

## 5. Waveform Verification

### 5.1 Commands

```bash
make wave                                     # writes results/waveforms/predictor_loop10.vcd (2-bit, loop10)
gtkwave results/waveforms/predictor_loop10.vcd results/waveforms/predictor.gtkw    # opens with the saved signal list
```

### 5.2 `results/waveforms/predictor.gtkw` (screenshot-friendly signal list)

The save file opens the VCD with these signals: `clk, rst, pc, pred_taken, actual_taken, counter_state, btb_hit, pred_target, actual_target, mispredict, flush, correct_pc, next_pc, mispredict_count, penalty_cycles`. `make wave` also writes `bht_fsm.vcd` (Arun's FSM test) and `bpu_top.vcd` (Mayank's integration test).

### 5.3 What the waveform shows (2-bit, `loop10`, first 12 branches)

These values come from the simulation and agree with the golden model.

```
branch #        0     1     2     3 … 8     9    10    11
pc           0010  0010  0010  0010 …    0010  0010  0010
counter_state  01    10    11    11 … 11    11    10    11
pred_taken      0     1     1     1 … 1      1     1     1
actual_taken    1     1     1     1 … 1      0     1     1
btb_hit         0     1     1     1 … 1      1     1     1
pred_target  0014  0000  0000  0000 …    0000  0000  0000   (low 16 bits)
mispredict    ‾‾‾                         ‾‾‾
flush         ‾‾‾                         ‾‾‾
correct_pc   0000                        0014
```

**Explanation to write under the screenshot:**
1. **Branch 0 (cold start):** the counter is at its reset value `01`, so it predicts NT, and the BTB is empty, so `pred_target = pc+4 = 0x00400014`. The branch is taken, so `mispredict` and `flush` pulse, and `correct_pc = 0x00400000`. The counter moves `01 → 10` and the BTB is filled.
2. **Branches 1–8:** the counter climbs to `11` and saturates. All predictions are correct and use the BTB target.
3. **Branch 9 (loop exit):** the counter is `11` and predicts T, but the branch is not taken, so `flush` pulses, `correct_pc = pc+4 = 0x00400014`, and the counter moves to `10`.
4. **Branch 10 (loop re-entry):** the counter is `10` and **still predicts taken**, which is correct. This is the cycle where a 1-bit predictor would mispredict a second time.
5. `mispredict_count` increases by one on each pulse, and `penalty_cycles` increases by 2.

---

## 6. Python Analysis Scripts

| Script | Purpose |
|---|---|
| `python/metrics.py` | `accuracy()`, `mispredict_rate()`, `cpi()`, `speedup()`; run it directly for a self-test with hand-computed values |
| `python/run_regression.py` | compiles `tb_predictor` per scheme, runs the golden model and the RTL for every trace, writes `results/simulation_results.csv` and `results/logs/`; `--sweep` adds the BHT-size runs (`results/bht_sweep.csv`); non-zero exit on any failure |
| `python/analyze.py` | reads those CSVs (never invents numbers), re-checks each run with the Python model, writes `results/accuracy_table.md`, `results/performance_summary.csv`, and the charts `accuracy.png`, `cpi.png`, `bht_sweep.png`; options `--branch-freq`, `--penalty`, `--base-cpi` |

Chart colours come from a validated colour-blind-safe palette. The CPI chart plots the misprediction overhead (CPI − 1) from zero, so bar lengths are honest.

## 7. Results (Report Section 6)

The final numbers are in `results/accuracy_table.md` and `docs/report.md` §7. Regenerate them with `make test report`: every input is deterministic, so the output is identical every time.

Overall comparison (all 1,256 branches, 8 traces):

| Scheme | Accuracy % | Mispredictions | CPI | Speedup vs NT |
|---|---:|---:|---:|---:|
| Static NT | 30.33 | 875 | 1.2787 | 1.000 |
| 1-bit BHT | 61.94 | 478 | 1.1522 | 1.110 |
| 2-bit BHT | 68.31 | 398 | 1.1268 | 1.135 |

The per-trace table, the BHT size sweep (now including the `random` trace) and the synthesis table are in the report.

## 8. Comparison and Analysis (Report Section 7)

**8.1 Why 2-bit beats 1-bit on loops.** On `loop10`, the 1-bit predictor mispredicts twice per loop visit (exit, then re-entry, because the exit wrote NT into its single bit), giving 20 mispredictions. The 2-bit counter only drops from `11` to `10` on the exit and still predicts taken on re-entry, giving 11 mispredictions (1 per visit plus 1 warm-up). Accuracy rises from 80 % to 89 % and CPI falls from 1.080 to 1.044. On `nested`, where the inner loop has only 4 iterations, the effect is much larger (56 % → 74 %), because exits make up a quarter of all inner-loop branches. On `loop100`, both schemes exceed 98 %, because the 1–2 mispredictions per visit are amortised over 100 iterations.

**8.2 Both dynamic schemes beat the baseline on loop code.** Static NT is wrong on every taken branch: 1 % accuracy on `loop100` and CPI 1.396. The 2-bit scheme reaches a **1.39× speedup** there. This shows why "predict not taken" is a poor default for loop-heavy code.

**8.3 Pathological pattern.** On `alternating`, both dynamic schemes reach **0 %** and are *worse* than static NT (50 %). The 1-bit predictor always predicts the previous outcome, which is always wrong. The 2-bit counter oscillates between `01` and `10` and never reaches a strong state. Simple counters cannot capture patterns that depend on *history*. This motivates correlating predictors (gshare), listed as future work.

**8.4 Data-dependent branches.** On `mixed`, the 2-bit scheme (72.5 %) clearly beats the 1-bit scheme (51.25 %). The random BEQ is biased towards not taken (30 % taken): the 2-bit counter settles on that bias, while the 1-bit predictor flips after every rare outcome. The inner 3-iteration loop also costs the 1-bit predictor 2 of every 3 predictions after warm-up.

**8.5 Aliasing effects.** In `multi_alias`, an always-taken and an always-not-taken branch share BHT index 4 for every table of 16 entries or fewer, so they continually overwrite each other. Accuracy is stuck at 51.6 % (1-bit) and 55.2 % (2-bit). At 32 entries they map to different indices and accuracy jumps to **91.2 % / 94.8 %**. The lower BTB hit rate on this trace (58.8 % = 147/250) is **not** caused by aliasing. The two always-not-taken branches (`0x408`, `0x450`) are never written into the BTB, by design, so their 100 lookups miss. Add 3 cold misses and that gives 103 misses. The BTB tag also stops `0x450` from wrongly using `0x410`'s target. Aliasing is **not always harmful**: on `mixed`, a 4-entry 1-bit BHT is slightly *better* (52.92 % vs 51.25 %), because two branches that share an entry happen to agree often enough (constructive aliasing), while the 2-bit scheme loses 1.25 points.

**8.5b No pattern, no gain.** On `random` (55 % taken), the 1-bit and 2-bit schemes are identical at 57.00 %; both learn only bias.

**8.6 BHT size sensitivity.** Once each static branch has its own entry, more entries do not help (`nested` and `random` are flat from 4 to 64 entries). The table only needs to be as large as the working set of active branches. Real programs have hundreds to thousands of branches, so real BHTs have thousands of entries.

**8.7 Cost vs benefit.** Moving from 1-bit to 2-bit costs 16 flip-flops (+4.4 % cells) for up to an 18-point accuracy gain. The BTB, not the BHT, dominates area.

**8.8 Limitations (state these honestly).**
- The evaluation uses traces, not a running 5-stage CPU. It assumes each branch updates the predictor before the next branch is predicted (no in-flight branches and no speculative history).
- The CPI is an analytical estimate (`base 1.0`, `branch_freq 0.2`, `penalty 2`). It ignores data hazards, cache misses and the size of the wrong-path work.
- The traces are synthetic and short. `array_sum` (16 branches) is dominated by warm-up.
- Fmax is not reported: the Yosys generic flow gives logic depth only, and the FPGA timing run (Vivado/nextpnr) is still pending.
- A direct-mapped BTB with 16 entries; no return-address stack for `jr $ra`.

---

## 9. Conclusion (Report Section 8, draft)

> We designed, implemented and verified a parameterised dynamic branch-prediction unit in synthesizable Verilog, consisting of a static not-taken baseline, a 1-bit BHT, a 2-bit saturating-counter BHT, a tagged BTB and a pipeline flush/control interface. Every state transition was verified with directed tests, and every prediction on eight BEQ/BNE traces (1,256 branches per scheme) was checked against an independent Python reference model, with all 64 runs passing. On loop-oriented code, the 2-bit predictor achieved 89–98.7 % accuracy and reduced the estimated CPI from up to 1.396 (static not-taken) to 1.005, a speedup of up to 1.39×, at a cost of only 16 extra flip-flops over the 1-bit design. The 2-bit hysteresis halves loop-related mispredictions compared with the 1-bit scheme. The experiments also exposed the limits of simple counters: alternating patterns defeat them completely, and destructive aliasing in a small untagged BHT can remove most of their benefit until the table is large enough to separate the conflicting branches. Global-history (gshare) and tournament predictors are natural extensions.

---

## 10. The Final Report

`docs/report.md` is assembled. It contains every member's section, the generated tables and charts, the synthesis results, the limitations and 10 viva questions. `docs/demo_guide.md` is the 10-minute live demonstration script.

Final pre-submission check (in a clean copy):

```bash
make clean && make all      # expect: 4 x PASS, REGRESSION PASSED: 64 of 64, tables, charts, synthesis
```

## 11. Viva Preparation (Your Part)

1. **How is your testbench self-checking?**
   For every branch it compares five RTL outputs (`pred_taken`, `btb_hit`, `pred_target`, `mispredict`, `next_pc`) against the golden model's expectation file. It stops counting at the first mismatch and reports that branch's index, cycle number and both values. It also cross-checks the hardware `branch_count` against its own count.

2. **What is the difference between accuracy and misprediction rate in your table?**
   Accuracy counts correct **directions** only. Mispredictions count **flushes**, which also include target mispredictions (a taken prediction with a BTB miss or a stale target). In general `mispred ≥ branches − correct`. In all our traces the two are equal (for example, 100 − 89 = 11 on `loop10`, 2-bit). Every branch's BTB entry was already filled by its first taken outcome before the BHT could predict taken, so no target-only mispredictions occurred. Mayank's directed test exercises that case explicitly.

3. **How did you get the CPI and speedup numbers?**
   `CPI = 1 + 0.2 × (mispredictions / branches) × 2`. Speedup = CPI(static NT) ÷ CPI(scheme) on the same trace. The misprediction counts come from the hardware counter `mispredict_count`.

4. **Why does a bigger BHT not always help?**
   Once every active branch has its own entry, extra entries stay unused (`nested` is flat). Size helps only when it removes aliasing (`multi_alias` jumps at 32 entries), and aliasing can even be slightly constructive (`mixed`, 1-bit).

---

## 12. Deliverables Checklist

- [x] `testbench/tb_predictor.v` — self-checking, first-mismatch report, `next_pc` invariant
- [x] `results/waveforms/*.vcd` + `predictor.gtkw` (take the GTKWave screenshot for the viva)
- [x] `python/metrics.py`, `python/run_regression.py`, `python/analyze.py`
- [x] `results/accuracy_table.md`, `results/performance_summary.csv`, `results/charts/*.png`
- [x] `docs/report.md`, `docs/demo_guide.md`
