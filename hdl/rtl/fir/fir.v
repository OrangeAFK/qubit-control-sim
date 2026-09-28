// =============================================================================
// fir — FIR low-pass + decimation (M), multi-cycle MAC (BRAM delay + engines)
//
// Matches dsp_ref: centered convolution (numpy mode='same') then keep-every-M.
// For odd NUM_TAPS, group delay L = (NUM_TAPS-1)/2; causal MAC at sample index
// n equals same[n-L]. Emit when n >= L and (n-L) % DECIM_M == 0.
//
// After the input stream ends, continue with zero-valued samples (flush) so
// trailing same-mode taps that look past the last input match numpy padding.
//
// Timing (xc7z007s @ 100 MHz):
//   - Circular delay line in per-engine block RAM (I/Q packed). Depth is
//     128 so in-flight MACs are not overwritten by new writes.
//   - On emit: bind wr_ptr as base; serial MAC (TAPS_PER_CYCLE=1) with
//     BRAM read → registered DSP product → accumulate (breaks BRAM→DSP→sat).
//   - NUM_ENGINES = ceil((NUM_TAPS+2)/DECIM_M) covers BRAM warmup + taps +
//     one post-product accumulate cycle.
//   - Round/sat is a registered cycle after the final accumulate.
//
// Q-format: docs/fixed_point_notes.md § fir
// Coeff ROM: fir_coeffs.mem (copied next to xsim work dir by sim_fir.tcl)
// =============================================================================

`timescale 1ns / 1ps

module fir #(
    parameter integer NUM_TAPS       = 63,
    parameter integer DECIM_M        = 4,
    // Block-RAM 1R1W path is serial; keep at 1 (parameter retained for call sites).
    parameter integer TAPS_PER_CYCLE = 1
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [15:0] in_i,
    input  wire signed [15:0] in_q,
    output reg                out_valid,
    output reg  signed [15:0] out_i,
    output reg  signed [15:0] out_q
);

    localparam integer L            = (NUM_TAPS - 1) / 2;
    localparam integer ACC_W        = 40;
    localparam integer IDX_W        = 16;
    // BRAM warmup + NUM_TAPS product regs + 1 final accumulate after last product
    localparam integer BUSY_CYCLES  = NUM_TAPS + 2;
    localparam integer NUM_ENGINES  = (BUSY_CYCLES + DECIM_M - 1) / DECIM_M;
    localparam integer MEM_DEPTH    = 128;
    localparam integer PTR_W        = $clog2(MEM_DEPTH);
    localparam integer PHASE_W      = $clog2(NUM_TAPS);
    localparam integer ENG_W        = $clog2(NUM_ENGINES);

    initial begin
        if (TAPS_PER_CYCLE != 1)
            $error("fir: BRAM architecture requires TAPS_PER_CYCLE==1");
        if (NUM_TAPS < 2)
            $error("fir: NUM_TAPS must be >= 2");
        if (MEM_DEPTH < (2 * NUM_TAPS))
            $error("fir: MEM_DEPTH must be >= 2*NUM_TAPS");
    end

    reg signed [15:0] coeffs [0:NUM_TAPS-1];

    initial begin
        $readmemh("fir_coeffs.mem", coeffs);
    end

    reg               active;
    reg [IDX_W-1:0]   sample_idx;
    reg [PTR_W-1:0]   wr_ptr;

    wire signed [15:0] new_i = in_valid ? in_i : 16'sd0;
    wire signed [15:0] new_q = in_valid ? in_q : 16'sd0;
    wire process = in_valid | active;
    wire [31:0] new_iq = {new_q, new_i};

    wire emit = process
                && (sample_idx >= IDX_W'(L))
                && (((sample_idx - IDX_W'(L)) % DECIM_M) == 0);

    reg               eng_busy       [0:NUM_ENGINES-1];
    reg               eng_samp_valid [0:NUM_ENGINES-1];
    reg [PHASE_W-1:0] eng_phase      [0:NUM_ENGINES-1];
    reg [PTR_W-1:0]   eng_base       [0:NUM_ENGINES-1];
    reg [PTR_W-1:0]   eng_rd_addr    [0:NUM_ENGINES-1];
    reg [IDX_W-1:0]   eng_fill       [0:NUM_ENGINES-1];
    reg signed [ACC_W-1:0] eng_acc_i [0:NUM_ENGINES-1];
    reg signed [ACC_W-1:0] eng_acc_q [0:NUM_ENGINES-1];
    reg               eng_acc_has    [0:NUM_ENGINES-1];

    reg signed [31:0] eng_prod_i     [0:NUM_ENGINES-1];
    reg signed [31:0] eng_prod_q     [0:NUM_ENGINES-1];
    reg               eng_prod_valid [0:NUM_ENGINES-1];
    reg               eng_prod_last  [0:NUM_ENGINES-1];

    reg [31:0]        eng_mem_out    [0:NUM_ENGINES-1];
    reg               eng_bypass     [0:NUM_ENGINES-1];
    reg [31:0]        eng_bypass_d   [0:NUM_ENGINES-1];

    reg [ENG_W-1:0] next_eng;

    reg               sat_pending;
    reg signed [ACC_W-1:0] sat_acc_i;
    reg signed [ACC_W-1:0] sat_acc_q;

    function automatic [PTR_W-1:0] sub_mod;
        input [PTR_W-1:0] base;
        input integer     t;
        begin
            sub_mod = base - PTR_W'(t);
        end
    endfunction

    function automatic signed [15:0] sat16;
        input signed [ACC_W-1:0] x;
        reg signed [ACC_W-1:0] rounded;
        reg signed [ACC_W-1:0] shifted;
        begin
            rounded = x + ({{(ACC_W-14){1'b0}}, 14'd8192});
            shifted = rounded >>> 14;
            if (shifted > ACC_W'(32767))
                sat16 = 16'sd32767;
            else if (shifted < -ACC_W'(32768))
                sat16 = -16'sd32768;
            else
                sat16 = shifted[15:0];
        end
    endfunction

    integer e;
    reg                    finishing [0:NUM_ENGINES-1];
    reg                    do_start;
    reg [ENG_W-1:0]        start_eng;
    reg                    mac_out_taken;
    reg signed [ACC_W-1:0] sum_i;
    reg signed [ACC_W-1:0] sum_q;
    reg signed [31:0]      prod_i;
    reg signed [31:0]      prod_q;
    reg signed [15:0]      samp_i;
    reg signed [15:0]      samp_q;
    reg [31:0]             sample_w;
    reg [PTR_W-1:0]        next_rd [0:NUM_ENGINES-1];
    reg                    will_start [0:NUM_ENGINES-1];

    // One simple-dual-port BRAM per engine (1D array — reliable inference).
    // Sync read of next_rd (combo) → registered dout = 1-cycle read latency.
    genvar gi;
    generate
        for (gi = 0; gi < NUM_ENGINES; gi = gi + 1) begin : gen_tap_bram
            (* ram_style = "block" *)
            reg [31:0] mem [0:MEM_DEPTH-1];

            always @(posedge clk) begin
                if (process)
                    mem[wr_ptr] <= new_iq;
                eng_mem_out[gi] <= mem[next_rd[gi]];
            end
        end
    endgenerate

    always @(*) begin
        for (e = 0; e < NUM_ENGINES; e = e + 1) begin
            will_start[e] = 1'b0;
            next_rd[e]    = eng_rd_addr[e];
            // Free on the cycle that folds the last registered product into acc.
            finishing[e]  = eng_busy[e] && eng_prod_valid[e] && eng_prod_last[e];
        end

        do_start  = process && emit;
        start_eng = next_eng;
        if (do_start) begin
            if (eng_busy[start_eng] && !finishing[start_eng]) begin
                if (start_eng == ENG_W'(NUM_ENGINES - 1))
                    start_eng = {ENG_W{1'b0}};
                else
                    start_eng = start_eng + 1'b1;
            end
            will_start[start_eng] = 1'b1;
            next_rd[start_eng]    = wr_ptr;
        end

        for (e = 0; e < NUM_ENGINES; e = e + 1) begin
            if (eng_busy[e] && !will_start[e]) begin
                if (!eng_samp_valid[e])
                    // Warmup: tap-0 read issued at start; request tap 1 now.
                    next_rd[e] = sub_mod(eng_base[e], 1);
                else if (eng_phase[e] != PHASE_W'(NUM_TAPS - 1))
                    next_rd[e] = sub_mod(eng_base[e], eng_phase[e] + 1);
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            active      <= 1'b0;
            sample_idx  <= {IDX_W{1'b0}};
            wr_ptr      <= {PTR_W{1'b0}};
            next_eng    <= {ENG_W{1'b0}};
            out_valid   <= 1'b0;
            out_i       <= 16'sd0;
            out_q       <= 16'sd0;
            sat_pending <= 1'b0;
            sat_acc_i   <= {ACC_W{1'b0}};
            sat_acc_q   <= {ACC_W{1'b0}};
            for (e = 0; e < NUM_ENGINES; e = e + 1) begin
                eng_busy[e]       <= 1'b0;
                eng_samp_valid[e] <= 1'b0;
                eng_phase[e]      <= {PHASE_W{1'b0}};
                eng_base[e]       <= {PTR_W{1'b0}};
                eng_rd_addr[e]    <= {PTR_W{1'b0}};
                eng_fill[e]       <= {IDX_W{1'b0}};
                eng_acc_i[e]      <= {ACC_W{1'b0}};
                eng_acc_q[e]      <= {ACC_W{1'b0}};
                eng_acc_has[e]    <= 1'b0;
                eng_prod_i[e]     <= 32'sd0;
                eng_prod_q[e]     <= 32'sd0;
                eng_prod_valid[e] <= 1'b0;
                eng_prod_last[e]  <= 1'b0;
                eng_bypass[e]     <= 1'b0;
                eng_bypass_d[e]   <= 32'd0;
            end
        end else begin
            out_valid     <= 1'b0;
            mac_out_taken = 1'b0;

            if (in_valid)
                active <= 1'b1;

            // Address + bypass registers (BRAM read uses eng_rd_addr).
            for (e = 0; e < NUM_ENGINES; e = e + 1) begin
                eng_rd_addr[e]  <= next_rd[e];
                eng_bypass[e]   <= process && (next_rd[e] == wr_ptr);
                eng_bypass_d[e] <= new_iq;
            end

            for (e = 0; e < NUM_ENGINES; e = e + 1) begin
                if (eng_busy[e]) begin
                    // --- Accumulate stage: fold prior registered product ---
                    // Runs even on will_start so a same-cycle restart still
                    // retires the previous MAC into sat_pending.
                    if (eng_prod_valid[e]) begin
                        if (!eng_acc_has[e]) begin
                            sum_i = {{(ACC_W-32){eng_prod_i[e][31]}}, eng_prod_i[e]};
                            sum_q = {{(ACC_W-32){eng_prod_q[e][31]}}, eng_prod_q[e]};
                        end else begin
                            sum_i = eng_acc_i[e]
                                    + {{(ACC_W-32){eng_prod_i[e][31]}}, eng_prod_i[e]};
                            sum_q = eng_acc_q[e]
                                    + {{(ACC_W-32){eng_prod_q[e][31]}}, eng_prod_q[e]};
                        end

                        if (eng_prod_last[e]) begin
                            eng_busy[e]       <= 1'b0;
                            eng_samp_valid[e] <= 1'b0;
                            eng_phase[e]      <= {PHASE_W{1'b0}};
                            eng_acc_i[e]      <= {ACC_W{1'b0}};
                            eng_acc_q[e]      <= {ACC_W{1'b0}};
                            eng_acc_has[e]    <= 1'b0;
                            eng_prod_valid[e] <= 1'b0;
                            eng_prod_last[e]  <= 1'b0;
                            if (!mac_out_taken && !sat_pending) begin
                                sat_acc_i     <= sum_i;
                                sat_acc_q     <= sum_q;
                                sat_pending   <= 1'b1;
                                mac_out_taken = 1'b1;
                            end
                        end else begin
                            eng_acc_i[e]      <= sum_i;
                            eng_acc_q[e]      <= sum_q;
                            eng_acc_has[e]    <= 1'b1;
                            // Keep prod_valid high while streaming; overwritten
                            // below when a new product is issued, else clear.
                            eng_prod_valid[e] <= 1'b0;
                        end
                    end

                    // --- Product stage: BRAM dout × coeff → product reg ---
                    if (!will_start[e] && !(eng_prod_valid[e] && eng_prod_last[e])) begin
                        if (!eng_samp_valid[e]) begin
                            // First BRAM sample (addr issued at will_start).
                            eng_samp_valid[e] <= 1'b1;
                            eng_phase[e]      <= PHASE_W'(1);
                            if (IDX_W'(0) >= eng_fill[e]) begin
                                prod_i = 32'sd0;
                                prod_q = 32'sd0;
                            end else begin
                                sample_w = eng_bypass[e] ? eng_bypass_d[e]
                                                         : eng_mem_out[e];
                                samp_i   = sample_w[15:0];
                                samp_q   = sample_w[31:16];
                                prod_i   = samp_i * coeffs[0];
                                prod_q   = samp_q * coeffs[0];
                            end
                            eng_prod_i[e]     <= prod_i;
                            eng_prod_q[e]     <= prod_q;
                            eng_prod_valid[e] <= 1'b1;
                            eng_prod_last[e]  <= 1'b0;
                        end else begin
                            // Taps 1 .. NUM_TAPS-1; eng_phase is the tap index.
                            if (IDX_W'(eng_phase[e]) >= eng_fill[e]) begin
                                prod_i = 32'sd0;
                                prod_q = 32'sd0;
                            end else begin
                                sample_w = eng_bypass[e] ? eng_bypass_d[e]
                                                         : eng_mem_out[e];
                                samp_i   = sample_w[15:0];
                                samp_q   = sample_w[31:16];
                                prod_i   = samp_i * coeffs[eng_phase[e]];
                                prod_q   = samp_q * coeffs[eng_phase[e]];
                            end
                            eng_prod_i[e]     <= prod_i;
                            eng_prod_q[e]     <= prod_q;
                            eng_prod_valid[e] <= 1'b1;
                            eng_prod_last[e]  <= (eng_phase[e]
                                                  == PHASE_W'(NUM_TAPS - 1));
                            if (eng_phase[e] == PHASE_W'(NUM_TAPS - 1)) begin
                                eng_samp_valid[e] <= 1'b0;
                                eng_phase[e]      <= {PHASE_W{1'b0}};
                            end else begin
                                eng_phase[e] <= eng_phase[e] + 1'b1;
                            end
                        end
                    end
                end

                if (will_start[e]) begin
                    eng_busy[e]       <= 1'b1;
                    eng_samp_valid[e] <= 1'b0;
                    eng_phase[e]      <= {PHASE_W{1'b0}};
                    eng_base[e]       <= wr_ptr;
                    eng_fill[e]       <= sample_idx + 1'b1;
                    eng_acc_i[e]      <= {ACC_W{1'b0}};
                    eng_acc_q[e]      <= {ACC_W{1'b0}};
                    eng_acc_has[e]    <= 1'b0;
                    eng_prod_valid[e] <= 1'b0;
                    eng_prod_last[e]  <= 1'b0;
                end
            end

            if (do_start) begin
                if (start_eng == ENG_W'(NUM_ENGINES - 1))
                    next_eng <= {ENG_W{1'b0}};
                else
                    next_eng <= start_eng + 1'b1;
            end

            if (sat_pending) begin
                out_i       <= sat16(sat_acc_i);
                out_q       <= sat16(sat_acc_q);
                out_valid   <= 1'b1;
                sat_pending <= 1'b0;
            end

            if (process) begin
                wr_ptr     <= wr_ptr + 1'b1;
                sample_idx <= sample_idx + 1'b1;
            end
        end
    end

endmodule
