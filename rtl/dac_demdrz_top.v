//-----------------------------------------------------------------------------
// dac_demdrz_top.v
//
// Digital encoder core of a 12-bit segmented current-steering DAC with the
// DEMDRZ technique (Lin/Huang/Kuo, IEEE JSSC vol.49 no.3, 2014, Fig. 5).
//
// Segmentation (unit-element weight in 12-bit LSBs):
//   data_in[11:9]  MSB   segment -> 7 elements x 512 LSB   (DEM coder)
//   data_in[8:6]   ULSB  segment -> 7 elements x  64 LSB   (DEM coder)
//   data_in[5:3]   LSB   segment -> 7 elements x   8 LSB   (DEM coder)
//   data_in[2:0]   LLSB  segment -> 7 elements x   1 LSB   (plain thermo)
//
// Operation (drz_en = 1): clk runs at 2x the sample rate. Each sample
// occupies two clk cycles - a signal phase carrying the DEM-randomized
// thermometer codes, followed by a DRZ phase carrying the fixed mid-code
// (alternating MSB elements 1/3/5/7 on = 2048 LSB), which makes the output
// transition independent of the previous sample. The DEM rotation R is
// frozen during the DRZ phase (the DRZ code bypasses the rotators), as in
// the paper. With drz_en = 0 the core degrades to plain NRZ (+optional DEM)
// at one sample per clk.
//
// Interface timing: data_in is captured on rising clk edges where data_req
// is high; the corresponding signal-phase code appears on sw_* after the
// next rising edge. All sw_* outputs are registered (the paper's "data
// latches" before the switch drivers) so the 28 lines to the analog switch
// drivers are glitch-free and skew-matched by placement.
//
// The analog portion (switch drivers, current cells, cascodes, biasing) is
// full-custom and outside RTL scope; see model/dac_analog_model.v for a
// simulation-only behavioral equivalent.
//-----------------------------------------------------------------------------

module dac_demdrz_top #(
    parameter [15:0] SEED_MSB  = 16'hACE1,   // distinct nonzero PRNG seeds
    parameter [15:0] SEED_ULSB = 16'h5EED,
    parameter [15:0] SEED_LSB  = 16'hB10D
) (
    input  wire        clk,       // 2x sample rate (1x when drz_en = 0)
    input  wire        rst_n,     // async active-low reset
    input  wire        dem_en,    // 1: randomize unit selection (DEM on)
    input  wire        drz_en,    // 1: insert DRZ phases (DEMDRZ), 0: NRZ
    input  wire [11:0] data_in,   // offset-binary sample, 0..4095
    output wire        data_req,  // data_in is captured when high
    output reg         phase,     // 1: sw_* carry signal code, 0: DRZ code
    output reg  [6:0]  sw_msb,    // MSB  switch-driver controls (512 LSB/elem)
    output reg  [6:0]  sw_ulsb,   // ULSB switch-driver controls ( 64 LSB/elem)
    output reg  [6:0]  sw_lsb,    // LSB  switch-driver controls (  8 LSB/elem)
    output reg  [6:0]  sw_llsb    // LLSB switch-driver controls (  1 LSB/elem)
);

    // DRZ mid-code: MSB elements 1, 3, 5, 7 on -> 4 x 512 = 2048 LSB,
    // all other segments off (paper Section III).
    localparam [6:0] DRZ_MSB  = 7'b1010101;
    localparam [6:0] DRZ_LOW  = 7'b0000000;

    reg  [11:0] data_q;
    wire        next_phase;
    wire        capture;
    wire [6:0]  dem_msb;
    wire [6:0]  dem_ulsb;
    wire [6:0]  dem_lsb;
    wire [6:0]  therm_llsb;

    // Phase of the code that the output registers will hold after the next
    // clk edge. In NRZ mode every cycle is a signal phase.
    assign next_phase = drz_en ? ~phase : 1'b1;

    // A new sample (and a new rotation R) is loaded during the cycle that
    // outputs the DRZ code, so the DEM path settles before the following
    // signal phase.
    assign capture  = ~next_phase | ~drz_en;
    assign data_req = capture;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_q <= 12'd0;
        else if (capture)
            data_q <= data_in;
    end

    // DEM coders on the upper 9 bits.
    dac_dem_coder #(.SEED(SEED_MSB)) u_dem_msb (
        .clk       (clk),
        .rst_n     (rst_n),
        .advance_r (capture),
        .dem_en    (dem_en),
        .bin       (data_q[11:9]),
        .therm     (dem_msb)
    );

    dac_dem_coder #(.SEED(SEED_ULSB)) u_dem_ulsb (
        .clk       (clk),
        .rst_n     (rst_n),
        .advance_r (capture),
        .dem_en    (dem_en),
        .bin       (data_q[8:6]),
        .therm     (dem_ulsb)
    );

    dac_dem_coder #(.SEED(SEED_LSB)) u_dem_lsb (
        .clk       (clk),
        .rst_n     (rst_n),
        .advance_r (capture),
        .dem_en    (dem_en),
        .bin       (data_q[5:3]),
        .therm     (dem_lsb)
    );

    // LLSB: conventional binary-to-thermometer, no DEM.
    dac_bin2therm u_b2t_llsb (
        .bin   (data_q[2:0]),
        .therm (therm_llsb)
    );

    // DEMDRZ MUX + output data latches. Reset state is the DRZ mid-code,
    // a safe near-zero differential output.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase   <= 1'b0;
            sw_msb  <= DRZ_MSB;
            sw_ulsb <= DRZ_LOW;
            sw_lsb  <= DRZ_LOW;
            sw_llsb <= DRZ_LOW;
        end else begin
            phase   <= next_phase;
            sw_msb  <= next_phase ? dem_msb    : DRZ_MSB;
            sw_ulsb <= next_phase ? dem_ulsb   : DRZ_LOW;
            sw_lsb  <= next_phase ? dem_lsb    : DRZ_LOW;
            sw_llsb <= next_phase ? therm_llsb : DRZ_LOW;
        end
    end

endmodule
