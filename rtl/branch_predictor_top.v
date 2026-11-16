// branch_predictor_top.v -- Dynamic Branch Prediction Unit (top level).
// Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit
//   SCHEME = 0 : static always-not-taken baseline
//   SCHEME = 1 : 1-bit BHT  + BTB
//   SCHEME = 2 : 2-bit BHT  + BTB
// Predict side (IF stage): pc, is_branch -> pred_taken, pred_target, btb_hit
// Update side (EX stage) : update_en, update_pc, actual_taken, actual_target
module branch_predictor_top #(
    parameter PC_WIDTH       = 32,
    parameter BHT_INDEX_BITS = 4,       // BHT entries = 2**BHT_INDEX_BITS
    parameter BTB_INDEX_BITS = 4,       // BTB entries = 2**BTB_INDEX_BITS
    parameter CTR_WIDTH      = 2,       // used by SCHEME 2
    parameter SCHEME         = 2
) (
    input  wire                 clk,
    input  wire                 rst,
    // ---- predict interface ----
    input  wire [PC_WIDTH-1:0]  pc,
    input  wire                 is_branch,
    output wire                 pred_taken,
    output wire [PC_WIDTH-1:0]  pred_target,
    output wire                 btb_hit,
    output wire [CTR_WIDTH-1:0] pred_state,   // predictor state at pc (waveform)
    // ---- update interface ----
    input  wire                 update_en,
    input  wire [PC_WIDTH-1:0]  update_pc,
    input  wire                 actual_taken,
    input  wire [PC_WIDTH-1:0]  actual_target
);
    wire                dir_taken;            // raw direction prediction
    wire [PC_WIDTH-1:0] btb_target;
    wire                bht_we, btb_we;

    // ---------------- update logic: which tables learn this branch ----------
    bp_update_logic u_update (
        .update_en(update_en), .actual_taken(actual_taken),
        .bht_we(bht_we), .btb_we(btb_we));

    // ---------------- direction predictor (selected at elaboration) ----------
    generate
        if (SCHEME == 0) begin : g_static
            static_not_taken #(.PC_WIDTH(PC_WIDTH)) u_dir (
                .pc(pc), .pred_taken(dir_taken));
            assign pred_state = {CTR_WIDTH{1'b0}};
        end else if (SCHEME == 1) begin : g_1bit
            wire state_bit;
            bht_1bit #(.PC_WIDTH(PC_WIDTH), .INDEX_BITS(BHT_INDEX_BITS)) u_dir (
                .clk(clk), .rst(rst), .pc(pc), .update_pc(update_pc),
                .pred_taken(dir_taken), .state_out(state_bit),
                .update_en(bht_we), .actual_taken(actual_taken));
            assign pred_state = {{(CTR_WIDTH-1){1'b0}}, state_bit};
        end else begin : g_2bit
            bht_2bit #(.PC_WIDTH(PC_WIDTH), .INDEX_BITS(BHT_INDEX_BITS),
                       .CTR_WIDTH(CTR_WIDTH)) u_dir (
                .clk(clk), .rst(rst), .pc(pc), .update_pc(update_pc),
                .pred_taken(dir_taken), .state_out(pred_state),
                .update_en(bht_we), .actual_taken(actual_taken));
        end
    endgenerate

    // ---------------- branch target buffer -----------------------------------
    btb #(.PC_WIDTH(PC_WIDTH), .INDEX_BITS(BTB_INDEX_BITS)) u_btb (
        .clk(clk), .rst(rst), .pc(pc), .update_pc(update_pc),
        .hit(btb_hit), .target(btb_target),
        .update_en(btb_we),                         // store taken branches only
        .update_target(actual_target));

    // ---------------- selection logic: final fetch decision -----------------
    // Direction comes from the BHT. The next fetch address is the BTB target
    // only when we predict taken AND the BTB knows the target; otherwise PC+4.
    bp_select_logic #(.PC_WIDTH(PC_WIDTH)) u_select (
        .pc(pc), .is_branch(is_branch), .dir_taken(dir_taken),
        .btb_hit(btb_hit), .btb_target(btb_target),
        .pred_taken(pred_taken), .pred_target(pred_target));
endmodule
