// =============================================================================
// tb_ddc — Phase 3 DDC module testbench (TESTBENCH ONLY; review before DUT).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz), matching fixture fs = 100e6 (1 sample/clk)
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   Phase 2 fixture IF IQ (Q1.14 hex from hdl/tb/ddc/vectors/*_in_{i,q}.mem),
//   exported by export_fixtures.py from
//   python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz
//
// Expected
//   Quantized dsp_ref.ddc(fixture IF) → *_exp_{i,q}.mem (not prose-invented)
//
// Compare window
//   After reset, stream N samples with in_valid=1. Collect the next N samples
//   where out_valid=1 (DUT may insert pipeline latency before first out_valid).
//   Pass if |dut - exp| <= DDC_TOL_LSB (4) on I and Q for every sample.
//
// Empty shell at hdl/rtl/ddc/ddc.v never asserts out_valid → TB times out FAIL
// (meaningful pre-DUT failure). Swap in real RTL after this TB is reviewed.
// =============================================================================

`timescale 1ns / 1ps

module tb_ddc;

  // ---------------------------------------------------------------------------
  // Parameters (vector metadata from export_fixtures.py)
  // ---------------------------------------------------------------------------
  localparam time CLK_PERIOD     = 10ns;  // 100 MHz ↔ fixture fs
  localparam int  RESET_CYCLES   = 8;
  localparam int  TIMEOUT_CYCLES = 100_000;

  // Compile-time include path: hdl/tb/ddc/vectors (see sim_ddc.tcl -i)
`include "ddc_params.svh"

  // Runtime vector directory: +VECDIR=<path> from sim_ddc.tcl (absolute path)
  string vec_dir;

  // ---------------------------------------------------------------------------
  // DUT I/O
  // ---------------------------------------------------------------------------
  logic               clk;
  logic               rst_n;
  logic               in_valid;
  logic signed [15:0] in_i;
  logic signed [15:0] in_q;
  logic        [31:0] phase_inc;
  logic        [31:0] phase0;
  logic               out_valid;
  logic signed [15:0] out_i;
  logic signed [15:0] out_q;

  ddc dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .in_valid  (in_valid),
      .in_i      (in_i),
      .in_q      (in_q),
      .phase_inc (phase_inc),
      .phase0    (phase0),
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
  logic signed [15:0] mem_in_i  [0:DDC_N_SAMPLES-1];
  logic signed [15:0] mem_in_q  [0:DDC_N_SAMPLES-1];
  logic signed [15:0] mem_exp_i [0:DDC_N_SAMPLES-1];
  logic signed [15:0] mem_exp_q [0:DDC_N_SAMPLES-1];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  function automatic string vec_path(input string case_name, input string suffix);
    return {vec_dir, "/", case_name, "_", suffix, ".mem"};
  endfunction

  task automatic load_case(input string case_name);
    begin
      $readmemh(vec_path(case_name, "in_i"),  mem_in_i);
      $readmemh(vec_path(case_name, "in_q"),  mem_in_q);
      $readmemh(vec_path(case_name, "exp_i"), mem_exp_i);
      $readmemh(vec_path(case_name, "exp_q"), mem_exp_q);
      $display("[%0t] Loaded case \"%s\" (%0d samples) from %s",
               $time, case_name, DDC_N_SAMPLES, vec_dir);
    end
  endtask

  task automatic apply_reset;
    begin
      rst_n     = 1'b0;
      in_valid  = 1'b0;
      in_i      = '0;
      in_q      = '0;
      phase_inc = DDC_PHASE_INC;
      phase0    = DDC_PHASE0;
      repeat (RESET_CYCLES) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  // Returns number of sample mismatches + timeout errors for this case.
  task automatic run_case(input string case_name, output int err_count);
    int got_count;
    int wait_cycles;
    int abs_err_i;
    int abs_err_q;
    int timed_out;
    begin
      load_case(case_name);
      apply_reset();

      err_count   = 0;
      got_count   = 0;
      wait_cycles = 0;
      timed_out   = 0;

      fork
        begin : drive
          int n;
          for (n = 0; n < DDC_N_SAMPLES; n++) begin
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
          while (out_valid !== 1'b1) begin
            @(posedge clk);
            wait_cycles++;
            if (wait_cycles > TIMEOUT_CYCLES) begin
              $error("[%s] TIMEOUT: no out_valid within %0d cycles (empty shell / missing DUT / stalled)",
                     case_name, TIMEOUT_CYCLES);
              err_count++;
              timed_out = 1;
              disable fork;
            end
          end
          $display("[%0t] %s: first out_valid after %0d wait cycles",
                   $time, case_name, wait_cycles);

          while (got_count < DDC_N_SAMPLES) begin
            if (out_valid === 1'b1) begin
              abs_err_i = (out_i >= mem_exp_i[got_count]) ?
                          (out_i - mem_exp_i[got_count]) :
                          (mem_exp_i[got_count] - out_i);
              abs_err_q = (out_q >= mem_exp_q[got_count]) ?
                          (out_q - mem_exp_q[got_count]) :
                          (mem_exp_q[got_count] - out_q);
              if ((abs_err_i > DDC_TOL_LSB) || (abs_err_q > DDC_TOL_LSB)) begin
                if (err_count < 16) begin
                  $error("[%s] sample %0d: dut=(%0d,%0d) exp=(%0d,%0d) |err|=(%0d,%0d) tol=%0d",
                         case_name, got_count, out_i, out_q,
                         mem_exp_i[got_count], mem_exp_q[got_count],
                         abs_err_i, abs_err_q, DDC_TOL_LSB);
                end
                err_count++;
              end
              got_count++;
            end
            @(posedge clk);
            wait_cycles++;
            if (wait_cycles > (TIMEOUT_CYCLES + DDC_N_SAMPLES)) begin
              $error("[%s] TIMEOUT draining outputs: got %0d / %0d",
                     case_name, got_count, DDC_N_SAMPLES);
              err_count++;
              timed_out = 1;
              disable fork;
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

    $display("=== tb_ddc ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_SAMPLES=%0d  N_CASES=%0d  TOL_LSB=%0d  PHASE_INC=0x%08h  PHASE0=0x%08h",
             DDC_N_SAMPLES, DDC_N_CASES, DDC_TOL_LSB, DDC_PHASE_INC, DDC_PHASE0);

    for (c = 0; c < DDC_N_CASES; c++) begin
      run_case(DDC_CASE_NAMES[c], case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_ddc: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_ddc: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_ddc failed");
    end
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (DDC_N_CASES + 1)
                    + DDC_N_SAMPLES * (DDC_N_CASES + 1)));
    $fatal(1, "tb_ddc global watchdog timeout");
  end

endmodule
