// =============================================================================
// NOT THE FIR IMPLEMENTATION — empty black-box shell for TB elaboration only.
//
// Purpose: let `tb_fir` compile/elaborate under xsim so the testbench can fail
// for a meaningful reason (no `out_valid` / compare timeout) before real RTL
// exists. Replace this file with the real synthesizable FIR(+decim M) after
// human review of `hdl/tb/fir/tb_fir.sv`.
//
// Port contract: docs/fixed_point_notes.md § fir (Phase-3 sim ports).
// Coeff ROM for a future DUT: hdl/tb/fir/vectors/fir_coeffs.mem (Q1.14).
// =============================================================================

`timescale 1ns / 1ps

module fir #(
    parameter integer NUM_TAPS = 63,
    parameter integer DECIM_M  = 4
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,       // Q1.14 post-DDC baseband
    input  wire signed [15:0] in_q,       // Q1.14
    output wire               out_valid,  // asserted ~1/DECIM_M when live
    output wire signed [15:0] out_i,      // Q1.14 filtered + decimated
    output wire signed [15:0] out_q       // Q1.14
);

    // Intentionally non-functional: never produces filtered samples.
    // (Silence unused-input / unused-param warnings without implementing FIR.)
    wire _unused = in_valid | in_i[0] | in_q[0] | clk | ~rst_n
                 | (NUM_TAPS[0]) | (DECIM_M[0]);

    assign out_valid = 1'b0;
    assign out_i     = 16'sd0;
    assign out_q     = 16'sd0;

endmodule
