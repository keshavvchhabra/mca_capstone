`timescale 1ns / 1ps
// bp_select_logic.v -- Branch prediction SELECTION logic.
// Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit
// Combines the direction predictor (BHT) and the Branch Target Buffer into
// the final fetch decision:
//   pred_taken  = instruction is a branch AND the BHT says taken
//   pred_target = BTB target  if predicted taken AND the BTB hits
//               = PC + 4      otherwise (sequential fetch)
module bp_select_logic #(
    parameter PC_WIDTH = 32
) (
    input  wire [PC_WIDTH-1:0] pc,
    input  wire                is_branch,
    input  wire                dir_taken,    // from the selected BHT scheme
    input  wire                btb_hit,
    input  wire [PC_WIDTH-1:0] btb_target,
    output wire                pred_taken,
    output wire [PC_WIDTH-1:0] pred_target
);
    wire [PC_WIDTH-1:0] pc_plus4 = pc + 4;

    assign pred_taken  = is_branch & dir_taken;
    assign pred_target = (pred_taken & btb_hit) ? btb_target : pc_plus4;
endmodule
