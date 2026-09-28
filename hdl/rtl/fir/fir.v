// =============================================================================
// fir — FIR low-pass + decimation (M), multi-cycle MAC (snapshot + engines)
//
// Matches dsp_ref: centered convolution (numpy mode='same') then keep-every-M.
// For odd NUM_TAPS, group delay L = (NUM_TAPS-1)/2; causal MAC at sample index
// n equals same[n-L]. Emit when n >= L and (n-L) % DECIM_M == 0.
//
// After the input stream ends, continue with zero-valued samples (flush) so
// trailing same-mode taps that look past the last input match numpy padding.
//
// Timing (xc7z007s @ 100 MHz):
//   - Shift delay line every sample (always accept).
//   - On emit: snapshot tap vector into a free engine; accumulate
//     TAPS_PER_CYCLE products/cycle (default 2 — shallow DSP/adder path).
//   - NUM_ENGINES = ceil(MAC_CYCLES / DECIM_M) keeps up with emit rate M.
//   - Round/sat is a registered cycle after the final accumulate.
//
// Q-format: docs/fixed_point_notes.md § fir
// Coeff ROM: fir_coeffs.mem (copied next to xsim work dir by sim_fir.tcl)
// =============================================================================

`timescale 1ns / 1ps

module fir #(
    parameter integer NUM_TAPS       = 63,
    parameter integer DECIM_M        = 4,
    parameter integer TAPS_PER_CYCLE = 2
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,
    input  wire signed [15:0] in_q,
    output reg                out_valid,
    output reg  signed [15:0] out_i,
    output reg  signed [15:0] out_q
);

    localparam integer L           = (NUM_TAPS - 1) / 2;
    localparam integer ACC_W       = 40;
    localparam integer IDX_W       = 16;
    localparam integer MAC_CYCLES  = (NUM_TAPS + TAPS_PER_CYCLE - 1) / TAPS_PER_CYCLE;
    localparam integer NUM_ENGINES = (MAC_CYCLES + DECIM_M - 1) / DECIM_M;
    localparam integer PHASE_W     = 6;
    localparam integer ENG_W       = 4;

    reg signed [15:0] coeffs [0:NUM_TAPS-1];

    initial begin
        $readmemh("fir_coeffs.mem", coeffs);
    end

    reg signed [15:0] delay_i [0:NUM_TAPS-1];
    reg signed [15:0] delay_q [0:NUM_TAPS-1];
    reg               active;
    reg [IDX_W-1:0]   sample_idx;

    wire signed [15:0] new_i = in_valid ? in_i : 16'sd0;
    wire signed [15:0] new_q = in_valid ? in_q : 16'sd0;
    wire process = in_valid | active;

    wire emit = process
                && (sample_idx >= IDX_W'(L))
                && (((sample_idx - IDX_W'(L)) % DECIM_M) == 0);

    reg               eng_busy  [0:NUM_ENGINES-1];
    reg [PHASE_W-1:0] eng_phase [0:NUM_ENGINES-1];
    reg signed [ACC_W-1:0] eng_acc_i [0:NUM_ENGINES-1];
    reg signed [ACC_W-1:0] eng_acc_q [0:NUM_ENGINES-1];
    reg signed [15:0] eng_snap_i [0:NUM_ENGINES-1][0:NUM_TAPS-1];
    reg signed [15:0] eng_snap_q [0:NUM_ENGINES-1][0:NUM_TAPS-1];

    reg [ENG_W-1:0] next_eng;

    reg               sat_pending;
    reg signed [ACC_W-1:0] sat_acc_i;
    reg signed [ACC_W-1:0] sat_acc_q;

    reg signed [ACC_W-1:0] partial_i [0:NUM_ENGINES-1];
    reg signed [ACC_W-1:0] partial_q [0:NUM_ENGINES-1];
    reg signed [31:0]      prod_i;
    reg signed [31:0]      prod_q;
    integer e, k, tap;

    always @(*) begin
        for (e = 0; e < NUM_ENGINES; e = e + 1) begin
            partial_i[e] = {ACC_W{1'b0}};
            partial_q[e] = {ACC_W{1'b0}};
            for (k = 0; k < TAPS_PER_CYCLE; k = k + 1) begin
                tap = eng_phase[e] * TAPS_PER_CYCLE + k;
                if (tap < NUM_TAPS) begin
                    prod_i = eng_snap_i[e][tap] * coeffs[tap];
                    prod_q = eng_snap_q[e][tap] * coeffs[tap];
                    partial_i[e] = partial_i[e]
                                   + {{(ACC_W-32){prod_i[31]}}, prod_i};
                    partial_q[e] = partial_q[e]
                                   + {{(ACC_W-32){prod_q[31]}}, prod_q};
                end
            end
        end
    end

    function automatic signed [15:0] sat16;
        input signed [ACC_W-1:0] x;
        reg signed [ACC_W-1:0] rounded;
        reg signed [ACC_W-1:0] shifted;
        begin
            rounded = x + ({{(ACC_W-14){1'b0}}, 14'd8192});
            shifted = rounded >>> 14;
            if (shifted > ACC_W'(32767))
                sat16 = 16'sd32767;
            else if (shifted < -ACC_W'(32768))
                sat16 = -16'sd32768;
            else
                sat16 = shifted[15:0];
        end
    endfunction

    integer t;
    reg                    finishing [0:NUM_ENGINES-1];
    reg                    do_start;
    reg [ENG_W-1:0]        start_eng;
    reg                    mac_out_taken;
    reg signed [ACC_W-1:0] sum_i;
    reg signed [ACC_W-1:0] sum_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            active      <= 1'b0;
            sample_idx  <= {IDX_W{1'b0}};
            next_eng    <= {ENG_W{1'b0}};
            out_valid   <= 1'b0;
            out_i       <= 16'sd0;
            out_q       <= 16'sd0;
            sat_pending <= 1'b0;
            sat_acc_i   <= {ACC_W{1'b0}};
            sat_acc_q   <= {ACC_W{1'b0}};
            for (t = 0; t < NUM_TAPS; t = t + 1) begin
                delay_i[t] <= 16'sd0;
                delay_q[t] <= 16'sd0;
            end
            for (e = 0; e < NUM_ENGINES; e = e + 1) begin
                eng_busy[e]  <= 1'b0;
                eng_phase[e] <= {PHASE_W{1'b0}};
                eng_acc_i[e] <= {ACC_W{1'b0}};
                eng_acc_q[e] <= {ACC_W{1'b0}};
                for (t = 0; t < NUM_TAPS; t = t + 1) begin
                    eng_snap_i[e][t] <= 16'sd0;
                    eng_snap_q[e][t] <= 16'sd0;
                end
            end
        end else begin
            out_valid     <= 1'b0;
            mac_out_taken = 1'b0;
            do_start      = process && emit;
            start_eng     = next_eng;

            if (in_valid)
                active <= 1'b1;

            for (e = 0; e < NUM_ENGINES; e = e + 1)
                finishing[e] = eng_busy[e]
                               && (eng_phase[e] == PHASE_W'(MAC_CYCLES - 1));

            for (e = 0; e < NUM_ENGINES; e = e + 1) begin
                if (eng_busy[e]) begin
                    sum_i = eng_acc_i[e] + partial_i[e];
                    sum_q = eng_acc_q[e] + partial_q[e];
                    if (finishing[e]) begin
                        eng_busy[e]  <= 1'b0;
                        eng_phase[e] <= {PHASE_W{1'b0}};
                        eng_acc_i[e] <= {ACC_W{1'b0}};
                        eng_acc_q[e] <= {ACC_W{1'b0}};
                        if (!mac_out_taken && !sat_pending) begin
                            sat_acc_i     <= sum_i;
                            sat_acc_q     <= sum_q;
                            sat_pending   <= 1'b1;
                            mac_out_taken = 1'b1;
                        end
                    end else begin
                        eng_acc_i[e] <= sum_i;
                        eng_acc_q[e] <= sum_q;
                        eng_phase[e] <= eng_phase[e] + 1'b1;
                    end
                end
            end

            if (sat_pending) begin
                out_i       <= sat16(sat_acc_i);
                out_q       <= sat16(sat_acc_q);
                out_valid   <= 1'b1;
                sat_pending <= 1'b0;
            end

            if (do_start) begin
                if (eng_busy[start_eng] && !finishing[start_eng]) begin
                    if (start_eng == ENG_W'(NUM_ENGINES - 1))
                        start_eng = {ENG_W{1'b0}};
                    else
                        start_eng = start_eng + 1'b1;
                end

                eng_snap_i[start_eng][0] <= new_i;
                eng_snap_q[start_eng][0] <= new_q;
                for (t = 1; t < NUM_TAPS; t = t + 1) begin
                    eng_snap_i[start_eng][t] <= delay_i[t-1];
                    eng_snap_q[start_eng][t] <= delay_q[t-1];
                end
                eng_busy[start_eng]  <= 1'b1;
                eng_phase[start_eng] <= {PHASE_W{1'b0}};
                eng_acc_i[start_eng] <= {ACC_W{1'b0}};
                eng_acc_q[start_eng] <= {ACC_W{1'b0}};
                if (start_eng == ENG_W'(NUM_ENGINES - 1))
                    next_eng <= {ENG_W{1'b0}};
                else
                    next_eng <= start_eng + 1'b1;
            end

            if (process) begin
                delay_i[0] <= new_i;
                delay_q[0] <= new_q;
                for (t = 1; t < NUM_TAPS; t = t + 1) begin
                    delay_i[t] <= delay_i[t-1];
                    delay_q[t] <= delay_q[t-1];
                end
                sample_idx <= sample_idx + 1'b1;
            end
        end
    end

endmodule
