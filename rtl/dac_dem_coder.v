//-----------------------------------------------------------------------------
// dac_dem_coder.v
//
// Block:  dac_dem_coder (per-segment DEM coder, dac_demdrz_top v2)
// MAS:    docs/arch/dac_demdrz_top_mas.md (§4.1.3, §4.1.4)
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
// binary-to-thermometer coder (paper Fig. 14(c)). The LFSR advances on
// every advance_r regardless of dem_en, so the PRN timeline is
// mode-independent (MAS §4.1.3).
//
// v2 plumbs the runtime seed write interface (seed_ld, seed_in) through to
// the private LFSR; the load takes priority over a same-cycle advance
// inside dac_lfsr16. At a write/advance collision edge, r_q samples
// mod7() of the pre-write PRN state (MAS decision D8) — the written seed
// first influences R at the next capture.
//
// Assumptions:
//   - SEED is nonzero (effective seed passed from the top, MAS §2.1).
//   - bin is registered upstream (data_q segment slice).
//
// Revision: v2.0 — rst_n (async, active-low) replaced by rst (synchronous,
// active-high, MAS decision D1); seed_ld/seed_in ports added and routed to
// dac_lfsr16. DEM math (b2t, mod7, rotator, R update rule) unchanged.
//-----------------------------------------------------------------------------

module dac_dem_coder #(
    parameter [15:0] SEED = 16'hACE1   // per-instance PRNG seed, nonzero
) (
    input  wire        clk,
    input  wire        rst,         // synchronous active-high reset
    input  wire        advance_r,   // load a new random rotation (1/sample)
    input  wire        dem_en,      // 0: bypass randomization (R = 0)
    input  wire        seed_ld,     // single-cycle LFSR seed write strobe
    input  wire [15:0] seed_in,     // LFSR seed write data
    input  wire [2:0]  bin,         // registered 3-bit segment code
    output wire [6:0]  therm        // randomized unit-element selection
);

    wire [15:0] prn;
    wire [2:0]  r_next;
    reg  [2:0]  r_q;
    wire [6:0]  therm_raw;
    wire        unused_prn_hi;      // prn[15:6] not consumed (mod7 uses [5:0])

    dac_lfsr16 #(
        .SEED (SEED)
    ) u_lfsr (
        .clk     (clk),
        .rst     (rst),
        .en      (advance_r),
        .seed_ld (seed_ld),
        .seed_in (seed_in),
        .prn     (prn)
    );

    // Only the low 6 PRN bits feed the rotation; sink the rest explicitly.
    assign unused_prn_hi = &{1'b0, prn[15:6]};

    dac_mod7 u_mod7 (
        .val (prn[5:0]),
        .r   (r_next)
    );

    // R updates exactly once per captured sample; dem_en = 0 forces plain
    // thermometer coding at the next R update (REQ-004).
    always @(posedge clk) begin
        if (rst)
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
