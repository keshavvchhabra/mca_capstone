// bht_2bit.v -- Branch History Table of saturating counters (default 2-bit).
// Owner: Arun  |  Project 5: Dynamic Branch Prediction Unit
//   00 Strongly NT | 01 Weakly NT | 10 Weakly T | 11 Strongly T
//   Prediction  : TAKEN when the counter MSB is 1.
//   Update rule : taken -> increment (saturate at 11)
//                 not taken -> decrement (saturate at 00)
//   Reset state : Weakly NOT TAKEN (01).
module bht_2bit #(
    parameter PC_WIDTH   = 32,
    parameter INDEX_BITS = 4,                   // entries = 2**INDEX_BITS
    parameter CTR_WIDTH  = 2                    // counter width (2 = classic)
) (
    input  wire                  clk,
    input  wire                  rst,           // synchronous, active-high
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [PC_WIDTH-1:0]   pc,
    input  wire [PC_WIDTH-1:0]   update_pc,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  pred_taken,
    output wire [CTR_WIDTH-1:0]  state_out,     // counter at pc (debug/waveform)
    input  wire                  update_en,
    input  wire                  actual_taken
);
    localparam ENTRIES = 1 << INDEX_BITS;
    localparam [CTR_WIDTH-1:0] CTR_MAX = {CTR_WIDTH{1'b1}};            // 11
    localparam [CTR_WIDTH-1:0] CTR_MIN = {CTR_WIDTH{1'b0}};            // 00
    localparam [CTR_WIDTH-1:0] WEAK_NT = {1'b0, {(CTR_WIDTH-1){1'b1}}}; // 01

    reg  [CTR_WIDTH-1:0]  counter [0:ENTRIES-1];
    wire [INDEX_BITS-1:0] rd_idx = pc[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] wr_idx = update_pc[INDEX_BITS+1:2];

    assign state_out  = counter[rd_idx];
    assign pred_taken = state_out[CTR_WIDTH-1];

    // Next-state function of one saturating counter (the FSM of the report).
    function [CTR_WIDTH-1:0] next_state;
        input [CTR_WIDTH-1:0] cur;
        input                 taken;
        begin
            if (taken)
                next_state = (cur == CTR_MAX) ? CTR_MAX : cur + 1'b1;
            else
                next_state = (cur == CTR_MIN) ? CTR_MIN : cur - 1'b1;
        end
    endfunction

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                counter[i] <= WEAK_NT;
        end else if (update_en) begin
            counter[wr_idx] <= next_state(counter[wr_idx], actual_taken);
        end
    end
endmodule
