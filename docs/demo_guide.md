# Demonstration Guide (Faculty / Viva)

A 10-minute live demonstration. Every step runs real simulations; nothing is pre-recorded.

## 0. Before the demo (once)

```bash
cd ~/Desktop/mca_final_project
make clean
make all          # about 1–2 minutes: tests, waveforms, report, synthesis
```

Open in VS Code: `code .`. Keep `docs/report.md` (Markdown preview) and `results/charts/` open.

## 1. Show the design (2 min) — Keshav

- Open `rtl/bpu_top.v` and point at the hierarchy: `branch_predictor_top` (BHT + BTB + update + selection) and `flush_ctrl`.
- Open `rtl/branch_predictor_top.v` and show the `generate` block that selects `SCHEME` 0/1/2.

## 2. Real program → trace (1 min) — Mayank

```bash
python3 python/mips_trace.py
```

This prints the MIPS machine code (`beq` = `11600001`, `bne` = `1509fffa`), executes the program (sum = 26) and writes `traces/array_sum.csv`.

## 3. FSM correctness (2 min) — Arun

```bash
make unit
```

Four `PASS` lines appear. Then show `results/logs/tb_bht_fsm.log`: all 8 transitions, saturation, and "steady-state misses per loop: 1-bit = 2, 2-bit = 1".

## 4. One command, three predictors (2 min) — Sarvesh

```bash
make demo
```

The same `loop10` trace runs on all three schemes against the golden model: 10 % → 80 % → 89 % accuracy, then the overall comparison table.

## 5. Waveform (2 min) — Sarvesh / Mayank

```bash
make view      # opens Surfer with clk, pc, pred_taken, actual_taken, counter_state, flush, next_pc ...
```

Point at branch 0 (cold miss, `flush` pulse), branch 9 (loop exit: counter `11 → 10`, `flush`) and branch 10 (re-entry predicted correctly with counter `10`). If no viewer is installed (`brew install surfer`), use the table in `docs/report.md` §7.4.

## 6. Golden model and full regression (1 min) — Rohit

```bash
python3 python/ref_model.py traces/multi_alias.csv 2 /tmp/x.exp
make regression
```

The regression ends with "REGRESSION PASSED". Explain the aliasing pair `0x00400410` / `0x00400450`.

## 7. Results and synthesis (1 min) — Sarvesh / Keshav

Open `results/charts/accuracy.png`, `results/charts/bht_sweep.png` and `results/synthesis/synthesis_summary.md`.

## Useful "what if" questions to answer live

| Question | Command |
|---|---|
| Penalty of 3 cycles? | `python3 python/analyze.py --penalty 3` |
| 30 % branches? | `python3 python/analyze.py --branch-freq 0.3` |
| Does the check really catch bugs? | Change `init = 0 if scheme == 1 else self.ctr_msb - 1` to `init = 0` in `python/ref_model.py`, run `make regression` (2-bit runs fail), then undo the change. |
| 64-entry BHT on the aliasing trace? | see the "BHT size sensitivity" table in `results/accuracy_table.md` |
