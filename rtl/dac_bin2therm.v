//-----------------------------------------------------------------------------
// dac_bin2therm.v
//
// 3-bit binary to 7-bit thermometer decoder.
//
// One instance per 3-bit segment (MSB / ULSB / LSB / LLSB) of the 12-bit
// segmented current-steering DAC. therm[i] = 1 when bin > i, so the number
// of asserted thermometer bits equals the binary input value.
//
// Reference: Lin/Huang/Kuo, "A 12-bit 40nm DAC ... With DEMDRZ Technique",
// IEEE JSSC vol.49 no.3, 2014 - Fig. 2 / Fig. 5.
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
