`timescale 1ns / 1ps
// tb_flush_ctrl.v -- directed tests for the pipeline flush/control interface.
// Owner: Mayank  |  Project 5: Dynamic Branch Prediction Unit
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
