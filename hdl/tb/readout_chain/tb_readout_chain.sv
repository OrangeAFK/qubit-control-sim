// =============================================================================
// tb_readout_chain — Phase 3 top-level readout-chain TB (TESTBENCH ONLY).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz), matching fixture fs = 100e6 (1 sample/clk)
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   Phase 2 fixture IF IQ (Q1.14 hex from vectors/*_in_{i,q}.mem), exported by
//   export_fixtures.py from
//   python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz
//   NCO words + threshold from same fixtures (RC_PHASE_*, RC_THRESHOLD_Q).
//
// Expected
//   Fixture output_iq_* → *_exp_{i,q}.mem (Q12.14)
//   Fixture decision_*  → *_exp_decision.mem (1-bit)
//   Compare: |dut_iq - exp| <= RC_TOL_LSB (16384 = 1.0 in Q12.14) AND
//            decision === exp (bit-exact). See docs/fixed_point_notes.md
//            § readout_chain.
//
// Compare window
//   After reset, stream RC_N_SAMPLES with in_valid=1, then hold in_valid=0
//   (FIR flush / pipeline may finish after the last IF sample). Wait for the
//   first out_valid. Pass iff IQ within tol and decision bit-exact.
//
// Empty shell at hdl/rtl/readout_chain/readout_chain.v never asserts
// out_valid → TB times out FAIL (meaningful pre-DUT failure). Wire real
// structural top after TB review.
// =============================================================================

`timescale 1ns / 1ps

module tb_readout_chain;

  // ---------------------------------------------------------------------------
  // Parameters (vector metadata from export_fixtures.py)
  // ---------------------------------------------------------------------------
  localparam time CLK_PERIOD     = 10ns;  // 100 MHz ↔ fixture fs
  localparam int  RESET_CYCLES   = 8;
  // Chain needs room for FIR flush after last IF sample; keep >> N_SAMPLES.
  localparam int  TIMEOUT_CYCLES = 200_000;

  // Compile-time include path: hdl/tb/readout_chain/vectors (see sim TCL -i)
`include "readout_chain_params.svh"

  // Runtime vector directory: +VECDIR=<path> from sim_readout_chain.tcl
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
  logic signed [31:0] threshold;
  logic               out_valid;
  logic signed [31:0] out_i;
  logic signed [31:0] out_q;
  logic               decision;

  readout_chain #(
      .NUM_TAPS         (RC_NUM_TAPS),
      .DECIM_M          (RC_DECIM_M),
      .INTEGRATE_START  (RC_INTEGRATE_START),
      .INTEGRATE_LENGTH (RC_INTEGRATE_LENGTH)
  ) dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .in_valid  (in_valid),
      .in_i      (in_i),
      .in_q      (in_q),
      .phase_inc (phase_inc),
      .phase0    (phase0),
      .threshold (threshold),
      .out_valid (out_valid),
      .out_i     (out_i),
      .out_q     (out_q),
      .decision  (decision)
  );

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Vector memories (loaded per case)
  // ---------------------------------------------------------------------------
  logic signed [15:0] mem_in_i         [0:RC_N_SAMPLES-1];
  logic signed [15:0] mem_in_q         [0:RC_N_SAMPLES-1];
  logic signed [31:0] mem_exp_i        [0:0];
  logic signed [31:0] mem_exp_q        [0:0];
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
      $readmemh(vec_path(case_name, "exp_i"),        mem_exp_i);
      $readmemh(vec_path(case_name, "exp_q"),        mem_exp_q);
      $readmemh(vec_path(case_name, "exp_decision"), mem_exp_decision);
      $display("[%0t] Loaded case \"%s\" (%0d IF samples) from %s",
               $time, case_name, RC_N_SAMPLES, vec_dir);
    end
  endtask

  task automatic apply_reset;
    begin
      rst_n     = 1'b0;
      in_valid  = 1'b0;
      in_i      = '0;
      in_q      = '0;
      phase_inc = RC_PHASE_INC;
      phase0    = RC_PHASE0;
      threshold = RC_THRESHOLD_Q;
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

      // fork/join + timed_out flags (same xsim-safe pattern as prior TBs).
      fork
        begin : drive
          int n;
          for (n = 0; n < RC_N_SAMPLES; n++) begin
            if (timed_out != 0)
              break;
            @(posedge clk);
            in_valid  <= 1'b1;
            in_i      <= mem_in_i[n];
            in_q      <= mem_in_q[n];
            phase_inc <= RC_PHASE_INC;
            phase0    <= RC_PHASE0;
            threshold <= RC_THRESHOLD_Q;
          end
          // Hold invalid after last IF sample so FIR flush / pipeline can finish.
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
            if ((abs_err_i > RC_TOL_LSB) || (abs_err_q > RC_TOL_LSB)) begin
              $error("[%s] iq dut=(%0d,%0d) exp=(%0d,%0d) |err|=(%0d,%0d) tol=%0d",
                     case_name, out_i, out_q,
                     mem_exp_i[0], mem_exp_q[0],
                     abs_err_i, abs_err_q, RC_TOL_LSB);
              err_count++;
            end else begin
              $display("[%0t] %s: IQ compare OK |err|=(%0d,%0d) tol=%0d",
                       $time, case_name, abs_err_i, abs_err_q, RC_TOL_LSB);
            end

            if (decision !== mem_exp_decision[0]) begin
              $error("[%s] decision=%0b exp=%0b (bit-exact required)",
                     case_name, decision, mem_exp_decision[0]);
              err_count++;
            end else begin
              $display("[%0t] %s: decision OK decision=%0b",
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

    $display("=== tb_readout_chain ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_SAMPLES=%0d  N_CASES=%0d  TOL_LSB=%0d  THRESHOLD_Q=%0d",
             RC_N_SAMPLES, RC_N_CASES, RC_TOL_LSB, RC_THRESHOLD_Q);
    $display("PHASE_INC=0x%08h  PHASE0=0x%08h  TAPS=%0d  M=%0d  START=%0d  LEN=%0d",
             RC_PHASE_INC, RC_PHASE0, RC_NUM_TAPS, RC_DECIM_M,
             RC_INTEGRATE_START, RC_INTEGRATE_LENGTH);

    for (c = 0; c < RC_N_CASES; c++) begin
      run_case(case_name(c), case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_readout_chain: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_readout_chain: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_readout_chain failed");
    end
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (RC_N_CASES + 1)
                    + RC_N_SAMPLES * (RC_N_CASES + 1)));
    $fatal(1, "tb_readout_chain global watchdog timeout");
  end

endmodule
