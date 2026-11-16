`timescale 1ns / 1ps
// bp_update_logic.v -- Branch prediction UPDATE logic.
// Owner: Keshav  |  Project 5: Dynamic Branch Prediction Unit
// Decides which tables are written when a branch resolves in the EX stage:
//   * the BHT learns the direction of EVERY resolved branch
//     (the BHT module itself applies the 1-bit or 2-bit update rule)
//   * the BTB stores a target only for branches that were actually TAKEN
//     (a not-taken branch continues at PC+4, which needs no storage)
module bp_update_logic (
    input  wire update_en,       // a conditional branch resolves this cycle
    input  wire actual_taken,    // real direction from the ALU compare
    output wire bht_we,          // write enable for the Branch History Table
    output wire btb_we           // write enable for the Branch Target Buffer
);
    assign bht_we = update_en;
    assign btb_we = update_en & actual_taken;
endmodule
