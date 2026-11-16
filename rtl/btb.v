// btb.v -- Branch Target Buffer (direct-mapped).
// Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit
// Each entry stores {valid, tag, target}. Lookup is combinational:
//   hit = valid[idx] && (tag[idx] == pc tag bits)
// An entry is written only when a branch is resolved TAKEN.
//   PC fields:  | tag : PC_WIDTH-1 .. INDEX_BITS+2 | index : INDEX_BITS+1 .. 2 | 00 |
module btb #(
    parameter PC_WIDTH   = 32,
    parameter INDEX_BITS = 4                    // entries = 2**INDEX_BITS
) (
    input  wire                 clk,
    input  wire                 rst,            // clears valid bits only
    // lookup port
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [PC_WIDTH-1:0]  pc,
    input  wire [PC_WIDTH-1:0]  update_pc,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                 hit,
    output wire [PC_WIDTH-1:0]  target,
    // update port
    input  wire                 update_en,      // = resolved branch AND taken
    input  wire [PC_WIDTH-1:0]  update_target
);
    localparam ENTRIES  = 1 << INDEX_BITS;
    localparam TAG_BITS = PC_WIDTH - INDEX_BITS - 2;

    reg [ENTRIES-1:0]  valid;
    reg [TAG_BITS-1:0] tag_mem    [0:ENTRIES-1];
    reg [PC_WIDTH-1:0] target_mem [0:ENTRIES-1];

    wire [INDEX_BITS-1:0] rd_idx = pc[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   rd_tag = pc[PC_WIDTH-1:INDEX_BITS+2];
    wire [INDEX_BITS-1:0] wr_idx = update_pc[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   wr_tag = update_pc[PC_WIDTH-1:INDEX_BITS+2];

    assign hit    = valid[rd_idx] && (tag_mem[rd_idx] == rd_tag);
    assign target = target_mem[rd_idx];

    // Valid bits need a reset; tag/target storage does not (RAM-friendly).
    always @(posedge clk) begin
        if (rst)
            valid <= {ENTRIES{1'b0}};
        else if (update_en)
            valid[wr_idx] <= 1'b1;
    end

    always @(posedge clk) begin
        if (update_en) begin
            tag_mem[wr_idx]    <= wr_tag;
            target_mem[wr_idx] <= update_target;
        end
    end
endmodule
