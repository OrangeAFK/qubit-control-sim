// =============================================================================
// ddc — digital downconversion (NCO mixer)
//
// y[n] = x[n] * exp(-j * θ[n]),  θ[n] = phase0 + n * phase_inc
//
// Pipeline: after phase0 load, each in_valid sample takes 4 clocks —
//   stage 0: capture addr/frac/quad + IQ; advance phase
//   stage 1: LUT read → register s0/s1/c0/c1 (+ frac/quad/IQ forward)
//   stage 2: linear interp + quadrant → cos/sin
//   stage 3: complex multiply, round/sat → out_*
// TB allows arbitrary DUT latency before first out_valid.
// =============================================================================

`timescale 1ns / 1ps

module ddc (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,
    input  wire signed [15:0] in_q,
    input  wire        [31:0] phase_inc,
    input  wire        [31:0] phase0,
    output reg                out_valid,
    output reg  signed [15:0] out_i,
    output reg  signed [15:0] out_q
);

    localparam integer LUT_N = 1024;

    reg signed [15:0] sin_lut [0:LUT_N];

    initial begin
`include "sin_q14.vh"
    end

    reg        [31:0] phase;
    reg               phase_loaded;

    // Stage 0
    reg [1:0]         quad_s0;
    reg [9:0]         addr_s0;
    reg [7:0]         frac_s0;
    reg signed [15:0] iq_i_s0;
    reg signed [15:0] iq_q_s0;
    reg               stage1_valid;

    // Stage 1: registered LUT samples
    reg signed [15:0] s0_r, s1_r, c0_r, c1_r;
    reg [1:0]         quad_s1;
    reg [7:0]         frac_s1;
    reg signed [15:0] iq_i_s1;
    reg signed [15:0] iq_q_s1;
    reg               stage2_valid;

    // Stage 2: NCO cos/sin
    reg signed [15:0] cos_nco;
    reg signed [15:0] sin_nco;
    reg signed [15:0] iq_i_s2;
    reg signed [15:0] iq_q_s2;
    reg               stage3_valid;

    // Combinational LUT from stage-0 addr
    wire signed [15:0] s0_c = sin_lut[addr_s0];
    wire signed [15:0] s1_c = sin_lut[{addr_s0 + 10'd1}];
    wire signed [15:0] c0_c = sin_lut[LUT_N - addr_s0];
    wire signed [15:0] c1_c = sin_lut[LUT_N - 1 - addr_s0];

    // Combinational interp from stage-1 regs
    wire [8:0] frac_comp = 9'd256 - {1'b0, frac_s1};

    wire signed [25:0] sin_interp_num =
        ($signed(s0_r) * $signed({1'b0, frac_comp})) +
        ($signed(s1_r) * $signed({1'b0, frac_s1}));
    wire signed [25:0] cos_interp_num =
        ($signed(c0_r) * $signed({1'b0, frac_comp})) +
        ($signed(c1_r) * $signed({1'b0, frac_s1}));

    wire signed [15:0] sin_q = sin_interp_num[23:8];
    wire signed [15:0] cos_q = cos_interp_num[23:8];

    reg signed [15:0] cos_nco_c;
    reg signed [15:0] sin_nco_c;

    always @(*) begin
        case (quad_s1)
            2'd0: begin
                cos_nco_c = cos_q;
                sin_nco_c = sin_q;
            end
            2'd1: begin
                cos_nco_c = -sin_q;
                sin_nco_c = cos_q;
            end
            2'd2: begin
                cos_nco_c = -cos_q;
                sin_nco_c = -sin_q;
            end
            default: begin
                cos_nco_c = sin_q;
                sin_nco_c = -cos_q;
            end
        endcase
    end

    wire signed [31:0] p_ii = iq_i_s2 * cos_nco;
    wire signed [31:0] p_qs = iq_q_s2 * sin_nco;
    wire signed [31:0] p_qi = iq_q_s2 * cos_nco;
    wire signed [31:0] p_is = iq_i_s2 * sin_nco;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase        <= 32'd0;
            phase_loaded <= 1'b0;
            quad_s0      <= 2'd0;
            addr_s0      <= 10'd0;
            frac_s0      <= 8'd0;
            iq_i_s0      <= 16'sd0;
            iq_q_s0      <= 16'sd0;
            stage1_valid <= 1'b0;
            s0_r         <= 16'sd0;
            s1_r         <= 16'sd0;
            c0_r         <= 16'sd0;
            c1_r         <= 16'sd0;
            quad_s1      <= 2'd0;
            frac_s1      <= 8'd0;
            iq_i_s1      <= 16'sd0;
            iq_q_s1      <= 16'sd0;
            stage2_valid <= 1'b0;
            cos_nco      <= 16'sd0;
            sin_nco      <= 16'sd0;
            iq_i_s2      <= 16'sd0;
            iq_q_s2      <= 16'sd0;
            stage3_valid <= 1'b0;
            out_valid    <= 1'b0;
            out_i        <= 16'sd0;
            out_q        <= 16'sd0;
        end else if (!phase_loaded) begin
            phase        <= phase0;
            phase_loaded <= 1'b1;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            stage3_valid <= 1'b0;
            out_valid    <= 1'b0;
        end else begin
            if (in_valid) begin
                quad_s0      <= phase[31:30];
                addr_s0      <= phase[29:20];
                frac_s0      <= phase[19:12];
                iq_i_s0      <= in_i;
                iq_q_s0      <= in_q;
                stage1_valid <= 1'b1;
                phase        <= phase + phase_inc;
            end else begin
                stage1_valid <= 1'b0;
            end

            if (stage1_valid) begin
                s0_r         <= s0_c;
                s1_r         <= s1_c;
                c0_r         <= c0_c;
                c1_r         <= c1_c;
                quad_s1      <= quad_s0;
                frac_s1      <= frac_s0;
                iq_i_s1      <= iq_i_s0;
                iq_q_s1      <= iq_q_s0;
                stage2_valid <= 1'b1;
            end else begin
                stage2_valid <= 1'b0;
            end

            if (stage2_valid) begin
                cos_nco      <= cos_nco_c;
                sin_nco      <= sin_nco_c;
                iq_i_s2      <= iq_i_s1;
                iq_q_s2      <= iq_q_s1;
                stage3_valid <= 1'b1;
            end else begin
                stage3_valid <= 1'b0;
            end

            if (stage3_valid) begin
                out_i     <= mix_i;
                out_q     <= mix_q;
                out_valid <= 1'b1;
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
