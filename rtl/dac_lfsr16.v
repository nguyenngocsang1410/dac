//-----------------------------------------------------------------------------
// dac_lfsr16.v
//
// 16-bit maximal-length Fibonacci LFSR used as the pseudo-random number
// generator of each DEM coder (the paper specifies a PRNG of 16-bit length
// per DEM coder). Polynomial: x^16 + x^14 + x^13 + x^11 + 1 (period 2^16-1).
//
// The seed parameter must be nonzero; each of the three DEM coders is
// instantiated with a distinct seed so the segment rotations are
// uncorrelated.
//-----------------------------------------------------------------------------

module dac_lfsr16 #(
    parameter [15:0] SEED = 16'hACE1   // must be nonzero
) (
    input  wire        clk,
    input  wire        rst_n,    // async active-low reset, loads SEED
    input  wire        en,       // advance one state per asserted clk edge
    output wire [15:0] prn       // current pseudo-random state
);

    reg  [15:0] lfsr_q;
    wire        fb;

    assign fb  = lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10];
    assign prn = lfsr_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr_q <= SEED;
        else if (en)
            lfsr_q <= {lfsr_q[14:0], fb};
    end

endmodule
