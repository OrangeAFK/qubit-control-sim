// =============================================================================
// ddc — digital downconversion (NCO mixer)
//
// y[n] = x[n] * exp(-j * θ[n]),  θ[n] = phase0 + n * phase_inc
//   (phase words: full circle = 2^32, matching docs/fixed_point_notes.md § ddc)
//
// NCO: 32-bit phase accumulator + quarter-wave Q1.14 sine LUT (1024+1) with
// 8-bit linear interpolation; complex multiply in Q2.28 then round-nearest /
// saturate back to Q1.14.
//
// Pipeline: 1 cycle after phase0 load. First in_valid sample emerges on the
// next clock with out_valid=1. TB allows arbitrary DUT latency before first
// out_valid.
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
    output reg                out_valid,
    output reg  signed [15:0] out_i,      // Q1.14
    output reg  signed [15:0] out_q       // Q1.14
);

    // -------------------------------------------------------------------------
    // Quarter-wave sine LUT: S[i] = round(sin(i*π/(2*1024)) * 2^14), i=0..1024
    // -------------------------------------------------------------------------
    localparam integer LUT_N = 1024;

    reg signed [15:0] sin_lut [0:LUT_N];

    initial begin
`include "sin_q14.vh"
    end

    // -------------------------------------------------------------------------
    // Phase accumulator + one-shot phase0 load after reset
    // -------------------------------------------------------------------------
    reg        [31:0] phase;
    reg               phase_loaded;

    // -------------------------------------------------------------------------
    // NCO: phase → cos/sin (Q1.14) via LUT + linear interpolation
    // -------------------------------------------------------------------------
    wire [1:0] quad = phase[31:30];
    wire [9:0] addr = phase[29:20];
    wire [7:0] frac = phase[19:12];

    wire signed [15:0] s0 = sin_lut[addr];
    wire signed [15:0] s1 = sin_lut[{addr + 10'd1}];
    // cos(θ) = sin(π/2 − θ)
    wire signed [15:0] c0 = sin_lut[LUT_N - addr];
    wire signed [15:0] c1 = sin_lut[LUT_N - 1 - addr];

    wire [8:0] frac_comp = 9'd256 - {1'b0, frac};

    // signed 16 × unsigned 0..256 → keep product wide, then >> 8
    wire signed [25:0] sin_interp_num =
        ($signed(s0) * $signed({1'b0, frac_comp})) +
        ($signed(s1) * $signed({1'b0, frac}));
    wire signed [25:0] cos_interp_num =
        ($signed(c0) * $signed({1'b0, frac_comp})) +
        ($signed(c1) * $signed({1'b0, frac}));

    wire signed [15:0] sin_q = sin_interp_num[23:8];
    wire signed [15:0] cos_q = cos_interp_num[23:8];

    reg signed [15:0] cos_nco;
    reg signed [15:0] sin_nco;

    always @(*) begin
        case (quad)
            2'd0: begin
                cos_nco = cos_q;
                sin_nco = sin_q;
            end
            2'd1: begin
                cos_nco = -sin_q;
                sin_nco = cos_q;
            end
            2'd2: begin
                cos_nco = -cos_q;
                sin_nco = -sin_q;
            end
            default: begin
                cos_nco = sin_q;
                sin_nco = -cos_q;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Complex multiply: (I + jQ) * (cos − j sin)
    //   out_i = I*cos + Q*sin
    //   out_q = Q*cos − I*sin
    // Products are Q2.28; sum in 33-bit Q3.28; round/sat → Q1.14
    // -------------------------------------------------------------------------
    wire signed [31:0] p_ii = in_i * cos_nco;
    wire signed [31:0] p_qs = in_q * sin_nco;
    wire signed [31:0] p_qi = in_q * cos_nco;
    wire signed [31:0] p_is = in_i * sin_nco;

    wire signed [32:0] acc_i = {p_ii[31], p_ii} + {p_qs[31], p_qs};
    wire signed [32:0] acc_q = {p_qi[31], p_qi} - {p_is[31], p_is};

    wire signed [32:0] round_i = acc_i + 33'sd8192;
    wire signed [32:0] round_q = acc_q + 33'sd8192;
    wire signed [32:0] shift_i = round_i >>> 14;
    wire signed [32:0] shift_q = round_q >>> 14;

    function automatic signed [15:0] sat16;
        input signed [32:0] x;
        begin
            if (x > 33'sd32767)
                sat16 = 16'sd32767;
            else if (x < -33'sd32768)
                sat16 = -16'sd32768;
            else
                sat16 = x[15:0];
        end
    endfunction

    wire signed [15:0] mix_i = sat16(shift_i);
    wire signed [15:0] mix_q = sat16(shift_q);

    // -------------------------------------------------------------------------
    // Sequential: load phase0 once after reset, then mix on in_valid
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase        <= 32'd0;
            phase_loaded <= 1'b0;
            out_valid    <= 1'b0;
            out_i        <= 16'sd0;
            out_q        <= 16'sd0;
        end else if (!phase_loaded) begin
            phase        <= phase0;
            phase_loaded <= 1'b1;
            out_valid    <= 1'b0;
        end else if (in_valid) begin
            out_i     <= mix_i;
            out_q     <= mix_q;
            out_valid <= 1'b1;
            phase     <= phase + phase_inc;
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule
