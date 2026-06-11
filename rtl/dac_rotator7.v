//-----------------------------------------------------------------------------
// dac_rotator7.v
//
// 7-bit barrel rotator for the DEM coder. Rotates the thermometer code by
// the random step R (0..6) so that, for the same input code, a different
// set of unit current cells is selected each sample. This is the
// "random rotation-based" unit selection of the DEMDRZ technique
// (paper Fig. 3(a)/(c)): therm_out[(i + r) mod 7] = therm_in[i].
//
// Implemented as a 7:1 case mux per output bit - pure combinational logic,
// no latches.
//-----------------------------------------------------------------------------

module dac_rotator7 (
    input  wire [6:0] therm_in,   // thermometer code, element 1 = bit 0
    input  wire [2:0] r,          // rotation step, 0..6 (7 treated as 0)
    output reg  [6:0] therm_out   // rotated unit-element selection
);

    always @* begin
        case (r)
            3'd1:    therm_out = {therm_in[5:0], therm_in[6]};
            3'd2:    therm_out = {therm_in[4:0], therm_in[6:5]};
            3'd3:    therm_out = {therm_in[3:0], therm_in[6:4]};
            3'd4:    therm_out = {therm_in[2:0], therm_in[6:3]};
            3'd5:    therm_out = {therm_in[1:0], therm_in[6:2]};
            3'd6:    therm_out = {therm_in[0],   therm_in[6:1]};
            default: therm_out = therm_in;   // r = 0 or 7: no rotation
        endcase
    end

endmodule
