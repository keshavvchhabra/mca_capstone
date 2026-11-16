`timescale 1ns / 1ps
// flush_ctrl.v -- Pipeline flush / control interface.
// Owner: Mayank  |  Project 5: Dynamic Branch Prediction Unit
// When a branch resolves (resolve_en), compare the prediction made at fetch
// with the real outcome. On a misprediction:
//   * flush      : squash the wrong-path instructions in IF/ID (and ID/EX)
//   * correct_pc : address to restart fetch from
// It also keeps performance counters for the CPI estimate.
module flush_ctrl #(
    parameter PC_WIDTH           = 32,
    parameter CNT_WIDTH          = 32,
    parameter MISPREDICT_PENALTY = 2      // cycles lost per misprediction
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 resolve_en,     // a branch resolves this cycle
    input  wire [PC_WIDTH-1:0]  branch_pc,
    input  wire                 pred_taken,
    input  wire [PC_WIDTH-1:0]  pred_target,
    input  wire                 actual_taken,
    input  wire [PC_WIDTH-1:0]  actual_target,
    output wire                 mispredict,
    output wire                 dir_mispredict, // wrong direction
    output wire                 tgt_mispredict, // right direction (T), wrong target
    output wire                 flush,
    output wire [PC_WIDTH-1:0]  correct_pc,
    output reg  [CNT_WIDTH-1:0] branch_count,
    output reg  [CNT_WIDTH-1:0] mispredict_count,
    output reg  [CNT_WIDTH-1:0] penalty_cycles
);
    assign dir_mispredict = (pred_taken != actual_taken);
    assign tgt_mispredict = pred_taken && actual_taken && (pred_target != actual_target);
    assign mispredict     = dir_mispredict || tgt_mispredict;

    assign flush      = resolve_en && mispredict;
    assign correct_pc = actual_taken ? actual_target : branch_pc + 4;

    always @(posedge clk) begin
        if (rst) begin
            branch_count     <= {CNT_WIDTH{1'b0}};
            mispredict_count <= {CNT_WIDTH{1'b0}};
            penalty_cycles   <= {CNT_WIDTH{1'b0}};
        end else if (resolve_en) begin
            branch_count <= branch_count + 1'b1;
            if (mispredict) begin
                mispredict_count <= mispredict_count + 1'b1;
                penalty_cycles   <= penalty_cycles + MISPREDICT_PENALTY;
            end
        end
    end
endmodule
