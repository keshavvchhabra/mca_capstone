`timescale 1ns / 1ps
// tb_bht_fsm.v -- directed state-transition tests for the 1-bit and 2-bit BHT.
// Owner: Arun  |  Project 5: Dynamic Branch Prediction Unit
//   Part A: all 8 transitions of the 2-bit FSM (4 states x 2 inputs)
//   Part B: saturation at 00 and at 11
//   Part C: all 4 transitions of the 1-bit FSM
//   Part D: loop exit and re-entry (2-bit: 1 miss per loop, 1-bit: 2 misses)
module tb_bht_fsm;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] pc  = 32'h0040_0010;
    reg         update_en = 1'b0;
    reg         taken = 1'b0;
    wire        p1, p2;
    wire        s1;
    wire [1:0]  s2;
    integer     errors = 0;
    integer     k, rep, miss1, miss2;
    reg  [1:0]  start, expect_next;

    always #5 clk = ~clk;

    bht_1bit #(.INDEX_BITS(2)) u1 (.clk(clk), .rst(rst), .pc(pc), .update_pc(pc),
        .pred_taken(p1), .state_out(s1), .update_en(update_en), .actual_taken(taken));
    bht_2bit #(.INDEX_BITS(2)) u2 (.clk(clk), .rst(rst), .pc(pc), .update_pc(pc),
        .pred_taken(p2), .state_out(s2), .update_en(update_en), .actual_taken(taken));

    // apply one resolved branch outcome (one clock edge)
    task apply(input t);
        begin
            @(negedge clk); update_en = 1'b1; taken = t;
            @(negedge clk); update_en = 1'b0;
        end
    endtask

    task do_reset;
        begin
            @(negedge clk) rst = 1'b1;
            @(negedge clk) rst = 1'b0;
        end
    endtask

    // drive the 2-bit counter from reset (01) to state 'st'
    task goto_state(input [1:0] st);
        begin
            do_reset;
            case (st)
                2'b00: apply(1'b0);
                2'b01: ;                              // reset state
                2'b10: apply(1'b1);
                2'b11: begin apply(1'b1); apply(1'b1); end
            endcase
        end
    endtask

    task check2(input [1:0] exp_state, input [8*24-1:0] msg);
        begin
            if (s2 !== exp_state || p2 !== exp_state[1]) begin
                errors = errors + 1;
                $display("FAIL %0s: state=%b pred=%b, expected state=%b", msg, s2, p2, exp_state);
            end else
                $display("ok   %0s: state=%b pred=%b", msg, s2, p2);
        end
    endtask

    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("results/waveforms/bht_fsm.vcd");
            $dumpvars(0, tb_bht_fsm);
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // ---- reset values ----
        do_reset;
        check2(2'b01, "reset 2-bit = 01");
        if (s1 !== 1'b0) begin errors = errors + 1; $display("FAIL reset 1-bit"); end
        else $display("ok   reset 1-bit = 0");

        // ---- Part A: 8 transitions ----
        $display("-- Part A: 2-bit transitions --");
        for (k = 0; k < 8; k = k + 1) begin
            start = k[2:1];
            goto_state(start);
            check2(start, "  start state");
            apply(k[0]);
            // expected next state: saturating increment / decrement
            if (k[0]) expect_next = (start == 2'b11) ? 2'b11 : start + 1'b1;
            else      expect_next = (start == 2'b00) ? 2'b00 : start - 1'b1;
            $display("   %b --%s--> expect %b", start, k[0] ? "T " : "NT", expect_next);
            check2(expect_next, "  next state");
        end

        // ---- Part B: saturation ----
        $display("-- Part B: saturation --");
        goto_state(2'b11); apply(1'b1); apply(1'b1); check2(2'b11, "11 + T,T stays 11");
        goto_state(2'b00); apply(1'b0); apply(1'b0); check2(2'b00, "00 + NT,NT stays 00");

        // ---- Part C: 1-bit transitions ----
        $display("-- Part C: 1-bit transitions --");
        do_reset; apply(1'b0); if (s1 !== 1'b0) errors = errors + 1; $display("   0 --NT--> %b", s1);
        apply(1'b1);           if (s1 !== 1'b1) errors = errors + 1; $display("   0 --T --> %b", s1);
        apply(1'b1);           if (s1 !== 1'b1) errors = errors + 1; $display("   1 --T --> %b", s1);
        apply(1'b0);           if (s1 !== 1'b0) errors = errors + 1; $display("   1 --NT--> %b", s1);

        // ---- Part D: loop exit and re-entry ----
        // Run a 10-iteration loop (T x9, NT x1) three times and count the
        // mispredictions in the 2nd and 3rd runs (steady state).
        $display("-- Part D: loop exit / re-entry --");
        do_reset;
        miss1 = 0; miss2 = 0;
        for (rep = 0; rep < 3; rep = rep + 1)
            for (k = 0; k < 10; k = k + 1) begin
                @(negedge clk);
                taken = (k < 9);
                #1;
                if (rep > 0 && p1 !== taken) miss1 = miss1 + 1;
                if (rep > 0 && p2 !== taken) miss2 = miss2 + 1;
                update_en = 1'b1;
                @(negedge clk) update_en = 1'b0;
            end
        $display("   steady-state misses per loop: 1-bit = %0d, 2-bit = %0d", miss1 / 2, miss2 / 2);
        if (miss1 != 4 || miss2 != 2) begin
            errors = errors + 1;
            $display("FAIL loop exit/re-entry (expected 1-bit 2/loop, 2-bit 1/loop)");
        end

        if (errors == 0) $display("PASS tb_bht_fsm");
        else             $display("FAIL tb_bht_fsm (%0d errors)", errors);
        $finish;
    end
endmodule
