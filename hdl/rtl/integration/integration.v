// =============================================================================
// integration — accumulate a fixed window of post-FIR/decim IQ samples
//
// Count accepted in_valid samples (0-based). Accumulate indices
//   [INTEGRATE_START : INTEGRATE_START+INTEGRATE_LENGTH)
// as Q12.14 (same frac grid as Q1.14 — sign-extend and add). Pulse out_valid
// one cycle when the window completes; outputs are the 26-bit sum
// sign-extended into 32-bit containers.
//
// Q-format: docs/fixed_point_notes.md § integration
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
    output reg                out_valid,  // one-cycle pulse when window done
    output reg  signed [31:0] out_i,      // Q12.14
    output reg  signed [31:0] out_q       // Q12.14
);

    localparam integer ACC_W   = 26;  // Q12.14 value width
    localparam integer CNT_W   = 16;  // sample index while streaming
    localparam integer WIN_END = INTEGRATE_START + INTEGRATE_LENGTH;

    reg [CNT_W-1:0]        sample_idx;
    reg signed [ACC_W-1:0] acc_i;
    reg signed [ACC_W-1:0] acc_q;

    // Sign-extend Q1.14 → Q12.14 (same fractional bits; no rescale).
    wire signed [ACC_W-1:0] in_i_sx =
        {{(ACC_W - 16){in_i[15]}}, in_i};
    wire signed [ACC_W-1:0] in_q_sx =
        {{(ACC_W - 16){in_q[15]}}, in_q};

    wire in_window =
        (sample_idx >= INTEGRATE_START) && (sample_idx < WIN_END);

    wire window_done =
        in_valid && (sample_idx == (WIN_END - 1));

    wire signed [ACC_W-1:0] next_acc_i =
        (in_valid && in_window) ? (acc_i + in_i_sx) : acc_i;
    wire signed [ACC_W-1:0] next_acc_q =
        (in_valid && in_window) ? (acc_q + in_q_sx) : acc_q;

    // Sign-extend 26-bit Q12.14 into 32-bit container.
    wire signed [31:0] out_i_sx =
        {{(32 - ACC_W){next_acc_i[ACC_W-1]}}, next_acc_i};
    wire signed [31:0] out_q_sx =
        {{(32 - ACC_W){next_acc_q[ACC_W-1]}}, next_acc_q};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_idx <= {CNT_W{1'b0}};
            acc_i      <= {ACC_W{1'b0}};
            acc_q      <= {ACC_W{1'b0}};
            out_valid  <= 1'b0;
            out_i      <= 32'sd0;
            out_q      <= 32'sd0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid) begin
                acc_i <= next_acc_i;
                acc_q <= next_acc_q;

                if (window_done) begin
                    out_i     <= out_i_sx;
                    out_q     <= out_q_sx;
                    out_valid <= 1'b1;
                end

                sample_idx <= sample_idx + 1'b1;
            end
        end
    end

endmodule
