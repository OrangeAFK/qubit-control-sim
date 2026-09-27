// =============================================================================
// state_discrim — threshold compare on integrated Re(IQ)
//
// Rule (docs/fixed_point_notes.md § state_discrim):
//   decision = (in_i >= threshold)   // signed Q12.14
//   in_q is unused (I-axis threshold only; reserved for Phase 8 classifier)
//
// When in_valid is asserted, register the compare result and pulse out_valid
// for one cycle. Bit-exact vs fixture exp_decision vectors.
// =============================================================================

`timescale 1ns / 1ps

module state_discrim (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [31:0] in_i,       // Q12.14 integrated I
    input  wire signed [31:0] in_q,       // Q12.14 integrated Q (unused)
    input  wire signed [31:0] threshold,  // Q12.14
    output reg                out_valid,  // one-cycle pulse when decision ready
    output reg                decision    // 1-bit state
);

    // in_q: port kept for chain IQ symmetry; not used by Phase-3 I-threshold rule.

    wire ge_threshold = (in_i >= threshold);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            decision  <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid) begin
                decision  <= ge_threshold;
                out_valid <= 1'b1;
            end
        end
    end

endmodule
