# 12-bit DEMDRZ Current-Steering DAC — Digital Encoder RTL

Synthesizable RTL implementation of the digital encoder of a 12-bit
segmented current-steering DAC using the **DEMDRZ** technique
(dynamic-element-matching + digital return-to-zero), following the
architecture of:

> W.-T. Lin, H.-Y. Huang, T.-H. Kuo, *"A 12-bit 40 nm DAC Achieving
> SFDR > 70 dB at 1.6 GS/s and IMD < −61 dB at 2.8 GS/s With DEMDRZ
> Technique"*, IEEE JSSC, vol. 49, no. 3, March 2014.

## Architecture (paper Fig. 5)

```
                 +--------------------------------------------------+
 data_in[11:0]   |                DEMDRZ coder (this RTL)            |
 ──────────────► | 3b MSB  ─► DEM coder (b2t + rotator + 16b PRNG) ─┐|
                 | 3b ULSB ─► DEM coder (b2t + rotator + 16b PRNG) ─┤|        ┌──────────┐   ┌─────────┐
                 | 3b LSB  ─► DEM coder (b2t + rotator + 16b PRNG) ─┼┼─ MUX ─►| data     |──►| switch  |─► current
                 | 3b LLSB ─► binary-to-thermometer (no DEM)       ─┤|  ▲     | latches  |   | drivers |   cells
                 |            DRZ coder (mid-code 2048)            ─┘|  │     | (DFFs)   |   | (analog)|  (analog)
                 |                                            phase ─┼──┘     └──────────┘   └─────────┘
                 +--------------------------------------------------+
```

* **Segmentation**: 3+3+3+3 bits (MSB / ULSB / LSB / LLSB), 7 thermometer
  unit elements per segment with weights 512 / 64 / 8 / 1 LSB. Total
  28 switch-control lines.
* **DEM**: the upper 9 bits use random-rotation DEM. Each DEM coder is a
  binary-to-thermometer decoder followed by a 7-bit barrel rotator whose
  step R ∈ {0..6} comes from a private 16-bit maximal-length LFSR (the
  paper's PRNG). R updates once per sample; the LLSB segment skips DEM
  because its mismatch contribution is negligible.
* **DRZ**: between every two samples a mid-code phase is inserted — MSB
  elements 1/3/5/7 on, everything else off (4 × 512 = 2048 → near-zero
  differential output). This decorrelates each output transition from the
  previous sample. The DRZ code bypasses the rotators (R effectively 0
  during the DRZ phase, as in the paper).
* **DEMDRZ MUX + data latches**: the signal/DRZ multiplexer feeds a final
  register stage (`sw_*` outputs), the paper's D-flip-flop data latches that
  synchronize all 28 bits before the switch drivers.

## File layout

| Path | Content |
|---|---|
| `rtl/dac_demdrz_top.v` | Top level: segmentation, DEM coders, DRZ coder, phase MUX, output latches |
| `rtl/dac_dem_coder.v` | One-segment DEM coder (b2t + rotator + PRNG + R register) |
| `rtl/dac_bin2therm.v` | 3-bit binary → 7-bit thermometer decoder |
| `rtl/dac_rotator7.v` | 7-bit barrel rotator (random unit selection) |
| `rtl/dac_lfsr16.v` | 16-bit maximal-length Fibonacci LFSR (PRNG) |
| `rtl/dac_mod7.v` | Uniform 0..6 rotation step from PRNG bits (octal digit-sum mod-7, no divider) |
| `model/dac_analog_model.v` | **Sim-only** behavioral model of the switch/current-cell arrays (with optional mismatch) |
| `tb/tb_dac_demdrz.v` | Self-checking testbench (all 4 modes) |
| `syn/yosys_synth.ys` | Yosys synthesizability check script |
| `syn/constraints.sdc` | Timing constraints template for DC/Genus/OpenROAD |

## Interface (`dac_demdrz_top`)

| Port | Dir | Description |
|---|---|---|
| `clk` | in | 2× sample rate in DEMDRZ mode (1× when `drz_en=0`) |
| `rst_n` | in | async active-low reset (deassert synchronously) |
| `dem_en` | in | 1: randomize unit selection; 0: plain thermometer |
| `drz_en` | in | 1: DEMDRZ (RTZ phases inserted); 0: NRZ |
| `data_in[11:0]` | in | offset-binary sample, captured when `data_req=1` |
| `data_req` | out | high on clk edges that consume `data_in` |
| `phase` | out | 1: `sw_*` carry the signal code, 0: the DRZ mid-code |
| `sw_msb/ulsb/lsb/llsb[6:0]` | out | registered unit-element switch controls |

Latency is 2 clk cycles from capture to the corresponding signal phase.
After reset the outputs hold the DRZ mid-code (safe near-zero differential).

## Verification

```sh
iverilog -g2005 -o tb.vvp rtl/*.v model/dac_analog_model.v tb/tb_dac_demdrz.v
vvp tb.vvp
```

The testbench checks, in DEMDRZ / DRZ-only / NRZ+DEM / NRZ modes:
1. every signal phase converts exactly the captured sample (DEM rotation
   never changes the value),
2. every DRZ phase outputs exactly the fixed 1/3/5/7 mid-code pattern,
3. with DEM off the selection equals the plain thermometer code,
4. with DEM on, repeated codes select different unit cells.

## Synthesis & layout notes

```sh
yosys -q syn/yosys_synth.ys     # latch-free, check -assert clean
```

* Pure Verilog-2001, single clock domain, async-reset DFFs only, no
  latches, no memories, no multipliers/dividers, no tri-states — clean for
  any ASIC or FPGA flow. Yosys generic synthesis flattens the core to
  ~640 cells, 98 of them flops (3×16 LFSR + 3×3 R + 12 data + 28 output
  latches + phase).
* The analog portion of the paper (switch drivers, cascoded current cells,
  bias, inter-placement floorplan with dummy rings) is full-custom and is
  represented here only by `model/dac_analog_model.v` for simulation. In a
  real implementation the encoder is placed as a digital block abutting
  the switch-driver array; route the 28 `sw_*` lines short and
  skew-matched (the paper relies on short identical wires, and residual
  random skew is whitened by the DEM randomization).
* `syn/constraints.sdc` is a template: set `CLK_PERIOD_NS` to your target
  (0.3125 ns for the paper's 1.6 GS/s DEMDRZ operation) and add
  `set_max_skew`/matched-routing rules for the `sw_*` bus in PnR.
* PRNG seeds for the three DEM coders are top-level parameters
  (`SEED_MSB`, `SEED_ULSB`, `SEED_LSB`); keep them distinct and nonzero.
