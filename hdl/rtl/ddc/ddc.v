// =============================================================================
// NOT THE DDC IMPLEMENTATION — empty black-box shell for TB elaboration only.
//
// Purpose: let `tb_ddc` compile/elaborate under xsim so the testbench can fail
// for a meaningful reason (no `out_valid` / compare timeout) before real RTL
// exists. Replace this file with the real synthesizable DDC after human review
// of `hdl/tb/ddc/tb_ddc.sv`.
//
// Port contract: docs/fixed_point_notes.md § ddc (Phase-3 sim ports).
// =============================================================================

`timescale 1ns / 1ps

module ddc (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,       // Q1.14
    input  wire signed [15:0] in_q,       // Q1.14
    input  wire        [31:0] phase_inc,  // f_lo/fs * 2^32
    input  wire        [31:0] phase0,     // phase0_rad/(2π) * 2^32
    output wire               out_valid,
    output wire signed [15:0] out_i,      // Q1.14
    output wire signed [15:0] out_q       // Q1.14
);

    // Intentionally non-functional: never produces baseband samples.
    // (Silence unused-input warnings without implementing mixer/NCO.)
    wire _unused = in_valid | in_i[0] | in_q[0] | phase_inc[0] | phase0[0] | clk | ~rst_n;

    assign out_valid = 1'b0;
    assign out_i     = 16'sd0;
    assign out_q     = 16'sd0;

endmodule
