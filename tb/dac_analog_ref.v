//-----------------------------------------------------------------------------
// dac_analog_ref.v  -- SIMULATION ONLY, NOT SYNTHESIZABLE
//
// Behavioral model of the full-custom analog portion of the DAC: the
// switch-driver / switch / current-source arrays of paper Fig. 5/8. Each
// asserted switch-control bit steers its unit current to the positive
// output; deasserted bits steer it to the negative output, modeling the
// complementary switch pair. Optional Gaussian unit-current mismatch lets
// a testbench reproduce the paper's DEM-on/off mismatch experiments.
//
// In the real chip this block is a hand-drawn layout (inter-placement
// floorplan, dummy rings, cascoded current cells) - it has no RTL
// equivalent and must be integrated as a hard macro.
//-----------------------------------------------------------------------------

module dac_analog_ref #(
    parameter real IFS_MA      = 16.0,  // full-scale load current, mA
    parameter real SIGMA_PCT   = 0.0,   // unit-current mismatch sigma, %
    parameter      MISMATCH_SEED = 1
) (
    input  wire [6:0] sw_msb,    // 512 LSB per element
    input  wire [6:0] sw_ulsb,   //  64 LSB per element
    input  wire [6:0] sw_lsb,    //   8 LSB per element
    input  wire [6:0] sw_llsb    //   1 LSB per element
);

    // Differential output currents in mA. Real-valued signals cannot be
    // ports in plain Verilog-2005, so testbenches access them
    // hierarchically (e.g. u_analog.iout_p) or via $dumpvars.
    real iout_p;
    real iout_n;

    localparam integer FS_LSB = 4095;

    // Per-element currents in LSB units, with optional static mismatch.
    real i_msb  [0:6];
    real i_ulsb [0:6];
    real i_lsb  [0:6];
    real i_llsb [0:6];

    integer seed;
    integer k;

    function real with_mismatch (input real nominal);
        begin
            with_mismatch = nominal
                * (1.0 + (SIGMA_PCT / 100.0)
                       * ($dist_normal(seed, 0, 1000) / 1000.0));
        end
    endfunction

    initial begin
        seed = MISMATCH_SEED;
        for (k = 0; k < 7; k = k + 1) begin
            i_msb[k]  = with_mismatch(512.0);
            i_ulsb[k] = with_mismatch(64.0);
            i_lsb[k]  = with_mismatch(8.0);
            i_llsb[k] = with_mismatch(1.0);
        end
    end

    real ip_lsb;
    integer j;

    always @* begin
        ip_lsb = 0.0;
        for (j = 0; j < 7; j = j + 1) begin
            if (sw_msb[j])  ip_lsb = ip_lsb + i_msb[j];
            if (sw_ulsb[j]) ip_lsb = ip_lsb + i_ulsb[j];
            if (sw_lsb[j])  ip_lsb = ip_lsb + i_lsb[j];
            if (sw_llsb[j]) ip_lsb = ip_lsb + i_llsb[j];
        end
    end

    always @* begin
        iout_p = IFS_MA * ip_lsb / FS_LSB;
        iout_n = IFS_MA * (FS_LSB - ip_lsb) / FS_LSB;
    end

endmodule
