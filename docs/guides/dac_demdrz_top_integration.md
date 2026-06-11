# dac_demdrz_top — Integration & User Guide
| Block | Version | Date | Status | Source RTL |
|---|---|---|---|---|
| dac_demdrz_top | 2.0 | 2026-06-11 | RELEASED | `rtl/dac_demdrz_top.v` + `rtl/dac_dem_coder.v`, `rtl/dac_lfsr16.v`, `rtl/dac_bin2therm.v`, `rtl/dac_rotator7.v`, `rtl/dac_mod7.v` @ git `c5a6ebd07eb96b1ca0c32d18f9e6a730c021fca7` (branch `claude/rtl-dac-design-9jtrdt`) |

Companion document: the Technical Reference Manual, `docs/trm/dac_demdrz_top_trm.md` (full port/parameter tables, theory of operation, corner cases).

## 1. What This Block Does

`dac_demdrz_top` turns a 12-bit sample stream into 28 thermometer-coded, registered switch controls (plus their registered complements) for a segmented current-steering DAC, applying random-rotation dynamic element matching (DEM) and an optional digital return-to-zero (DRZ) mid-code phase between samples. Use it as the digital encoder in front of full-custom DAC switch drivers when you need mismatch decorrelation (DEM), code-dependent-transient suppression (DRZ), or both — or run it as a plain binary-to-thermometer encoder with both features disabled.

## 2. Instantiation Example (copy-pasteable, valid Verilog-2001)

All ports connected by name, in RTL declaration order. New-in-v2 inputs are shown driven; if you do not need them, tie `fmt_sel = 1'b0` and `seed_wr = 1'b0` (then `seed_addr`/`seed_wdata` are don't-care) for exact v1 behavior.

```verilog
    // -- upstream / system signals -------------------------------------------
    wire        dac_clk;          // 2x sample rate (drz_en=1) or 1x (drz_en=0)
    wire        dac_rst;          // sync active-high, deassertion synchronized
                                  //   to dac_clk, asserted >= 1 full cycle
    wire        cfg_dem_en;       // quasi-static mode controls
    wire        cfg_drz_en;
    wire        cfg_fmt_twos;     // 0: offset-binary, 1: two's-complement
    wire [11:0] dsp_sample;       // sample stream from the DSP
    wire        csr_seed_wr;      // seed write port from the system controller
    wire [1:0]  csr_seed_addr;    // 00 MSB, 01 ULSB, 10 LSB (11 reserved)
    wire [15:0] csr_seed_wdata;

    // -- encoder outputs ------------------------------------------------------
    wire        dac_data_req;     // sample-consume handshake back to the DSP
    wire        dac_phase;        // 1: signal code, 0: DRZ mid-code
    wire [6:0]  drv_msb,   drv_ulsb,   drv_lsb,   drv_llsb;    // true rail
    wire [6:0]  drv_msb_n, drv_ulsb_n, drv_lsb_n, drv_llsb_n;  // complement rail

    dac_demdrz_top #(
        .SEED_MSB   (16'h8A2F),   // distinct nonzero reset seeds per instance
        .SEED_ULSB  (16'h31C7),   //   (override to decorrelate multiple DACs;
        .SEED_LSB   (16'hD4B9)    //    defaults ACE1/5EED/B10D if omitted)
    ) u_dac_encoder (
        .clk        (dac_clk),
        .rst        (dac_rst),
        .dem_en     (cfg_dem_en),
        .drz_en     (cfg_drz_en),
        .fmt_sel    (cfg_fmt_twos),
        .data_in    (dsp_sample),
        .seed_wr    (csr_seed_wr),
        .seed_addr  (csr_seed_addr),
        .seed_wdata (csr_seed_wdata),
        .data_req   (dac_data_req),
        .phase      (dac_phase),
        .sw_msb     (drv_msb),
        .sw_ulsb    (drv_ulsb),
        .sw_lsb     (drv_lsb),
        .sw_llsb    (drv_llsb),
        .sw_msb_n   (drv_msb_n),
        .sw_ulsb_n  (drv_ulsb_n),
        .sw_lsb_n   (drv_lsb_n),
        .sw_llsb_n  (drv_llsb_n)
    );
```

Compile order for simulation/synthesis (six files, one module each): `rtl/dac_demdrz_top.v`, `rtl/dac_dem_coder.v`, `rtl/dac_lfsr16.v`, `rtl/dac_bin2therm.v`, `rtl/dac_rotator7.v`, `rtl/dac_mod7.v`.

## 3. Bring-Up Instructions

### 3.1 Clocking and reset requirements

- **One clock, `clk`.** It must run at **2× the sample rate when `drz_en = 1`** (each sample occupies one signal phase + one DRZ phase) and 1× the sample rate when `drz_en = 0`. All inputs must be synchronous to `clk` — the block has no CDC logic.
- **Reset is synchronous, active-high** (`rst`). This differs from v1 (`rst_n`, async active-low). Rules:
  1. `clk` must be toggling — nothing is reset without a clock edge.
  2. Hold `rst = 1` across **at least one rising edge** (more is fine).
  3. Deassert `rst` **synchronously to `clk`** (use your chip-level reset synchronizer; there is none inside the block).
- During reset the outputs hold the DRZ mid-code (`sw_msb = 7'b1010101`, all other true-rail bits 0, complements inverted), `phase = 0`, and `data_req = 0`. This is a safe near-zero differential code for the analog side.

### 3.2 Initialization sequence

1. Set the mode inputs (`dem_en`, `drz_en`, `fmt_sel`) to their intended values. Drive `seed_wr = 0`.
2. Assert `rst` for ≥ 1 clk cycle, then deassert it synchronously. The three LFSRs now hold the parameter seeds and the outputs hold the DRZ mid-code.
3. (Optional) Reprogram PRNG seeds: pulse `seed_wr` for one cycle with `seed_addr` = `2'b00`/`2'b01`/`2'b10` (MSB/ULSB/LSB) and the 16-bit seed on `seed_wdata`. One write per cycle; writes never disturb the sample stream. Writing `16'h0000` loads the parameter seed instead; address `2'b11` is ignored.
4. Start presenting samples whenever `data_req = 1` (see below). No other enable or warm-up is needed.

### 3.3 First transaction, cycle by cycle (DEMDRZ mode: `dem_en = 1`, `drz_en = 1`)

Let cycle 1 be the first cycle after `rst` deasserts. "Edge N" is the rising edge ending cycle N.

| Cycle | `phase` | `data_req` | Outputs `sw_*`/`sw_*_n` | What you do / what happens at the ending edge |
|---|---|---|---|---|
| (reset) | 0 | 0 | DRZ mid-code | Hold `rst = 1` ≥ 1 cycle, then release synchronously. |
| 1 | 0 | 0 | DRZ mid-code | Nothing to drive. Edge 1 loads a signal phase from the reset-value code 0 (all elements off). |
| 2 | 1 | **1** | all elements off (code 0 preamble) | Present your first sample `D0` on `data_in` (with `fmt_sel` valid). Edge 2 **captures `D0`** and launches a DRZ phase. |
| 3 | 0 | 0 | DRZ mid-code (`sw_msb = 1010101`, rest 0) | DEM path settles internally. Edge 3 loads the signal code for `D0`. |
| 4 | 1 | 1 | **signal code for `D0`** (weighted sum = captured code) | Present the next sample `D1`; edge 4 captures it. Steady state from here: a new sample every second cycle, each visible exactly 2 cycles after its capture. |

In NRZ mode (`drz_en = 0`): `data_req = 1` from cycle 1 onward, one sample is captured at every edge, and each sample's code appears on the outputs two cycles after the cycle in which it was presented (the pipeline accepts one sample per clock with no stalls).

Sanity checks during bring-up: `phase` alternates 1,0,1,0,… (DRZ) or sticks at 1 (NRZ); every `phase = 0` cycle shows exactly `sw_msb = 7'b1010101` with all other true-rail bits 0; `sw_*_n` is the bitwise inverse of `sw_*` on every cycle; during every `phase = 1` cycle, `512·popcount(sw_msb) + 64·popcount(sw_ulsb) + 8·popcount(sw_lsb) + popcount(sw_llsb)` equals the captured sample's offset-binary code.

## 4. Running the Testbench

From the repo root (`build/` and `verif/results/` must exist):

```sh
mkdir -p build verif/results
iverilog -g2001 -o build/dac_demdrz_top.vvp \
    rtl/dac_demdrz_top.v rtl/dac_dem_coder.v rtl/dac_lfsr16.v \
    rtl/dac_bin2therm.v rtl/dac_rotator7.v rtl/dac_mod7.v \
    tb/dac_demdrz_top_tb.v
vvp build/dac_demdrz_top.vvp | tee verif/results/dac_demdrz_top_sim.log
```

**Interpreting the output.** The testbench is fully self-checking (cycle-exact reference model + independent invariant checkers, see `verif/plans/dac_demdrz_top_testplan.md`). A passing run prints one `[T-0xx] PASS` line per directed test (T-020, T-001..T-019), a summary line, and ends with:

```
[TB] directed tests: 20, cycles checked: 39901, captures: 30351, signal-phase sum checks: 30352
ALL TESTS PASSED
```

Any failure prints one `TEST FAILED: <test> <checker> expected=... actual=... t=<time>` line per mismatch (per-cycle checkers cap at 100 messages), the affected test reports `[T-0xx] FAIL (n errors)`, and the run ends with `<n> TESTS FAILED` instead of `ALL TESTS PASSED`. A `TEST FAILED: WATCHDOG simulation did not finish` message means the simulation hung. Exit criterion for scripts: grep the log for the literal line `ALL TESTS PASSED`.

**Viewing waveforms.** The testbench dumps every signal (including DUT internals such as `dut.u_dem_msb.u_lfsr.lfsr_q` and `dut.u_dem_msb.r_q`) to `build/dac_demdrz_top.vcd`:

```sh
gtkwave build/dac_demdrz_top.vcd &
```

Useful signals to add first: `clk`, `rst`, `data_req`, `phase`, `data_in`, `sw_msb`, `sw_msb_n`, and the failing checker's `t=` timestamp from the log to navigate directly to the mismatch.

**Lint** (RTL only, never the testbench): `verilator --lint-only -Wall rtl/dac_demdrz_top.v rtl/dac_dem_coder.v rtl/dac_lfsr16.v rtl/dac_bin2therm.v rtl/dac_rotator7.v rtl/dac_mod7.v`.

## 5. Common Pitfalls & FAQ

### Pitfalls

1. **Wrong clock-to-sample-rate ratio.** `clk` is 2× the sample rate **only when `drz_en = 1`**. In NRZ modes it is 1×. If you change `drz_en` you change the consumption rate — watch `data_req`, which tells you exactly which cycles consume `data_in`.
2. **Treating `rst` like the v1 `rst_n`.** Polarity is inverted *and* the scheme changed from asynchronous to synchronous. Without clock edges nothing resets, and the outputs are undefined before the first `rst = 1` edge. Migrations from v1 must adapt the reset connection (e.g. `rst = ~rst_n_sync`) and ensure ≥ 1 full-cycle assertion with synchronized deassertion.
3. **Driving `data_in` only on `data_req` edges but expecting immediate output.** The latency is exactly 2 clk cycles from the presented cycle to the output cycle; in DRZ mode the intervening cycle is a DRZ phase. Align any downstream timestamping with `phase`.
4. **Assuming `fmt_sel` reinterprets data already in flight.** `fmt_sel` is consumed only at capture edges (`data_req = 1`). Toggling it mid-stream is legal but affects only samples captured from then on; a captured sample is never reinterpreted.
5. **Expecting a seed write to change the very next rotation.** The LFSR state changes on the write edge, but the rotation R registered at a colliding capture edge still derives from the pre-write PRN; the written seed first influences R at the **next** capture. The conversion values are never affected either way.
6. **Holding `seed_wr` high "to be safe."** Every cycle with `seed_wr = 1` is a new write, and write priority suppresses the addressed LFSR's natural advance — holding the strobe pins that segment's PRN and freezes its DEM rotation sequence. Pulse it for one cycle per write.
7. **Regenerating `sw_*_n` externally as `~sw_*`.** The complement rail exists precisely so both rails are flop outputs with matched launch timing (no boundary inversion path). An external wire inversion reintroduces the skew the design removes. Use the provided `sw_*_n` pins.
8. **Expecting an error on bad seed traffic.** Address `2'b11` is reserved and **silently ignored**; `seed_wdata = 16'h0000` silently loads the parameter seed; a zero seed *parameter* override silently falls back to the v1 default. There are no error/status flags — by design.
9. **Re-registering `data_req`.** It is combinational (from the `phase` register, `drz_en`, `rst`). Adding a flop shifts the handshake one cycle and you will capture the wrong samples. Use it combinationally, and budget its decode in your timing.
10. **Forgetting the new v2 inputs when porting a v1 integration.** Tie `fmt_sel = 1'b0` and `seed_wr = 1'b0` (leave `seed_addr`/`seed_wdata` tied to anything) and the block is functionally identical to v1 on all v1 outputs.

### FAQ

**Q: How do I get a plain binary-to-thermometer encoder (no DEM, no DRZ)?**
Set `dem_en = 0`, `drz_en = 0`. One sample per clk, `phase ≡ 1`, every segment is the plain thermometer code of its 3-bit field.

**Q: What is on the outputs during DRZ phases?**
Always exactly `sw_msb = 7'b1010101`, all other true-rail bits 0 (mid-code, 2048 LSB), complements inverted — regardless of data, `dem_en`, or seed writes. `phase = 0` marks these cycles.

**Q: What does the analog side see right after reset?**
The DRZ mid-code (near-zero differential), held until the clocked sequence starts. The first signal phase after release carries code 0 (all elements off) as a one-sample preamble before your first captured sample appears.

**Q: Can I write seeds while the DAC is streaming?**
Yes. Seed writes at any time — including capture edges, back-to-back, or to the reserved address — never disturb phase sequencing, `data_req`, or output values; only the future rotation sequence changes. This was soak-tested with random writes during streaming (test T-013).

**Q: Does two's-complement mode change gain or offset?**
No. `fmt_sel = 1` maps value v to internal code v + 2048 (an MSB inversion): −2048 → 0, 0 → 2048, +2047 → 4095. Element-sum-identical to offset-binary with the same shifted code.

**Q: How do I decorrelate several DAC instances?**
Either override `SEED_MSB`/`SEED_ULSB`/`SEED_LSB` per instance (distinct, nonzero) or write distinct seeds at runtime through the seed interface. Reset always restores the parameter seeds.

**Q: Is there a read-back path for seeds or LFSR state?**
No (by design). In simulation you can observe `u_dac_encoder.u_dem_msb.u_lfsr.lfsr_q` etc. hierarchically.

**Q: What is the maximum clock frequency?**
Not characterized; no numeric target is imposed (the reference silicon in the underlying paper runs a 3.2 GHz encoder clock at 1.6 GS/s, technology-dependent). Close timing in your target process.
