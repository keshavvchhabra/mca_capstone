// tb_predictor.v -- trace-driven, self-checking system testbench for bpu_top.
// Owner: Sarvesh  |  Project 5: Dynamic Branch Prediction Unit
//
// One branch per clock cycle:
//   negedge : drive the branch on the IF port and resolve it on the EX port
//   #1      : sample combinational outputs, compare with the golden model
//   posedge : BHT, BTB and performance counters update
// Checked per branch: pred_taken, btb_hit, pred_target, mispredict, next_pc,
// and next_pc must ALWAYS equal the architecturally correct next PC.
//
// Plusargs: +TRACE=<csv> +EXP=<expectation file> +NAME=<label> +VCD=<file>
module tb_predictor;
    parameter SCHEME         = 2;
    parameter BHT_INDEX_BITS = 4;
    parameter BTB_INDEX_BITS = 4;
    parameter PENALTY        = 2;
    parameter MAX_BRANCHES   = 100000;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] pc = 32'd0;
    reg         is_branch = 1'b0;
    reg         update_en = 1'b0;
    reg         actual_taken = 1'b0;
    reg  [31:0] actual_target = 32'd0;

    wire        pred_taken, btb_hit;
    wire [31:0] pred_target;
    wire [1:0]  counter_state;
    wire        mispredict, dir_mispredict, tgt_mispredict, flush;
    wire [31:0] correct_pc, next_pc, branch_count, mispredict_count, penalty_cycles;

    always #5 clk = ~clk;

    // In this trace-driven test a branch is predicted and resolved in the same
    // cycle, so the IF-stage prediction is fed straight back as ex_pred_*.
    bpu_top #(.SCHEME(SCHEME), .BHT_INDEX_BITS(BHT_INDEX_BITS),
              .BTB_INDEX_BITS(BTB_INDEX_BITS), .MISPREDICT_PENALTY(PENALTY)) dut (
        .clk(clk), .rst(rst),
        .fetch_pc(pc), .fetch_is_branch(is_branch),
        .pred_taken(pred_taken), .pred_target(pred_target),
        .btb_hit(btb_hit), .pred_state(counter_state),
        .ex_valid(update_en), .ex_pc(pc),
        .ex_pred_taken(pred_taken), .ex_pred_target(pred_target),
        .ex_actual_taken(actual_taken), .ex_actual_target(actual_target),
        .mispredict(mispredict), .dir_mispredict(dir_mispredict),
        .tgt_mispredict(tgt_mispredict), .flush(flush),
        .correct_pc(correct_pc), .next_pc(next_pc),
        .branch_count(branch_count), .mispredict_count(mispredict_count),
        .penalty_cycles(penalty_cycles));

    // ---------------- trace / expectation reading ----------------
    reg [8*256-1:0] trace_file, exp_file, name, vcd_file;
    reg [8*80-1:0]  line_buf;
    reg [7:0]       k0, k1, k2;               // branch type characters (BEQ/BNE)
    integer fd_t, fd_e, r;
    integer n, correct, hits, errors, first_err;
    reg [31:0] t_pc, t_target, e_target, e_next, arch_next;
    integer    t_taken, e_taken, e_hit, e_mis;
    reg        have_exp;

    task report_mismatch(input [8*40-1:0] why);
        begin
            errors = errors + 1;
            if (first_err < 0) begin
                first_err = n;
                $display("MISMATCH (%0s) at branch %0d, cycle %0d, t=%0t, pc=%h",
                         why, n, n + 3, $time, t_pc);
                $display("   RTL  : pred=%b hit=%b tgt=%h mis=%b next=%h",
                         pred_taken, btb_hit, pred_target, mispredict, next_pc);
                if (have_exp)
                    $display("   MODEL: pred=%0d hit=%0d tgt=%h mis=%0d next=%h",
                             e_taken, e_hit, e_target, e_mis, e_next);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_file)) trace_file = "traces/loop10.csv";
        have_exp = $value$plusargs("EXP=%s", exp_file);
        if (!$value$plusargs("NAME=%s", name)) name = "trace";
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_predictor);
        end

        fd_t = $fopen(trace_file, "r");
        if (fd_t == 0) begin $display("FATAL: cannot open trace %0s", trace_file); $finish; end
        fd_e = 0;
        if (have_exp) begin
            fd_e = $fopen(exp_file, "r");
            if (fd_e == 0) begin $display("FATAL: cannot open %0s", exp_file); $finish; end
        end

        n = 0; correct = 0; hits = 0; errors = 0; first_err = -1;
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Read the CSV line by line. The header line "pc,type,taken,target"
        // does not parse as numbers and is skipped automatically.
        while (!$feof(fd_t) && n < MAX_BRANCHES) begin
            line_buf = 0;
            r = $fgets(line_buf, fd_t);
            r = $sscanf(line_buf, "%h,%c%c%c,%d,%h", t_pc, k0, k1, k2, t_taken, t_target);
            if (r == 6) begin
                pc = t_pc; is_branch = 1'b1;
                update_en = 1'b1; actual_taken = t_taken[0]; actual_target = t_target;
                #1;
                if (pred_taken == actual_taken) correct = correct + 1;
                if (btb_hit) hits = hits + 1;

                // 1) the pipeline must always continue on the correct path
                arch_next = actual_taken ? actual_target : pc + 4;
                if (next_pc !== arch_next) report_mismatch("next_pc != correct path");

                // 2) every output must match the golden model
                if (have_exp) begin
                    r = $fscanf(fd_e, "%d %d %h %d %h\n", e_taken, e_hit, e_target, e_mis, e_next);
                    if (pred_taken !== e_taken[0] || btb_hit !== e_hit[0] ||
                        pred_target !== e_target || mispredict !== e_mis[0] ||
                        next_pc !== e_next)
                        report_mismatch("RTL != golden model");
                end
                n = n + 1;
                @(negedge clk);
            end
        end
        update_en = 1'b0; is_branch = 1'b0;
        @(negedge clk);

        // the hardware counters must agree with the testbench's own count
        if (branch_count != n) begin
            errors = errors + 1;
            $display("COUNTER ERROR: branch_count=%0d expected %0d", branch_count, n);
        end
        if (penalty_cycles != PENALTY * mispredict_count) begin
            errors = errors + 1;
            $display("COUNTER ERROR: penalty_cycles=%0d", penalty_cycles);
        end

        $display("RESULT name=%0s scheme=%0d bht=%0d branches=%0d correct=%0d mispred=%0d btb_hits=%0d penalty=%0d",
                 name, SCHEME, 1 << BHT_INDEX_BITS, n, correct, mispredict_count, hits,
                 penalty_cycles);
        $display("  accuracy = %0.2f %%   btb hit rate = %0.2f %%",
                 100.0 * correct / n, 100.0 * hits / n);
        if (!have_exp && errors == 0) $display("PASS %0s scheme=%0d (next_pc check only, no +EXP file)", name, SCHEME);
        else if (errors == 0)         $display("PASS %0s scheme=%0d", name, SCHEME);
        else                          $display("FAIL %0s scheme=%0d (%0d mismatches, first at branch %0d)",
                                               name, SCHEME, errors, first_err);
        $fclose(fd_t);
        if (fd_e) $fclose(fd_e);
        $finish;
    end
endmodule
