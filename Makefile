# =============================================================================
#  Project 5: Dynamic Branch Prediction Unit  --  build, test, analyse, synthesize
#  Owner: Keshav (integration)          Run "make help" for the list of targets.
# =============================================================================
IVERILOG := iverilog -Wall -g2005
VVP      := vvp -n
PY       := python3
BUILD    := build
RTL      := $(sort $(wildcard rtl/*.v))
LOGS     := results/logs
WAVES    := results/waveforms

.PHONY: help all traces unit regression sweep test wave view report synth demo lint clean distclean

help:
	@echo "make traces      generate branch traces (traces/*.csv)"
	@echo "make unit        directed tests: 2-bit/1-bit FSM, BTB, flush control, integrated BPU"
	@echo "make regression  every trace x every scheme vs the Python golden model"
	@echo "make test        traces + unit + regression + BHT-size sweep"
	@echo "make wave        dump VCD waveforms into results/waveforms/"
	@echo "make view        open the predictor waveform in the Surfer viewer"
	@echo "make report      accuracy / misprediction / CPI tables and charts"
	@echo "make synth       Yosys synthesis of all three schemes"
	@echo "make all         test + wave + report + synth"
	@echo "make demo        short live demonstration for the viva"
	@echo "make clean       remove build/ (keeps results/)"

all: test wave report synth

$(BUILD) $(LOGS) $(WAVES):
	@mkdir -p $@

# ---- Rohit / Mayank: workloads -------------------------------------------
traces:
	$(PY) python/gen_traces.py traces
	$(PY) python/mips_trace.py traces

# ---- Arun, Keshav, Mayank: directed unit tests ----------------------------
define RUN_UNIT
	$(IVERILOG) -o $(BUILD)/$(1).vvp testbench/$(1).v $(2)
	@$(VVP) $(BUILD)/$(1).vvp $(3) > $(LOGS)/$(1).log; \
	  grep -E "^(PASS|FAIL)" $(LOGS)/$(1).log | tail -1; \
	  ! grep -q "^FAIL" $(LOGS)/$(1).log
endef

unit: | $(BUILD) $(LOGS)
	$(call RUN_UNIT,tb_bht_fsm,rtl/bht_1bit.v rtl/bht_2bit.v)
	$(call RUN_UNIT,tb_btb,rtl/btb.v)
	$(call RUN_UNIT,tb_flush_ctrl,rtl/flush_ctrl.v)
	$(call RUN_UNIT,tb_bpu_top,$(RTL))

# ---- Sarvesh: system regression against the golden model ------------------
regression: | $(BUILD)
	$(PY) python/run_regression.py

sweep: | $(BUILD)
	$(PY) python/run_regression.py --sweep

test: traces unit sweep
	@echo "ALL TESTS PASSED"

# ---- waveforms (GTKWave) ---------------------------------------------------
wave: | $(BUILD) $(WAVES)
	$(IVERILOG) -Ptb_predictor.SCHEME=2 -o $(BUILD)/tb_wave.vvp testbench/tb_predictor.v $(RTL)
	$(VVP) $(BUILD)/tb_wave.vvp +TRACE=traces/loop10.csv +NAME=loop10 \
	    +VCD=$(WAVES)/predictor_loop10.vcd | grep -E "^(RESULT|PASS|FAIL)"
	$(IVERILOG) -o $(BUILD)/tb_bht_fsm.vvp testbench/tb_bht_fsm.v rtl/bht_1bit.v rtl/bht_2bit.v
	$(VVP) $(BUILD)/tb_bht_fsm.vvp +VCD > /dev/null
	$(IVERILOG) -o $(BUILD)/tb_bpu_top.vvp testbench/tb_bpu_top.v $(RTL)
	$(VVP) $(BUILD)/tb_bpu_top.vvp +VCD > /dev/null
	@ls -1 $(WAVES)/*.vcd
	@echo "view: make view   (or: gtkwave $(WAVES)/predictor_loop10.vcd $(WAVES)/predictor.gtkw)"

# ---- open the waveform in Surfer (brew install surfer) ---------------------
view:
	@test -f $(WAVES)/predictor_loop10.vcd || $(MAKE) wave
	surfer $(WAVES)/predictor_loop10.vcd -c $(WAVES)/predictor_signals.txt

# ---- Sarvesh: analysis -----------------------------------------------------
report:
	$(PY) python/analyze.py

# ---- Keshav: synthesis -----------------------------------------------------
synth: | $(BUILD)
	$(PY) python/synth_report.py

# ---- lint: every RTL file with all warnings enabled ------------------------
lint: | $(BUILD)
	$(IVERILOG) -o $(BUILD)/lint.vvp $(RTL) && echo "iverilog -Wall: no warnings"

# ---- live demonstration ----------------------------------------------------
demo: | $(BUILD) $(LOGS)
	@echo "=== 1. MIPS program -> branch trace ==="
	@$(PY) python/mips_trace.py traces
	@echo; echo "=== 2. 2-bit FSM: all 8 transitions, saturation, loop exit/re-entry ==="
	@$(IVERILOG) -o $(BUILD)/tb_bht_fsm.vvp testbench/tb_bht_fsm.v rtl/bht_1bit.v rtl/bht_2bit.v
	@$(VVP) $(BUILD)/tb_bht_fsm.vvp | grep -E "^(   |--|PASS|FAIL)"
	@echo; echo "=== 3. Same loop trace on the three predictors (RTL vs golden model) ==="
	@for s in 0 1 2; do \
	  $(IVERILOG) -Ptb_predictor.SCHEME=$$s -o $(BUILD)/demo_s$$s.vvp testbench/tb_predictor.v $(RTL); \
	  $(PY) python/ref_model.py traces/loop10.csv $$s $(BUILD)/demo_s$$s.exp > /dev/null; \
	  $(VVP) $(BUILD)/demo_s$$s.vvp +TRACE=traces/loop10.csv +EXP=$(BUILD)/demo_s$$s.exp +NAME=loop10 \
	    | grep -E "^(RESULT|  accuracy|PASS|FAIL)"; \
	done
	@echo; echo "=== 4. Overall comparison (from results/accuracy_table.md) ==="
	@sed -n '/## 1\./,/## 2\./p' results/accuracy_table.md | grep '^|'

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -rf results/logs results/charts results/synthesis results/*.csv results/*.md $(WAVES)/*.vcd
