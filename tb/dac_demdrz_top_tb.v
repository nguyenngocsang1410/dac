//-----------------------------------------------------------------------------
// dac_demdrz_top_tb.v -- self-checking testbench for dac_demdrz_top v2
//
// Test plan: verif/plans/dac_demdrz_top_testplan.md
// MAS:       docs/arch/dac_demdrz_top_mas.md
//
// Strategy:
//   * Cycle-accurate behavioral reference model built from the MAS (capture
//     equation, fmt XOR, 3x LFSR16 with rst > load > advance priority and
//     zero-write substitution, R = prn % 7 (independent of the RTL digit-sum
//     implementation), rotation, DRZ mux, output stage). DUT outputs are
//     compared bit-exactly against the model EVERY cycle of EVERY test.
//   * Independent invariant checkers every cycle: weighted-sum decode
//     (512/64/8/1), DRZ pattern exactness, sw_*_n === ~sw_*, data_req
//     equation, off-edge output-change monitor.
//   * Structural checks via hierarchical references (stated choice): LFSR
//     state and r_q of each segment vs the reference model, and the
//     never-zero LFSR assertion (REQ-015), every cycle.
//   * dut2: SEED_ULSB=16'h0000 override (CFG-002/C16) -> must be output-
//     identical to dut. dut3: three nonzero seed overrides (CFG-001) ->
//     LFSRs tracked by an override-seeded model instance.
//
// Inputs are driven at negedge+1ns (off the sampling edge); checks run at
// negedge (delta 0) so they observe the values that were valid at/after the
// preceding posedge. No races.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module dac_demdrz_top_tb;

    //-------------------------------------------------------------------------
    // Parameters / constants
    //-------------------------------------------------------------------------
    localparam [15:0] P_SEED_MSB  = 16'hACE1;
    localparam [15:0] P_SEED_ULSB = 16'h5EED;
    localparam [15:0] P_SEED_LSB  = 16'hB10D;
    // dut3 overrides (CFG-001)
    localparam [15:0] S3_MSB  = 16'h1357;
    localparam [15:0] S3_ULSB = 16'h7531;
    localparam [15:0] S3_LSB  = 16'h0F0F;

    localparam [6:0] DRZ_MSB = 7'b1010101;
    localparam [6:0] DRZ_LOW = 7'b0000000;

    //-------------------------------------------------------------------------
    // DUT I/O
    //-------------------------------------------------------------------------
    reg         clk;
    reg         rst;
    reg         dem_en;
    reg         drz_en;
    reg         fmt_sel;
    reg  [11:0] data_in;
    reg         seed_wr;
    reg  [1:0]  seed_addr;
    reg  [15:0] seed_wdata;

    wire        data_req;
    wire        phase;
    wire [6:0]  sw_msb,   sw_ulsb,   sw_lsb,   sw_llsb;
    wire [6:0]  sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n;

    // dut2 (zero ULSB seed parameter, CFG-002/C16)
    wire        d2_data_req, d2_phase;
    wire [6:0]  d2_sw_msb,   d2_sw_ulsb,   d2_sw_lsb,   d2_sw_llsb;
    wire [6:0]  d2_sw_msb_n, d2_sw_ulsb_n, d2_sw_lsb_n, d2_sw_llsb_n;

    // dut3 (nonzero seed overrides, CFG-001) - outputs only sunk
    wire        d3_data_req, d3_phase;
    wire [6:0]  d3_sw_msb,   d3_sw_ulsb,   d3_sw_lsb,   d3_sw_llsb;
    wire [6:0]  d3_sw_msb_n, d3_sw_ulsb_n, d3_sw_lsb_n, d3_sw_llsb_n;

    dac_demdrz_top dut (
        .clk(clk), .rst(rst), .dem_en(dem_en), .drz_en(drz_en),
        .fmt_sel(fmt_sel), .data_in(data_in),
        .seed_wr(seed_wr), .seed_addr(seed_addr), .seed_wdata(seed_wdata),
        .data_req(data_req), .phase(phase),
        .sw_msb(sw_msb), .sw_ulsb(sw_ulsb), .sw_lsb(sw_lsb), .sw_llsb(sw_llsb),
        .sw_msb_n(sw_msb_n), .sw_ulsb_n(sw_ulsb_n),
        .sw_lsb_n(sw_lsb_n), .sw_llsb_n(sw_llsb_n)
    );

    dac_demdrz_top #(.SEED_ULSB(16'h0000)) dut2 (
        .clk(clk), .rst(rst), .dem_en(dem_en), .drz_en(drz_en),
        .fmt_sel(fmt_sel), .data_in(data_in),
        .seed_wr(seed_wr), .seed_addr(seed_addr), .seed_wdata(seed_wdata),
        .data_req(d2_data_req), .phase(d2_phase),
        .sw_msb(d2_sw_msb), .sw_ulsb(d2_sw_ulsb),
        .sw_lsb(d2_sw_lsb), .sw_llsb(d2_sw_llsb),
        .sw_msb_n(d2_sw_msb_n), .sw_ulsb_n(d2_sw_ulsb_n),
        .sw_lsb_n(d2_sw_lsb_n), .sw_llsb_n(d2_sw_llsb_n)
    );

    dac_demdrz_top #(.SEED_MSB(S3_MSB), .SEED_ULSB(S3_ULSB), .SEED_LSB(S3_LSB)) dut3 (
        .clk(clk), .rst(rst), .dem_en(dem_en), .drz_en(drz_en),
        .fmt_sel(fmt_sel), .data_in(data_in),
        .seed_wr(seed_wr), .seed_addr(seed_addr), .seed_wdata(seed_wdata),
        .data_req(d3_data_req), .phase(d3_phase),
        .sw_msb(d3_sw_msb), .sw_ulsb(d3_sw_ulsb),
        .sw_lsb(d3_sw_lsb), .sw_llsb(d3_sw_llsb),
        .sw_msb_n(d3_sw_msb_n), .sw_ulsb_n(d3_sw_ulsb_n),
        .sw_lsb_n(d3_sw_lsb_n), .sw_llsb_n(d3_sw_llsb_n)
    );

    //-------------------------------------------------------------------------
    // Clock / watchdog / dump
    //-------------------------------------------------------------------------
    always #5 clk = ~clk;        // 100 MHz TB clock (frequency-agnostic RTL)

    initial begin
        #3_000_000;              // 300k cycles - generous
        $display("TIMEOUT");
        $display("TEST FAILED: WATCHDOG simulation did not finish");
        $finish;
    end

    initial begin
        $dumpfile("build/dac_demdrz_top.vcd");
        $dumpvars(0, dac_demdrz_top_tb);
    end

    //-------------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------------
    integer errors;
    integer n_tests, n_failed, err_at_start;
    integer n_chk_cycles, n_captures, n_sig_checked;
    reg [8*8:1] cur_test;
    reg         check_en;

    task test_begin (input [8*8:1] id);
        begin
            cur_test     = id;
            err_at_start = errors;
            $display("[%0s] start (t=%0t)", id, $time);
        end
    endtask

    task test_end;
        begin
            n_tests = n_tests + 1;
            if (errors == err_at_start)
                $display("[%0s] PASS", cur_test);
            else begin
                n_failed = n_failed + 1;
                $display("[%0s] FAIL (%0d errors)", cur_test, errors - err_at_start);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Reference-model helper functions (from the MAS, independent of RTL)
    //-------------------------------------------------------------------------
    function [6:0] f_b2t (input [2:0] b);
        integer i;
        begin
            for (i = 0; i < 7; i = i + 1)
                f_b2t[i] = (b > i);
        end
    endfunction

    // therm_out[(i+r) mod 7] = therm_in[i]
    function [6:0] f_rot (input [6:0] t, input [2:0] r);
        integer i;
        begin
            for (i = 0; i < 7; i = i + 1)
                f_rot[(i + r) % 7] = t[i];
        end
    endfunction

    function [2:0] f_mod7 (input [5:0] v);
        begin
            f_mod7 = v % 7;      // independent of the RTL digit-sum trick
        end
    endfunction

    // x^16 + x^14 + x^13 + x^11 + 1, Fibonacci, shift left
    function [15:0] f_lfsr_next (input [15:0] q);
        begin
            f_lfsr_next = {q[14:0], q[15] ^ q[13] ^ q[12] ^ q[10]};
        end
    endfunction

    function integer f_pop7 (input [6:0] v);
        integer i;
        begin
            f_pop7 = 0;
            for (i = 0; i < 7; i = i + 1)
                f_pop7 = f_pop7 + v[i];
        end
    endfunction

    function integer f_sum (input [6:0] m, input [6:0] u,
                            input [6:0] l, input [6:0] ll);
        begin
            f_sum = 512 * f_pop7(m) + 64 * f_pop7(u) + 8 * f_pop7(l) + f_pop7(ll);
        end
    endfunction

    function integer f_lfsr_period (input [15:0] seed);
        reg [15:0] s;
        integer    n;
        begin
            s = f_lfsr_next(seed);
            n = 1;
            while (s !== seed && n < 70000) begin
                s = f_lfsr_next(s);
                n = n + 1;
            end
            f_lfsr_period = n;
        end
    endfunction

    //-------------------------------------------------------------------------
    // Reference model state (mirrors MAS section 4, not the RTL text)
    //-------------------------------------------------------------------------
    reg         m_phase;
    reg  [11:0] m_data_q;
    reg  [15:0] m_lfsr_m, m_lfsr_u, m_lfsr_l;       // dut/dut2 effective seeds
    reg  [2:0]  m_r_m,    m_r_u,    m_r_l;
    reg         e_phase;
    reg  [6:0]  e_msb, e_ulsb, e_lsb, e_llsb;
    reg  [11:0] code_vis;                            // code carried by the
                                                     // output regs when phase=1
    // dut3 LFSR mirrors (overridden seeds, CFG-001)
    reg  [15:0] m3_lfsr_m, m3_lfsr_u, m3_lfsr_l;

    wire m_next_phase = drz_en ? ~m_phase : 1'b1;
    wire m_capture    = (~m_next_phase | ~drz_en) & ~rst;

    // R histograms (REQ-010, T-018)
    integer hist_m [0:6];
    integer hist_u [0:6];
    integer hist_l [0:6];
    integer hist_n;

    always @(posedge clk) begin
        if (rst) begin
            m_phase   <= 1'b0;
            m_data_q  <= 12'h000;
            m_lfsr_m  <= P_SEED_MSB;
            m_lfsr_u  <= P_SEED_ULSB;
            m_lfsr_l  <= P_SEED_LSB;
            m_r_m     <= 3'd0;
            m_r_u     <= 3'd0;
            m_r_l     <= 3'd0;
            e_phase   <= 1'b0;
            e_msb     <= DRZ_MSB;
            e_ulsb    <= DRZ_LOW;
            e_lsb     <= DRZ_LOW;
            e_llsb    <= DRZ_LOW;
            code_vis  <= 12'h000;
            m3_lfsr_m <= S3_MSB;
            m3_lfsr_u <= S3_ULSB;
            m3_lfsr_l <= S3_LSB;
        end else begin
            // FSM state + S1 output stage (reads pre-edge S0 state)
            m_phase <= m_next_phase;
            e_phase <= m_next_phase;
            e_msb   <= m_next_phase ? f_rot(f_b2t(m_data_q[11:9]), m_r_m) : DRZ_MSB;
            e_ulsb  <= m_next_phase ? f_rot(f_b2t(m_data_q[8:6]),  m_r_u) : DRZ_LOW;
            e_lsb   <= m_next_phase ? f_rot(f_b2t(m_data_q[5:3]),  m_r_l) : DRZ_LOW;
            e_llsb  <= m_next_phase ? f_b2t(m_data_q[2:0])                : DRZ_LOW;
            if (m_next_phase)
                code_vis <= m_data_q;

            // S0: capture register (fmt XOR in front, MAS 4.1.2)
            if (m_capture)
                m_data_q <= {data_in[11] ^ fmt_sel, data_in[10:0]};

            // LFSRs: priority load > advance (rst handled above), zero subst.
            if (seed_wr && seed_addr == 2'b00) begin
                m_lfsr_m  <= (seed_wdata == 16'h0000) ? P_SEED_MSB : seed_wdata;
                m3_lfsr_m <= (seed_wdata == 16'h0000) ? S3_MSB     : seed_wdata;
            end else if (m_capture) begin
                m_lfsr_m  <= f_lfsr_next(m_lfsr_m);
                m3_lfsr_m <= f_lfsr_next(m3_lfsr_m);
            end
            if (seed_wr && seed_addr == 2'b01) begin
                m_lfsr_u  <= (seed_wdata == 16'h0000) ? P_SEED_ULSB : seed_wdata;
                m3_lfsr_u <= (seed_wdata == 16'h0000) ? S3_ULSB     : seed_wdata;
            end else if (m_capture) begin
                m_lfsr_u  <= f_lfsr_next(m_lfsr_u);
                m3_lfsr_u <= f_lfsr_next(m3_lfsr_u);
            end
            if (seed_wr && seed_addr == 2'b10) begin
                m_lfsr_l  <= (seed_wdata == 16'h0000) ? P_SEED_LSB : seed_wdata;
                m3_lfsr_l <= (seed_wdata == 16'h0000) ? S3_LSB     : seed_wdata;
            end else if (m_capture) begin
                m_lfsr_l  <= f_lfsr_next(m_lfsr_l);
                m3_lfsr_l <= f_lfsr_next(m3_lfsr_l);
            end

            // R registers: update once per capture, from pre-edge PRN
            // (collision: pre-write PRN, MAS D8/M5 - nonblocking gives this)
            if (m_capture) begin
                m_r_m <= dem_en ? f_mod7(m_lfsr_m[5:0]) : 3'd0;
                m_r_u <= dem_en ? f_mod7(m_lfsr_u[5:0]) : 3'd0;
                m_r_l <= dem_en ? f_mod7(m_lfsr_l[5:0]) : 3'd0;
                if (dem_en) begin
                    hist_m[f_mod7(m_lfsr_m[5:0])] = hist_m[f_mod7(m_lfsr_m[5:0])] + 1;
                    hist_u[f_mod7(m_lfsr_u[5:0])] = hist_u[f_mod7(m_lfsr_u[5:0])] + 1;
                    hist_l[f_mod7(m_lfsr_l[5:0])] = hist_l[f_mod7(m_lfsr_l[5:0])] + 1;
                    hist_n = hist_n + 1;
                end
                n_captures = n_captures + 1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // CHK-08: outputs change only at rising clk edges (REQ-028, REQ-020 part)
    //-------------------------------------------------------------------------
    time t_pos;
    initial t_pos = 0;
    always @(posedge clk) t_pos = $time;

    always @(phase or sw_msb or sw_ulsb or sw_lsb or sw_llsb or
             sw_msb_n or sw_ulsb_n or sw_lsb_n or sw_llsb_n) begin
        if (check_en && ($time != t_pos)) begin
            errors = errors + 1;
            $display("TEST FAILED: %0s CHK-08 output changed off posedge expected=stable actual=event t=%0t",
                     cur_test, $time);
        end
    end

    //-------------------------------------------------------------------------
    // Per-cycle checkers (sample at negedge, delta 0 - before stimulus moves)
    //-------------------------------------------------------------------------
    integer got_sum;
    integer tp_en, tp_cyc, tp_req;

    always @(negedge clk) if (check_en) begin
        n_chk_cycles = n_chk_cycles + 1;

        // CHK-02: complement rail (REQ-019, C11)
        if ({sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n}
            !== ~{sw_msb, sw_ulsb, sw_lsb, sw_llsb}) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-02 sw_*_n not complement expected=%b actual=%b t=%0t",
                         cur_test, ~{sw_msb, sw_ulsb, sw_lsb, sw_llsb},
                         {sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n}, $time);
        end

        // CHK-01: bit-exact model compare (REQ-001..004/009/021..024/026/029)
        if (phase !== e_phase) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-01 phase mismatch expected=%b actual=%b t=%0t",
                         cur_test, e_phase, phase, $time);
        end
        if ({sw_msb, sw_ulsb, sw_lsb, sw_llsb} !== {e_msb, e_ulsb, e_lsb, e_llsb}) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-01 sw mismatch expected=%b_%b_%b_%b actual=%b_%b_%b_%b t=%0t",
                         cur_test, e_msb, e_ulsb, e_lsb, e_llsb,
                         sw_msb, sw_ulsb, sw_lsb, sw_llsb, $time);
        end

        // CHK-03 / CHK-04: weighted sum on signal phases, DRZ pattern else
        if (phase === 1'b1) begin
            got_sum = f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb);
            n_sig_checked = n_sig_checked + 1;
            if (got_sum !== code_vis) begin
                errors = errors + 1;
                if (errors <= 100)
                    $display("TEST FAILED: %0s CHK-03 signal-phase sum expected=%0d actual=%0d t=%0t",
                             cur_test, code_vis, got_sum, $time);
            end
        end else begin
            if ({sw_msb, sw_ulsb, sw_lsb, sw_llsb} !== {DRZ_MSB, 21'b0}) begin
                errors = errors + 1;
                if (errors <= 100)
                    $display("TEST FAILED: %0s CHK-04 DRZ pattern expected=%b_0_0_0 actual=%b_%b_%b_%b t=%0t",
                             cur_test, DRZ_MSB, sw_msb, sw_ulsb, sw_lsb, sw_llsb, $time);
            end
        end

        // CHK-05: data_req equation (REQ-025)
        if (data_req !== m_capture) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-05 data_req expected=%b actual=%b t=%0t",
                         cur_test, m_capture, data_req, $time);
        end

        // CHK-06: LFSR state vs reference + never zero (REQ-011/013/015, C18)
        if (dut.u_dem_msb.u_lfsr.lfsr_q !== m_lfsr_m
            || dut.u_dem_ulsb.u_lfsr.lfsr_q !== m_lfsr_u
            || dut.u_dem_lsb.u_lfsr.lfsr_q !== m_lfsr_l) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-06 lfsr state expected=%h/%h/%h actual=%h/%h/%h t=%0t",
                         cur_test, m_lfsr_m, m_lfsr_u, m_lfsr_l,
                         dut.u_dem_msb.u_lfsr.lfsr_q, dut.u_dem_ulsb.u_lfsr.lfsr_q,
                         dut.u_dem_lsb.u_lfsr.lfsr_q, $time);
        end
        if (dut.u_dem_msb.u_lfsr.lfsr_q  === 16'h0000
            || dut.u_dem_ulsb.u_lfsr.lfsr_q === 16'h0000
            || dut.u_dem_lsb.u_lfsr.lfsr_q  === 16'h0000) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-06 LFSR lock-up expected=nonzero actual=0000 t=%0t",
                         cur_test, $time);
        end

        // CHK-07: r_q vs reference (REQ-010 update/stability)
        if (dut.u_dem_msb.r_q !== m_r_m || dut.u_dem_ulsb.r_q !== m_r_u
            || dut.u_dem_lsb.r_q !== m_r_l) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-07 r_q expected=%0d/%0d/%0d actual=%0d/%0d/%0d t=%0t",
                         cur_test, m_r_m, m_r_u, m_r_l,
                         dut.u_dem_msb.r_q, dut.u_dem_ulsb.r_q, dut.u_dem_lsb.r_q, $time);
        end

        // CHK-09: dut2 (zero ULSB seed param) identical to dut; dut3 mirrors
        if ({d2_data_req, d2_phase, d2_sw_msb, d2_sw_ulsb, d2_sw_lsb, d2_sw_llsb,
             d2_sw_msb_n, d2_sw_ulsb_n, d2_sw_lsb_n, d2_sw_llsb_n}
            !== {data_req, phase, sw_msb, sw_ulsb, sw_lsb, sw_llsb,
                 sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n}) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-09 dut2(SEED_ULSB=0) diverges from dut expected=identical actual=mismatch t=%0t",
                         cur_test, $time);
        end
        if (dut2.u_dem_ulsb.u_lfsr.lfsr_q !== m_lfsr_u
            || dut2.u_dem_ulsb.u_lfsr.lfsr_q === 16'h0000) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-09 dut2 ULSB lfsr expected=%h actual=%h t=%0t",
                         cur_test, m_lfsr_u, dut2.u_dem_ulsb.u_lfsr.lfsr_q, $time);
        end
        if (dut3.u_dem_msb.u_lfsr.lfsr_q !== m3_lfsr_m
            || dut3.u_dem_ulsb.u_lfsr.lfsr_q !== m3_lfsr_u
            || dut3.u_dem_lsb.u_lfsr.lfsr_q !== m3_lfsr_l
            || dut3.u_dem_msb.u_lfsr.lfsr_q === 16'h0000
            || dut3.u_dem_ulsb.u_lfsr.lfsr_q === 16'h0000
            || dut3.u_dem_lsb.u_lfsr.lfsr_q === 16'h0000) begin
            errors = errors + 1;
            if (errors <= 100)
                $display("TEST FAILED: %0s CHK-09 dut3 override lfsr expected=%h/%h/%h actual=%h/%h/%h t=%0t",
                         cur_test, m3_lfsr_m, m3_lfsr_u, m3_lfsr_l,
                         dut3.u_dem_msb.u_lfsr.lfsr_q, dut3.u_dem_ulsb.u_lfsr.lfsr_q,
                         dut3.u_dem_lsb.u_lfsr.lfsr_q, $time);
        end

        // throughput window counters (PERF-001/002)
        if (tp_en == 1) begin
            tp_cyc = tp_cyc + 1;
            if (data_req === 1'b1)
                tp_req = tp_req + 1;
        end
    end

    //-------------------------------------------------------------------------
    // Stimulus tasks (all driving at negedge + 1ns)
    //-------------------------------------------------------------------------
    task run_cycles (input integer n);     // random data every cycle
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk); #1;
                data_in = $random;
            end
        end
    endtask

    task run_ramp;                          // full-code ramp at capture cycles
        integer i;
        begin
            i = 0;
            while (i < 4096) begin
                @(negedge clk); #1;
                if (data_req === 1'b1) begin
                    data_in = i[11:0];
                    i = i + 1;
                end else begin
                    data_in = $random;
                end
            end
        end
    endtask

    // NRZ directed code: drive, then check plain-thermometer outputs (dem off)
    task nrz_dir_check (input [11:0] code, input check_therm);
        begin
            @(negedge clk); #1; data_in = code;
            @(negedge clk); #1; data_in = $random;
            @(negedge clk); #2;
            if (check_therm &&
                ({sw_msb, sw_ulsb, sw_lsb, sw_llsb}
                 !== {f_b2t(code[11:9]), f_b2t(code[8:6]),
                      f_b2t(code[5:3]),  f_b2t(code[2:0])})) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s thermometer code=%h expected=%b_%b_%b_%b actual=%b_%b_%b_%b t=%0t",
                         cur_test, code, f_b2t(code[11:9]), f_b2t(code[8:6]),
                         f_b2t(code[5:3]), f_b2t(code[2:0]),
                         sw_msb, sw_ulsb, sw_lsb, sw_llsb, $time);
            end
            if (f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb) !== code) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s directed sum code=%h expected=%0d actual=%0d t=%0t",
                         cur_test, code, code,
                         f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb), $time);
            end
        end
    endtask

    // NRZ two's-complement directed: drive din, expect weighted sum expsum
    task tc_check (input [11:0] din, input integer expsum);
        begin
            @(negedge clk); #1; data_in = din;
            @(negedge clk); #1; data_in = $random;
            @(negedge clk); #2;
            if (f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb) !== expsum) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s 2s-comp din=%h expected=%0d actual=%0d t=%0t",
                         cur_test, din, expsum,
                         f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb), $time);
            end
        end
    endtask

    // DRZ-mode capture with given fmt_sel; fmt toggled during the
    // non-capture cycle to prove the in-flight sample is unaffected (C6)
    task drz_cap_check (input [11:0] din, input fsel, input integer expsum);
        begin
            @(negedge clk); #1;
            while (data_req !== 1'b1) begin @(negedge clk); #1; end
            data_in = din;
            fmt_sel = fsel;
            @(posedge clk);                 // capture edge
            @(negedge clk); #1;
            fmt_sel = ~fsel;                // toggle in non-capture cycle
            data_in = $random;
            @(posedge clk);                 // signal-latch edge
            @(negedge clk); #2;
            if (phase !== 1'b1) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s drz_cap phase expected=1 actual=%b t=%0t",
                         cur_test, phase, $time);
            end
            if (f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb) !== expsum) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s fmt per-capture din=%h fsel=%b expected=%0d actual=%0d t=%0t",
                         cur_test, din, fsel, expsum,
                         f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb), $time);
            end
            fmt_sel = 1'b0;
        end
    endtask

    task tp_begin;
        begin
            @(negedge clk); #1;
            tp_cyc = 0; tp_req = 0; tp_en = 1;
        end
    endtask

    task tp_end_drz;        // expect 1 capture per 2 cycles (PERF-001)
        begin
            @(negedge clk); #1; tp_en = 0;
            if ((2 * tp_req > tp_cyc + 2) || (2 * tp_req < tp_cyc - 2)) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s PERF-001 DRZ throughput expected=%0d actual=%0d (cycles=%0d)",
                         cur_test, tp_cyc / 2, tp_req, tp_cyc);
            end
        end
    endtask

    task tp_end_nrz;        // expect 1 capture per cycle (PERF-002)
        begin
            @(negedge clk); #1; tp_en = 0;
            if (tp_req !== tp_cyc) begin
                errors = errors + 1;
                $display("TEST FAILED: %0s PERF-002 NRZ throughput expected=%0d actual=%0d",
                         cur_test, tp_cyc, tp_req);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Main sequence
    //-------------------------------------------------------------------------
    integer i, k, per;
    reg [15:0] pre_u, snap_m, snap_u, snap_l;
    reg [20:0] prev21;
    integer    ndiff;
    integer    hist_lo, hist_hi;
    reg [11:0] v;

    initial begin
        clk        = 1'b0;
        rst        = 1'b0;
        dem_en     = 1'b1;
        drz_en     = 1'b1;
        fmt_sel    = 1'b0;
        data_in    = 12'h000;
        seed_wr    = 1'b0;
        seed_addr  = 2'b00;
        seed_wdata = 16'h0000;
        errors     = 0;
        n_tests    = 0;
        n_failed   = 0;
        check_en   = 0;
        tp_en      = 0; tp_cyc = 0; tp_req = 0;
        n_chk_cycles = 0; n_captures = 0; n_sig_checked = 0;
        hist_n     = 0;
        cur_test   = "INIT";
        for (k = 0; k < 7; k = k + 1) begin
            hist_m[k] = 0; hist_u[k] = 0; hist_l[k] = 0;
        end

        //---------------------------------------------------------------------
        // T-020: LFSR maximal-length software-model check (REQ-011)
        //---------------------------------------------------------------------
        test_begin("T-020");
        per = f_lfsr_period(P_SEED_MSB);
        if (per !== 65535) begin
            errors = errors + 1;
            $display("TEST FAILED: T-020 period(seed=%h) expected=65535 actual=%0d", P_SEED_MSB, per);
        end
        per = f_lfsr_period(P_SEED_ULSB);
        if (per !== 65535) begin
            errors = errors + 1;
            $display("TEST FAILED: T-020 period(seed=%h) expected=65535 actual=%0d", P_SEED_ULSB, per);
        end
        per = f_lfsr_period(P_SEED_LSB);
        if (per !== 65535) begin
            errors = errors + 1;
            $display("TEST FAILED: T-020 period(seed=%h) expected=65535 actual=%0d", P_SEED_LSB, per);
        end
        test_end;

        //---------------------------------------------------------------------
        // T-001: reset state and release sequence (REQ-029, C10)
        //---------------------------------------------------------------------
        test_begin("T-001");
        @(negedge clk); #1; rst = 1;
        @(negedge clk); #1; check_en = 1;       // 1 reset edge has occurred
        repeat (2) @(negedge clk);
        #2;
        // explicit reset-state checks (independent of the model)
        if (phase !== 1'b0) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset phase expected=0 actual=%b", phase);
        end
        if ({sw_msb, sw_ulsb, sw_lsb, sw_llsb} !== {DRZ_MSB, 21'b0}) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset sw expected=%b_0_0_0 actual=%b_%b_%b_%b",
                     DRZ_MSB, sw_msb, sw_ulsb, sw_lsb, sw_llsb);
        end
        if ({sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n}
            !== {~DRZ_MSB, ~DRZ_LOW, ~DRZ_LOW, ~DRZ_LOW}) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset sw_n expected=%b_%b_%b_%b actual=%b_%b_%b_%b",
                     ~DRZ_MSB, ~DRZ_LOW, ~DRZ_LOW, ~DRZ_LOW,
                     sw_msb_n, sw_ulsb_n, sw_lsb_n, sw_llsb_n);
        end
        if (data_req !== 1'b0) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset data_req expected=0 actual=%b", data_req);
        end
        if (dut.u_dem_msb.u_lfsr.lfsr_q  !== P_SEED_MSB
            || dut.u_dem_ulsb.u_lfsr.lfsr_q !== P_SEED_ULSB
            || dut.u_dem_lsb.u_lfsr.lfsr_q  !== P_SEED_LSB) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset seeds expected=%h/%h/%h actual=%h/%h/%h",
                     P_SEED_MSB, P_SEED_ULSB, P_SEED_LSB,
                     dut.u_dem_msb.u_lfsr.lfsr_q, dut.u_dem_ulsb.u_lfsr.lfsr_q,
                     dut.u_dem_lsb.u_lfsr.lfsr_q);
        end
        if (dut3.u_dem_msb.u_lfsr.lfsr_q !== S3_MSB
            || dut3.u_dem_ulsb.u_lfsr.lfsr_q !== S3_ULSB
            || dut3.u_dem_lsb.u_lfsr.lfsr_q !== S3_LSB) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 dut3 override seeds expected=%h/%h/%h actual=%h/%h/%h",
                     S3_MSB, S3_ULSB, S3_LSB,
                     dut3.u_dem_msb.u_lfsr.lfsr_q, dut3.u_dem_ulsb.u_lfsr.lfsr_q,
                     dut3.u_dem_lsb.u_lfsr.lfsr_q);
        end
        if (dut.u_dem_msb.r_q !== 3'd0) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 reset r_q expected=0 actual=%0d", dut.u_dem_msb.r_q);
        end
        // release and follow MAS section 3 sequence (drz_en=1)
        @(negedge clk); #1; rst = 0; data_in = 12'hABC;
        @(negedge clk); #2;
        if (phase !== 1'b1) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 post-release phase expected=1 actual=%b", phase);
        end
        if ({sw_msb, sw_ulsb, sw_lsb, sw_llsb} !== 28'b0) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 first signal phase expected=all-off actual=%b_%b_%b_%b",
                     sw_msb, sw_ulsb, sw_lsb, sw_llsb);
        end
        if (data_req !== 1'b1) begin
            errors = errors + 1;
            $display("TEST FAILED: T-001 post-release data_req expected=1 actual=%b", data_req);
        end
        test_end;

        //---------------------------------------------------------------------
        // T-002: DEMDRZ streaming, random + full ramp (REQ-003/021/024)
        //---------------------------------------------------------------------
        test_begin("T-002");
        dem_en = 1; drz_en = 1; fmt_sel = 0;
        tp_begin;
        run_cycles(6000);
        tp_end_drz;
        run_ramp;
        test_end;

        //---------------------------------------------------------------------
        // T-003: DRZ-only (dem off) (REQ-004/024)
        //---------------------------------------------------------------------
        test_begin("T-003");
        @(negedge clk); #1; dem_en = 0;
        run_cycles(4000);
        test_end;

        //---------------------------------------------------------------------
        // T-004: NRZ+DEM back-to-back (REQ-023, PERF-002, C12)
        //---------------------------------------------------------------------
        test_begin("T-004");
        @(negedge clk); #1; dem_en = 1; drz_en = 0;
        tp_begin;
        run_cycles(4000);
        tp_end_nrz;
        test_end;

        //---------------------------------------------------------------------
        // T-005: plain NRZ (REQ-004/023/024)
        //---------------------------------------------------------------------
        test_begin("T-005");
        @(negedge clk); #1; dem_en = 0;
        run_cycles(2000);
        test_end;

        //---------------------------------------------------------------------
        // T-006: directed segmentation / thermometer (REQ-001/002/004)
        //---------------------------------------------------------------------
        test_begin("T-006");                 // still dem=0, drz=0
        nrz_dir_check(12'h000, 1);
        nrz_dir_check(12'hFFF, 1);
        nrz_dir_check({3'd1, 3'd2, 3'd3, 3'd4}, 1);   // 12'h29C
        nrz_dir_check({3'd7, 3'd0, 3'd5, 3'd2}, 1);   // 12'hE2A
        nrz_dir_check({3'd4, 3'd4, 3'd4, 3'd4}, 1);   // 12'h924
        nrz_dir_check(12'h800, 1);
        nrz_dir_check(12'h7FF, 1);
        nrz_dir_check(12'h200, 1);
        nrz_dir_check(12'h040, 1);
        nrz_dir_check(12'h008, 1);
        nrz_dir_check(12'h001, 1);
        test_end;

        //---------------------------------------------------------------------
        // T-007: two's-complement mapping (REQ-005/006/007, C7)
        //---------------------------------------------------------------------
        test_begin("T-007");                 // NRZ, dem=0 (sum is mode-blind)
        @(negedge clk); #1; fmt_sel = 1;
        tc_check(12'h800, 0);                // -2048 -> code 0
        tc_check(12'h7FF, 4095);             // +2047 -> code 4095
        tc_check(12'h000, 2048);             //     0 -> code 2048
        tc_check(12'hFFF, 2047);             //    -1 -> code 2047
        for (i = 0; i < 200; i = i + 1) begin
            v = $random;
            tc_check(v, {~v[11], v[10:0]});  // sum-identical to OB v+2048
        end
        @(negedge clk); #1; fmt_sel = 0;
        test_end;

        //---------------------------------------------------------------------
        // T-008: fmt_sel per-capture semantics (REQ-008, C6)
        //---------------------------------------------------------------------
        test_begin("T-008");
        @(negedge clk); #1; dem_en = 1; drz_en = 1;
        run_cycles(6);
        drz_cap_check(12'h800, 1'b0, 2048);  // OB: midscale
        drz_cap_check(12'h800, 1'b1, 0);     // TC: -2048 -> 0
        drz_cap_check(12'h000, 1'b1, 2048);  // TC: 0 -> midscale
        drz_cap_check(12'h7FF, 1'b1, 4095);  // TC: +2047 -> full scale
        test_end;

        //---------------------------------------------------------------------
        // T-009: seed write at a non-capture edge (REQ-012/013/017, C1)
        //---------------------------------------------------------------------
        test_begin("T-009");                 // dem=1, drz=1
        @(negedge clk); #1;
        while (data_req !== 1'b0) begin @(negedge clk); #1; end
        seed_wr = 1; seed_addr = 2'b00; seed_wdata = 16'h1234;
        @(negedge clk); #1; seed_wr = 0;
        #1;
        if (dut.u_dem_msb.u_lfsr.lfsr_q !== 16'h1234) begin
            errors = errors + 1;
            $display("TEST FAILED: T-009 lfsr after write expected=1234 actual=%h",
                     dut.u_dem_msb.u_lfsr.lfsr_q);
        end
        run_cycles(40);                      // R sequence from 16'h1234 (CHK-07)
        test_end;

        //---------------------------------------------------------------------
        // T-010: write/advance collision, write wins (REQ-013, C2, A4/D8)
        //---------------------------------------------------------------------
        test_begin("T-010");                 // dem=1, drz=1
        @(negedge clk); #1;
        while (data_req !== 1'b1) begin @(negedge clk); #1; end
        pre_u = dut.u_dem_ulsb.u_lfsr.lfsr_q;
        seed_wr = 1; seed_addr = 2'b01; seed_wdata = 16'hBEEF;
        @(negedge clk); #1; seed_wr = 0;
        #1;
        if (dut.u_dem_ulsb.u_lfsr.lfsr_q !== 16'hBEEF) begin
            errors = errors + 1;
            $display("TEST FAILED: T-010 collision write expected=beef actual=%h",
                     dut.u_dem_ulsb.u_lfsr.lfsr_q);
        end
        if (dut.u_dem_ulsb.r_q !== f_mod7(pre_u[5:0])) begin
            errors = errors + 1;
            $display("TEST FAILED: T-010 colliding-sample R expected=%0d actual=%0d (pre-write prn=%h)",
                     f_mod7(pre_u[5:0]), dut.u_dem_ulsb.r_q, pre_u);
        end
        run_cycles(40);
        test_end;

        //---------------------------------------------------------------------
        // T-011: zero-seed write -> parameter seed (REQ-015/016, C3)
        //---------------------------------------------------------------------
        test_begin("T-011");
        @(negedge clk); #1;
        while (data_req !== 1'b0) begin @(negedge clk); #1; end
        seed_wr = 1; seed_addr = 2'b10; seed_wdata = 16'h0000;
        @(negedge clk); #1; seed_wr = 0;
        #1;
        if (dut.u_dem_lsb.u_lfsr.lfsr_q !== P_SEED_LSB) begin
            errors = errors + 1;
            $display("TEST FAILED: T-011 zero write expected=%h actual=%h",
                     P_SEED_LSB, dut.u_dem_lsb.u_lfsr.lfsr_q);
        end
        run_cycles(20);
        test_end;

        //---------------------------------------------------------------------
        // T-012: reserved address write is a no-op (REQ-018, C4)
        //---------------------------------------------------------------------
        test_begin("T-012");
        @(negedge clk); #1;
        while (data_req !== 1'b0) begin @(negedge clk); #1; end
        snap_m = dut.u_dem_msb.u_lfsr.lfsr_q;
        snap_u = dut.u_dem_ulsb.u_lfsr.lfsr_q;
        snap_l = dut.u_dem_lsb.u_lfsr.lfsr_q;
        seed_wr = 1; seed_addr = 2'b11; seed_wdata = 16'hDEAD;
        @(negedge clk); #1; seed_wr = 0;
        #1;
        if (dut.u_dem_msb.u_lfsr.lfsr_q !== snap_m
            || dut.u_dem_ulsb.u_lfsr.lfsr_q !== snap_u
            || dut.u_dem_lsb.u_lfsr.lfsr_q !== snap_l) begin
            errors = errors + 1;
            $display("TEST FAILED: T-012 reserved-addr write changed state expected=%h/%h/%h actual=%h/%h/%h",
                     snap_m, snap_u, snap_l,
                     dut.u_dem_msb.u_lfsr.lfsr_q, dut.u_dem_ulsb.u_lfsr.lfsr_q,
                     dut.u_dem_lsb.u_lfsr.lfsr_q);
        end
        run_cycles(10);
        test_end;

        //---------------------------------------------------------------------
        // T-013: back-to-back / held / random write soak (PERF-004, C5)
        //---------------------------------------------------------------------
        test_begin("T-013");
        // (a) strobe held high: LFSR pinned to written value
        @(negedge clk); #1; seed_wr = 1; seed_addr = 2'b00; seed_wdata = 16'h7777;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk); #1; data_in = $random;
            if (dut.u_dem_msb.u_lfsr.lfsr_q !== 16'h7777) begin
                errors = errors + 1;
                $display("TEST FAILED: T-013 held strobe pin expected=7777 actual=%h t=%0t",
                         dut.u_dem_msb.u_lfsr.lfsr_q, $time);
            end
        end
        // (b) back-to-back writes to the three segments on consecutive cycles
        seed_addr = 2'b00; seed_wdata = 16'h1111;
        @(negedge clk); #1;
        if (dut.u_dem_msb.u_lfsr.lfsr_q !== 16'h1111) begin
            errors = errors + 1;
            $display("TEST FAILED: T-013 b2b MSB write expected=1111 actual=%h",
                     dut.u_dem_msb.u_lfsr.lfsr_q);
        end
        seed_addr = 2'b01; seed_wdata = 16'h2222;
        @(negedge clk); #1;
        if (dut.u_dem_ulsb.u_lfsr.lfsr_q !== 16'h2222) begin
            errors = errors + 1;
            $display("TEST FAILED: T-013 b2b ULSB write expected=2222 actual=%h",
                     dut.u_dem_ulsb.u_lfsr.lfsr_q);
        end
        seed_addr = 2'b10; seed_wdata = 16'h3333;
        @(negedge clk); #1;
        if (dut.u_dem_lsb.u_lfsr.lfsr_q !== 16'h3333) begin
            errors = errors + 1;
            $display("TEST FAILED: T-013 b2b LSB write expected=3333 actual=%h",
                     dut.u_dem_lsb.u_lfsr.lfsr_q);
        end
        seed_wr = 0;
        // (c) random write soak during DEMDRZ streaming (REQ-016/017/018)
        for (i = 0; i < 400; i = i + 1) begin
            @(negedge clk); #1;
            data_in    = $random;
            seed_wr    = (($random & 3) == 0);
            seed_addr  = $random;                       // includes 2'b11
            seed_wdata = (($random & 7) == 0) ? 16'h0000 : $random;
        end
        @(negedge clk); #1; seed_wr = 0;
        test_end;

        //---------------------------------------------------------------------
        // T-014: write during reset; reset restores parameter seeds (REQ-014)
        //---------------------------------------------------------------------
        test_begin("T-014");
        @(negedge clk); #1; rst = 1; seed_wr = 1; seed_addr = 2'b00; seed_wdata = 16'h5555;
        repeat (2) @(negedge clk);
        #2;
        if (dut.u_dem_msb.u_lfsr.lfsr_q  !== P_SEED_MSB
            || dut.u_dem_ulsb.u_lfsr.lfsr_q !== P_SEED_ULSB
            || dut.u_dem_lsb.u_lfsr.lfsr_q  !== P_SEED_LSB) begin
            errors = errors + 1;
            $display("TEST FAILED: T-014 reset-over-write expected=%h/%h/%h actual=%h/%h/%h",
                     P_SEED_MSB, P_SEED_ULSB, P_SEED_LSB,
                     dut.u_dem_msb.u_lfsr.lfsr_q, dut.u_dem_ulsb.u_lfsr.lfsr_q,
                     dut.u_dem_lsb.u_lfsr.lfsr_q);
        end
        @(negedge clk); #1; rst = 0; seed_wr = 0;
        run_cycles(10);
        test_end;

        //---------------------------------------------------------------------
        // T-015: dem_en toggles mid-stream (C8)
        //---------------------------------------------------------------------
        test_begin("T-015");                 // drz=1
        for (i = 0; i < 6; i = i + 1) begin
            run_cycles(37);
            @(negedge clk); #1; dem_en = ~dem_en;
        end
        @(negedge clk); #1; dem_en = 1;
        test_end;

        //---------------------------------------------------------------------
        // T-016: drz_en toggles mid-stream (C9)
        //---------------------------------------------------------------------
        test_begin("T-016");
        for (i = 0; i < 6; i = i + 1) begin
            run_cycles(23);
            @(negedge clk); #1; drz_en = ~drz_en;
        end
        @(negedge clk); #1; drz_en = 1;
        run_cycles(10);
        test_end;

        //---------------------------------------------------------------------
        // T-017: rotation-invariant codes + DEM variability (REQ-009, C13)
        //---------------------------------------------------------------------
        test_begin("T-017");
        @(negedge clk); #1; dem_en = 1; drz_en = 0;
        run_cycles(4);
        nrz_dir_check(12'h000, 1);           // all-off regardless of R
        nrz_dir_check(12'hFFF, 1);           // all-on regardless of R
        ndiff  = 0;
        prev21 = 21'h0;
        for (i = 0; i < 60; i = i + 1) begin
            @(negedge clk); #1; data_in = 12'h924;   // segment code 4 everywhere
            if (i > 3) begin
                if (sw_llsb !== 7'b0001111) begin
                    errors = errors + 1;
                    $display("TEST FAILED: T-017 LLSB must stay plain thermometer expected=0001111 actual=%b t=%0t",
                             sw_llsb, $time);
                end
                if ({sw_msb, sw_ulsb, sw_lsb} !== prev21)
                    ndiff = ndiff + 1;
            end
            prev21 = {sw_msb, sw_ulsb, sw_lsb};
        end
        if (ndiff < 2) begin
            errors = errors + 1;
            $display("TEST FAILED: T-017 DEM selection never varied expected>=2 actual=%0d", ndiff);
        end
        test_end;

        //---------------------------------------------------------------------
        // T-018: R uniformity histogram (REQ-010)
        //---------------------------------------------------------------------
        test_begin("T-018");                 // NRZ+DEM, fast capture rate
        @(negedge clk); #1; dem_en = 1; drz_en = 0;
        hist_n = 0;
        for (k = 0; k < 7; k = k + 1) begin
            hist_m[k] = 0; hist_u[k] = 0; hist_l[k] = 0;
        end
        run_cycles(14000);
        hist_lo = (hist_n / 7) * 85  / 100;
        hist_hi = (hist_n / 7) * 115 / 100;
        for (k = 0; k < 7; k = k + 1) begin
            if (hist_m[k] < hist_lo || hist_m[k] > hist_hi) begin
                errors = errors + 1;
                $display("TEST FAILED: T-018 MSB R=%0d count expected=%0d..%0d actual=%0d",
                         k, hist_lo, hist_hi, hist_m[k]);
            end
            if (hist_u[k] < hist_lo || hist_u[k] > hist_hi) begin
                errors = errors + 1;
                $display("TEST FAILED: T-018 ULSB R=%0d count expected=%0d..%0d actual=%0d",
                         k, hist_lo, hist_hi, hist_u[k]);
            end
            if (hist_l[k] < hist_lo || hist_l[k] > hist_hi) begin
                errors = errors + 1;
                $display("TEST FAILED: T-018 LSB R=%0d count expected=%0d..%0d actual=%0d",
                         k, hist_lo, hist_hi, hist_l[k]);
            end
        end
        $display("[T-018] R samples per segment: %0d (bound %0d..%0d per bin)",
                 hist_n, hist_lo, hist_hi);
        test_end;

        //---------------------------------------------------------------------
        // T-019: directed latency, capture -> signal phase (REQ-027/PERF-003)
        //---------------------------------------------------------------------
        test_begin("T-019");
        // DRZ mode
        @(negedge clk); #1; dem_en = 1; drz_en = 1;
        run_cycles(6);
        @(negedge clk); #1;
        while (data_req !== 1'b1) begin @(negedge clk); #1; end
        data_in = 12'h5A5;                   // presented during cycle C
        @(posedge clk);                      // capture edge (ends cycle C)
        @(negedge clk); #2;
        if (phase !== 1'b0) begin
            errors = errors + 1;
            $display("TEST FAILED: T-019 DRZ cycle C+1 phase expected=0 actual=%b", phase);
        end
        @(posedge clk);                      // output-latch edge
        @(negedge clk); #2;                  // cycle C+2: code visible
        if (phase !== 1'b1
            || f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb) !== 12'h5A5) begin
            errors = errors + 1;
            $display("TEST FAILED: T-019 DRZ latency expected=sum %0d @phase=1 actual=sum %0d @phase=%b",
                     12'h5A5, f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb), phase);
        end
        // NRZ mode
        @(negedge clk); #1; drz_en = 0;
        run_cycles(4);
        @(negedge clk); #1; data_in = 12'h3C3;   // presented during cycle C
        @(posedge clk);                          // capture edge
        @(negedge clk); #1; data_in = 12'h000;   // next sample
        @(posedge clk);                          // output-latch edge
        @(negedge clk); #2;                      // cycle C+2
        if (phase !== 1'b1
            || f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb) !== 12'h3C3) begin
            errors = errors + 1;
            $display("TEST FAILED: T-019 NRZ latency expected=sum %0d @phase=1 actual=sum %0d @phase=%b",
                     12'h3C3, f_sum(sw_msb, sw_ulsb, sw_lsb, sw_llsb), phase);
        end
        run_cycles(6);
        test_end;

        //---------------------------------------------------------------------
        // Final report
        //---------------------------------------------------------------------
        $display("[TB] directed tests: %0d, cycles checked: %0d, captures: %0d, signal-phase sum checks: %0d",
                 n_tests, n_chk_cycles, n_captures, n_sig_checked);
        if (errors > 0 && n_failed == 0)
            n_failed = 1;                    // errors outside any test window
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TESTS FAILED", n_failed);
        $finish;
    end

endmodule
