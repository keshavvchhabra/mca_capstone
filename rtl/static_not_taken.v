// static_not_taken.v -- Baseline predictor: always predicts NOT TAKEN.
// Owner: Arun  |  Project 5: Dynamic Branch Prediction Unit
// It needs no state and no table, so the fetch stage simply continues
// with PC + 4. Every taken branch therefore becomes a misprediction.
module static_not_taken #(
    parameter PC_WIDTH = 32
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [PC_WIDTH-1:0] pc,          // unused: kept for a uniform interface
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                pred_taken
);
    assign pred_taken = 1'b0;
endmodule
