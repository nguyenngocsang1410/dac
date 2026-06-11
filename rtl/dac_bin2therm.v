//-----------------------------------------------------------------------------
// dac_bin2therm.v
//
// Block:  dac_bin2therm (binary-to-thermometer decoder, dac_demdrz_top v2)
// MAS:    docs/arch/dac_demdrz_top_mas.md (§1 file table, §4.1.3)
//
// 3-bit binary to 7-bit thermometer decoder.
//
// One instance per 3-bit segment (MSB / ULSB / LSB / LLSB) of the 12-bit
// segmented current-steering DAC. therm[i] = 1 when bin > i, so the number
// of asserted thermometer bits equals the binary input value.
//
// Assumptions: purely combinational; no clock or reset.
//
// Reference: Lin/Huang/Kuo, "A 12-bit 40nm DAC ... With DEMDRZ Technique",
// IEEE JSSC vol.49 no.3, 2014 - Fig. 2 / Fig. 5.
//
// Revision: v2.0 — functionally unchanged from v1 (MAS §1: "unchanged,
// combinational"); header updated for the v2 release.
//-----------------------------------------------------------------------------

module dac_bin2therm (
    input  wire [2:0] bin,    // binary segment code, 0..7
    output reg  [6:0] therm   // unit-element thermometer code
);

    always @* begin
        case (bin)
            3'd0:    therm = 7'b0000000;
            3'd1:    therm = 7'b0000001;
            3'd2:    therm = 7'b0000011;
            3'd3:    therm = 7'b0000111;
            3'd4:    therm = 7'b0001111;
            3'd5:    therm = 7'b0011111;
            3'd6:    therm = 7'b0111111;
            default: therm = 7'b1111111;
        endcase
    end

endmodule
