// =============================================================================
// tb_axis_if_ingress — Phase 4 AXI-Stream IF ingress TB (TESTBENCH FIRST).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz), same as Phase 3 fixture fs
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   Phase 2/3 Q1.14 IF IQ from hdl/tb/readout_chain/vectors/*_in_{i,q}.mem
//   Packed per ARCHITECTURE §3.3.1: TDATA = {Q[15:0], I[15:0]}
//   Master inserts one TVALID gap and a mid-stream accept=0 backpressure window.
//   TLAST asserted only on the last sample of each case.
//
// Expected (sink monitor toward readout_chain ports)
//   Every m_valid beat: m_i/m_q match fixture I/Q bit-exact
//   sample_count == RC_N_SAMPLES after the case
//   m_last == 1 only on the final accepted beat
//
// Compare window
//   After reset + clear_count, stream one fixture case; sink collects N samples
//   (DUT may add 1-cycle registered latency). Repeat all RC_N_CASES.
// =============================================================================

`timescale 1ns / 1ps

module tb_axis_if_ingress;

  localparam time CLK_PERIOD     = 10ns;
  localparam int  RESET_CYCLES   = 8;
  localparam int  TIMEOUT_CYCLES = 100_000;

  // Reuse Phase 3 chain vector metadata (N, case count). Include dir via TCL -i.
`include "readout_chain_params.svh"

  string vec_dir;

  logic               clk;
  logic               rst_n;
  logic               accept;
  logic               clear_count;
  logic        [31:0] s_axis_tdata;
  logic               s_axis_tvalid;
  logic               s_axis_tlast;
  logic               s_axis_tready;
  logic               m_valid;
  logic signed [15:0] m_i;
  logic signed [15:0] m_q;
  logic               m_last;
  logic        [31:0] sample_count;

  axis_if_ingress dut (
      .clk           (clk),
      .rst_n         (rst_n),
      .accept        (accept),
      .clear_count   (clear_count),
      .s_axis_tdata  (s_axis_tdata),
      .s_axis_tvalid (s_axis_tvalid),
      .s_axis_tlast  (s_axis_tlast),
      .s_axis_tready (s_axis_tready),
      .m_valid       (m_valid),
      .m_i           (m_i),
      .m_q           (m_q),
      .m_last        (m_last),
      .sample_count  (sample_count)
  );

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  logic signed [15:0] mem_in_i [0:RC_N_SAMPLES-1];
  logic signed [15:0] mem_in_q [0:RC_N_SAMPLES-1];

  // xsim corrupts localparam string arrays from included svh — hardcode names.
  function automatic string case_name(input int idx);
    case (idx)
      0: case_name = "noiseless_s0";
      1: case_name = "noiseless_s1";
      2: case_name = "noisy";
      default: case_name = "UNKNOWN";
    endcase
  endfunction

  function automatic string vec_path(input string cname, input string suffix);
    return {vec_dir, "/", cname, "_", suffix, ".mem"};
  endfunction

  task automatic load_case(input string cname);
    begin
      $readmemh(vec_path(cname, "in_i"), mem_in_i);
      $readmemh(vec_path(cname, "in_q"), mem_in_q);
      $display("[%0t] Loaded case \"%s\" (%0d IF samples) from %s",
               $time, cname, RC_N_SAMPLES, vec_dir);
    end
  endtask

  task automatic apply_reset;
    begin
      rst_n         = 1'b0;
      accept        = 1'b0;
      clear_count   = 1'b0;
      s_axis_tdata  = 32'h0;
      s_axis_tvalid = 1'b0;
      s_axis_tlast  = 1'b0;
      repeat (RESET_CYCLES) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  task automatic pulse_clear_count;
    begin
      @(posedge clk);
      clear_count <= 1'b1;
      @(posedge clk);
      clear_count <= 1'b0;
      @(posedge clk);
    end
  endtask

  // Send one AXIS beat; holds until TREADY accepts (standard AXI-Stream).
  task automatic axis_send(input logic [31:0] data, input logic last);
    begin
      s_axis_tdata  <= data;
      s_axis_tvalid <= 1'b1;
      s_axis_tlast  <= last;
      @(posedge clk);
      while (s_axis_tready !== 1'b1) begin
        @(posedge clk);
      end
      // Deassert so a delayed next call cannot re-fire the same beat.
      s_axis_tvalid <= 1'b0;
      s_axis_tlast  <= 1'b0;
    end
  endtask

  task automatic run_case(input string cname, output int err_count);
    int timed_out;
    int sink_idx;
    int last_seen;
    int gap_at;
    int bp_at;
    int n;
    begin
      load_case(cname);
      apply_reset();
      accept <= 1'b1;
      pulse_clear_count();

      if (sample_count !== 32'd0) begin
        $error("[%s] sample_count not 0 after clear (got %0d)", cname, sample_count);
        err_count = 1;
        return;
      end

      err_count  = 0;
      timed_out  = 0;
      sink_idx   = 0;
      last_seen  = 0;
      gap_at     = RC_N_SAMPLES / 4;
      bp_at      = RC_N_SAMPLES / 2;

      fork
        begin : drive
          for (n = 0; n < RC_N_SAMPLES; n++) begin
            if (timed_out != 0)
              break;

            // Mid-stream backpressure before presenting beat bp_at.
            if (n == bp_at) begin
              accept <= 1'b0;
              s_axis_tdata  <= {mem_in_q[n], mem_in_i[n]};
              s_axis_tvalid <= 1'b1;
              s_axis_tlast  <= (n == RC_N_SAMPLES - 1);
              repeat (8) @(posedge clk);
              accept <= 1'b1;
            end

            axis_send({mem_in_q[n], mem_in_i[n]}, (n == RC_N_SAMPLES - 1));

            // One-cycle TVALID gap after gap_at
            if (n == gap_at) begin
              s_axis_tvalid <= 1'b0;
              s_axis_tlast  <= 1'b0;
              @(posedge clk);
            end
          end
          s_axis_tvalid <= 1'b0;
          s_axis_tlast  <= 1'b0;
          accept        <= 1'b1;
        end

        begin : sink
          int wait_cycles;
          wait_cycles = 0;
          while ((sink_idx < RC_N_SAMPLES) && (timed_out == 0)) begin
            @(posedge clk);
            wait_cycles++;
            if (wait_cycles > TIMEOUT_CYCLES) begin
              $error("[%s] TIMEOUT: sink got %0d / %0d", cname, sink_idx, RC_N_SAMPLES);
              err_count++;
              timed_out = 1;
            end else if (m_valid === 1'b1) begin
              if (m_i !== mem_in_i[sink_idx] || m_q !== mem_in_q[sink_idx]) begin
                $error("[%s] sink @%0d got I=%0d Q=%0d exp I=%0d Q=%0d",
                       cname, sink_idx, m_i, m_q,
                       mem_in_i[sink_idx], mem_in_q[sink_idx]);
                err_count++;
              end
              if (m_last !== (sink_idx == RC_N_SAMPLES - 1)) begin
                $error("[%s] m_last @%0d=%b expected %b",
                       cname, sink_idx, m_last, (sink_idx == RC_N_SAMPLES - 1));
                err_count++;
              end
              if (m_last === 1'b1)
                last_seen = 1;
              sink_idx++;
            end
          end
        end
      join

      @(posedge clk);
      @(posedge clk);

      if (timed_out == 0) begin
        if (sample_count !== RC_N_SAMPLES) begin
          $error("[%s] sample_count=%0d expected %0d",
                 cname, sample_count, RC_N_SAMPLES);
          err_count++;
        end
        if (last_seen == 0) begin
          $error("[%s] never saw m_last", cname);
          err_count++;
        end
      end

      if (err_count == 0)
        $display("[%0t] PASS case \"%s\" (N=%0d)", $time, cname, RC_N_SAMPLES);
      else
        $display("[%0t] FAIL case \"%s\" (%0d errors)", $time, cname, err_count);
    end
  endtask

  int failures;
  int case_errs;
  int c;

  initial begin : main
    failures = 0;

    if (!$value$plusargs("VECDIR=%s", vec_dir)) begin
      vec_dir = ".";
      $display("WARNING: +VECDIR not set; using cwd for $readmemh");
    end

    $display("=== tb_axis_if_ingress ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_SAMPLES=%0d  N_CASES=%0d", RC_N_SAMPLES, RC_N_CASES);
    $display("Packing: TDATA = {Q[15:0], I[15:0]} Q1.14");

    for (c = 0; c < RC_N_CASES; c++) begin
      run_case(case_name(c), case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_axis_if_ingress: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_axis_if_ingress: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_axis_if_ingress failed");
    end
  end

  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (RC_N_CASES + 1)
                    + RC_N_SAMPLES * (RC_N_CASES + 1)));
    $fatal(1, "tb_axis_if_ingress global watchdog timeout");
  end

endmodule
