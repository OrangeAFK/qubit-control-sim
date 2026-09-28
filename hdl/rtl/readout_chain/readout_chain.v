// =============================================================================
// readout_chain — structural top: ddc → fir(+decim) → integration → state_discrim
//
// Port / Q-format contract (docs/fixed_point_notes.md § readout_chain):
//   in_i / in_q   : signed Q1.14 IF IQ (sim AXI-Stream style)
//   phase_inc/0   : NCO words (same as ddc)
//   threshold     : signed Q12.14 (same as state_discrim)
//   out_i / out_q : signed Q12.14 integrated IQ (held from integration)
//   decision      : 1-bit state (from state_discrim)
//   out_valid     : one-cycle pulse when IQ + decision are ready
//                   (aligned to state_discrim; IQ held from prior integration pulse)
//
// After the last IF sample, hold in_valid=0 so FIR flush (zero-pad) can finish
// and integration can collect the full post-decim window.
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
    output wire               out_valid,   // pulse: IQ + decision ready
    output wire signed [31:0] out_i,       // Q12.14 integrated I
    output wire signed [31:0] out_q,       // Q12.14 integrated Q
    output wire               decision     // 1-bit state
);

    // -------------------------------------------------------------------------
    // Stage 1: DDC (NCO mixer) — Q1.14 IF → Q1.14 baseband
    // -------------------------------------------------------------------------
    wire               ddc_valid;
    wire signed [15:0] ddc_i;
    wire signed [15:0] ddc_q;

    ddc u_ddc (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_i      (in_i),
        .in_q      (in_q),
        .phase_inc (phase_inc),
        .phase0    (phase0),
        .out_valid (ddc_valid),
        .out_i     (ddc_i),
        .out_q     (ddc_q)
    );

    // -------------------------------------------------------------------------
    // Stage 2: FIR LPF + decimation — Q1.14 → Q1.14 @ fs/M
    // When ddc_valid drops after the last IF sample, fir continues flushing
    // with zero samples (active sticky) so trailing same-mode taps match.
    // -------------------------------------------------------------------------
    wire               fir_valid;
    wire signed [15:0] fir_i;
    wire signed [15:0] fir_q;

    fir #(
        .NUM_TAPS (NUM_TAPS),
        .DECIM_M  (DECIM_M)
    ) u_fir (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (ddc_valid),
        .in_i      (ddc_i),
        .in_q      (ddc_q),
        .out_valid (fir_valid),
        .out_i     (fir_i),
        .out_q     (fir_q)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Integration window — Q1.14 → Q12.14
    // -------------------------------------------------------------------------
    wire               int_valid;
    wire signed [31:0] int_i;
    wire signed [31:0] int_q;

    integration #(
        .INTEGRATE_START  (INTEGRATE_START),
        .INTEGRATE_LENGTH (INTEGRATE_LENGTH)
    ) u_integration (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (fir_valid),
        .in_i      (fir_i),
        .in_q      (fir_q),
        .out_valid (int_valid),
        .out_i     (int_i),
        .out_q     (int_q)
    );

    // -------------------------------------------------------------------------
    // Stage 4: State discrimination — Q12.14 I vs threshold → 1-bit
    // -------------------------------------------------------------------------
    wire sd_valid;
    wire sd_decision;

    state_discrim u_state_discrim (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (int_valid),
        .in_i      (int_i),
        .in_q      (int_q),
        .threshold (threshold),
        .out_valid (sd_valid),
        .decision  (sd_decision)
    );

    // Chain outputs: IQ held by integration after its window pulse; decision /
    // out_valid aligned to state_discrim (one cycle after integration).
    assign out_i     = int_i;
    assign out_q     = int_q;
    assign out_valid = sd_valid;
    assign decision  = sd_decision;

endmodule
