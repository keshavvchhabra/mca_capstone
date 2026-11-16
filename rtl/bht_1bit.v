`timescale 1ns / 1ps
// bht_1bit.v -- Branch History Table with one history bit per entry.
// Owner: Arun  |  Project 5: Dynamic Branch Prediction Unit
//   bit = 0 : predict NOT TAKEN      bit = 1 : predict TAKEN
//   Update rule: bit <= actual_taken (remember the last outcome).
// Index = pc[INDEX_BITS+1:2]; pc[1:0] is always 00 for word-aligned code.
module bht_1bit #(
    parameter PC_WIDTH   = 32,
    parameter INDEX_BITS = 4                    // entries = 2**INDEX_BITS
) (
    input  wire                  clk,
    input  wire                  rst,           // synchronous, active-high
    // predict port (combinational read)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [PC_WIDTH-1:0]   pc,
    input  wire [PC_WIDTH-1:0]   update_pc,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  pred_taken,
    output wire                  state_out,     // history bit at pc (debug/waveform)
    // update port (written at the clock edge)
    input  wire                  update_en,
    input  wire                  actual_taken
);
    localparam ENTRIES = 1 << INDEX_BITS;

    reg  [ENTRIES-1:0]    history;              // one bit per entry
    wire [INDEX_BITS-1:0] rd_idx = pc[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] wr_idx = update_pc[INDEX_BITS+1:2];

    assign state_out  = history[rd_idx];
    assign pred_taken = history[rd_idx];

    always @(posedge clk) begin
        if (rst)
            history <= {ENTRIES{1'b0}};         // reset: all entries NOT TAKEN
        else if (update_en)
            history[wr_idx] <= actual_taken;
    end
endmodule
