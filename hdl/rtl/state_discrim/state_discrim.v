// =============================================================================
// state_discrim — empty shell for TB elaborate only (NO real RTL yet).
//
// Intended contract (docs/fixed_point_notes.md § state_discrim):
//   in_i / threshold : signed Q12.14 (32-bit containers)
//   decision         : 1-bit  (Re(iq) >= threshold → 1 else 0)
//   out_valid        : one-cycle pulse when a decision is presented
//
// This shell never asserts out_valid so tb_state_discrim times out FAIL
// until real discrimination logic replaces it after TB review.
// =============================================================================

`timescale 1ns / 1ps

module state_discrim (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [31:0] in_i,       // Q12.14 integrated I
    input  wire signed [31:0] in_q,       // Q12.14 integrated Q (unused by rule)
    input  wire signed [31:0] threshold,  // Q12.14
    output reg                out_valid,
    output reg                decision    // 1-bit state
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            decision  <= 1'b0;
        end else begin
            // Empty shell: never complete a decision.
            // (in_valid / in_i / in_q / threshold intentionally unused)
            out_valid <= 1'b0;
            decision  <= 1'b0;
        end
    end

endmodule
