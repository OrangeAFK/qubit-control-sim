// =============================================================================
// tb_fir — Phase 3 FIR(+decim) module testbench (TESTBENCH ONLY; review before DUT).
//
// Clocks / reset
//   clk     : 10 ns period (100 MHz), matching fixture fs = 100e6 (1 input/clk)
//   rst_n   : active-low; held low for RESET_CYCLES after time 0
//
// Stimulus
//   Post-DDC baseband IQ (Q1.14 hex from hdl/tb/fir/vectors/*_in_{i,q}.mem),
//   exported by export_fixtures.py = quantize(dsp_ref.ddc(fixture IF)).
//   Coeffs for the future DUT: vectors/fir_coeffs.mem (fixture fir_coeffs).
//
// Expected
//   quantize(decimate(apply_fir(baseband, fir_coeffs), M=4)) → *_exp_{i,q}.mem
//   (not prose-invented). Decimation is part of this stage per fixed_point_notes.
//
// Compare window
//   After reset, stream FIR_N_IN samples with in_valid=1. Collect the next
//   FIR_N_OUT samples where out_valid=1 (DUT may insert pipeline latency and
//   emits ~1/M outputs). Pass if |dut - exp| <= FIR_TOL_LSB (8) on I and Q.
//
// Empty shell at hdl/rtl/fir/fir.v never asserts out_valid → TB times out FAIL
// (meaningful pre-DUT failure). Swap in real RTL after this TB is reviewed.
// =============================================================================

`timescale 1ns / 1ps

module tb_fir;

  // ---------------------------------------------------------------------------
  // Parameters (vector metadata from export_fixtures.py)
  // ---------------------------------------------------------------------------
  localparam time CLK_PERIOD     = 10ns;  // 100 MHz ↔ fixture fs
  localparam int  RESET_CYCLES   = 8;
  localparam int  TIMEOUT_CYCLES = 100_000;

  // Compile-time include path: hdl/tb/fir/vectors (see sim_fir.tcl -i)
`include "fir_params.svh"

  // Runtime vector directory: +VECDIR=<path> from sim_fir.tcl (absolute path)
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
  logic signed [15:0] out_i;
  logic signed [15:0] out_q;

  fir #(
      .NUM_TAPS (FIR_NUM_TAPS),
      .DECIM_M  (FIR_DECIM_M)
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
  logic signed [15:0] mem_in_i  [0:FIR_N_IN-1];
  logic signed [15:0] mem_in_q  [0:FIR_N_IN-1];
  logic signed [15:0] mem_exp_i [0:FIR_N_OUT-1];
  logic signed [15:0] mem_exp_q [0:FIR_N_OUT-1];

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
      $display("[%0t] Loaded case \"%s\" (n_in=%0d n_out=%0d) from %s",
               $time, case_name, FIR_N_IN, FIR_N_OUT, vec_dir);
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

      // fork/join_any + disable fork: xsim ignores disable-fork *inside* a
      // while (tb_ddc latent), so exit wait loops via timed_out flags instead.
      fork
        begin : drive
          int n;
          for (n = 0; n < FIR_N_IN; n++) begin
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

            while ((got_count < FIR_N_OUT) && (timed_out == 0)) begin
              if (out_valid === 1'b1) begin
                abs_err_i = (out_i >= mem_exp_i[got_count]) ?
                            (out_i - mem_exp_i[got_count]) :
                            (mem_exp_i[got_count] - out_i);
                abs_err_q = (out_q >= mem_exp_q[got_count]) ?
                            (out_q - mem_exp_q[got_count]) :
                            (mem_exp_q[got_count] - out_q);
                if ((abs_err_i > FIR_TOL_LSB) || (abs_err_q > FIR_TOL_LSB)) begin
                  if (err_count < 16) begin
                    $error("[%s] sample %0d: dut=(%0d,%0d) exp=(%0d,%0d) |err|=(%0d,%0d) tol=%0d",
                           case_name, got_count, out_i, out_q,
                           mem_exp_i[got_count], mem_exp_q[got_count],
                           abs_err_i, abs_err_q, FIR_TOL_LSB);
                  end
                  err_count++;
                end
                got_count++;
              end
              @(posedge clk);
              wait_cycles++;
              if (wait_cycles > (TIMEOUT_CYCLES + FIR_N_IN + FIR_NUM_TAPS)) begin
                $error("[%s] TIMEOUT draining outputs: got %0d / %0d",
                       case_name, got_count, FIR_N_OUT);
                err_count++;
                timed_out = 1;
              end
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

    $display("=== tb_fir ===");
    $display("VECDIR=%s", vec_dir);
    $display("N_IN=%0d  N_OUT=%0d  N_CASES=%0d  TAPS=%0d  M=%0d  TOL_LSB=%0d",
             FIR_N_IN, FIR_N_OUT, FIR_N_CASES, FIR_NUM_TAPS, FIR_DECIM_M,
             FIR_TOL_LSB);

    for (c = 0; c < FIR_N_CASES; c++) begin
      run_case(case_name(c), case_errs);
      if (case_errs != 0)
        failures++;
    end

    if (failures == 0) begin
      $display("=== tb_fir: ALL CASES PASSED ===");
      $finish(0);
    end else begin
      $display("=== tb_fir: FAILED (%0d case failures) ===", failures);
      $fatal(1, "tb_fir failed");
    end
  end

  // Global watchdog
  initial begin
    #(CLK_PERIOD * (TIMEOUT_CYCLES * (FIR_N_CASES + 1)
                    + FIR_N_IN * (FIR_N_CASES + 1)));
    $fatal(1, "tb_fir global watchdog timeout");
  end

endmodule
