// =============================================================================
// tb_integration — Phase 3 integration/accumulation TB (TESTBENCH ONLY).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz), matching fixture fs/M after FIR decim
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   Post-FIR/decim IQ (Q1.14 hex from vectors/*_in_{i,q}.mem), exported by
//   export_fixtures.py = quantize(decimate(apply_fir(ddc(fixture IF)))).
//   Window params from fixture: INTEGRATE_START=8, INTEGRATE_LENGTH=1016.
//
// Expected
//   quantize_Q12.14(integrate(decimated, start, length)) → *_exp_{i,q}.mem
//   (single complex IQ per case; cross-checked vs fixture output_iq_*).
//
// Compare window
//   After reset, stream INT_N_IN samples with in_valid=1. Wait for the first
//   out_valid (DUT may insert pipeline latency). Pass if |dut - exp| <=
//   INT_TOL_LSB (16384 = 1.0 in Q12.14) on I and Q.
//
// Empty shell at hdl/rtl/integration/integration.v never asserts out_valid →
// TB times out FAIL (meaningful pre-DUT failure). Swap in real RTL after review.
// =============================================================================

`timescale 1ns / 1ps

module tb_integration;

  // ---------------------------------------------------------------------------
  // Parameters (vector metadata from export_fixtures.py)
  // ---------------------------------------------------------------------------
  localparam time CLK_PERIOD     = 10ns;  // 100 MHz ↔ fixture fs (post-decim rate)
  localparam int  RESET_CYCLES   = 8;
  localparam int  TIMEOUT_CYCLES = 100_000;

  // Compile-time include path: hdl/tb/integration/vectors (see sim_integration.tcl -i)
`include "integration_params.svh"

  // Runtime vector directory: +VECDIR=<path> from sim_integration.tcl
  string vec_dir;

  // ---------------------------------------------------------------------------
  // DUT I/O
  // ---------------------------------------------------------------------------
  logic               clk;
  logic               rst_n;
  logic               in_valid;
  logic signed [15:0] in_i;
  logic signed [15:0] in_q;
  logic               out_valid;
  logic signed [31:0] out_i;  // Q12.14 in 32-bit container
  logic signed [31:0] out_q;

  integration #(
      .INTEGRATE_START  (INT_INTEGRATE_START),
      .INTEGRATE_LENGTH (INT_INTEGRATE_LENGTH)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .in_valid  (in_valid),
      .in_i      (in_i),
      .in_q      (in_q),
      .out_valid (out_valid),
      .out_i     (out_i),
      .out_q     (out_q)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Vector memories (loaded per case)
  // ---------------------------------------------------------------------------
  logic signed [15:0] mem_in_i  [0:INT_N_IN-1];
  logic signed [15:0] mem_in_q  [0:INT_N_IN-1];
  logic signed [31:0] mem_exp_i [0:0];
  logic signed [31:0] mem_exp_q [0:0];

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
      $readmemh(vec_path(case_name, "in_i"),  mem_in_i);
      $readmemh(vec_path(case_name, "in_q"),  mem_in_q);
      $readmemh(vec_path(case_name, "exp_i"), mem_exp_i);
      $readmemh(vec_path(case_name, "exp_q"), mem_exp_q);
      $display("[%0t] Loaded case \"%s\" (n_in=%0d start=%0d length=%0d) from %s",
               $time, case_name, INT_N_IN, INT_INTEGRATE_START,
               INT_INTEGRATE_LENGTH, vec_dir);
    end
  endtask

  task automatic apply_reset;
    begin
      rst_n    = 1'b0;
      in_valid = 1'b0;
      in_i     = '0;
      in_q     = '0;
      repeat (RESET_CYCLES) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // Returns number of mismatches + timeout errors for this case.
  task automatic run_case(input string case_name, output int err_count);
    int wait_cycles;
    int abs_err_i;
    int abs_err_q;
    int timed_out;
    begin
      load_case(case_name);
      apply_reset();

      err_count   = 0;
      wait_cycles = 0;
      timed_out   = 0;

      // fork/join + timed_out flags (same xsim-safe pattern as tb_fir/tb_ddc).
      fork
        begin : drive
          int n;
          for (n = 0; n < INT_N_IN; n++) begin
            if (timed_out != 0)
              break;
            @(posedge clk);
            in_valid <= 1'b1;
            in_i     <= mem_in_i[n];
            in_q     <= mem_in_q[n];
          end
          @(posedge clk);
          in_valid <= 1'b0;
          in_i     <= '0;
          in_q     <= '0;
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

            abs_err_i = (out_i >= mem_exp_i[0]) ?
                        (out_i - mem_exp_i[0]) :
                        (mem_exp_i[0] - out_i);
            abs_err_q = (out_q >= mem_exp_q[0]) ?
                        (out_q - mem_exp_q[0]) :
                        (mem_exp_q[0] - out_q);
            if ((abs_err_i > INT_TOL_LSB) || (abs_err_q > INT_TOL_LSB)) begin
              $error("[%s] dut=(%0d,%0d) exp=(%0d,%0d) |err|=(%0d,%0d) tol=%0d",
                     case_name, out_i, out_q,
                     mem_exp_i[0], mem_exp_q[0],
                     abs_err_i, abs_err_q, INT_TOL_LSB);
              err_count++;
            end else begin
              $display("[%0t] %s: compare OK |err|=(%0d,%0d) tol=%0d",
                       $time, case_name, abs_err_i, abs_err_q, INT_TOL_LSB);
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

    $display("=== tb_integration ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_IN=%0d  N_CASES=%0d  START=%0d  LENGTH=%0d  TOL_LSB=%0d",
             INT_N_IN, INT_N_CASES, INT_INTEGRATE_START, INT_INTEGRATE_LENGTH,
             INT_TOL_LSB);

    for (c = 0; c < INT_N_CASES; c++) begin
      run_case(case_name(c), case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_integration: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_integration: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_integration failed");
    end
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (INT_N_CASES + 1)
                    + INT_N_IN * (INT_N_CASES + 1)));
    $fatal(1, "tb_integration global watchdog timeout");
  end

endmodule
