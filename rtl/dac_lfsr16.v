//-----------------------------------------------------------------------------
// dac_lfsr16.v
//
// Block:  dac_lfsr16 (PRNG of one DEM coder, dac_demdrz_top v2)
// MAS:    docs/arch/dac_demdrz_top_mas.md (§2.1, §4.1.4, decisions D3/D4)
//
// 16-bit maximal-length Fibonacci LFSR used as the pseudo-random number
// generator of each DEM coder (the paper specifies a PRNG of 16-bit length
// per DEM coder). Polynomial: x^16 + x^14 + x^13 + x^11 + 1 (period 2^16-1).
//
// v2 adds a synchronous seed-load port: seed_ld loads seed_in in a single
// cycle, taking priority over a same-cycle natural advance (PRD A4). A
// written value of 16'h0000 is substituted by the parameter SEED (REQ-016 /
// PRD A5), so the all-zero lock-up state is unreachable by construction
// (REQ-015): reset and the load mux are the only paths into lfsr_q, and
// both are guaranteed nonzero given a nonzero SEED.
//
// Assumptions:
//   - SEED is nonzero. The top level guarantees this by passing only the
//     effective (zero-substituted) seed localparams (MAS §2.1, CFG-002).
//   - seed_in is don't-care when seed_ld = 0 (MAS M4).
//
// Revision: v2.0 — rst_n (async, active-low) replaced by rst (synchronous,
// active-high, MAS decision D1); seed_ld/seed_in load port added with
// priority rst > seed_ld > en and zero-value substitution. v1 polynomial,
// width, and advance behavior unchanged.
//-----------------------------------------------------------------------------

module dac_lfsr16 #(
    parameter [15:0] SEED = 16'hACE1   // must be nonzero (top passes effective seed)
) (
    input  wire        clk,
    input  wire        rst,       // synchronous active-high reset, loads SEED
    input  wire        en,        // advance one state per asserted clk edge
    input  wire        seed_ld,   // single-cycle seed write (wins over en)
    input  wire [15:0] seed_in,   // seed value; 16'h0000 -> SEED substituted
    output wire [15:0] prn        // current pseudo-random state
);

    reg  [15:0] lfsr_q;
    wire        fb;
    wire [15:0] seed_eff;

    assign fb  = lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10];
    assign prn = lfsr_q;

    // Zero-write substitution (REQ-016): an all-zero write behaves exactly
    // like writing the effective parameter seed, so lfsr_q can never load 0.
    assign seed_eff = (seed_in == 16'h0000) ? SEED : seed_in;

    // Priority: reset > seed load > natural advance (MAS §4.1.4). A write
    // colliding with an advance consumes the advance (PRD A4); the next
    // enabled edge shifts from the written value (REQ-013).
    always @(posedge clk) begin
        if (rst)
            lfsr_q <= SEED;
        else if (seed_ld)
            lfsr_q <= seed_eff;
        else if (en)
            lfsr_q <= {lfsr_q[14:0], fb};
    end

endmodule
