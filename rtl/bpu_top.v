// bpu_top.v -- Complete Branch Prediction Unit as seen by a 5-stage pipeline.
// Owner: Mayank  |  Project 5: Dynamic Branch Prediction Unit
//
//   IF stage  : fetch_pc  ──► branch_predictor_top ──► pred_taken / pred_target
//   EX stage  : resolved branch ──► flush_ctrl ──► flush / correct_pc
//   PC select : next_pc = flush      ? correct_pc        (repair wrong path)
//                       : pred_target                    (BTB target or PC+4)
//
// The prediction made in IF travels down the pipeline with the branch and is
// presented again on the ex_pred_* inputs when the branch resolves in EX.
module bpu_top #(
    parameter PC_WIDTH           = 32,
    parameter BHT_INDEX_BITS     = 4,
    parameter BTB_INDEX_BITS     = 4,
    parameter CTR_WIDTH          = 2,
    parameter SCHEME             = 2,   // 0 = static NT, 1 = 1-bit, 2 = 2-bit
    parameter MISPREDICT_PENALTY = 2,
    parameter CNT_WIDTH          = 32
) (
    input  wire                 clk,
    input  wire                 rst,
    // ---- IF stage: prediction ----
    input  wire [PC_WIDTH-1:0]  fetch_pc,
    input  wire                 fetch_is_branch,
    output wire                 pred_taken,
    output wire [PC_WIDTH-1:0]  pred_target,
    output wire                 btb_hit,
    output wire [CTR_WIDTH-1:0] pred_state,
    // ---- EX stage: resolution ----
    input  wire                 ex_valid,          // a branch resolves this cycle
    input  wire [PC_WIDTH-1:0]  ex_pc,
    input  wire                 ex_pred_taken,     // prediction carried from IF
    input  wire [PC_WIDTH-1:0]  ex_pred_target,
    input  wire                 ex_actual_taken,
    input  wire [PC_WIDTH-1:0]  ex_actual_target,
    // ---- pipeline control ----
    output wire                 mispredict,
    output wire                 dir_mispredict,
    output wire                 tgt_mispredict,
    output wire                 flush,
    output wire [PC_WIDTH-1:0]  correct_pc,
    output wire [PC_WIDTH-1:0]  next_pc,
    // ---- performance counters ----
    output wire [CNT_WIDTH-1:0] branch_count,
    output wire [CNT_WIDTH-1:0] mispredict_count,
    output wire [CNT_WIDTH-1:0] penalty_cycles
);
    branch_predictor_top #(
        .PC_WIDTH(PC_WIDTH), .BHT_INDEX_BITS(BHT_INDEX_BITS),
        .BTB_INDEX_BITS(BTB_INDEX_BITS), .CTR_WIDTH(CTR_WIDTH), .SCHEME(SCHEME)
    ) u_predictor (
        .clk(clk), .rst(rst),
        .pc(fetch_pc), .is_branch(fetch_is_branch),
        .pred_taken(pred_taken), .pred_target(pred_target),
        .btb_hit(btb_hit), .pred_state(pred_state),
        .update_en(ex_valid), .update_pc(ex_pc),
        .actual_taken(ex_actual_taken), .actual_target(ex_actual_target));

    flush_ctrl #(
        .PC_WIDTH(PC_WIDTH), .CNT_WIDTH(CNT_WIDTH),
        .MISPREDICT_PENALTY(MISPREDICT_PENALTY)
    ) u_flush (
        .clk(clk), .rst(rst), .resolve_en(ex_valid), .branch_pc(ex_pc),
        .pred_taken(ex_pred_taken), .pred_target(ex_pred_target),
        .actual_taken(ex_actual_taken), .actual_target(ex_actual_target),
        .mispredict(mispredict), .dir_mispredict(dir_mispredict),
        .tgt_mispredict(tgt_mispredict), .flush(flush), .correct_pc(correct_pc),
        .branch_count(branch_count), .mispredict_count(mispredict_count),
        .penalty_cycles(penalty_cycles));

    // A misprediction in EX has priority over the new prediction in IF.
    assign next_pc = flush ? correct_pc : pred_target;
endmodule
