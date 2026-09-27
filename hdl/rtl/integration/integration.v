// =============================================================================
// integration — accumulation window (EMPTY SHELL for TB elaborate only)
//
// Real DUT is intentionally absent. Do not implement until tb_integration is
// human-reviewed (AGENTS.md HDL workflow).
//
// Port / Q-format contract: docs/fixed_point_notes.md § integration
//   in  : Q1.14 signed 16-bit (post-FIR/decim)
//   out : Q12.14 signed in 32-bit container
//   window: [INTEGRATE_START : INTEGRATE_START+INTEGRATE_LENGTH)
// =============================================================================

`timescale 1ns / 1ps

module integration #(
    parameter integer INTEGRATE_START  = 8,
    parameter integer INTEGRATE_LENGTH = 1016
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,       // Q1.14
    input  wire signed [15:0] in_q,       // Q1.14
    output wire               out_valid,  // one-cycle pulse when window done
    output wire signed [31:0] out_i,      // Q12.14
    output wire signed [31:0] out_q       // Q12.14
);

    // Empty shell: never completes → TB TIMEOUT / FAIL (expected pre-DUT).
    assign out_valid = 1'b0;
    assign out_i     = 32'sd0;
    assign out_q     = 32'sd0;

    // Silence unused-port warnings until real RTL lands.
    wire _unused = &{1'b0, clk, rst_n, in_valid, in_i, in_q,
                     INTEGRATE_START[0], INTEGRATE_LENGTH[0]};

endmodule
