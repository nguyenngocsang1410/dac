# 12-bit DEMDRZ Current-Steering DAC — Digital Encoder (`dac_demdrz_top`, v2)

Synthesizable Verilog-2001 implementation of the digital encoder of a 12-bit
segmented current-steering DAC using the **DEMDRZ** technique
(dynamic-element-matching + digital return-to-zero), following the
architecture of:

> W.-T. Lin, H.-Y. Huang, T.-H. Kuo, *"A 12-bit 40 nm DAC Achieving
> SFDR > 70 dB at 1.6 GS/s and IMD < −61 dB at 2.8 GS/s With DEMDRZ
> Technique"*, IEEE JSSC, vol. 49, no. 3, March 2014.

## Architecture (paper Fig. 5, v2 interface)

```
                  +---------------------------------------------------+
 fmt_sel ───────► | bit-11 XOR ─► capture reg ─► 3+3+3+3 split        |
 data_in[11:0]    |                                                   |
 ───────────────► | 3b MSB  ─► DEM coder (b2t + rotator + 16b LFSR) ─┐|
                  | 3b ULSB ─► DEM coder (b2t + rotator + 16b LFSR) ─┤|        ┌──────────┐   ┌─────────┐
 seed_wr ───────► | 3b LSB  ─► DEM coder (b2t + rotator + 16b LFSR) ─┼┼─ MUX ─►| output   |──►| switch  |─► current
 seed_addr[1:0]   | 3b LLSB ─► binary-to-thermometer (no DEM)       ─┤|  ▲     | regs     |   | drivers |   cells
 seed_wdata[15:0] |            DRZ coder (mid-code 2048)            ─┘|  │     | sw_*,    |   | (analog)|  (analog)
 (LFSR seed i/f)  |                                            phase ─┼──┘     | sw_*_n   |   └─────────┘
                  +---------------------------------------------------+        └──────────┘
```

* **Segmentation**: 3+3+3+3 bits (MSB / ULSB / LSB / LLSB), 7 thermometer
  unit elements per segment with weights 512 / 64 / 8 / 1 LSB — 28
  switch-control lines per rail.
* **DEM**: the upper 9 bits use random-rotation DEM. Each DEM coder is a
  binary-to-thermometer decoder followed by a 7-bit barrel rotator whose
  step R ∈ {0..6} comes from a private 16-bit maximal-length LFSR (the
  paper's PRNG, reduced mod 7 without a divider). R updates once per
  sample; the LLSB segment skips DEM.
* **DRZ**: between every two samples a mid-code phase is inserted — MSB
  elements 1/3/5/7 on, everything else off (4 × 512 = 2048 → near-zero
  differential output), decorrelating each transition from the previous
  sample. The DRZ code bypasses the rotators. `clk` runs at 2× the sample
  rate when `drz_en = 1`, 1× when `drz_en = 0` (NRZ).
* **Output stage**: the signal/DRZ multiplexer feeds a single register
  stage; capture-to-output latency is exactly 2 clk cycles, with a
  `data_req` handshake marking the capturing edges.

## New in v2

* **`fmt_sel` input format select** — 0: offset-binary (v1-compatible),
  1: two's-complement, applied per captured sample.
* **Runtime seed loading** — single-cycle synchronous writes to any of the
  three DEM LFSRs via `seed_wr` / `seed_addr[1:0]` / `seed_wdata[15:0]`,
  with zero-write substitution and a reserved address (`2'b11`, ignored).
* **Complementary output rails `sw_*_n[6:0]`** — 28 additional flops in the
  same output stage; `sw_*_n === ~sw_*` on every cycle, no boundary
  inversion path.
* **Synchronous active-high reset `rst`** — replaces v1's asynchronous
  active-low `rst_n`. Assert ≥ 1 full clk cycle; deassert synchronously.

With `fmt_sel = 0` and `seed_wr = 0` the block is functionally identical to
v1 on all v1 outputs. Full port/parameter tables: `docs/trm/`; instantiation
example and bring-up: `docs/guides/` (see below).

## Repository layout (deliverables pipeline)

| Path | Content |
|---|---|
| `rtl/` | Six synthesizable Verilog-2001 files, one module each; top is `rtl/dac_demdrz_top.v` (+ `dac_dem_coder.v`, `dac_lfsr16.v`, `dac_bin2therm.v`, `dac_rotator7.v`, `dac_mod7.v`) |
| `tb/dac_demdrz_top_tb.v` | Self-checking regression testbench (20 directed tests, cycle-exact reference model) |
| `tb/dac_analog_ref.v` | **Sim-only** behavioral model of the analog switch/current-cell arrays (module `dac_analog_ref`, optional mismatch); **not compiled in the regression by default** |
| `verif/plans/` | Test plan (`dac_demdrz_top_testplan.md`, traces every requirement ID to a test) |
| `verif/results/` | Lint and regression logs (`dac_demdrz_top_lint.log`, `dac_demdrz_top_sim.log`) |
| `docs/prd/`, `docs/arch/` | Product requirements (PRD) and microarchitecture spec (MAS) |
| `docs/trm/` | Technical Reference Manual — complete port/parameter tables, FSM, latency, corner cases |
| `docs/guides/` | Integration & User Guide — copy-pasteable instantiation, bring-up, pitfalls |
| `docs/reviews/` | Design review report (`dac_demdrz_top_review.md`) |
| `docs/templates/` | Document templates used by all of the above |
| `syn/` | `yosys_synth.ys` synthesizability check; `constraints.sdc` v2 timing constraints template |
| `CLAUDE.md`, `.claude/` | Phase-gated multi-agent deliverables pipeline (orchestrator rules + six specialized agents in `.claude/agents/`) |

Port and parameter details live in `docs/trm/dac_demdrz_top_trm.md`; first-time
users should start with `docs/guides/dac_demdrz_top_integration.md`. This
README intentionally duplicates neither.

## Lint

```sh
verilator --lint-only -Wall --top-module dac_demdrz_top \
    rtl/dac_bin2therm.v rtl/dac_lfsr16.v rtl/dac_mod7.v \
    rtl/dac_rotator7.v rtl/dac_dem_coder.v rtl/dac_demdrz_top.v
```

Clean (zero warnings, no waivers/pragmas) as of the v2 release.

## Regression

```sh
mkdir -p build verif/results
iverilog -g2001 -o build/dac_demdrz_top.vvp \
    rtl/dac_demdrz_top.v rtl/dac_dem_coder.v rtl/dac_lfsr16.v \
    rtl/dac_bin2therm.v rtl/dac_rotator7.v rtl/dac_mod7.v \
    tb/dac_demdrz_top_tb.v
vvp build/dac_demdrz_top.vvp | tee verif/results/dac_demdrz_top_sim.log
```

A passing run ends with the literal line `ALL TESTS PASSED`; failures print
`TEST FAILED: ... expected=... actual=...` lines and a `TESTS FAILED`
summary. Waveforms are dumped to `build/dac_demdrz_top.vcd` (view with
gtkwave). Reference logs are committed under `verif/results/`. The analog
behavioral model `tb/dac_analog_ref.v` is not part of this compile; add it
only if your own testbench instantiates `dac_analog_ref`.

## Synthesis check

```sh
yosys -q syn/yosys_synth.ys     # hierarchy/proc/synth, check -assert clean (no latches)
```

`syn/constraints.sdc` is the v2 constraints template: set `CLK_PERIOD_NS`
to your target (0.3125 ns for the paper's 1.6 GS/s DEMDRZ operation), keep
the `sw_*`/`sw_*_n`/`phase` lines skew-matched in PnR, and note that `rst`
is a normal timed synchronous path (do not false-path it).

## Verification status (v2 release)

* Regression: **20/20 directed tests PASS** — 39,901 checked cycles,
  `ALL TESTS PASSED` (`verif/results/dac_demdrz_top_sim.log`), independently
  reproduced by the design reviewer, including testbench mutation checks.
* Design review: **APPROVED-WITH-WAIVERS** — 0 CRITICAL, 1 MAJOR (stale
  v1 synthesis constraints — regenerated at release), 6 MINOR. Full report:
  `docs/reviews/dac_demdrz_top_review.md`.

PRNG seeds for the three DEM coders are top-level parameters (`SEED_MSB`,
`SEED_ULSB`, `SEED_LSB`); keep them distinct and nonzero (a zero override
silently falls back to the per-segment default), or load seeds at runtime
through the seed write interface.
