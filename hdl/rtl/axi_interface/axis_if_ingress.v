// =============================================================================
// axis_if_ingress — AXI4-Stream slave → native IF IQ for readout_chain
//
// Packing (ARCHITECTURE.md §3.3.1 / docs/fixed_point_notes.md § axis_if_ingress):
//   s_axis_tdata[31:0] = {Q[15:0], I[15:0]}, each lane signed Q1.14
//
// Handshake:
//   s_axis_tready = rst_n && accept
//   Beat accepted when s_axis_tvalid && s_axis_tready (posedge sample)
//   One-cycle registered native outputs (m_valid / m_i / m_q / m_last)
//
// TLAST: forwarded as m_last on the accepted beat; does not gate earlier samples.
// sample_count: number of accepted beats since reset or clear_count pulse.
// =============================================================================

`timescale 1ns / 1ps

module axis_if_ingress (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               accept,       // gate TREADY (ARM/BUSY in later wrapper)
    input  wire               clear_count,  // pulse: zero sample_count
    // AXI4-Stream slave
    input  wire        [31:0] s_axis_tdata,
    input  wire               s_axis_tvalid,
    input  wire               s_axis_tlast,
    output wire               s_axis_tready,
    // Native IF toward readout_chain (in_valid / in_i / in_q)
    output reg                m_valid,
    output reg  signed [15:0] m_i,
    output reg  signed [15:0] m_q,
    output reg                m_last,
    output reg         [31:0] sample_count
);

    wire fire;

    assign s_axis_tready = rst_n & accept;
    assign fire          = s_axis_tvalid & s_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid      <= 1'b0;
            m_i          <= 16'sd0;
            m_q          <= 16'sd0;
            m_last       <= 1'b0;
            sample_count <= 32'd0;
        end else begin
            if (clear_count) begin
                sample_count <= fire ? 32'd1 : 32'd0;
            end else if (fire) begin
                sample_count <= sample_count + 32'd1;
            end

            if (fire) begin
                m_valid <= 1'b1;
                m_i     <= s_axis_tdata[15:0];
                m_q     <= s_axis_tdata[31:16];
                m_last  <= s_axis_tlast;
            end else begin
                m_valid <= 1'b0;
                m_last  <= 1'b0;
            end
        end
    end

endmodule
