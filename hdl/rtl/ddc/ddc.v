// =============================================================================
// ddc — digital downconversion (NCO mixer)
//
// y[n] = x[n] * exp(-j * θ[n]),  θ[n] = phase0 + n * phase_inc
//
// Pipeline: after phase0 load, each in_valid sample takes 6 clocks —
//   stage 0: capture addr/frac/quad + IQ; advance phase
//   stage 1: LUT read → register s0/s1/c0/c1 (+ frac/quad/IQ forward)
//   stage 2: linear interp → register sin_q/cos_q (+ quad/IQ forward)
//   stage 3: quadrant map → cos_nco/sin_nco (+ IQ forward)
//   stage 4: complex-multiply products → register p_ii/p_qs/p_qi/p_is
//   stage 5: add/sub + round/sat → out_*
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

    // Stage 2: registered linear-interp Q1.14 (pre-quadrant)
    reg signed [15:0] sin_q_r, cos_q_r;
    reg [1:0]         quad_s2;
    reg signed [15:0] iq_i_s2;
    reg signed [15:0] iq_q_s2;
    reg               stage3_valid;

    // Stage 3: NCO cos/sin after quadrant
    reg signed [15:0] cos_nco;
    reg signed [15:0] sin_nco;
    reg signed [15:0] iq_i_s3;
    reg signed [15:0] iq_q_s3;
    reg               stage4_valid;

    // Stage 4: registered mix products (Q2.28)
    reg signed [31:0] p_ii_r, p_qs_r, p_qi_r, p_is_r;
    reg               stage5_valid;

    // Combinational LUT from stage-0 addr
    wire signed [15:0] s0_c = sin_lut[addr_s0];
    wire signed [15:0] s1_c = sin_lut[{addr_s0 + 10'd1}];
    wire signed [15:0] c0_c = sin_lut[LUT_N - addr_s0];
    wire signed [15:0] c1_c = sin_lut[LUT_N - 1 - addr_s0];

    // Combinational interp from stage-1 regs (ends at stage-2 flops)
    wire [8:0] frac_comp = 9'd256 - {1'b0, frac_s1};

    wire signed [25:0] sin_interp_num =
        ($signed(s0_r) * $signed({1'b0, frac_comp})) +
        ($signed(s1_r) * $signed({1'b0, frac_s1}));
    wire signed [25:0] cos_interp_num =
        ($signed(c0_r) * $signed({1'b0, frac_comp})) +
        ($signed(c1_r) * $signed({1'b0, frac_s1}));

    wire signed [15:0] sin_q = sin_interp_num[23:8];
    wire signed [15:0] cos_q = cos_interp_num[23:8];

    // Combinational quadrant from stage-2 regs (ends at cos_nco/sin_nco)
    reg signed [15:0] cos_nco_c;
    reg signed [15:0] sin_nco_c;

    always @(*) begin
        case (quad_s2)
            2'd0: begin
                cos_nco_c = cos_q_r;
                sin_nco_c = sin_q_r;
            end
            2'd1: begin
                cos_nco_c = -sin_q_r;
                sin_nco_c = cos_q_r;
            end
            2'd2: begin
                cos_nco_c = -cos_q_r;
                sin_nco_c = -sin_q_r;
            end
            default: begin
                cos_nco_c = sin_q_r;
                sin_nco_c = -cos_q_r;
            end
        endcase
    end

    // Combinational products from stage-3 regs (ends at stage-4 product flops)
    wire signed [31:0] p_ii = iq_i_s3 * cos_nco;
    wire signed [31:0] p_qs = iq_q_s3 * sin_nco;
    wire signed [31:0] p_qi = iq_q_s3 * cos_nco;
    wire signed [31:0] p_is = iq_i_s3 * sin_nco;

    // Combinational add/round/sat from stage-4 product regs → out_*
    wire signed [32:0] acc_i = {p_ii_r[31], p_ii_r} + {p_qs_r[31], p_qs_r};
    wire signed [32:0] acc_q = {p_qi_r[31], p_qi_r} - {p_is_r[31], p_is_r};

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
            sin_q_r      <= 16'sd0;
            cos_q_r      <= 16'sd0;
            quad_s2      <= 2'd0;
            iq_i_s2      <= 16'sd0;
            iq_q_s2      <= 16'sd0;
            stage3_valid <= 1'b0;
            cos_nco      <= 16'sd0;
            sin_nco      <= 16'sd0;
            iq_i_s3      <= 16'sd0;
            iq_q_s3      <= 16'sd0;
            stage4_valid <= 1'b0;
            p_ii_r       <= 32'sd0;
            p_qs_r       <= 32'sd0;
            p_qi_r       <= 32'sd0;
            p_is_r       <= 32'sd0;
            stage5_valid <= 1'b0;
            out_valid    <= 1'b0;
            out_i        <= 16'sd0;
            out_q        <= 16'sd0;
        end else if (!phase_loaded) begin
            phase        <= phase0;
            phase_loaded <= 1'b1;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            stage3_valid <= 1'b0;
            stage4_valid <= 1'b0;
            stage5_valid <= 1'b0;
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
                sin_q_r      <= sin_q;
                cos_q_r      <= cos_q;
                quad_s2      <= quad_s1;
                iq_i_s2      <= iq_i_s1;
                iq_q_s2      <= iq_q_s1;
                stage3_valid <= 1'b1;
            end else begin
                stage3_valid <= 1'b0;
            end

            if (stage3_valid) begin
                cos_nco      <= cos_nco_c;
                sin_nco      <= sin_nco_c;
                iq_i_s3      <= iq_i_s2;
                iq_q_s3      <= iq_q_s2;
                stage4_valid <= 1'b1;
            end else begin
                stage4_valid <= 1'b0;
            end

            if (stage4_valid) begin
                p_ii_r       <= p_ii;
                p_qs_r       <= p_qs;
                p_qi_r       <= p_qi;
                p_is_r       <= p_is;
                stage5_valid <= 1'b1;
            end else begin
                stage5_valid <= 1'b0;
            end

            if (stage5_valid) begin
                out_i     <= mix_i;
                out_q     <= mix_q;
                out_valid <= 1'b1;
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
