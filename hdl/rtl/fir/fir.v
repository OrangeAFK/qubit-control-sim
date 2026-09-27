// =============================================================================
// fir — FIR low-pass + decimation (M)
//
// Matches dsp_ref: centered convolution (numpy mode='same') then keep-every-M.
// For odd NUM_TAPS, group delay L = (NUM_TAPS-1)/2; causal MAC at sample index
// n equals same[n-L]. Emit when n >= L and (n-L) % DECIM_M == 0.
//
// After the input stream ends, continue with zero-valued samples (flush) so
// trailing same-mode taps that look past the last input match numpy padding.
//
// Q-format: docs/fixed_point_notes.md § fir
//   in/out/coeffs Q1.14; tap product Q2.28; MAC Q8.28-class; round/sat → Q1.14
// Coeff ROM: fir_coeffs.mem (copied next to xsim work dir by sim_fir.tcl)
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
    output reg                out_valid,  // one-cycle pulse per decimated sample
    output reg  signed [15:0] out_i,      // Q1.14 filtered + decimated
    output reg  signed [15:0] out_q       // Q1.14
);

    localparam integer L           = (NUM_TAPS - 1) / 2;
    localparam integer ACC_W       = 40;  // >= Q8.28 headroom for 63-tap MAC
    localparam integer IDX_W       = 16;  // sample index while streaming / flush

    // -------------------------------------------------------------------------
    // Coefficient ROM (Q1.14), loaded from fir_coeffs.mem
    // -------------------------------------------------------------------------
    reg signed [15:0] coeffs [0:NUM_TAPS-1];

    initial begin
        $readmemh("fir_coeffs.mem", coeffs);
    end

    // -------------------------------------------------------------------------
    // Delay lines (newest sample at index 0)
    // -------------------------------------------------------------------------
    reg signed [15:0] delay_i [0:NUM_TAPS-1];
    reg signed [15:0] delay_q [0:NUM_TAPS-1];

    reg               active;       // set on first in_valid; flush zeros after
    reg [IDX_W-1:0]   sample_idx;   // index of sample currently being absorbed

    // -------------------------------------------------------------------------
    // Combinational MAC on next delay-line state (new sample at tap 0)
    // -------------------------------------------------------------------------
    wire signed [15:0] new_i = in_valid ? in_i : 16'sd0;
    wire signed [15:0] new_q = in_valid ? in_q : 16'sd0;

    wire process = in_valid | active;

    integer k;
    reg signed [ACC_W-1:0] acc_i;
    reg signed [ACC_W-1:0] acc_q;
    reg signed [31:0]      prod_i;
    reg signed [31:0]      prod_q;
    reg signed [15:0]      tap_i;
    reg signed [15:0]      tap_q;

    always @(*) begin
        acc_i = {ACC_W{1'b0}};
        acc_q = {ACC_W{1'b0}};
        for (k = 0; k < NUM_TAPS; k = k + 1) begin
            if (k == 0) begin
                tap_i = new_i;
                tap_q = new_q;
            end else begin
                tap_i = delay_i[k-1];
                tap_q = delay_q[k-1];
            end
            prod_i = tap_i * coeffs[k];
            prod_q = tap_q * coeffs[k];
            acc_i  = acc_i + {{(ACC_W-32){prod_i[31]}}, prod_i};
            acc_q  = acc_q + {{(ACC_W-32){prod_q[31]}}, prod_q};
        end
    end

    // Round-nearest ( + 2^13 ) then arithmetic >> 14, saturate to Q1.14
    wire signed [ACC_W-1:0] round_i = acc_i + ({{(ACC_W-14){1'b0}}, 14'd8192});
    wire signed [ACC_W-1:0] round_q = acc_q + ({{(ACC_W-14){1'b0}}, 14'd8192});
    wire signed [ACC_W-1:0] shift_i = round_i >>> 14;
    wire signed [ACC_W-1:0] shift_q = round_q >>> 14;

    function automatic signed [15:0] sat16;
        input signed [ACC_W-1:0] x;
        begin
            if (x > ACC_W'(32767))
                sat16 = 16'sd32767;
            else if (x < -ACC_W'(32768))
                sat16 = -16'sd32768;
            else
                sat16 = x[15:0];
        end
    endfunction

    wire signed [15:0] fir_i = sat16(shift_i);
    wire signed [15:0] fir_q = sat16(shift_q);

    // Emit when causal index n maps to same[n-L] on a decimation phase
    wire emit = process
                && (sample_idx >= IDX_W'(L))
                && (((sample_idx - IDX_W'(L)) % DECIM_M) == 0);

    // -------------------------------------------------------------------------
    // Sequential: shift, sample index, optional decimated output pulse
    // -------------------------------------------------------------------------
    integer t;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            sample_idx <= {IDX_W{1'b0}};
            out_valid  <= 1'b0;
            out_i      <= 16'sd0;
            out_q      <= 16'sd0;
            for (t = 0; t < NUM_TAPS; t = t + 1) begin
                delay_i[t] <= 16'sd0;
                delay_q[t] <= 16'sd0;
            end
        end else begin
            out_valid <= 1'b0;

            if (in_valid)
                active <= 1'b1;

            if (process) begin
                // Shift delay line: tap0 <- new sample
                delay_i[0] <= new_i;
                delay_q[0] <= new_q;
                for (t = 1; t < NUM_TAPS; t = t + 1) begin
                    delay_i[t] <= delay_i[t-1];
                    delay_q[t] <= delay_q[t-1];
                end

                if (emit) begin
                    out_i     <= fir_i;
                    out_q     <= fir_q;
                    out_valid <= 1'b1;
                end

                sample_idx <= sample_idx + 1'b1;
            end
        end
    end

endmodule
