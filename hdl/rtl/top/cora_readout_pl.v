// =============================================================================
// cora_readout_pl — synthesizable PL wrapper for Cora Z7-07S Phase 4 readout
//
// Integrates:
//   axi_lite_regs     — frozen AXI-Lite map (ARCHITECTURE.md §3.3.1)
//   axis_if_ingress   — AXI-Stream IF sample unpack
//   readout_chain     — Phase 3 DDC→FIR→integrate→discriminate
//
// Scope of this first synth:
//   - PL fabric DSP path + Lite stub + Stream slave ports
//   - No Zynq PS / AXI DMA / Block Design (document as next/manual step)
//   - INTEGRATE_* Lite regs are software-visible only; chain window is still
//     compile-time parameters (fixture defaults 8 / 1016)
//
// Clock: top-level pl_clk (constrain to 100 MHz in XDC; matches Phase 3 sim).
// =============================================================================

`timescale 1ns / 1ps

module cora_readout_pl #(
    parameter integer NUM_TAPS         = 63,
    parameter integer DECIM_M          = 4,
    parameter integer INTEGRATE_START  = 8,
    parameter integer INTEGRATE_LENGTH = 1016
) (
    input  wire        pl_clk,
    input  wire        rst_n,

    // AXI4-Lite slave (PS GP0 attach point later)
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI4-Stream slave (DMA MM2S attach point later)
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready
);

    wire        soft_rst_pulse;
    wire        arm_pulse;
    wire        clr_done_pulse;
    wire [31:0] phase_inc;
    wire [31:0] phase0;
    wire signed [31:0] threshold;

    // Soft-reset stretches one extra cycle so async-reset flops see rst_n low.
    reg soft_rst_d;
    always @(posedge pl_clk or negedge rst_n) begin
        if (!rst_n)
            soft_rst_d <= 1'b0;
        else
            soft_rst_d <= soft_rst_pulse;
    end
    wire dsp_rst_n = rst_n & ~soft_rst_pulse & ~soft_rst_d;

    // Acquisition status FSM
    reg        status_busy;
    reg        status_done;
    reg        status_overrun;
    reg        status_armed;
    reg signed [31:0] result_i;
    reg signed [31:0] result_q;
    reg        result_decision;

    wire        accept = status_armed | status_busy;
    wire        clear_count = arm_pulse;

    wire               ing_valid;
    wire signed [15:0] ing_i;
    wire signed [15:0] ing_q;
    wire [31:0]        if_sample_count;

    wire               chain_out_valid;
    wire signed [31:0] chain_out_i;
    wire signed [31:0] chain_out_q;
    wire               chain_decision;

    // Overrun: Stream presents a beat while not accepting
    wire axis_fire_attempt = s_axis_tvalid & ~s_axis_tready;

    always @(posedge pl_clk or negedge rst_n) begin
        if (!rst_n) begin
            status_busy     <= 1'b0;
            status_done     <= 1'b0;
            status_overrun  <= 1'b0;
            status_armed    <= 1'b0;
            result_i        <= 32'sd0;
            result_q        <= 32'sd0;
            result_decision <= 1'b0;
        end else if (soft_rst_pulse | soft_rst_d) begin
            status_busy     <= 1'b0;
            status_done     <= 1'b0;
            status_overrun  <= 1'b0;
            status_armed    <= 1'b0;
            result_i        <= 32'sd0;
            result_q        <= 32'sd0;
            result_decision <= 1'b0;
        end else begin
            if (arm_pulse) begin
                status_done    <= 1'b0;
                status_overrun <= 1'b0;
                status_armed   <= 1'b1;
                status_busy    <= 1'b0;
            end
            if (clr_done_pulse) begin
                status_done <= 1'b0;
            end
            if (axis_fire_attempt) begin
                status_overrun <= 1'b1;
            end
            if (accept && s_axis_tvalid && s_axis_tready) begin
                status_busy <= 1'b1;
            end
            if (chain_out_valid) begin
                result_i        <= chain_out_i;
                result_q        <= chain_out_q;
                result_decision <= chain_decision;
                status_done     <= 1'b1;
                status_busy     <= 1'b0;
                status_armed    <= 1'b0;
            end
        end
    end

    axi_lite_regs #(
        .DECIM_M_RO            (DECIM_M),
        .NUM_TAPS_RO           (NUM_TAPS),
        .INTEGRATE_START_RST   (INTEGRATE_START),
        .INTEGRATE_LENGTH_RST  (INTEGRATE_LENGTH)
    ) u_lite (
        .clk              (pl_clk),
        .rst_n            (rst_n),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .phase_inc        (phase_inc),
        .phase0           (phase0),
        .threshold        (threshold),
        .integrate_start  (),  // software-visible only (see header)
        .integrate_length (),
        .soft_rst_pulse   (soft_rst_pulse),
        .arm_pulse        (arm_pulse),
        .clr_done_pulse   (clr_done_pulse),
        .status_busy      (status_busy),
        .status_done      (status_done),
        .status_overrun   (status_overrun),
        .status_armed     (status_armed),
        .result_i         (result_i),
        .result_q         (result_q),
        .result_decision  (result_decision),
        .if_sample_count  (if_sample_count)
    );

    axis_if_ingress u_ingress (
        .clk           (pl_clk),
        .rst_n         (dsp_rst_n),
        .accept        (accept),
        .clear_count   (clear_count),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),
        .m_valid       (ing_valid),
        .m_i           (ing_i),
        .m_q           (ing_q),
        .m_last        (),  // chain flush uses in_valid=0 after stream ends
        .sample_count  (if_sample_count)
    );

    readout_chain #(
        .NUM_TAPS         (NUM_TAPS),
        .DECIM_M          (DECIM_M),
        .INTEGRATE_START  (INTEGRATE_START),
        .INTEGRATE_LENGTH (INTEGRATE_LENGTH)
    ) u_chain (
        .clk       (pl_clk),
        .rst_n     (dsp_rst_n),
        .in_valid  (ing_valid),
        .in_i      (ing_i),
        .in_q      (ing_q),
        .phase_inc (phase_inc),
        .phase0    (phase0),
        .threshold (threshold),
        .out_valid (chain_out_valid),
        .out_i     (chain_out_i),
        .out_q     (chain_out_q),
        .decision  (chain_decision)
    );

endmodule
