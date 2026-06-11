//-----------------------------------------------------------------------------
// tb_dac_demdrz.v  -- self-checking testbench for the DEMDRZ encoder core
//
// Checks, for DEMDRZ / DEM-off / NRZ modes:
//   1. Signal phase: the weighted sum of the 28 switch controls equals the
//      captured 12-bit sample, for every sample (DEM rotation must never
//      change the converted value).
//   2. DRZ phase: the output is exactly the mid-code 2048 with the fixed
//      1/3/5/7 MSB element pattern.
//   3. DEM off: unit selection equals the plain thermometer code.
//   4. DEM on: rotation actually varies (selection differs across samples
//      with the same input code).
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_dac_demdrz;

    reg         clk;
    reg         rst_n;
    reg         dem_en;
    reg         drz_en;
    reg  [11:0] data_in;
    wire        data_req;
    wire        phase;
    wire [6:0]  sw_msb, sw_ulsb, sw_lsb, sw_llsb;

    integer errors;
    integer n_checked;

    dac_demdrz_top dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .dem_en   (dem_en),
        .drz_en   (drz_en),
        .data_in  (data_in),
        .data_req (data_req),
        .phase    (phase),
        .sw_msb   (sw_msb),
        .sw_ulsb  (sw_ulsb),
        .sw_lsb   (sw_lsb),
        .sw_llsb  (sw_llsb)
    );

    // Behavioral analog array; differential currents are visible as
    // u_analog.iout_p / u_analog.iout_n in the waveform dump.
    dac_analog_model u_analog (
        .sw_msb  (sw_msb),
        .sw_ulsb (sw_ulsb),
        .sw_lsb  (sw_lsb),
        .sw_llsb (sw_llsb)
    );

    always #5 clk = ~clk;   // 100 MHz TB clock (frequency-agnostic RTL)

    function integer ones7 (input [6:0] v);
        integer i;
        begin
            ones7 = 0;
            for (i = 0; i < 7; i = i + 1)
                ones7 = ones7 + v[i];
        end
    endfunction

    function integer decode_lsb (input [6:0] m, u, l, ll);
        decode_lsb = 512 * ones7(m) + 64 * ones7(u)
                   + 8 * ones7(l) + ones7(ll);
    endfunction

    // Reference model: queue of captured samples (2-cycle output latency).
    reg [11:0] pend_d1, pend_d2;
    reg        vld_d1,  vld_d2;
    reg [27:0] sel_seen [0:4095];   // last unit selection per code (DEM check)
    reg        seen     [0:4095];
    integer    n_resel, n_diff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vld_d1 <= 1'b0;
            vld_d2 <= 1'b0;
        end else begin
            vld_d2  <= 1'b0;
            if (vld_d1 && (phase == 1'b0 || !drz_en)) begin
                // sample was captured last cycle; its signal phase is next
                pend_d2 <= pend_d1;
                vld_d2  <= 1'b1;
            end
            if (data_req) begin
                pend_d1 <= data_in;
                vld_d1  <= 1'b1;
            end else begin
                vld_d1 <= 1'b0;
            end
        end
    end

    // Checkers sample outputs just before each rising edge.
    always @(negedge clk) if (rst_n) begin
        if (phase) begin : sig_chk
            integer got;
            got = decode_lsb(sw_msb, sw_ulsb, sw_lsb, sw_llsb);
            if (vld_d2 && got !== pend_d2) begin
                errors = errors + 1;
                $display("ERROR @%0t: signal phase sum %0d != sample %0d",
                         $time, got, pend_d2);
            end
            if (vld_d2) begin
                n_checked = n_checked + 1;
                // DEM activity / bypass check
                if (!dem_en) begin : thermo_chk
                    reg [6:0] exp_m, exp_u, exp_l;
                    exp_m = therm_of(pend_d2[11:9]);
                    exp_u = therm_of(pend_d2[8:6]);
                    exp_l = therm_of(pend_d2[5:3]);
                    if ({sw_msb, sw_ulsb, sw_lsb}
                        !== {exp_m, exp_u, exp_l}) begin
                        errors = errors + 1;
                        $display("ERROR @%0t: DEM-off selection not plain thermometer",
                                 $time);
                    end
                end else begin
                    if (seen[pend_d2]) begin
                        n_resel = n_resel + 1;
                        if (sel_seen[pend_d2]
                            !== {sw_msb, sw_ulsb, sw_lsb, sw_llsb})
                            n_diff = n_diff + 1;
                    end
                    seen[pend_d2]     = 1'b1;
                    sel_seen[pend_d2] = {sw_msb, sw_ulsb, sw_lsb, sw_llsb};
                end
            end
        end else begin : drz_chk
            if ({sw_msb, sw_ulsb, sw_lsb, sw_llsb}
                !== {7'b1010101, 21'b0}) begin
                errors = errors + 1;
                $display("ERROR @%0t: DRZ phase pattern %b_%b_%b_%b != mid-code",
                         $time, sw_msb, sw_ulsb, sw_lsb, sw_llsb);
            end
        end
    end

    function [6:0] therm_of (input [2:0] b);
        therm_of = 7'b1111111 >> (3'd7 - b);
    endfunction

    task run_samples (input integer n, input integer mode_ramp);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                while (!data_req) @(negedge clk);
                data_in = mode_ramp ? (i[11:0]) : ($random & 12'hFFF);
                @(posedge clk);
            end
        end
    endtask

    // Reset between mode changes so the TB reference pipeline and the DUT
    // restart in lockstep.
    task mode_reset;
        begin
            @(negedge clk);
            rst_n = 0;
            repeat (2) @(negedge clk);
            rst_n = 1;
            @(negedge clk);
        end
    endtask

    integer c;

    initial begin
        $dumpfile("tb_dac_demdrz.vcd");
        $dumpvars(0, tb_dac_demdrz);

        clk     = 0;
        rst_n   = 0;
        dem_en  = 1;
        drz_en  = 1;
        data_in = 0;
        errors  = 0;
        n_checked = 0;
        n_resel = 0;
        n_diff  = 0;
        for (c = 0; c < 4096; c = c + 1) seen[c] = 1'b0;

        repeat (4) @(negedge clk);
        rst_n = 1;

        // --- Mode 1: DEMDRZ, random data + full ramp ---
        $display("[TB] DEMDRZ mode (dem_en=1, drz_en=1)");
        run_samples(2000, 0);
        run_samples(4096, 1);

        // --- Mode 2: DRZ only (DEM off) ---
        $display("[TB] DRZ-only mode (dem_en=0, drz_en=1)");
        dem_en = 0;
        mode_reset;
        run_samples(1000, 0);

        // --- Mode 3: NRZ + DEM ---
        $display("[TB] NRZ+DEM mode (dem_en=1, drz_en=0)");
        dem_en = 1;
        drz_en = 0;
        mode_reset;
        run_samples(1000, 0);

        // --- Mode 4: plain NRZ ---
        $display("[TB] NRZ mode (dem_en=0, drz_en=0)");
        dem_en = 0;
        mode_reset;
        run_samples(1000, 0);

        if (n_resel > 0 && n_diff == 0) begin
            errors = errors + 1;
            $display("ERROR: DEM enabled but unit selection never varied (%0d repeats)",
                     n_resel);
        end

        $display("[TB] %0d signal-phase samples checked, DEM re-selections: %0d (varied: %0d)",
                 n_checked, n_resel, n_diff);
        if (errors == 0)
            $display("[TB] PASS");
        else
            $display("[TB] FAIL: %0d errors", errors);
        $finish;
    end

endmodule
