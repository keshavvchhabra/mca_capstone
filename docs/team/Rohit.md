# Part 4 of 5 — Branch Traces and the Golden Reference Model

**Project:** Dynamic Branch Prediction Unit (Project 5, *Modern Computer Architecture – Verilog Projects*)
**Member:** Rohit
**Role:** Workload and reference-model engineer (workflow step 4: "feed branch traces")

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

1. Define and document the **trace file format**.
2. Write `python/gen_traces.py`, which generates the six required traces plus a `random` trace:
   1. single loop, 10 iterations (9 T + 1 NT), repeated
   2. single loop, 100 iterations
   3. nested loops (inner 4, outer 10)
   4. alternating T/NT (worst case for 1-bit)
   5. multiple branches with different PCs, **including an aliasing pair**
   6. mixed realistic trace (loop + if/else, data-dependent, seeded random)
3. Write `python/ref_model.py`, a **bit-exact** model of all three schemes (BHT + BTB + misprediction rule) that writes an expectation file.
4. **Hand-check** the model on the simple traces, so that the golden model itself is trusted.
5. Write report **Section 5 — Trace descriptions**.

---

## 3. Trace File Format (CSV) — `python/trace_io.py`

One resolved branch per row, with a required header row:

```
pc,type,taken,target
00400010,BNE,1,00400000
00400010,BNE,0,00400000
```

| Column | Meaning |
|---|---|
| `pc` | address of the branch instruction, 8 hex digits, no `0x` (word aligned) |
| `type` | `BEQ` or `BNE`; documentation only, since prediction does not depend on it |
| `taken` | the real outcome, 1 or 0 |
| `target` | the branch's taken-target (present even when not taken) |

`trace_io.py` holds `read_trace()` and `write_trace()`, which every Python script uses, and it rejects unknown branch types. The Verilog testbench reads the same file directly with `$sscanf(line, "%h,%c%c%c,%d,%h", ...)`; the header row does not parse as numbers and is skipped.

## 4. Trace Design

PCs are in the MIPS `.text` region (`0x0040xxxx`). The BHT index for the default 16 entries is `pc[5:2]`.

| # | Name | Source-code pattern | Branch PCs → BHT index | Branches | Taken | What it tests |
|---|---|---|---|---:|---:|---|
| 1 | `loop10` | `for r<10 { for i<10 {…} }` (inner branch only) | `0x00400010 → 4` | 100 | 90 | 1 vs 2 mispredictions per loop visit |
| 2 | `loop100` | 100-iteration loop × 3 runs | `0x00400110 → 4` | 300 | 297 | long loops, where warm-up cost is negligible |
| 3 | `nested` | outer 10 × inner 4 | inner `0x00400208 → 2`, outer `0x00400210 → 4` | 50 | 39 | short inner loop, two interleaved branches |
| 4 | `alternating` | `if (i % 2 == 0)` | `0x00400300 → 0` | 100 | 50 | pathological case for both 1-bit and 2-bit |
| 5 | `multi_alias` | 5 branches: always-T, always-NT, loop-of-5, and an **alias pair** | `0x404→1`, `0x408→2`, `0x40C→3`, `0x410→4`, **`0x450→4`** | 250 | 140 | destructive aliasing in the BHT, and BTB conflicts |
| 6a | `random` | one branch, `if (a[i] > threshold)` on random data | `0x00400604 → 1` | 200 | 110 | no learnable pattern (50 % random, seed 7) |
| 6 | `mixed` | loop with a random `if`, inner 3-loop, periodic `if` | `0x504→1`, `0x51C→7`, `0x524→9`, `0x530→12` | 240 | 139 | realistic mix; data-dependent branch (30 % taken, seed 2026) |
| 7 | `array_sum` | recorded by `python/mips_trace.py` (Mayank) | `0x014→5`, `0x024→9` | 16 | 10 | real MIPS program |

**The aliasing pair:** `0x00400410` and `0x00400450` differ by `0x40` = 16 entries × 4 bytes, so `pc[5:2]` is identical (index 4). One branch is *always taken* and the other *always not taken*, so they keep overwriting each other's history (**destructive aliasing**). With 32 or more entries, `pc[6:2]` differs (index 4 vs 20) and the conflict disappears. Sarvesh's size sweep shows this.

Pattern sketch (`nested`, one outer iteration):

```
inner BNE @0x208 :  T  T  T  N        (4 iterations)
outer BNE @0x210 :              T     (N on the 10th outer iteration)
```

---

## 5. `python/gen_traces.py`

Open `python/gen_traces.py` for the full source. It has one small function per trace (`t_loop10`, `t_loop100`, `t_nested`, `t_alternating`, `t_random`, `t_multi_alias`, `t_mixed`), plus a helper `loop(pc, target, iters)` that produces a loop-closing branch (taken `iters − 1` times, then not taken once).

Actual output of `python3 python/gen_traces.py traces`:

```
traces/loop10.csv           100 branches,   90 taken
traces/loop100.csv          300 branches,  297 taken
traces/nested.csv            50 branches,   39 taken
traces/alternating.csv      100 branches,   50 taken
traces/random.csv           200 branches,  110 taken
traces/multi_alias.csv      250 branches,  140 taken
traces/mixed.csv            240 branches,  139 taken
```

**Reproducibility:** `random` and `mixed` use private generators with fixed seeds (`random.Random(7)` and `random.Random(2026)`), so every team member gets byte-identical traces.

## 6. `python/ref_model.py` — the Golden Model

### 6.1 What "bit-exact" means here

The model must copy every hardware decision, not only the textbook idea:

| Hardware behaviour | Owner | Model code |
|---|---|---|
| BHT index `pc[INDEX+1:2]` | Arun | `(pc >> 2) & (2**bits − 1)` |
| Reset: 1-bit = 0, 2-bit = `01` | Arun | `init = 0 if scheme == 1 else ctr_msb − 1` |
| 2-bit saturating update | Arun | `min(c+1, max)` / `max(c−1, 0)` |
| BTB tag = `pc[31:INDEX+2]`, write only on taken | Keshav | `_btb_split`, `if taken:` |
| `pred_target` = BTB target only if predicted T **and** hit, else `pc+4` | Keshav | `target = entry[1] if (direction and hit) else pc + 4` |
| Misprediction rule (direction **or** target) | Mayank | `mis = pt != taken or (pt and taken and ptgt != target)` |
| Predict **before** update for every branch | Sarvesh | `predict()` then `update()` |

### 6.2 Code structure (`python/ref_model.py`)

| Part | Purpose |
|---|---|
| `class BranchPredictor` | `bht_index()`, `btb_split()`, `state()`, `predict(pc)` → `(pred_taken, btb_hit, pred_target)`, `update(pc, taken, target)` |
| `simulate(trace, scheme, bht_bits, btb_bits)` | predict, then compute `mispredict` and `next_pc`, then update, for every branch; returns one dict per branch |
| `main()` | CLI: `ref_model.py <trace.csv> <scheme> <out.exp> [bht_bits] [btb_bits]`; prints a `MODEL ...` summary line |

`simulate()` is also imported by `python/analyze.py`, which re-checks every RTL run with the model ("model/RTL agreement: 24 of 24 runs").

### 6.3 Expectation file format (`build/<trace>_s<scheme>_b<bits>.exp`)

One line per trace branch: `pred_taken btb_hit pred_target mispredict next_pc`. For example, the first lines for `loop10` with the 2-bit scheme:

```
0 0 00400014 1 00400000   <- cold: counter 01 predicts NT, BTB empty -> mispredict, redirect to target
1 1 00400000 0 00400000   <- counter 10 predicts T, BTB hit -> correct
```

**Usage:**

```bash
python3 python/ref_model.py traces/loop10.csv 2 build/loop10.exp        # 16-entry BHT
python3 python/ref_model.py traces/multi_alias.csv 1 build/x.exp 6      # 64-entry BHT
```

## 7. Validating the Golden Model by Hand

A golden model is only useful if it is itself correct. The simple traces have closed-form answers, which are compared below with the model output.

| Trace | Scheme | Hand derivation | Expected mispredictions | Model output |
|---|---|---|---:|---:|
| `loop10` | NT | every taken branch: 9 × 10 | 90 | 90 ✓ |
| `loop10` | 1-bit | run 1: warm-up + exit = 2; runs 2–10: re-entry + exit = 2 each | 20 | 20 ✓ |
| `loop10` | 2-bit | run 1: warm-up + exit = 2; runs 2–10: exit only = 1 each | 11 | 11 ✓ |
| `loop100` | 1-bit | 2 per run × 3 | 6 | 6 ✓ |
| `loop100` | 2-bit | 2 + 1 + 1 | 4 | 4 ✓ |
| `nested` | 2-bit | inner: warm-up 1 + 10 exits; outer: warm-up 1 + exit 1 | 13 | 13 ✓ |
| `alternating` | 2-bit | counter oscillates 01 ↔ 10, so it is wrong every time | 100 | 100 ✓ |
| `alternating` | NT | wrong on every taken branch | 50 | 50 ✓ |

Full model summary (`MODEL` lines, 16-entry BHT/BTB):

| Trace | NT mispred | 1-bit mispred | 2-bit mispred |
|---|---:|---:|---:|
| loop10 | 90 | 20 | 11 |
| loop100 | 297 | 6 | 4 |
| nested | 39 | 22 | 13 |
| alternating | 50 | 100 | 100 |
| random | 110 | 86 | 86 |
| multi_alias | 140 | 121 | 112 |
| mixed | 139 | 117 | 66 |
| array_sum | 10 | 6 | 6 |

These match the RTL in every one of the 24 trace × scheme runs, and in all 40 BHT-size runs (`make test` ends with `REGRESSION PASSED: 64 of 64 runs`).

**Mutation check (proof that the comparison is sensitive):** changing the model's 2-bit reset value from `01` to `00` made the testbench report:

```
MISMATCH at branch 1 (cycle 4, t=31): pc=00400010
   RTL  : pred=1 hit=1 tgt=00400000 mis=0
   MODEL: pred=0 hit=1 tgt=00400014 mis=1
FAIL loop10 scheme=2 (1 mismatches, first at branch 1)
```

---

## 8. Report Section 5 — Trace Descriptions (draft)

> Eight branch traces are used. Seven are produced by `python/gen_traces.py` and one is recorded by executing a MIPS array-sum program (`python/mips_trace.py`). All traces contain only conditional `BEQ`/`BNE` branches and are stored as CSV (`pc,type,taken,target`). `random` is a single 50 % random branch with no learnable pattern. `loop10` and `loop100` model a single counted loop and isolate the cost of loop exit and re-entry. `nested` interleaves a short inner loop (4 iterations) with an outer loop (10 iterations). `alternating` is a deliberately adversarial pattern that defeats both 1-bit and 2-bit counters. `multi_alias` contains five static branches, two of which (`0x00400410`, `0x00400450`) map to the same entry of a 16-entry BHT with opposite biases, to expose destructive aliasing. `mixed` combines a data-dependent `if` (30 % taken, fixed seed 2026), a short inner loop, a periodic `if` and an outer loop, to approximate a realistic workload. A Python reference model reproduces the exact RTL behaviour and generates the expected prediction for every branch.

Include the table from Section 4 of this file.

---

## 9. Interfaces with Teammates

| You give | To |
|---|---|
| `traces/*.csv` and the format | Sarvesh (testbench parser), Mayank (hand-written trace) |
| `ref_model.py` CLI and `.exp` format | Sarvesh (`tb_predictor.v` reads the `.exp` file; `analyze.py` and the `Makefile` call the model) |
| Optional `bht_index_bits` argument | Sarvesh (BHT size sweep) |

| You need | From |
|---|---|
| Reset values and update rules | Arun |
| BTB indexing, tag and policy, and the `pred_target` rule | Keshav |
| Misprediction rule | Mayank |

---

## 10. Viva Preparation (Your Part)

1. **Why do you need a separate reference model at all?**
   Without one, the testbench can only print numbers that nobody can check. The model is an independent implementation in another language. If both agree on every one of about 1,000 branches, a design bug that happens to match a model bug is very unlikely.

2. **How do you know the model is right?**
   It was hand-checked on closed-form traces (Section 7), and a deliberate mutation was detected by the comparison.

3. **Why is the random trace seeded?**
   For reproducibility: every run and every team member gets identical traces, so the results in the report can be regenerated exactly.

4. **How did you create an aliasing case?**
   Two PCs that differ by exactly `entries × 4` bytes (`0x40` for 16 entries) share `pc[5:2]` and therefore one BHT counter. Giving them opposite biases makes the interference destructive.

---

## 11. Deliverables Checklist

- [x] CSV trace format + `python/trace_io.py`
- [x] `python/gen_traces.py` producing 7 traces
- [x] `python/ref_model.py` with the `.exp` output and `MODEL` summary line
- [x] Hand-validation table (Section 7)
- [x] Report Section 5
