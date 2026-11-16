# Part 3 of 5 — Pipeline Flush/Control Interface and Control-Hazard Analysis

**Project:** Dynamic Branch Prediction Unit (Project 5, *Modern Computer Architecture – Verilog Projects*)
**Member:** Mayank
**Role:** Pipeline-control designer (misprediction detection, flush, penalty accounting, ISA test program)

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

1. Write report **Section 1 — Problem statement**: control hazards in the 5-stage MIPS pipeline and why mispredictions cost cycles.
2. Derive the **misprediction penalty** (2 cycles for EX-stage resolution) and the **CPI model** used by Sarvesh.
3. Implement `rtl/flush_ctrl.v`: misprediction detection, `flush`, `correct_pc`, and the branch / misprediction / penalty counters.
4. Implement `rtl/bpu_top.v`: the **complete unit** a pipeline would instantiate. It connects Keshav's predictor (IF port) with `flush_ctrl` (EX port) and selects `next_pc = flush ? correct_pc : pred_target`.
5. Write the directed testbenches `testbench/tb_flush_ctrl.v` and `testbench/tb_bpu_top.v`.
6. Write `python/mips_trace.py`: assemble the array-sum MIPS program, execute it on a small interpreter, and write `traces/array_sum.csv`.
7. Write the **flush-controller / bpu_top part of Section 4**.

## 3. Control Hazards (Report Section 1)

### 3.1 Where the branch is decided

In the classic 5-stage MIPS pipeline, a `BEQ`/`BNE` compares two registers in the **ALU (EX stage)**, so its outcome and target are known only at the end of EX. Meanwhile, the IF stage keeps fetching a new instruction every cycle.

```
cycle:        1     2     3     4     5     6     7
BNE  (i)     IF    ID    EX    MEM   WB                    ← outcome known at end of EX (cycle 3)
i+1          ·     IF    ID    ✗                           ← fetched before outcome known
i+2          ·     ·     IF    ✗                           ← fetched before outcome known
target       ·     ·     ·     IF    ID    EX    ...       ← correct path starts in cycle 4
```

If the branch went a different way than the fetch stage assumed, the two instructions `i+1` and `i+2` are on the **wrong path**. They are turned into bubbles (squashed), so **2 cycles are lost**:

> **Misprediction penalty = number of stages between fetch and branch resolution = EX(3) − IF(1) = 2 cycles.**

This is why `MISPREDICT_PENALTY` defaults to 2. A deeper pipeline, or resolution in MEM, would raise it to 3 or more. It is a parameter so that the effect can be studied.

### 3.2 Strategies, from worst to best

| Strategy | Cost per branch | Comment |
|---|---|---|
| Stall until resolved | always 2 cycles | simple but slow |
| Predict not taken (static) | 2 cycles for every *taken* branch | loops are mostly taken, so this is bad for loops |
| Dynamic prediction (BHT + BTB) | 2 cycles only on a *misprediction* | this project |

### 3.3 Two kinds of misprediction

| Kind | Condition | Example |
|---|---|---|
| **Direction** misprediction | `pred_taken != actual_taken` | predicted NT, loop branch actually T |
| **Target** misprediction | predicted T, actually T, but `pred_target != actual_target` | BHT says T but the BTB missed, so fetch used `pc+4` |

Both cause the same flush and the same penalty.

### 3.4 The CPI model (assumptions stated explicitly)

Every misprediction adds `penalty` stall cycles on top of an ideal pipeline:

```
CPI = base_CPI + branch_freq × mispredict_rate × mispredict_penalty
```

| Symbol | Value used | Justification |
|---|---|---|
| `base_CPI` | 1.0 | ideal pipeline, no other hazards (data hazards are handled by forwarding, Project 4) |
| `branch_freq` | 0.2 | about 1 in 5 instructions is a branch in typical integer code (parameter) |
| `mispredict_rate` | mispredictions / branches | **measured** by the RTL `mispredict_count` |
| `mispredict_penalty` | 2 cycles | derived in 3.1 (parameter) |

**Worked example (real result, `loop10`, 2-bit):** 11 mispredictions out of 100 branches →
`CPI = 1 + 0.2 × 0.11 × 2 = 1.044`. Static NT: 90/100 → `CPI = 1 + 0.2 × 0.90 × 2 = 1.36`. Speedup = 1.36 / 1.044 = **1.30×**.

---

## 4. Module Specification — `flush_ctrl`

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `clk`, `rst` | in | 1 | clock, synchronous active-high reset |
| `resolve_en` | in | 1 | a branch resolves in EX this cycle |
| `branch_pc` | in | 32 | PC of the resolving branch |
| `pred_taken`, `pred_target` | in | 1, 32 | what fetch assumed (from Keshav's top level, carried down the pipeline) |
| `actual_taken`, `actual_target` | in | 1, 32 | real outcome from the ALU / branch adder |
| `mispredict` | out | 1 | direction **or** target wrong |
| `dir_mispredict`, `tgt_mispredict` | out | 1 | which kind (for statistics and waveforms) |
| `flush` | out | 1 | `resolve_en && mispredict`: squash IF/ID (and ID/EX) |
| `correct_pc` | out | 32 | restart address: `actual_taken ? actual_target : branch_pc + 4` |
| `branch_count`, `mispredict_count`, `penalty_cycles` | out | 32 | performance counters |

Parameters: `PC_WIDTH = 32`, `CNT_WIDTH = 32`, `MISPREDICT_PENALTY = 2`.

**How it connects to a real pipeline** (for the report's discussion; this project evaluates the unit with traces, so no full CPU is built):

```
           ┌──────────┐ pred_taken/pred_target travel with the instruction
   IF ────►│  IF/ID   ├────────►│  ID/EX  ├────────► EX: compare with actual
   ▲       └────▲─────┘          └───▲─────┘              │
   │            │ clear (flush)      │ clear (flush)       ▼
   │            └────────────────────┴──────────── flush_ctrl
   └──────────── next_pc = flush ? correct_pc : (pred_taken ? pred_target : pc+4)
```

---

## 5. Verilog Implementation — `rtl/flush_ctrl.v`

```verilog
// flush_ctrl.v -- Pipeline flush / control interface.
// When a branch resolves (resolve_en), compare the prediction made at fetch
// with the real outcome. On a misprediction:
//   * flush      : squash the wrong-path instructions in IF/ID (and ID/EX)
//   * correct_pc : address to restart fetch from
// It also keeps performance counters for the CPI estimate.
module flush_ctrl #(
    parameter PC_WIDTH           = 32,
    parameter CNT_WIDTH          = 32,
    parameter MISPREDICT_PENALTY = 2      // cycles lost per misprediction
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 resolve_en,     // a branch resolves this cycle
    input  wire [PC_WIDTH-1:0]  branch_pc,
    input  wire                 pred_taken,
    input  wire [PC_WIDTH-1:0]  pred_target,
    input  wire                 actual_taken,
    input  wire [PC_WIDTH-1:0]  actual_target,
    output wire                 mispredict,
    output wire                 dir_mispredict, // wrong direction
    output wire                 tgt_mispredict, // right direction (T), wrong target
    output wire                 flush,
    output wire [PC_WIDTH-1:0]  correct_pc,
    output reg  [CNT_WIDTH-1:0] branch_count,
    output reg  [CNT_WIDTH-1:0] mispredict_count,
    output reg  [CNT_WIDTH-1:0] penalty_cycles
);
    assign dir_mispredict = (pred_taken != actual_taken);
    assign tgt_mispredict = pred_taken && actual_taken && (pred_target != actual_target);
    assign mispredict     = dir_mispredict || tgt_mispredict;

    assign flush      = resolve_en && mispredict;
    assign correct_pc = actual_taken ? actual_target : branch_pc + 4;

    always @(posedge clk) begin
        if (rst) begin
            branch_count     <= {CNT_WIDTH{1'b0}};
            mispredict_count <= {CNT_WIDTH{1'b0}};
            penalty_cycles   <= {CNT_WIDTH{1'b0}};
        end else if (resolve_en) begin
            branch_count <= branch_count + 1'b1;
            if (mispredict) begin
                mispredict_count <= mispredict_count + 1'b1;
                penalty_cycles   <= penalty_cycles + MISPREDICT_PENALTY;
            end
        end
    end
endmodule
```

**Design notes**
- `flush` and `correct_pc` are **combinational**, so the redirect reaches the PC multiplexer in the same cycle as the EX-stage comparison.
- `correct_pc` is valid every cycle, but it is only *used* when `flush = 1`.
- The counters are the hardware source of the CPI numbers. Sarvesh's testbench checks that `branch_count` equals the number of trace lines.

---

## 6. Directed Testbench — `testbench/tb_flush_ctrl.v`

Five cases cover every row of the decision table: NT/NT, T/T with the correct target, NT→T, T→NT, and T/T with the wrong target.

```verilog
// tb_flush_ctrl.v -- directed tests for the pipeline flush/control interface.
module tb_flush_ctrl;
    reg         clk = 1'b0, rst = 1'b1, resolve_en = 1'b0;
    reg  [31:0] branch_pc = 32'h0040_0024;
    reg         pred_taken = 1'b0, actual_taken = 1'b0;
    reg  [31:0] pred_target = 32'd0, actual_target = 32'h0040_0010;
    wire        mispredict, dir_mis, tgt_mis, flush;
    wire [31:0] correct_pc, branch_count, mispredict_count, penalty_cycles;
    integer     errors = 0;

    always #5 clk = ~clk;

    flush_ctrl #(.MISPREDICT_PENALTY(2)) dut (
        .clk(clk), .rst(rst), .resolve_en(resolve_en), .branch_pc(branch_pc),
        .pred_taken(pred_taken), .pred_target(pred_target),
        .actual_taken(actual_taken), .actual_target(actual_target),
        .mispredict(mispredict), .dir_mispredict(dir_mis), .tgt_mispredict(tgt_mis),
        .flush(flush), .correct_pc(correct_pc), .branch_count(branch_count),
        .mispredict_count(mispredict_count), .penalty_cycles(penalty_cycles));

    // one resolved branch: (prediction, outcome) -> expected (flush, correct_pc)
    task case_check(input [8*30-1:0] msg, input pt, input [31:0] ptgt, input at,
                    input exp_flush, input [31:0] exp_pc);
        begin
            @(negedge clk);
            pred_taken = pt; pred_target = ptgt; actual_taken = at; resolve_en = 1'b1;
            #1;
            if (flush !== exp_flush || correct_pc !== exp_pc) begin
                errors = errors + 1;
                $display("FAIL %0s: flush=%b correct_pc=%h", msg, flush, correct_pc);
            end else
                $display("ok   %0s: flush=%b correct_pc=%h", msg, flush, correct_pc);
            @(negedge clk) resolve_en = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        //          description                 pred  pred_tgt       act  flush  correct_pc
        case_check("NT predicted, NT actual",  0, 32'h0040_0028, 0,   0, 32'h0040_0028);
        case_check("T  predicted, T  actual",  1, 32'h0040_0010, 1,   0, 32'h0040_0010);
        case_check("NT predicted, T  actual",  0, 32'h0040_0028, 1,   1, 32'h0040_0010);
        case_check("T  predicted, NT actual",  1, 32'h0040_0010, 0,   1, 32'h0040_0028);
        case_check("T  predicted, wrong tgt",  1, 32'h0040_0028, 1,   1, 32'h0040_0010);
        @(negedge clk);
        if (branch_count !== 5 || mispredict_count !== 3 || penalty_cycles !== 6) begin
            errors = errors + 1;
            $display("FAIL counters: branches=%0d mispred=%0d penalty=%0d",
                     branch_count, mispredict_count, penalty_cycles);
        end else
            $display("ok   counters: branches=5 mispred=3 penalty=6 cycles");
        if (errors == 0) $display("PASS tb_flush_ctrl");
        else             $display("FAIL tb_flush_ctrl (%0d errors)", errors);
        $finish;
    end
endmodule
```

**Run:** `make unit`, or

```bash
iverilog -Wall -g2005 -o build/tb_flush_ctrl.vvp testbench/tb_flush_ctrl.v rtl/flush_ctrl.v
vvp -n build/tb_flush_ctrl.vvp
```

**Actual output:**

```
ok   NT predicted, NT actual: flush=0 correct_pc=00400028
ok   T  predicted, T  actual: flush=0 correct_pc=00400010
ok   NT predicted, T  actual: flush=1 correct_pc=00400010
ok   T  predicted, NT actual: flush=1 correct_pc=00400028
ok   T  predicted, wrong tgt: flush=1 correct_pc=00400010
ok   counters: branches=5 mispred=3 penalty=6 cycles
PASS tb_flush_ctrl
```

---

## 7. Hand-Written MIPS Program and Its Branch Trace

### 7.1 C source

```c
int a[8] = {3, 0, 5, 7, 0, 0, 2, 9};
int sum = 0;
for (int i = 0; i != 8; i++) {
    if (a[i] == 0) continue;     // skip zero elements  -> BEQ
    sum += a[i];
}                                 // loop back           -> BNE
```

### 7.2 MIPS32 assembly (`.text` starts at `0x00400000`)

| Address | Instruction | Comment |
|---|---|---|
| `0x00400000` | `addi $t0, $zero, 0` | i = 0 |
| `0x00400004` | `addi $t1, $zero, 8` | n = 8 |
| `0x00400008` | `addi $s0, $zero, 0` | sum = 0 |
| `0x0040000C` | `addi $t2, $zero, 0x100` | pointer to `a[0]` (simplified data address) |
| `0x00400010` | **loop:** `lw $t3, 0($t2)` | load `a[i]` |
| `0x00400014` | `beq $t3, $zero, skip` | **branch 1:** if `a[i] == 0`, skip the add |
| `0x00400018` | `add $s0, $s0, $t3` | sum += a[i] |
| `0x0040001C` | **skip:** `addi $t2, $t2, 4` | pointer++ |
| `0x00400020` | `addi $t0, $t0, 1` | i++ |
| `0x00400024` | `bne $t0, $t1, loop` | **branch 2:** loop while `i != n` |
| `0x00400028` | `sw $s0, 0x200($zero)` | store the result (sum = 26) |

### 7.3 Encoding the two branches (I-format)

MIPS branch target = `PC + 4 + (sign_extend(imm16) << 2)`, so `imm16 = (target − (PC + 4)) / 4`.

| Branch | opcode | rs | rt | imm16 | Target check | Machine code |
|---|---|---|---|---|---|---|
| `beq $t3,$zero,skip` @ `0x14` | `000100` | `$t3` = 11 = `01011` | `$zero` = `00000` | (0x1C − 0x18)/4 = **+1** = `0x0001` | 0x18 + 4 = 0x1C ✓ | **`0x11600001`** |
| `bne $t0,$t1,loop` @ `0x24` | `000101` | `$t0` = 8 = `01000` | `$t1` = 9 = `01001` | (0x10 − 0x28)/4 = **−6** = `0xFFFA` | 0x28 − 24 = 0x10 ✓ | **`0x1509FFFA`** |

Bit layout for `bne`: `000101 01000 01001 1111111111111010` → `0001 0101 0000 1001 1111 1111 1111 1010` = `0x1509FFFA`.

### 7.4 Deriving the trace

| i | a[i] | BEQ @ 0x00400014 (taken if a[i] = 0) | BNE @ 0x00400024 (taken if i+1 ≠ 8) |
|---|---|---|---|
| 0 | 3 | 0 | 1 |
| 1 | 0 | 1 | 1 |
| 2 | 5 | 0 | 1 |
| 3 | 7 | 0 | 1 |
| 4 | 0 | 1 | 1 |
| 5 | 0 | 1 | 1 |
| 6 | 2 | 0 | 1 |
| 7 | 9 | 0 | **0** (loop exit) |

### 7.5 `python/mips_trace.py` → `traces/array_sum.csv`

The trace is not typed by hand: the script assembles the program, executes it, and records every executed BEQ/BNE. Actual output of `python3 python/mips_trace.py`:

```
Address   Machine code  Instruction
00400000  20080000            addi $t0, $zero, 0
00400004  20090008            addi $t1, $zero, 8
00400008  20100000            addi $s0, $zero, 0
0040000c  200a0100            addi $t2, $zero, 256
00400010  8d4b0000      loop: lw   $t3, 0x0($t2)
00400014  11600001            beq  $t3, $zero, skip
00400018  020b8020            add  $s0, $s0, $t3
0040001c  214a0004      skip: addi $t2, $t2, 4
00400020  21080001            addi $t0, $t0, 1
00400024  1509fffa            bne  $t0, $t1, loop
00400028  ac100200            sw   $s0, 0x200($zero)
sum = 26 (expected 26); 16 branches -> traces/array_sum.csv
```

The encodings `0x11600001` and `0x1509fffa` match the hand calculation in 7.3, and the 16 recorded branches match the table in 7.4. The CSV format is shared with Rohit's traces:

```
pc,type,taken,target
00400014,BEQ,0,0040001c
00400024,BNE,1,00400010
00400014,BEQ,1,0040001c
...
```

### 7.6 Results on this trace (from the verified simulation)

| Scheme | Accuracy | Mispredictions | Estimated CPI |
|---|---:|---:|---:|
| Static NT | 37.50 % | 10 | 1.250 |
| 1-bit | 62.50 % | 6 | 1.150 |
| 2-bit | 62.50 % | 6 | 1.150 |

**Interpretation:** with only 8 iterations, the warm-up cost (the first BNE and the first BEQ) is a large share of all branches. The data-dependent BEQ (`0,1,0,0,1,1,0,0`) also has no stable bias for a counter to learn. The 1-bit and 2-bit schemes tie here, and the longer traces (Rohit) are needed to show the advantage of the 2-bit scheme. This is a useful honest observation for the report.

---

## 7A. The Integrated Unit — `rtl/bpu_top.v` and `testbench/tb_bpu_top.v`

`bpu_top` is the unit a 5-stage pipeline would instantiate:

| Port group | Signals |
|---|---|
| IF stage | `fetch_pc`, `fetch_is_branch` → `pred_taken`, `pred_target`, `btb_hit`, `pred_state` |
| EX stage | `ex_valid`, `ex_pc`, `ex_pred_taken`, `ex_pred_target` (the prediction carried down the pipeline), `ex_actual_taken`, `ex_actual_target` |
| Control | `mispredict`, `dir_mispredict`, `tgt_mispredict`, `flush`, `correct_pc`, `next_pc` |
| Counters | `branch_count`, `mispredict_count`, `penalty_cycles` |

```verilog
// A misprediction in EX has priority over the new prediction in IF.
assign next_pc = flush ? correct_pc : pred_target;
```

`tb_bpu_top.v` checks the integrated behaviour (actual output, all `ok`, ending in `PASS tb_bpu_top`):

| Case | What is checked |
|---|---|
| A. cold branch | counter 01 predicts NT, BTB miss → flush, `next_pc` = real target |
| B. trained branch | counter 10 predicts T, BTB hit → no flush, `next_pc` = BTB target |
| C. loop exit | counter 11 predicts T, actual NT → flush, `next_pc` = pc + 4 |
| D. **target misprediction** | `0x00400050` aliases `0x00400010` in the BHT (predicts T) but misses in the tagged BTB → `pred_target` = pc + 4, `tgt_mispredict` = 1, flush to the real target |
| E. non-branch | no prediction, `next_pc` = pc + 4 |
| F. flush priority | IF predicts T while an older branch mispredicts in EX → `next_pc` = EX's `correct_pc` |
| G. counters | 7 branches, 4 mispredictions, 8 penalty cycles |

During development, cases F and G first failed. Both failures were errors in the test's expectations, not in the RTL: case D had already evicted `0x00400010` from BTB entry 4, and the test runs 7 branches, not 8. The RTL behaviour was correct, and the test was corrected to match it. This is a good example to mention in the viva.

## 8. Interfaces with Teammates

| You give | To |
|---|---|
| `flush_ctrl.v`, with counters and `dir_/tgt_mispredict` | Sarvesh (instantiated in `tb_predictor.v`; the waveform shows `mispredict`, `flush`) |
| Misprediction rule (exact formula) | Rohit (golden model must use the same rule) |
| Penalty = 2 and the CPI formula with assumptions | Sarvesh (`analyze.py`, report Sections 6–7) |
| `traces/array_sum.csv` | Sarvesh (picked up automatically by `make test`) |
| Report Section 1 and the flush part of Section 4 | Sarvesh (final report) |

| You need | From |
|---|---|
| Definition of `pred_target` (BTB target only if predicted T and hit, else `pc+4`) | Keshav |
| Trace file format | Rohit |

---

## 9. Viva Preparation (Your Part)

1. **Why is the misprediction penalty 2 cycles in our model?**
   The branch resolves in EX, which is the 3rd stage. The two younger instructions in IF and ID are on the wrong path and must be squashed.

2. **Why is a predicted-taken branch with the right direction still a misprediction sometimes?**
   If the BTB missed or held a stale target, fetch went to the wrong address. The direction was right, but the fetched instructions are wrong, so the pipeline must still flush. This is `tgt_mispredict`.

3. **What does `correct_pc` contain when a predicted-taken branch is actually not taken?**
   `branch_pc + 4`, the fall-through instruction.

4. **How would moving branch resolution to the ID stage change the results?**
   The penalty would drop to 1 cycle. The CPI overhead term `branch_freq × rate × penalty` halves for every scheme, but the relative ranking of the schemes stays the same.

---

## 10. Deliverables Checklist

- [x] Report Section 1 (control hazards, penalty derivation, CPI model)
- [x] `rtl/flush_ctrl.v`, `rtl/bpu_top.v` — lint-clean
- [x] `testbench/tb_flush_ctrl.v` — `PASS tb_flush_ctrl`
- [x] `testbench/tb_bpu_top.v` — `PASS tb_bpu_top`
- [x] `python/mips_trace.py` → `traces/array_sum.csv`
- [x] Flush / bpu_top part of Section 4
