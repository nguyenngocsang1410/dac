//-----------------------------------------------------------------------------
// dac_mod7.v
//
// Block:  dac_mod7 (PRN-to-rotation reducer, dac_demdrz_top v2)
// MAS:    docs/arch/dac_demdrz_top_mas.md (§1 file table, §4.1.3)
//
// Reduces a 6-bit slice of the PRNG state to a uniform rotation step
// R in 0..6 for the DEM rotator (REQ-010: the 64 input values map
// ceil(64/7)-balanced onto 0..6).
//
// Uses the octal digit-sum identity (mod-7 analogue of casting out nines):
//   val mod 7 = (val[5:3] + val[2:0]) mod 7
// The digit sum is at most 14, so the final reduction needs only two
// conditional subtractions. This is small combinational logic with no
// division operator, keeping the critical path short for multi-GHz-class
// encoder clocks.
//
// Assumptions: purely combinational; no clock or reset.
//
// Revision: v2.0 — functionally unchanged from v1 (MAS §1: "unchanged,
// combinational"); header updated for the v2 release.
//-----------------------------------------------------------------------------

module dac_mod7 (
    input  wire [5:0] val,   // raw PRNG bits
    output reg  [2:0] r      // rotation step, 0..6
);

    wire [3:0] digit_sum;   // 0..14

    assign digit_sum = {1'b0, val[5:3]} + {1'b0, val[2:0]};

    always @* begin
        if (digit_sum >= 4'd14)
            r = 3'd0;                    // 14 -> 0
        else if (digit_sum >= 4'd7)
            r = digit_sum[2:0] - 3'd7;   // 7..13 -> 0..6 (3-bit wrap is exact here)
        else
            r = digit_sum[2:0];          // 0..6
    end

endmodule
