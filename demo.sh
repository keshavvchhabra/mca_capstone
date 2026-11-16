#!/usr/bin/env bash
# =============================================================================
#  demo.sh -- live demonstration of the Dynamic Branch Prediction Unit
#  Project 5, MCA (Modern Computer Architecture)
#
#  usage:  ./demo.sh                3-minute demo (5 steps), press Enter to continue
#          ./demo.sh --full         full 10-step demo (about 12 minutes)
#          ./demo.sh --auto         run without pausing (combine with --full)
#          ./demo.sh 3              start at step 3
# =============================================================================
cd "$(dirname "$0")" || exit 1

AUTO=0
FULL=0
START=1
for arg in "$@"; do
  case "$arg" in
    --auto) AUTO=1 ;;
    --full) FULL=1 ;;
    [0-9]*) START=$arg ;;
  esac
done

BOLD=$'\e[1m'; BLUE=$'\e[34m'; GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; RESET=$'\e[0m'
[ -t 1 ] || { BOLD=; BLUE=; GREEN=; RED=; DIM=; RESET=; }

step() {   # step <number> <title> <explanation>
  STEP=$1
  [ "$STEP" -lt "$START" ] && return 1
  echo
  echo "${BLUE}${BOLD}=====================================================================${RESET}"
  echo "${BLUE}${BOLD} STEP $1: $2${RESET}"
  echo "${BLUE}${BOLD}=====================================================================${RESET}"
  echo "${DIM}$3${RESET}"
  return 0
}
run() {    # show the command, then run it
  echo
  echo "${BOLD}\$ $*${RESET}"
  eval "$@"
}
pause() {
  [ "$AUTO" -eq 1 ] && return
  echo
  read -r -p "${DIM}Press Enter for the next step...${RESET}" _
}

# =============================================================================
#  3-MINUTE DEMO (default)
# =============================================================================
if [ "$FULL" -eq 0 ]; then

if step 1 "The design  (0:00 - 0:30)" \
"A dynamic branch prediction unit in synthesizable Verilog: 3 predictors,
a Branch Target Buffer and pipeline flush control."; then
  echo "  bpu_top                      complete unit                (Mayank)"
  echo "  |-- branch_predictor_top     predicts in the IF stage     (Keshav)"
  echo "  |   |-- static_not_taken | bht_1bit | bht_2bit            (Arun)"
  echo "  |   |-- btb                  branch target buffer         (Keshav)"
  echo "  |   \`-- bp_update_logic, bp_select_logic                  (Keshav)"
  echo "  \`-- flush_ctrl               checks the guess in EX       (Mayank)"
  run "make -s lint"
  pause
fi

if step 2 "Unit tests: the 2-bit state machine  (0:30 - 1:00)" \
"All 8 transitions of the 2-bit counter, saturation, BTB and flush control."; then
  run "make -s unit 2>&1 | grep -E '^(PASS|FAIL)'"
  run "grep 'steady-state' results/logs/tb_bht_fsm.log"
  pause
fi

if step 3 "Same loop, three predictors  (1:00 - 1:40)" \
"A 10-iteration loop run 10 times, simulated in Verilog and checked against
the Python golden model."; then
  mkdir -p build
  for s in 0 1 2; do
    python3 python/ref_model.py traces/loop10.csv $s build/demo_s$s.exp > /dev/null
    iverilog -g2005 -Ptb_predictor.SCHEME=$s -o build/demo_s$s.vvp testbench/tb_predictor.v rtl/*.v
    name=$(echo 'Static not-taken|1-bit BHT       |2-bit BHT       ' | cut -d'|' -f$((s+1)))
    out=$(vvp -n build/demo_s$s.vvp +TRACE=traces/loop10.csv +EXP=build/demo_s$s.exp +NAME=loop10)
    acc=$(echo "$out" | awk '/accuracy =/{print $3}')
    res=$(echo "$out" | grep -oE '^(PASS|FAIL)')
    echo "  ${BOLD}$name${RESET}  accuracy $acc %   ${GREEN}$res${RESET} (matches golden model)"
  done
  pause
fi

if step 4 "All traces: accuracy and CPI  (1:40 - 2:10)" \
"8 traces x 3 predictors, every prediction compared with the golden model.
CPI = 1 + 0.2 x misprediction rate x 2 cycles."; then
  run "python3 python/run_regression.py | tail -1"
  python3 python/analyze.py > /dev/null
  run "sed -n '/## 1\./,/## 2\./p' results/accuracy_table.md | grep '^|' | cut -d'|' -f2,5,6,8,9"
  pause
fi

if step 5 "Waveform in Surfer  (2:10 - 3:00)" \
"Branch 0 at 21 ns: cold miss, flush.  Branch 9 at 111 ns: loop exit, flush,
counter 11 -> 10.  Branch 10 at 121 ns: re-entry predicted correctly."; then
  make -s wave > /dev/null
  if [ "$AUTO" -eq 0 ] && command -v surfer >/dev/null; then
    run "surfer results/waveforms/predictor_loop10.vcd -c results/waveforms/predictor_signals.txt > /dev/null 2>&1 &"
  else
    echo "Open it with:  make view"
  fi
fi

echo
echo "${GREEN}${BOLD}Demo complete.${RESET}  (Full 10-step version: ./demo.sh --full)"
exit 0
fi

# =============================================================================
#  FULL DEMO (--full)
# =============================================================================
# ---------------------------------------------------------------------------
if step 1 "Check the tools" \
"Icarus Verilog simulates the hardware, Python generates traces and analyses
results, Yosys synthesizes the design, and Surfer shows the waveforms."; then
  for t in iverilog vvp python3 yosys surfer; do
    if command -v "$t" >/dev/null; then echo "  ${GREEN}found${RESET}    $t"
    else echo "  ${RED}missing${RESET}  $t"; fi
  done
  run "iverilog -V 2>&1 | head -1"
  pause
fi

# ---------------------------------------------------------------------------
if step 2 "Project structure and module hierarchy" \
"rtl/ holds 9 synthesizable Verilog modules, testbench/ the 5 testbenches,
python/ the trace generator, golden model and analysis scripts."; then
  run "ls rtl testbench traces python/*.py"
  echo
  echo "${BOLD}Module hierarchy (bpu_top is the complete unit):${RESET}"
  cat <<'EOF'
  bpu_top                       (Mayank)
  |-- branch_predictor_top      (Keshav)
  |   |-- bp_update_logic       (Keshav)
  |   |-- static_not_taken | bht_1bit | bht_2bit   (Arun, chosen by SCHEME)
  |   |-- btb                   (Keshav)
  |   `-- bp_select_logic       (Keshav)
  `-- flush_ctrl                (Mayank)
EOF
  run "make lint"
  pause
fi

# ---------------------------------------------------------------------------
if step 3 "A real MIPS program becomes a branch trace" \
"mips_trace.py assembles an array-sum program, prints its machine code,
executes it and records every BEQ/BNE it executes."; then
  run "python3 python/mips_trace.py traces"
  run "head -5 traces/array_sum.csv"
  pause
fi

# ---------------------------------------------------------------------------
if step 4 "Generate the test traces" \
"Loop, nested-loop, alternating, random, aliasing and mixed patterns."; then
  run "python3 python/gen_traces.py traces"
  pause
fi

# ---------------------------------------------------------------------------
if step 5 "Directed unit tests (FSM, BTB, flush control, integrated unit)" \
"Every 2-bit transition, saturation, loop exit/re-entry, BTB hit/miss/alias,
flush cases, a target misprediction and flush priority."; then
  run "make unit"
  echo
  echo "${BOLD}2-bit FSM transitions and loop behaviour (from the log):${RESET}"
  run "grep -E '^   [01]|steady-state' results/logs/tb_bht_fsm.log"
  pause
fi

# ---------------------------------------------------------------------------
if step 6 "Same loop, three predictors (RTL checked against the golden model)" \
"loop10 = a 10-iteration loop run 10 times. Static not-taken is wrong on
every taken branch, the 1-bit predictor misses twice per loop, the 2-bit
predictor only once."; then
  mkdir -p build
  python3 python/ref_model.py traces/loop10.csv 0 build/demo_s0.exp > /dev/null
  python3 python/ref_model.py traces/loop10.csv 1 build/demo_s1.exp > /dev/null
  python3 python/ref_model.py traces/loop10.csv 2 build/demo_s2.exp > /dev/null
  for s in 0 1 2; do
    iverilog -g2005 -Ptb_predictor.SCHEME=$s -o build/demo_s$s.vvp testbench/tb_predictor.v rtl/*.v
    echo
    echo "${BOLD}--- SCHEME $s ($(echo 'Static not-taken|1-bit BHT|2-bit BHT' | cut -d'|' -f$((s+1)))) ---${RESET}"
    vvp -n build/demo_s$s.vvp +TRACE=traces/loop10.csv +EXP=build/demo_s$s.exp +NAME=loop10 \
      | grep -E "^(RESULT|  accuracy|PASS|FAIL)"
  done
  pause
fi

# ---------------------------------------------------------------------------
if step 7 "Full regression: every trace on every predictor" \
"24 runs plus 40 BHT-size runs; each branch of each run is compared with the
Python golden model."; then
  run "python3 python/run_regression.py --sweep | tail -12"
  pause
fi

# ---------------------------------------------------------------------------
if step 8 "Performance comparison: accuracy and CPI" \
"CPI = 1 + 0.2 x misprediction rate x 2 cycles."; then
  run "python3 python/analyze.py > /dev/null && sed -n '/## 1\./,/## 2\./p' results/accuracy_table.md | grep '^|'"
  if [ "$AUTO" -eq 0 ] && command -v open >/dev/null; then
    run "open results/charts/accuracy.png results/charts/cpi.png results/charts/bht_sweep.png"
  fi
  pause
fi

# ---------------------------------------------------------------------------
if step 9 "Synthesis (Yosys): hardware cost" \
"0 latches; the 2-bit predictor costs only 16 flip-flops more than the 1-bit one."; then
  if command -v yosys >/dev/null; then
    run "python3 python/synth_report.py | sed -n '/Generic/,/^Notes/p' | grep '^|'"
  else
    run "cat results/synthesis/synthesis_summary.md"
  fi
  pause
fi

# ---------------------------------------------------------------------------
if step 10 "Waveform in Surfer" \
"Look at branch 0 (cold miss -> flush), branch 9 (loop exit -> flush, counter
11 -> 10) and branch 10 (re-entry predicted correctly with counter 10)."; then
  run "make -s wave > /dev/null && ls results/waveforms/*.vcd"
  if [ "$AUTO" -eq 0 ] && command -v surfer >/dev/null; then
    run "surfer results/waveforms/predictor_loop10.vcd -c results/waveforms/predictor_signals.txt > /dev/null 2>&1 &"
    echo "Surfer is opening with the predictor signals already added."
  else
    echo "Open it with:  make view"
  fi
fi

echo
echo "${GREEN}${BOLD}Demo complete.${RESET}"
