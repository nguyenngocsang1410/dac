//-----------------------------------------------------------------------------
// dac_demdrz_top.v
//
// Block:  dac_demdrz_top (v2)
// MAS:    docs/arch/dac_demdrz_top_mas.md
//
// Digital encoder core of a 12-bit segmented current-steering DAC with the
// DEMDRZ technique (Lin/Huang/Kuo, IEEE JSSC vol.49 no.3, 2014, Fig. 5).
//
// Segmentation (unit-element weight in 12-bit LSBs):
//   data[11:9]  MSB   segment -> 7 elements x 512 LSB   (DEM coder)
//   data[8:6]   ULSB  segment -> 7 elements x  64 LSB   (DEM coder)
//   data[5:3]   LSB   segment -> 7 elements x   8 LSB   (DEM coder)
//   data[2:0]   LLSB  segment -> 7 elements x   1 LSB   (plain thermo)
//
// Operation (drz_en = 1): clk runs at 2x the sample rate. Each sample
// occupies two clk cycles - a signal phase carrying the DEM-randomized
// thermometer codes, followed by a DRZ phase carrying the fixed mid-code
// (alternating MSB elements 1/3/5/7 on = 2048 LSB). With drz_en = 0 the
// core degrades to plain NRZ (+optional DEM) at one sample per clk.
// data_in is captured on rising clk edges where data_req is high; the
// corresponding signal-phase code appears 2 clk cycles later (REQ-027).
//
// v2 features (MAS §1):
//   - fmt_sel: 0 = offset-binary input (v1-compatible), 1 = two's-complement,
//     mapped to the internal offset-binary code by inverting data_in[11]
//     in front of the capture register (decision D2; per-capture semantics).
//   - Seed write interface (seed_wr/seed_addr/seed_wdata): single-cycle
//     synchronous load of the addressed segment LFSR; address 2'b11 is
//     reserved and silently ignored (REQ-018). Decode lives here; load
//     priority and zero substitution live in dac_lfsr16 (decision D3/D4).
//   - Complementary rail sw_*_n: 28 additional flops in the same output
//     register stage, loaded with the inverted MUX value on the same edge —
//     no combinational path from sw_* to sw_*_n at the boundary (D5).
//
// Assumptions (MAS §8): all inputs synchronous to clk, no CDC (M1); rst
// asserted >= 1 full clk cycle (M2); seed_addr/seed_wdata don't-care when
// seed_wr = 0 (M4); data_req combinational, forced 0 during reset (M6/D7).
//
// The analog portion (switch drivers, current cells, cascodes, biasing) is
// full-custom and outside RTL scope.
//
// Revision: v2.0 — added fmt_sel input-format XOR, seed write interface
// with address decode and zero-parameter substitution localparams, sw_*_n
// complementary registered outputs; rst_n (async, active-low) replaced by
// rst (synchronous, active-high, MAS decision D1); data_req now gated low
// during reset (decision D7). v1 microarchitecture otherwise unchanged.
//-----------------------------------------------------------------------------

module dac_demdrz_top #(
    parameter [15:0] SEED_MSB  = 16'hACE1,   // distinct nonzero PRNG seeds
    parameter [15:0] SEED_ULSB = 16'h5EED,
    parameter [15:0] SEED_LSB  = 16'hB10D
) (
    input  wire        clk,        // 2x sample rate (1x when drz_en = 0)
    input  wire        rst,        // synchronous active-high reset
    input  wire        dem_en,     // 1: randomize unit selection (DEM on)
    input  wire        drz_en,     // 1: insert DRZ phases (DEMDRZ), 0: NRZ
    input  wire        fmt_sel,    // 0: offset-binary, 1: two's-complement
    input  wire [11:0] data_in,    // input sample, interpretation per fmt_sel
    input  wire        seed_wr,    // seed write strobe (single-cycle write)
    input  wire [1:0]  seed_addr,  // 00: MSB, 01: ULSB, 10: LSB, 11: reserved
    input  wire [15:0] seed_wdata, // seed value (16'h0000 -> parameter seed)
    output wire        data_req,   // data_in is captured when high
    output reg         phase,      // 1: sw_* carry signal code, 0: DRZ code
    output reg  [6:0]  sw_msb,     // MSB  switch controls (512 LSB/elem)
    output reg  [6:0]  sw_ulsb,    // ULSB switch controls ( 64 LSB/elem)
    output reg  [6:0]  sw_lsb,     // LSB  switch controls (  8 LSB/elem)
    output reg  [6:0]  sw_llsb,    // LLSB switch controls (  1 LSB/elem)
    output reg  [6:0]  sw_msb_n,   // complement rail, separate flops,
    output reg  [6:0]  sw_ulsb_n,  //   sw_*_n === ~sw_* on every cycle
    output reg  [6:0]  sw_lsb_n,   //   including reset (REQ-019/020)
    output reg  [6:0]  sw_llsb_n
);

    // DRZ mid-code: MSB elements 1, 3, 5, 7 on -> 4 x 512 = 2048 LSB,
    // all other segments off (paper Section III).
    localparam [6:0] DRZ_MSB = 7'b1010101;
    localparam [6:0] DRZ_LOW = 7'b0000000;

    // Zero-parameter substitution (CFG-002, REQ-015): a misconfigured zero
    // seed parameter silently falls back to the v1 default for that segment,
    // so every dac_lfsr16 instance receives a guaranteed-nonzero SEED.
    localparam [15:0] SEED_MSB_EFF  = (SEED_MSB  != 16'h0000) ? SEED_MSB  : 16'hACE1;
    localparam [15:0] SEED_ULSB_EFF = (SEED_ULSB != 16'h0000) ? SEED_ULSB : 16'h5EED;
    localparam [15:0] SEED_LSB_EFF  = (SEED_LSB  != 16'h0000) ? SEED_LSB  : 16'hB10D;

    // Seed address map (MAS §4.1.3 decode; 2'b11 reserved).
    localparam [1:0] SEED_ADDR_MSB  = 2'b00;
    localparam [1:0] SEED_ADDR_ULSB = 2'b01;
    localparam [1:0] SEED_ADDR_LSB  = 2'b10;

    reg  [11:0] data_q;
    wire [11:0] data_int;
    wire        next_phase;
    wire        capture;
    wire        seed_wr_msb;
    wire        seed_wr_ulsb;
    wire        seed_wr_lsb;
    wire [6:0]  dem_msb;
    wire [6:0]  dem_ulsb;
    wire [6:0]  dem_lsb;
    wire [6:0]  therm_llsb;

    //-------------------------------------------------------------------------
    // Phase sequencer (2-state FSM, MAS §4.2): next-state logic separate
    // from the 1-bit state register (the phase output flop below).
    // PH_DRZ = 1'b0, PH_SIG = 1'b1; encoding = the phase output itself.
    //-------------------------------------------------------------------------
    assign next_phase = drz_en ? ~phase : 1'b1;

    // A new sample (and a new rotation R) is loaded during the cycle that
    // outputs the DRZ code (every cycle in NRZ mode), so the DEM path
    // settles before the following signal phase. capture is forced low
    // during reset so data_req = 1 <=> this edge captures (REQ-025, D7).
    assign capture  = (~next_phase | ~drz_en) & ~rst;
    assign data_req = capture;

    //-------------------------------------------------------------------------
    // Input format mapping (REQ-005..008, decision D2): two's-complement
    // value v maps to offset-binary v + 2048 = MSB inversion. Placed in
    // front of the capture register so fmt_sel is consumed only at capture
    // edges; everything downstream operates on offset-binary codes as in v1.
    //-------------------------------------------------------------------------
    assign data_int = {data_in[11] ^ fmt_sel, data_in[10:0]};

    always @(posedge clk) begin
        if (rst)
            data_q <= 12'h000;
        else if (capture)
            data_q <= data_int;
    end

    //-------------------------------------------------------------------------
    // Seed write address decode (MAS §4.1.4). Reserved address 2'b11
    // asserts no strobe: the write is silently ignored (REQ-018). Reset
    // priority over a coincident write is enforced inside dac_lfsr16.
    //-------------------------------------------------------------------------
    assign seed_wr_msb  = seed_wr & (seed_addr == SEED_ADDR_MSB);
    assign seed_wr_ulsb = seed_wr & (seed_addr == SEED_ADDR_ULSB);
    assign seed_wr_lsb  = seed_wr & (seed_addr == SEED_ADDR_LSB);

    //-------------------------------------------------------------------------
    // DEM coders on the upper 9 bits; LLSB is plain thermometer (REQ-009).
    //-------------------------------------------------------------------------
    dac_dem_coder #(.SEED(SEED_MSB_EFF)) u_dem_msb (
        .clk       (clk),
        .rst       (rst),
        .advance_r (capture),
        .dem_en    (dem_en),
        .seed_ld   (seed_wr_msb),
        .seed_in   (seed_wdata),
        .bin       (data_q[11:9]),
        .therm     (dem_msb)
    );

    dac_dem_coder #(.SEED(SEED_ULSB_EFF)) u_dem_ulsb (
        .clk       (clk),
        .rst       (rst),
        .advance_r (capture),
        .dem_en    (dem_en),
        .seed_ld   (seed_wr_ulsb),
        .seed_in   (seed_wdata),
        .bin       (data_q[8:6]),
        .therm     (dem_ulsb)
    );

    dac_dem_coder #(.SEED(SEED_LSB_EFF)) u_dem_lsb (
        .clk       (clk),
        .rst       (rst),
        .advance_r (capture),
        .dem_en    (dem_en),
        .seed_ld   (seed_wr_lsb),
        .seed_in   (seed_wdata),
        .bin       (data_q[5:3]),
        .therm     (dem_lsb)
    );

    dac_bin2therm u_b2t_llsb (
        .bin   (data_q[2:0]),
        .therm (therm_llsb)
    );

    //-------------------------------------------------------------------------
    // DEMDRZ MUX + output register stage (MAS §4.1.5): all 57 output flops
    // (28 true + 28 complement + phase) update on the same edge. The
    // inversion sits in front of the _n flops, so both rails are register
    // outputs and sw_*_n === ~sw_* holds on every cycle, including reset.
    // Reset state is the DRZ mid-code, a safe near-zero differential output.
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            phase     <= 1'b0;
            sw_msb    <=  DRZ_MSB;
            sw_msb_n  <= ~DRZ_MSB;
            sw_ulsb   <=  DRZ_LOW;
            sw_ulsb_n <= ~DRZ_LOW;
            sw_lsb    <=  DRZ_LOW;
            sw_lsb_n  <= ~DRZ_LOW;
            sw_llsb   <=  DRZ_LOW;
            sw_llsb_n <= ~DRZ_LOW;
        end else begin
            phase     <= next_phase;
            sw_msb    <=  (next_phase ? dem_msb    : DRZ_MSB);
            sw_msb_n  <= ~(next_phase ? dem_msb    : DRZ_MSB);
            sw_ulsb   <=  (next_phase ? dem_ulsb   : DRZ_LOW);
            sw_ulsb_n <= ~(next_phase ? dem_ulsb   : DRZ_LOW);
            sw_lsb    <=  (next_phase ? dem_lsb    : DRZ_LOW);
            sw_lsb_n  <= ~(next_phase ? dem_lsb    : DRZ_LOW);
            sw_llsb   <=  (next_phase ? therm_llsb : DRZ_LOW);
            sw_llsb_n <= ~(next_phase ? therm_llsb : DRZ_LOW);
        end
    end

endmodule
