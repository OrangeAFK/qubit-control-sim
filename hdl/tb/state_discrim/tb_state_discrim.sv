// =============================================================================
// tb_state_discrim — Phase 3 threshold/state-discrimination TB (TESTBENCH ONLY).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz)
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   One integrated IQ sample per case (Q12.14 hex from vectors/*_in_{i,q}.mem),
//   exported by export_fixtures.py = quantize(fixture output_iq_*).
//   Threshold held at SD_THRESHOLD_Q (same Q12.14 format).
//
// Expected
//   Fixture decision_* → *_exp_decision.mem (1-bit). Must match bit-exact
//   (docs/fixed_point_notes.md § state_discrim): Re(iq) >= threshold → 1 else 0.
//
// Compare window
//   After reset, present one sample with in_valid=1. Wait for the first
//   out_valid (DUT may insert pipeline latency). Pass iff decision === exp.
//
// Empty shell at hdl/rtl/state_discrim/state_discrim.v never asserts out_valid →
// TB times out FAIL (meaningful pre-DUT failure). Swap in real RTL after review.
// =============================================================================

`timescale 1ns / 1ps

module tb_state_discrim;

  // ---------------------------------------------------------------------------
  // Parameters (vector metadata from export_fixtures.py)
  // ---------------------------------------------------------------------------
  localparam time CLK_PERIOD     = 10ns;  // 100 MHz
  localparam int  RESET_CYCLES   = 8;
  localparam int  TIMEOUT_CYCLES = 100_000;

  // Compile-time include path: hdl/tb/state_discrim/vectors (see sim TCL -i)
`include "state_discrim_params.svh"

  // Runtime vector directory: +VECDIR=<path> from sim_state_discrim.tcl
  string vec_dir;

  // ---------------------------------------------------------------------------
  // DUT I/O
  // ---------------------------------------------------------------------------
  logic               clk;
  logic               rst_n;
  logic               in_valid;
  logic signed [31:0] in_i;
  logic signed [31:0] in_q;
  logic signed [31:0] threshold;
  logic               out_valid;
  logic               decision;

  state_discrim dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .in_valid  (in_valid),
      .in_i      (in_i),
      .in_q      (in_q),
      .threshold (threshold),
      .out_valid (out_valid),
      .decision  (decision)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Vector memories (loaded per case; one sample each)
  // ---------------------------------------------------------------------------
  logic signed [31:0] mem_in_i        [0:0];
  logic signed [31:0] mem_in_q        [0:0];
  logic        [0:0]  mem_exp_decision [0:0];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  // xsim (Vivado 2025.1) corrupts `localparam string NAME [0:N]` from the
  // included svh; resolve case names here so $readmemh paths are real.
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

  task automatic load_case(input string case_name);
    begin
      $readmemh(vec_path(case_name, "in_i"),         mem_in_i);
      $readmemh(vec_path(case_name, "in_q"),         mem_in_q);
      $readmemh(vec_path(case_name, "exp_decision"), mem_exp_decision);
      $display("[%0t] Loaded case \"%s\" (threshold_q=%0d) from %s",
               $time, case_name, SD_THRESHOLD_Q, vec_dir);
    end
  endtask

  task automatic apply_reset;
    begin
      rst_n     = 1'b0;
      in_valid  = 1'b0;
      in_i      = '0;
      in_q      = '0;
      threshold = SD_THRESHOLD_Q;
      repeat (RESET_CYCLES) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // Returns number of mismatches + timeout errors for this case.
  task automatic run_case(input string case_name, output int err_count);
    int wait_cycles;
    int timed_out;
    begin
      load_case(case_name);
      apply_reset();

      err_count   = 0;
      wait_cycles = 0;
      timed_out   = 0;

      // fork/join + timed_out flags (same xsim-safe pattern as tb_integration).
      fork
        begin : drive
          if (timed_out == 0) begin
            @(posedge clk);
            in_valid  <= 1'b1;
            in_i      <= mem_in_i[0];
            in_q      <= mem_in_q[0];
            threshold <= SD_THRESHOLD_Q;
            @(posedge clk);
            in_valid <= 1'b0;
            in_i     <= '0;
            in_q     <= '0;
          end
        end

        begin : compare
          while ((out_valid !== 1'b1) && (timed_out == 0)) begin
            @(posedge clk);
            wait_cycles++;
            if (wait_cycles > TIMEOUT_CYCLES) begin
              $error("[%s] TIMEOUT: no out_valid within %0d cycles (empty shell / missing DUT / stalled)",
                     case_name, TIMEOUT_CYCLES);
              err_count++;
              timed_out = 1;
            end
          end

          if (timed_out == 0) begin
            $display("[%0t] %s: first out_valid after %0d wait cycles",
                     $time, case_name, wait_cycles);

            if (decision !== mem_exp_decision[0]) begin
              $error("[%s] decision=%0b exp=%0b (bit-exact required)",
                     case_name, decision, mem_exp_decision[0]);
              err_count++;
            end else begin
              $display("[%0t] %s: compare OK decision=%0b",
                       $time, case_name, decision);
            end
          end
        end
      join

      if ((err_count == 0) && (timed_out == 0))
        $display("[%0t] PASS case \"%s\"", $time, case_name);
      else
        $display("[%0t] FAIL case \"%s\" (%0d errors)", $time, case_name,
                 err_count);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------
  int failures;
  int case_errs;
  int c;

  initial begin : main
    failures = 0;

    if (!$value$plusargs("VECDIR=%s", vec_dir)) begin
      vec_dir = ".";
      $display("WARNING: +VECDIR not set; using cwd for $readmemh");
    end

    $display("=== tb_state_discrim ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_CASES=%0d  N_IN=%0d  THRESHOLD_Q=%0d  (bit-exact decisions)",
             SD_N_CASES, SD_N_IN, SD_THRESHOLD_Q);

    for (c = 0; c < SD_N_CASES; c++) begin
      run_case(case_name(c), case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_state_discrim: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_state_discrim: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_state_discrim failed");
    end
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (SD_N_CASES + 1) + 64));
    $fatal(1, "tb_state_discrim global watchdog timeout");
  end

endmodule
