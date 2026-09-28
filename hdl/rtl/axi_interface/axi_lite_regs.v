// =============================================================================
// axi_lite_regs — Phase 4 AXI4-Lite slave stub (ARCHITECTURE.md §3.3.1)
//
// Synthesizable register file matching the frozen map. Single outstanding
// transaction; 32-bit data, byte address [7:2] (256-byte primary aperture).
// CTRL W1P fields pulse for one cycle on the write acceptance beat.
//
// INTEGRATE_START / INTEGRATE_LENGTH are stored here for software visibility;
// the Phase-3 readout_chain still uses compile-time parameters until a later
// RTL change wires runtime window ports.
// =============================================================================

`timescale 1ns / 1ps

module axi_lite_regs #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 8,
    parameter integer DECIM_M_RO         = 4,
    parameter integer NUM_TAPS_RO        = 63,
    parameter integer VERSION_RO         = 32'h0004_0001,
    parameter integer MAGIC_RO           = 32'h4352_4F34,
    parameter integer INTEGRATE_START_RST = 8,
    parameter integer INTEGRATE_LENGTH_RST = 1016
) (
    input  wire                               clk,
    input  wire                               rst_n,

    // AXI4-Lite slave
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire                               s_axi_awvalid,
    output reg                                s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]  s_axi_wstrb,
    input  wire                               s_axi_wvalid,
    output reg                                s_axi_wready,
    output reg  [1:0]                         s_axi_bresp,
    output reg                                s_axi_bvalid,
    input  wire                               s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire                               s_axi_arvalid,
    output reg                                s_axi_arready,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]      s_axi_rdata,
    output reg  [1:0]                         s_axi_rresp,
    output reg                                s_axi_rvalid,
    input  wire                               s_axi_rready,

    // Config toward DSP (latched)
    output reg  [31:0]                        phase_inc,
    output reg  [31:0]                        phase0,
    output reg  signed [31:0]                 threshold,
    output reg  [31:0]                        integrate_start,
    output reg  [31:0]                        integrate_length,

    // CTRL pulses (one cycle)
    output reg                                soft_rst_pulse,
    output reg                                arm_pulse,
    output reg                                clr_done_pulse,

    // Status / results from wrapper FSM
    input  wire                               status_busy,
    input  wire                               status_done,
    input  wire                               status_overrun,
    input  wire                               status_armed,
    input  wire signed [31:0]                 result_i,
    input  wire signed [31:0]                 result_q,
    input  wire                               result_decision,
    input  wire [31:0]                        if_sample_count
);

    // Write channel: accept AW+W together, then B
    // -------------------------------------------------------------------------
    wire wr_fire = s_axi_awvalid & s_axi_wvalid & s_axi_awready & s_axi_wready;
    wire [7:0] wr_off = {s_axi_awaddr[7:2], 2'b00};
    // s_axi_wstrb: ignored (full-word writes) in this synth stub.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            soft_rst_pulse  <= 1'b0;
            arm_pulse       <= 1'b0;
            clr_done_pulse  <= 1'b0;
            phase_inc       <= 32'd0;
            phase0          <= 32'd0;
            threshold       <= 32'sd0;
            integrate_start <= INTEGRATE_START_RST;
            integrate_length<= INTEGRATE_LENGTH_RST;
        end else begin
            soft_rst_pulse <= 1'b0;
            arm_pulse      <= 1'b0;
            clr_done_pulse <= 1'b0;

            // Ready when not waiting for B handshake
            if (!s_axi_bvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            if (wr_fire) begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
                // Full-word writes (STRB ignored in this synth stub).
                if (wr_off == 8'h00) begin
                    soft_rst_pulse <= s_axi_wdata[0];
                    arm_pulse      <= s_axi_wdata[1];
                    clr_done_pulse <= s_axi_wdata[2];
                end else if (wr_off == 8'h08) begin
                    phase_inc <= s_axi_wdata;
                end else if (wr_off == 8'h0C) begin
                    phase0 <= s_axi_wdata;
                end else if (wr_off == 8'h10) begin
                    threshold <= s_axi_wdata;
                end else if (wr_off == 8'h14) begin
                    integrate_start <= s_axi_wdata;
                end else if (wr_off == 8'h18) begin
                    integrate_length <= s_axi_wdata;
                end
            end

            if (s_axi_bvalid & s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read channel
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (!s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_arvalid & s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case ({s_axi_araddr[7:2], 2'b00})
                    8'h00: s_axi_rdata <= 32'd0; // CTRL W1P reads as 0
                    8'h04: s_axi_rdata <= {28'd0, status_armed, status_overrun,
                                           status_done, status_busy};
                    8'h08: s_axi_rdata <= phase_inc;
                    8'h0C: s_axi_rdata <= phase0;
                    8'h10: s_axi_rdata <= threshold;
                    8'h14: s_axi_rdata <= integrate_start;
                    8'h18: s_axi_rdata <= integrate_length;
                    8'h1C: s_axi_rdata <= result_i;
                    8'h20: s_axi_rdata <= result_q;
                    8'h24: s_axi_rdata <= {31'd0, result_decision};
                    8'h28: s_axi_rdata <= DECIM_M_RO;
                    8'h2C: s_axi_rdata <= NUM_TAPS_RO;
                    8'h30: s_axi_rdata <= VERSION_RO;
                    8'h34: s_axi_rdata <= MAGIC_RO;
                    8'h38: s_axi_rdata <= if_sample_count;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end

            if (s_axi_rvalid & s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
