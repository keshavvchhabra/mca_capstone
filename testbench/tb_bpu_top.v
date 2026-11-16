// tb_bpu_top.v -- directed pipeline-level tests of the integrated bpu_top.
// Owner: Mayank  |  Project 5: Dynamic Branch Prediction Unit
// Uses the 2-bit scheme with a 16-entry BHT and BTB.
//   A. cold branch: predicted NT, actually T  -> flush, next_pc = target
//   B. trained branch: predicted T with BTB target -> no flush, next_pc = target
//   C. loop exit: predicted T, actually NT   -> flush, next_pc = pc + 4
//   D. TARGET misprediction: an alias PC shares the trained BHT counter
//      (predicts T) but misses in the tagged BTB -> pred_target = pc+4,
//      flush with tgt_mispredict = 1 and next_pc = real target
//   E. non-branch instruction: no prediction, next_pc = pc + 4
//   F. flush has priority over the IF-stage prediction in the same cycle
//   G. performance counters
module tb_bpu_top;
    reg         clk = 1'b0, rst = 1'b1;
    reg  [31:0] fetch_pc = 32'd0;
    reg         fetch_is_branch = 1'b0;
    reg         ex_valid = 1'b0, ex_pred_taken = 1'b0, ex_actual_taken = 1'b0;
    reg  [31:0] ex_pc = 32'd0, ex_pred_target = 32'd0, ex_actual_target = 32'd0;
    wire        pred_taken, btb_hit, mispredict, dir_mis, tgt_mis, flush;
    wire [1:0]  pred_state;
    wire [31:0] pred_target, correct_pc, next_pc, branch_count, mispredict_count, penalty_cycles;
    integer     errors = 0;

    always #5 clk = ~clk;

    bpu_top #(.SCHEME(2)) dut (
        .clk(clk), .rst(rst), .fetch_pc(fetch_pc), .fetch_is_branch(fetch_is_branch),
        .pred_taken(pred_taken), .pred_target(pred_target), .btb_hit(btb_hit),
        .pred_state(pred_state), .ex_valid(ex_valid), .ex_pc(ex_pc),
        .ex_pred_taken(ex_pred_taken), .ex_pred_target(ex_pred_target),
        .ex_actual_taken(ex_actual_taken), .ex_actual_target(ex_actual_target),
        .mispredict(mispredict), .dir_mispredict(dir_mis), .tgt_mispredict(tgt_mis),
        .flush(flush), .correct_pc(correct_pc), .next_pc(next_pc),
        .branch_count(branch_count), .mispredict_count(mispredict_count),
        .penalty_cycles(penalty_cycles));

    task check(input [8*44-1:0] msg, input cond);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL %0s", msg); end
            else $display("ok   %0s", msg);
        end
    endtask

    // Predict a branch in IF and resolve the SAME branch in EX (one cycle).
    task branch(input [31:0] bpc, input taken, input [31:0] tgt);
        begin
            @(negedge clk);
            fetch_pc = bpc; fetch_is_branch = 1'b1;
            #1;
            ex_valid = 1'b1; ex_pc = bpc; ex_pred_taken = pred_taken;
            ex_pred_target = pred_target; ex_actual_taken = taken; ex_actual_target = tgt;
            #1;
        end
    endtask

    task idle;
        begin
            @(negedge clk); ex_valid = 1'b0; fetch_is_branch = 1'b0;
        end
    endtask

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("results/waveforms/bpu_top.vcd");
            $dumpvars(0, tb_bpu_top);
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;

        $display("-- A. cold branch --");
        branch(32'h0040_0010, 1'b1, 32'h0040_0000);
        check("A pred NT (counter 01), BTB miss", !pred_taken && !btb_hit && pred_state == 2'b01);
        check("A flush, dir mispredict",          flush && dir_mis && !tgt_mis);
        check("A next_pc = real target 00400000", next_pc == 32'h0040_0000);
        idle;

        $display("-- B. trained branch --");
        branch(32'h0040_0010, 1'b1, 32'h0040_0000);
        check("B pred T (counter 10), BTB hit",   pred_taken && btb_hit && pred_state == 2'b10);
        check("B no flush",                       !flush && !mispredict);
        check("B next_pc = BTB target",           next_pc == 32'h0040_0000);
        idle;

        $display("-- C. loop exit --");
        branch(32'h0040_0010, 1'b1, 32'h0040_0000);       // counter -> 11
        idle;
        branch(32'h0040_0010, 1'b0, 32'h0040_0000);       // exit
        check("C pred T (counter 11), actual NT", pred_taken && pred_state == 2'b11);
        check("C flush, correct_pc = pc+4",       flush && correct_pc == 32'h0040_0014);
        check("C next_pc = 00400014",             next_pc == 32'h0040_0014);
        idle;

        $display("-- D. target misprediction through BHT aliasing --");
        // 0x00400050 has the same BHT index (pc[5:2] = 4) as 0x00400010, whose
        // counter is 10 (weakly taken), but a different BTB tag.
        branch(32'h0040_0050, 1'b1, 32'h0040_0400);
        check("D pred T from shared counter",     pred_taken && pred_state == 2'b10);
        check("D BTB miss -> pred_target = pc+4", !btb_hit && pred_target == 32'h0040_0054);
        check("D target mispredict + flush",      flush && tgt_mis && !dir_mis);
        check("D next_pc = real target 00400400", next_pc == 32'h0040_0400);
        idle;
        branch(32'h0040_0050, 1'b1, 32'h0040_0400);
        check("D' BTB now hits with new target",  btb_hit && pred_target == 32'h0040_0400 && !flush);
        idle;

        $display("-- E. non-branch instruction --");
        @(negedge clk); fetch_pc = 32'h0040_0018; fetch_is_branch = 1'b0; ex_valid = 1'b0; #1;
        check("E no prediction, next_pc = pc+4",  !pred_taken && next_pc == 32'h0040_001C && !flush);

        $display("-- F. flush priority --");
        // IF fetches the trained branch 0x00400050 (predicts T to 00400400)
        // while an older branch at 0x00400024 mispredicts in EX.
        @(negedge clk);
        fetch_pc = 32'h0040_0050; fetch_is_branch = 1'b1;
        ex_valid = 1'b1; ex_pc = 32'h0040_0024; ex_pred_taken = 1'b0;
        ex_pred_target = 32'h0040_0028; ex_actual_taken = 1'b1; ex_actual_target = 32'h0040_0300;
        #1;
        check("F IF predicts T to 00400400",      pred_taken && pred_target == 32'h0040_0400);
        check("F EX flush wins: next_pc=00400300", flush && next_pc == 32'h0040_0300);
        idle;
        @(negedge clk);

        $display("-- G. counters --");
        $display("   branches=%0d mispredictions=%0d penalty=%0d",
                 branch_count, mispredict_count, penalty_cycles);
        // branches: A, B, C x2, D x2, F = 7; mispredictions: A, C-exit, D, F = 4
        check("G counters 7 / 4 / 8 cycles",
              branch_count == 7 && mispredict_count == 4 && penalty_cycles == 8);

        if (errors == 0) $display("PASS tb_bpu_top");
        else             $display("FAIL tb_bpu_top (%0d errors)", errors);
        $finish;
    end
endmodule
