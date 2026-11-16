// tb_btb.v -- directed tests for the Branch Target Buffer.
// Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit
//   1. reset: every lookup misses
//   2. fill on a taken branch, then hit with the stored target
//   3. same index, different tag  -> miss (no false target)
//   4. conflict replacement: the newer branch evicts the older one
//   5. independent entries at different indices
//   6. target update for an existing entry
//   7. no write when update_en = 0
//   8. reset clears all valid bits
module tb_btb;
    reg         clk = 1'b0, rst = 1'b1;
    reg  [31:0] pc = 32'd0, update_pc = 32'd0, update_target = 32'd0;
    reg         update_en = 1'b0;
    wire        hit;
    wire [31:0] target;
    integer     errors = 0;

    always #5 clk = ~clk;

    btb #(.INDEX_BITS(4)) dut (.clk(clk), .rst(rst), .pc(pc), .update_pc(update_pc),
        .hit(hit), .target(target), .update_en(update_en), .update_target(update_target));

    task write_entry(input [31:0] bpc, input [31:0] tgt);
        begin
            @(negedge clk); update_pc = bpc; update_target = tgt; update_en = 1'b1;
            @(negedge clk); update_en = 1'b0;
        end
    endtask

    task expect_lookup(input [8*40-1:0] msg, input [31:0] lpc, input exp_hit,
                       input [31:0] exp_tgt);
        begin
            pc = lpc; #1;
            if (hit !== exp_hit || (exp_hit && target !== exp_tgt)) begin
                errors = errors + 1;
                $display("FAIL %0s: pc=%h hit=%b target=%h", msg, lpc, hit, target);
            end else
                $display("ok   %0s: pc=%h hit=%b target=%h", msg, lpc, hit, exp_hit ? target : 32'h0);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        expect_lookup("1 cold miss after reset",       32'h0040_0010, 0, 0);
        write_entry(32'h0040_0010, 32'h0040_0000);
        expect_lookup("2 hit after taken branch",      32'h0040_0010, 1, 32'h0040_0000);
        expect_lookup("3 alias (same idx, new tag)",   32'h0040_0050, 0, 0);
        write_entry(32'h0040_0050, 32'h0040_0080);
        expect_lookup("4 newer branch now hits",       32'h0040_0050, 1, 32'h0040_0080);
        expect_lookup("4 older branch evicted",        32'h0040_0010, 0, 0);
        write_entry(32'h0040_0024, 32'h0040_0010);
        expect_lookup("5 other index hits",            32'h0040_0024, 1, 32'h0040_0010);
        expect_lookup("5 first entry unaffected",      32'h0040_0050, 1, 32'h0040_0080);
        write_entry(32'h0040_0024, 32'h0040_0100);
        expect_lookup("6 target updated",              32'h0040_0024, 1, 32'h0040_0100);
        @(negedge clk); update_pc = 32'h0040_0030; update_target = 32'h1; update_en = 1'b0;
        @(negedge clk);
        expect_lookup("7 no write when update_en=0",   32'h0040_0030, 0, 0);
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        expect_lookup("8 reset clears entries",        32'h0040_0024, 0, 0);
        if (errors == 0) $display("PASS tb_btb");
        else             $display("FAIL tb_btb (%0d errors)", errors);
        $finish;
    end
endmodule
