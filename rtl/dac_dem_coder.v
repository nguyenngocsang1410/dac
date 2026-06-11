//-----------------------------------------------------------------------------
// dac_dem_coder.v
//
// DEM coder for one 3-bit segment: binary-to-thermometer decoder followed
// by a random barrel rotation (paper Fig. 2, "DEM coder" = rotator +
// 16-bit PRNG). One instance each for the MSB, ULSB and LSB segments;
// the LLSB segment uses a plain binary-to-thermometer decoder because its
// mismatch contribution is negligible (paper Fig. 5).
//
// The rotation step R is registered and updated once per sample
// (advance_r), so it is stable for the whole signal phase. When dem_en is
// low, R is forced to 0 and the coder degenerates to a conventional
// binary-to-thermometer coder (used for the measured DEM-off comparison
// in the paper, Fig. 14(c)).
//-----------------------------------------------------------------------------

module dac_dem_coder #(
    parameter [15:0] SEED = 16'hACE1   // per-instance PRNG seed, nonzero
) (
    input  wire       clk,
    input  wire       rst_n,       // async active-low reset
    input  wire       advance_r,   // load a new random rotation (1/sample)
    input  wire       dem_en,      // 0: bypass randomization (R = 0)
    input  wire [2:0] bin,         // registered 3-bit segment code
    output wire [6:0] therm        // randomized unit-element selection
);

    wire [15:0] prn;
    wire [2:0]  r_next;
    reg  [2:0]  r_q;
    wire [6:0]  therm_raw;

    dac_lfsr16 #(
        .SEED (SEED)
    ) u_lfsr (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (advance_r),
        .prn   (prn)
    );

    dac_mod7 u_mod7 (
        .val (prn[5:0]),
        .r   (r_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_q <= 3'd0;
        else if (advance_r)
            r_q <= dem_en ? r_next : 3'd0;
    end

    dac_bin2therm u_b2t (
        .bin   (bin),
        .therm (therm_raw)
    );

    dac_rotator7 u_rot (
        .therm_in  (therm_raw),
        .r         (r_q),
        .therm_out (therm)
    );

endmodule
