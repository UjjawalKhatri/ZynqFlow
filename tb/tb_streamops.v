`timescale 1ns / 1ps

module tb_streamops;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter DATA_W    = 64;
    parameter N_LANES   = DATA_W / 8;
    parameter CLK_PER   = 10;  // 100 MHz
    parameter MAX_BEATS = 16384;

    // -----------------------------------------------------------------------
    // Mode constants
    // -----------------------------------------------------------------------
    localparam MODE_BYPASS    = 3'd0;
    localparam MODE_RELU      = 3'd1;
    localparam MODE_ADD_SAT   = 3'd2;
    localparam MODE_CLAMP     = 3'd3;
    localparam MODE_ABS       = 3'd4;
    localparam MODE_THRESHOLD = 3'd5;
    localparam MODE_XOR       = 3'd6;

    // -----------------------------------------------------------------------
    // Clock and reset
    // -----------------------------------------------------------------------
    reg aclk;
    reg aresetn;

    initial aclk = 0;
    always #(CLK_PER/2) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT connections
    // -----------------------------------------------------------------------
    // AXI4-Stream slave (source -> DUT)
    wire [DATA_W-1:0]   s_axis_tdata;
    wire [N_LANES-1:0]  s_axis_tkeep;
    wire                s_axis_tvalid;
    wire                s_axis_tready;
    wire                s_axis_tlast;

    // AXI4-Stream master (DUT -> sink)
    wire [DATA_W-1:0]   m_axis_tdata;
    wire [N_LANES-1:0]  m_axis_tkeep;
    wire                m_axis_tvalid;
    wire                m_axis_tready;
    wire                m_axis_tlast;

    // Control signals
    reg         enable;
    reg  [2:0]  mode;
    reg  [7:0]  imm8;
    reg  [7:0]  clamp_lo;
    reg  [7:0]  clamp_hi;
    reg         cnt_clear;

    // Counter outputs
    wire [31:0] input_beats;
    wire [31:0] output_beats;
    wire [31:0] stall_cycles;
    wire [31:0] frame_count;
    wire [31:0] active_cycles;

    // -----------------------------------------------------------------------
    // Source BFM control
    // -----------------------------------------------------------------------
    reg         src_start;
    reg  [31:0] src_num_beats;
    reg         src_gap_enable;
    reg  [7:0]  src_gap_prob;
    wire        src_done;

    // -----------------------------------------------------------------------
    // Sink BFM control
    // -----------------------------------------------------------------------
    reg         snk_enable;
    reg         snk_bp_enable;
    reg  [7:0]  snk_bp_prob;
    wire [31:0] snk_beat_count;
    wire        snk_frame_done;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    streamops_axis #(
        .DATA_W(DATA_W)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        .enable         (enable),
        .mode           (mode),
        .imm8           (imm8),
        .clamp_lo       (clamp_lo),
        .clamp_hi       (clamp_hi),
        .cnt_clear      (cnt_clear),
        .input_beats    (input_beats),
        .output_beats   (output_beats),
        .stall_cycles   (stall_cycles),
        .frame_count    (frame_count),
        .active_cycles  (active_cycles)
    );

    // -----------------------------------------------------------------------
    // Source BFM
    // -----------------------------------------------------------------------
    axis_source_bfm #(
        .DATA_W(DATA_W),
        .MAX_BEATS(MAX_BEATS)
    ) u_source (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .m_axis_tdata    (s_axis_tdata),
        .m_axis_tkeep    (s_axis_tkeep),
        .m_axis_tvalid   (s_axis_tvalid),
        .m_axis_tready   (s_axis_tready),
        .m_axis_tlast    (s_axis_tlast),
        .start           (src_start),
        .num_beats       (src_num_beats),
        .gap_enable      (src_gap_enable),
        .gap_probability (src_gap_prob),
        .done            (src_done)
    );

    // -----------------------------------------------------------------------
    // Sink BFM
    // -----------------------------------------------------------------------
    axis_sink_bfm #(
        .DATA_W(DATA_W),
        .MAX_BEATS(MAX_BEATS)
    ) u_sink (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_tdata    (m_axis_tdata),
        .s_axis_tkeep    (m_axis_tkeep),
        .s_axis_tvalid   (m_axis_tvalid),
        .s_axis_tready   (m_axis_tready),
        .s_axis_tlast    (m_axis_tlast),
        .enable          (snk_enable),
        .bp_enable       (snk_bp_enable),
        .bp_probability  (snk_bp_prob),
        .beat_count      (snk_beat_count),
        .frame_done      (snk_frame_done)
    );

    // -----------------------------------------------------------------------
    // Protocol violation monitor
    // -----------------------------------------------------------------------
    reg [DATA_W-1:0]  prev_tdata;
    reg [N_LANES-1:0] prev_tkeep;
    reg               prev_tlast;
    reg               prev_tvalid;
    reg               prev_tready;
    integer           protocol_errors;

    always @(posedge aclk) begin
        if (aresetn) begin
            // Check: output must not change while stalled (tvalid=1, tready=0)
            if (prev_tvalid && !prev_tready && m_axis_tvalid) begin
                if (m_axis_tdata !== prev_tdata) begin
                    $display("ERROR [%0t]: Output TDATA changed while stalled! prev=%h new=%h",
                             $time, prev_tdata, m_axis_tdata);
                    protocol_errors = protocol_errors + 1;
                end
                if (m_axis_tlast !== prev_tlast) begin
                    $display("ERROR [%0t]: Output TLAST changed while stalled!", $time);
                    protocol_errors = protocol_errors + 1;
                end
                if (m_axis_tkeep !== prev_tkeep) begin
                    $display("ERROR [%0t]: Output TKEEP changed while stalled!", $time);
                    protocol_errors = protocol_errors + 1;
                end
            end
        end

        prev_tdata  <= m_axis_tdata;
        prev_tkeep  <= m_axis_tkeep;
        prev_tlast  <= m_axis_tlast;
        prev_tvalid <= m_axis_tvalid;
        prev_tready <= m_axis_tready;
    end

    // -----------------------------------------------------------------------
    // Software reference model functions
    // -----------------------------------------------------------------------
    // (Implemented as Verilog functions for self-checking)

    function [7:0] ref_lane;
        input [2:0] f_mode;
        input [7:0] f_x;
        input [7:0] f_imm8;
        input [7:0] f_lo;
        input [7:0] f_hi;

        reg signed [7:0] xs, imms, los, his;
        reg signed [8:0] add_res;
        begin
            xs   = f_x;
            imms = f_imm8;
            los  = f_lo;
            his  = f_hi;

            case (f_mode)
                MODE_BYPASS:    ref_lane = f_x;
                MODE_RELU:      ref_lane = (xs < 0) ? 8'd0 : f_x;
                MODE_ADD_SAT: begin
                    add_res = {xs[7], xs} + {imms[7], imms};
                    if (add_res > 127)
                        ref_lane = 8'h7F;
                    else if (add_res < -128)
                        ref_lane = 8'h80;
                    else
                        ref_lane = add_res[7:0];
                end
                MODE_CLAMP: begin
                    if (xs < los)
                        ref_lane = f_lo;
                    else if (xs > his)
                        ref_lane = f_hi;
                    else
                        ref_lane = f_x;
                end
                MODE_ABS:       ref_lane = (xs == -128) ? 8'h7F : (xs < 0 ? -xs : f_x);
                MODE_THRESHOLD: ref_lane = (xs >= imms) ? 8'h7F : 8'h00;
                MODE_XOR:       ref_lane = f_x ^ f_imm8;
                default:        ref_lane = f_x;
            endcase
        end
    endfunction

    function [DATA_W-1:0] ref_beat;
        input [2:0]        f_mode;
        input [DATA_W-1:0] f_data;
        input [7:0]        f_imm8;
        input [7:0]        f_lo;
        input [7:0]        f_hi;

        integer lane;
        begin
            ref_beat = {DATA_W{1'b0}};
            for (lane = 0; lane < N_LANES; lane = lane + 1) begin
                ref_beat[lane*8 +: 8] = ref_lane(f_mode,
                                                  f_data[lane*8 +: 8],
                                                  f_imm8, f_lo, f_hi);
            end
        end
    endfunction

    // -----------------------------------------------------------------------
    // Test infrastructure
    // -----------------------------------------------------------------------
    integer total_tests;
    integer total_pass;
    integer total_fail;
    integer test_errors;

    task reset_dut;
        begin
            aresetn   <= 1'b0;
            enable    <= 1'b0;
            mode      <= 3'd0;
            imm8      <= 8'd0;
            clamp_lo  <= 8'd0;
            clamp_hi  <= 8'd0;
            cnt_clear <= 1'b0;
            src_start     <= 1'b0;
            src_num_beats <= 32'd0;
            src_gap_enable <= 1'b0;
            src_gap_prob   <= 8'd0;
            snk_enable    <= 1'b0;
            snk_bp_enable <= 1'b0;
            snk_bp_prob   <= 8'd0;
            protocol_errors <= 0;
            repeat (10) @(posedge aclk);
            aresetn <= 1'b1;
            repeat (5) @(posedge aclk);
        end
    endtask

    task clear_counters;
        begin
            cnt_clear <= 1'b1;
            @(posedge aclk);
            cnt_clear <= 1'b0;
            @(posedge aclk);
        end
    endtask

    // Run a transfer and verify
    task run_transfer;
        input [2:0]  t_mode;
        input [7:0]  t_imm8;
        input [7:0]  t_lo;
        input [7:0]  t_hi;
        input [31:0] t_num_beats;
        input        t_gap_en;
        input [7:0]  t_gap_prob;
        input        t_bp_en;
        input [7:0]  t_bp_prob;

        integer idx;
        integer timeout;
        reg [DATA_W-1:0] expected;
        begin
            test_errors = 0;

            // Configure DUT
            mode     <= t_mode;
            imm8     <= t_imm8;
            clamp_lo <= t_lo;
            clamp_hi <= t_hi;
            enable   <= 1'b1;
            clear_counters;

            // Configure BFMs
            src_num_beats  <= t_num_beats;
            src_gap_enable <= t_gap_en;
            src_gap_prob   <= t_gap_prob;
            snk_enable     <= 1'b1;
            snk_bp_enable  <= t_bp_en;
            snk_bp_prob    <= t_bp_prob;

            @(posedge aclk);

            // Start transfer
            src_start <= 1'b1;
            @(posedge aclk);
            src_start <= 1'b0;

            // Wait for completion with timeout
            timeout = 0;
            while (!src_done && timeout < (t_num_beats * 10 + 1000)) begin
                @(posedge aclk);
                timeout = timeout + 1;
            end

            // Wait for sink to receive all beats
            timeout = 0;
            while (snk_beat_count < t_num_beats && timeout < (t_num_beats * 10 + 1000)) begin
                @(posedge aclk);
                timeout = timeout + 1;
            end

            // Let pipeline drain
            repeat (20) @(posedge aclk);

            // Verify beat count
            if (snk_beat_count !== t_num_beats) begin
                $display("ERROR: Beat count mismatch. Expected %0d, got %0d",
                         t_num_beats, snk_beat_count);
                test_errors = test_errors + 1;
            end

            // Verify data
            for (idx = 0; idx < t_num_beats; idx = idx + 1) begin
                expected = ref_beat(t_mode, u_source.source_mem[idx],
                                   t_imm8, t_lo, t_hi);
                if (u_sink.sink_mem[idx] !== expected) begin
                    $display("ERROR: Beat %0d mismatch. Input=%h Expected=%h Got=%h",
                             idx, u_source.source_mem[idx], expected,
                             u_sink.sink_mem[idx]);
                    test_errors = test_errors + 1;
                    if (test_errors > 10) begin
                        $display("  ... suppressing further mismatch messages");
                        idx = t_num_beats;  // break
                    end
                end
            end

            // Verify TLAST on last beat
            if (t_num_beats > 0 && !u_sink.sink_last[t_num_beats-1]) begin
                $display("ERROR: TLAST not set on final beat");
                test_errors = test_errors + 1;
            end

            // Verify TKEEP
            for (idx = 0; idx < t_num_beats; idx = idx + 1) begin
                if (u_sink.sink_keep[idx] !== {N_LANES{1'b1}}) begin
                    $display("ERROR: TKEEP wrong at beat %0d: %h",
                             idx, u_sink.sink_keep[idx]);
                    test_errors = test_errors + 1;
                end
            end

            // Verify counters
            if (input_beats !== t_num_beats) begin
                $display("ERROR: input_beats counter = %0d, expected %0d",
                         input_beats, t_num_beats);
                test_errors = test_errors + 1;
            end
            if (output_beats !== t_num_beats) begin
                $display("ERROR: output_beats counter = %0d, expected %0d",
                         output_beats, t_num_beats);
                test_errors = test_errors + 1;
            end
            if (frame_count !== 32'd1) begin
                $display("ERROR: frame_count = %0d, expected 1", frame_count);
                test_errors = test_errors + 1;
            end

            // Check protocol violations
            if (protocol_errors > 0) begin
                $display("ERROR: %0d protocol violations detected", protocol_errors);
                test_errors = test_errors + protocol_errors;
            end

            // Disable sink and reset its counter for next test
            snk_enable <= 1'b0;
            enable     <= 1'b0;

            total_tests = total_tests + 1;
            if (test_errors == 0) begin
                total_pass = total_pass + 1;
            end else begin
                total_fail = total_fail + 1;
            end
        end
    endtask

    // Fill source memory with random data
    task fill_random;
        input [31:0] n_beats;
        input [31:0] seed;
        integer i;
        reg [31:0] r;
        begin
            r = seed;
            for (i = 0; i < n_beats; i = i + 1) begin
                r = r * 32'd1103515245 + 32'd12345;  // LCG
                u_source.source_mem[i][31:0]  = r;
                r = r * 32'd1103515245 + 32'd12345;
                u_source.source_mem[i][63:32] = r;
            end
        end
    endtask

    // Fill source memory with specific edge-case bytes
    task fill_edge_cases;
        input [31:0] beat_idx;
        begin
            // Pack critical INT8 values: -128, -127, -1, 0, 1, 126, 127, 42
            u_source.source_mem[beat_idx] = {8'd42, 8'h7F, 8'h7E, 8'h01,
                                              8'h00, 8'hFF, 8'h81, 8'h80};
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer test_idx;
    integer rand_seed;

    initial begin
        $display("============================================================");
        $display("ZynqFlow StreamOps Testbench");
        $display("============================================================");

        total_tests = 0;
        total_pass  = 0;
        total_fail  = 0;

        // ==================================================================
        // TEST 1: Reset while idle
        // ==================================================================
        $display("\n--- TEST 1: Reset while idle ---");
        reset_dut;
        if (m_axis_tvalid === 1'b0 && input_beats === 32'd0 &&
            output_beats === 32'd0) begin
            $display("PASS: Clean state after reset");
            total_tests = total_tests + 1;
            total_pass  = total_pass + 1;
        end else begin
            $display("FAIL: Not clean after reset");
            total_tests = total_tests + 1;
            total_fail  = total_fail + 1;
        end

        // ==================================================================
        // TEST 2: Single beat BYPASS (no gaps, no backpressure)
        // ==================================================================
        $display("\n--- TEST 2: Single beat BYPASS ---");
        reset_dut;
        u_source.source_mem[0] = 64'hDEADBEEF_CAFEBABE;
        run_transfer(MODE_BYPASS, 8'd0, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 2: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 3: Two beats BYPASS
        // ==================================================================
        $display("\n--- TEST 3: Two beats BYPASS ---");
        reset_dut;
        u_source.source_mem[0] = 64'h0102030405060708;
        u_source.source_mem[1] = 64'hF1F2F3F4F5F6F7F8;
        run_transfer(MODE_BYPASS, 8'd0, 8'd0, 8'd0, 32'd2,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 3: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 4: 1000 continuous beats BYPASS
        // ==================================================================
        $display("\n--- TEST 4: 1000 beats BYPASS (continuous) ---");
        reset_dut;
        fill_random(32'd1000, 32'd12345);
        run_transfer(MODE_BYPASS, 8'd0, 8'd0, 8'd0, 32'd1000,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 4: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 5: RELU with edge cases
        // ==================================================================
        $display("\n--- TEST 5: RELU edge cases ---");
        reset_dut;
        fill_edge_cases(32'd0);
        fill_random(32'd99, 32'd54321);
        // Copy random data starting at index 1 (edge case is at index 0)
        // Actually fill_random overwrites index 0. Let's fix:
        u_source.source_mem[0] = {8'd42, 8'h7F, 8'h7E, 8'h01,
                                   8'h00, 8'hFF, 8'h81, 8'h80};
        run_transfer(MODE_RELU, 8'd0, 8'd0, 8'd0, 32'd100,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 5: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 6: ADD_SAT positive overflow
        // ==================================================================
        $display("\n--- TEST 6: ADD_SAT positive overflow ---");
        reset_dut;
        // x=120, imm=50 -> should saturate to 127
        u_source.source_mem[0] = {8{8'h78}};  // 120 in all lanes
        run_transfer(MODE_ADD_SAT, 8'h32, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 6: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 7: ADD_SAT negative overflow
        // ==================================================================
        $display("\n--- TEST 7: ADD_SAT negative overflow ---");
        reset_dut;
        // x=-100 (0x9C), imm=-50 (0xCE) -> should saturate to -128
        u_source.source_mem[0] = {8{8'h9C}};
        run_transfer(MODE_ADD_SAT, 8'hCE, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 7: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 8: ABS of -128
        // ==================================================================
        $display("\n--- TEST 8: ABS of -128 ---");
        reset_dut;
        u_source.source_mem[0] = {8{8'h80}};  // -128 in all lanes
        run_transfer(MODE_ABS, 8'd0, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 8: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 9: CLAMP edge cases
        // ==================================================================
        $display("\n--- TEST 9: CLAMP edge cases ---");
        reset_dut;
        // Clamp to [-10, 10] with values spanning the range
        // Lanes: -128, -10, -5, 0, 5, 10, 100, 127
        u_source.source_mem[0] = {8'h7F, 8'h64, 8'h0A, 8'h05,
                                   8'h00, 8'hFB, 8'hF6, 8'h80};
        run_transfer(MODE_CLAMP, 8'd0, 8'hF6, 8'h0A, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 9: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 10: THRESHOLD at boundary
        // ==================================================================
        $display("\n--- TEST 10: THRESHOLD at boundary ---");
        reset_dut;
        // threshold = 0, values spanning negative/zero/positive
        u_source.source_mem[0] = {8'h7F, 8'h01, 8'h00, 8'hFF,
                                   8'hFE, 8'h80, 8'h02, 8'h03};
        run_transfer(MODE_THRESHOLD, 8'h00, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 10: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 11: XOR
        // ==================================================================
        $display("\n--- TEST 11: XOR ---");
        reset_dut;
        u_source.source_mem[0] = 64'hFF00AA5512345678;
        run_transfer(MODE_XOR, 8'hFF, 8'd0, 8'd0, 32'd1,
                     1'b0, 8'd0, 1'b0, 8'd0);
        $display("TEST 11: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 12: Random input gaps (RELU, 500 beats)
        // ==================================================================
        $display("\n--- TEST 12: Random input gaps ---");
        reset_dut;
        fill_random(32'd500, 32'd99999);
        run_transfer(MODE_RELU, 8'd0, 8'd0, 8'd0, 32'd500,
                     1'b1, 8'd80, 1'b0, 8'd0);
        $display("TEST 12: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 13: Random output backpressure (ADD_SAT, 500 beats)
        // ==================================================================
        $display("\n--- TEST 13: Random output backpressure ---");
        reset_dut;
        fill_random(32'd500, 32'd77777);
        run_transfer(MODE_ADD_SAT, 8'h0A, 8'd0, 8'd0, 32'd500,
                     1'b0, 8'd0, 1'b1, 8'd80);
        $display("TEST 13: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 14: Both gaps AND backpressure (CLAMP, 500 beats)
        // ==================================================================
        $display("\n--- TEST 14: Gaps + backpressure ---");
        reset_dut;
        fill_random(32'd500, 32'd55555);
        run_transfer(MODE_CLAMP, 8'd0, 8'hE0, 8'h20, 32'd500,
                     1'b1, 8'd60, 1'b1, 8'd60);
        $display("TEST 14: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 15: All modes, 200 beats each, with gaps+backpressure
        // ==================================================================
        $display("\n--- TEST 15: All modes sweep ---");
        for (test_idx = 0; test_idx < 7; test_idx = test_idx + 1) begin
            reset_dut;
            fill_random(32'd200, 32'd10000 + test_idx * 1000);
            $display("  Mode %0d...", test_idx);
            run_transfer(test_idx[2:0], 8'h05, 8'hF0, 8'h10, 32'd200,
                         1'b1, 8'd40, 1'b1, 8'd40);
        end
        $display("TEST 15: All modes complete");

        // ==================================================================
        // TEST 16: Large randomized regression (10,000 beats with stress)
        // ==================================================================
        $display("\n--- TEST 16: 10,000 beat randomized regression ---");
        reset_dut;
        fill_random(32'd10000, 32'd42);
        run_transfer(MODE_RELU, 8'd0, 8'd0, 8'd0, 32'd10000,
                     1'b1, 8'd50, 1'b1, 8'd50);
        $display("TEST 16: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // TEST 17: 10,000 beat ADD_SAT regression
        // ==================================================================
        $display("\n--- TEST 17: 10,000 beat ADD_SAT regression ---");
        reset_dut;
        fill_random(32'd10000, 32'd123456);
        run_transfer(MODE_ADD_SAT, 8'hFB, 8'd0, 8'd0, 32'd10000,
                     1'b1, 8'd30, 1'b1, 8'd30);
        $display("TEST 17: %s", (test_errors == 0) ? "PASS" : "FAIL");

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n============================================================");
        $display("TESTBENCH COMPLETE");
        $display("  Total tests:  %0d", total_tests);
        $display("  Passed:       %0d", total_pass);
        $display("  Failed:       %0d", total_fail);
        $display("============================================================");

        if (total_fail == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> %0d TESTS FAILED <<<", total_fail);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #100_000_000;  // 100 ms
        $display("ERROR: Global simulation timeout!");
        $finish;
    end

    // Note: VCD dump removed. Vivado xsim records waveforms natively.
    // To dump VCD for external viewers, uncomment:
    // initial begin
    //     $dumpfile("streamops.vcd");
    //     $dumpvars(0, tb_streamops);
    // end

endmodule
