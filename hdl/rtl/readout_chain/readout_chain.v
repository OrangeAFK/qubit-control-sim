// =============================================================================
// readout_chain — empty shell for TB elaborate only (NO structural wiring yet).
//
// Intended contract (docs/fixed_point_notes.md § readout_chain):
//   in_i / in_q   : signed Q1.14 IF IQ (sim AXI-Stream style)
//   phase_inc/0   : NCO words (same as ddc)
//   threshold     : signed Q12.14 (same as state_discrim)
//   out_i / out_q : signed Q12.14 integrated IQ
//   decision      : 1-bit state (bit-exact vs fixture)
//   out_valid     : one-cycle pulse when integrated IQ + decision are ready
//
// Future DUT (after TB review): structural
//   ddc → fir(+decim) → integration → state_discrim
// with parameters NUM_TAPS / DECIM_M / INTEGRATE_* matching Phase 2 fixtures.
//
// This shell never asserts out_valid so tb_readout_chain times out FAIL
// until real chain wiring replaces it after TB review.
// =============================================================================

`timescale 1ns / 1ps

module readout_chain #(
    parameter integer NUM_TAPS          = 63,
    parameter integer DECIM_M           = 4,
    parameter integer INTEGRATE_START   = 8,
    parameter integer INTEGRATE_LENGTH  = 1016
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,        // Q1.14 IF I
    input  wire signed [15:0] in_q,        // Q1.14 IF Q
    input  wire        [31:0] phase_inc,   // f_lo/fs * 2^32
    input  wire        [31:0] phase0,      // phase0_rad/(2π) * 2^32
    input  wire signed [31:0] threshold,   // Q12.14
    output reg                out_valid,   // pulse: IQ + decision ready
    output reg  signed [31:0] out_i,       // Q12.14 integrated I
    output reg  signed [31:0] out_q,       // Q12.14 integrated Q
    output reg                decision     // 1-bit state
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_i     <= 32'sd0;
            out_q     <= 32'sd0;
            decision  <= 1'b0;
        end else begin
            // Empty shell: never complete a chain result.
            // (ports / parameters intentionally unused until structural DUT)
            out_valid <= 1'b0;
            out_i     <= 32'sd0;
            out_q     <= 32'sd0;
            decision  <= 1'b0;
        end
    end

    // Silence unused-port / unused-parameter warnings until real wiring lands.
    wire _unused = &{1'b0, in_valid, in_i[0], in_q[0], phase_inc[0], phase0[0],
                     threshold[0], NUM_TAPS[0], DECIM_M[0],
                     INTEGRATE_START[0], INTEGRATE_LENGTH[0]};

endmodule
