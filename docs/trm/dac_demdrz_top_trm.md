# dac_demdrz_top — Technical Reference Manual
| Block | Version | Date | Status | Source RTL |
|---|---|---|---|---|
| dac_demdrz_top | 2.0 | 2026-06-11 | DRAFT (pending design review) | `rtl/dac_demdrz_top.v` + `rtl/dac_dem_coder.v`, `rtl/dac_lfsr16.v`, `rtl/dac_bin2therm.v`, `rtl/dac_rotator7.v`, `rtl/dac_mod7.v` @ git `c5a6ebd07eb96b1ca0c32d18f9e6a730c021fca7` (branch `claude/rtl-dac-design-9jtrdt`) |

This manual documents the design **as built** in the RTL listed above. PRD: `docs/prd/dac_demdrz_top_prd.md`. MAS: `docs/arch/dac_demdrz_top_mas.md`. All behavior marked "verified" refers to the passing regression in `verif/results/dac_demdrz_top_sim.log` (20 directed tests, 39,901 checked cycles, `ALL TESTS PASSED`) against the test plan `verif/plans/dac_demdrz_top_testplan.md`.

## 1. Overview & Features

`dac_demdrz_top` is the digital encoder core of a 12-bit segmented current-steering DAC using the DEMDRZ technique (dynamic element matching + digital return-to-zero; Lin/Huang/Kuo, IEEE JSSC vol. 49, no. 3, 2014). It converts a 12-bit sample stream into 28 registered unit-element switch controls plus their registered complements.

Features (v2):

- 3+3+3+3 segmentation: MSB / ULSB / LSB / LLSB segments of 7 thermometer-coded unit elements each, with element weights 512 / 64 / 8 / 1 LSB.
- Random-rotation DEM on the MSB, ULSB, and LSB segments (`dem_en`), each with a private 16-bit maximal-length LFSR (polynomial x^16 + x^14 + x^13 + x^11 + 1, period 2^16 − 1). The LLSB segment is always plain thermometer.
- Optional digital return-to-zero (`drz_en`): one DRZ mid-code phase (2048 LSB) inserted between every two samples; `clk` runs at 2× the sample rate in DRZ modes.
- Four operating modes: DEMDRZ, DRZ-only, NRZ+DEM, plain NRZ (`dem_en` × `drz_en`).
- Input format select (`fmt_sel`): offset-binary (v1-compatible) or two's-complement, applied per captured sample.
- Runtime-loadable PRNG seeds via a native single-cycle synchronous write interface (`seed_wr` / `seed_addr` / `seed_wdata`), with zero-write substitution and a reserved address that is silently ignored.
- Complementary output rail `sw_*_n`: 28 additional flops in the same output register stage; `sw_*_n === ~sw_*` on every cycle, including reset.
- `data_req` capture handshake; capture-to-output latency exactly 2 clk cycles in all modes.
- Single clock domain; synchronous active-high reset; every flop reset; all `sw_*`, `sw_*_n`, `phase` outputs registered (glitch-free at the boundary).

Verilog-2001, synthesizable, one module per file. The analog portion (switch drivers, current cells, cascodes, biasing) is full-custom and outside RTL scope.

## 2. Block Diagram

```
                       fmt_sel ──┐
 data_in[11:0] ──────────────────▼──────────────────────────────────────────────
              │  bit11 ^ fmt_sel │ bits[10:0] pass    (combinational, sampled
              └──────────►┌──────┴──────┐              only at capture edges)
                          │  data_q[11:0] reg, EN = capture                   │
                          └──┬─────┬─────┬─────┬──────────────────────────────┘
                 [11:9]      │[8:6]│[5:3]│[2:0]│
                  ┌──────────▼┐ ┌──▼───┐ ┌─▼────┐ ┌──▼────────┐
   seed i/f ───►  │ DEM coder │ │ DEM  │ │ DEM  │ │ bin2therm │   (LLSB: no DEM)
   (decoded       │  MSB      │ │ ULSB │ │ LSB  │ │  LLSB     │
    wr strobes)   │ b2t→rot7  │ │      │ │      │ └──────┬────┘
                  │ LFSR16+R  │ │      │ │      │        │
                  └─────┬─────┘ └──┬───┘ └──┬───┘        │
                  dem_msb│   dem_ulsb│ dem_lsb│ therm_llsb│
                  ┌──────▼──────────▼────────▼───────────▼──────┐
   next_phase ───►│ DEMDRZ MUX: signal code  vs  DRZ mid-code   │
                  │ (DRZ: msb=7'b1010101, others=7'b0000000)    │
                  └──────────────────────┬──────────────────────┘
                  ┌──────────────────────▼──────────────────────┐
                  │ output register stage (single clk edge):    │
                  │   phase, sw_msb/ulsb/lsb/llsb  (true rail)  │
                  │   sw_msb_n/ulsb_n/lsb_n/llsb_n (inverted    │
                  │   rail, separate flops, same always block)  │
                  └─────────────────────────────────────────────┘
```

Module hierarchy (instance names as in the RTL, usable for hierarchical references):

| Instance | Module | Function |
|---|---|---|
| `u_dem_msb` / `u_dem_ulsb` / `u_dem_lsb` | `dac_dem_coder` | Per-segment DEM coder (b2t + rotator + LFSR + mod-7 + R register `r_q`) |
| `u_dem_*.u_lfsr` | `dac_lfsr16` | 16-bit maximal-length LFSR (`lfsr_q`) |
| `u_dem_*.u_mod7` | `dac_mod7` | PRN[5:0] → R ∈ 0..6 (octal digit-sum mod-7, no division) |
| `u_dem_*.u_b2t`, `u_b2t_llsb` | `dac_bin2therm` | 3-bit binary → 7-bit thermometer (`therm[i] = (bin > i)`) |
| `u_dem_*.u_rot` | `dac_rotator7` | 7-bit barrel rotation: `therm_out[(i+r) mod 7] = therm_in[i]` |

## 3. Parameters

| Name | Type | Default | Legal range | Effect |
|---|---|---|---|---|
| `SEED_MSB` | `parameter [15:0]` | `16'hACE1` | any 16-bit value; nonzero intended | Reset-default seed of the MSB-segment LFSR. A `16'h0000` override is silently substituted by `16'hACE1` at elaboration (localparam `SEED_MSB_EFF`). |
| `SEED_ULSB` | `parameter [15:0]` | `16'h5EED` | any 16-bit value; nonzero intended | Reset-default seed of the ULSB-segment LFSR. Zero override substituted by `16'h5EED` (`SEED_ULSB_EFF`). |
| `SEED_LSB` | `parameter [15:0]` | `16'hB10D` | any 16-bit value; nonzero intended | Reset-default seed of the LSB-segment LFSR. Zero override substituted by `16'hB10D` (`SEED_LSB_EFF`). |

Notes:

- Seeds should be distinct and nonzero so the three segments' rotation sequences are decorrelated. A zero parameter is not an error: the top level derives effective seeds `SEED_*_EFF = (SEED_* != 16'h0000) ? SEED_* : <v1 default>` and passes only those to the LFSRs, so the all-zero LFSR lock-up state is unreachable even under misconfiguration (CFG-002; verified, test CHK-09/`dut2`). "Parameter seed" everywhere in this document means the **effective** seed.
- Runtime seed writes never alter these reset defaults; `rst` always reloads `SEED_*_EFF` (REQ-014; verified, T-014).
- Non-overridable constants (`localparam`): DRZ mid-code `DRZ_MSB = 7'b1010101`, `DRZ_LOW = 7'b0000000`; seed address map `2'b00`/`2'b01`/`2'b10` (MSB/ULSB/LSB); LFSR polynomial x^16 + x^14 + x^13 + x^11 + 1.

## 4. Ports

All inputs are synchronous to `clk` and sampled on the rising edge; there is no CDC logic inside the block. All outputs except `data_req` are driven directly by flops and change only on rising `clk` edges. "Reset value" is the value loaded on every rising edge with `rst = 1` (inputs have none).

| Name | Dir | Width | Reset value | Timing | Description |
|---|---|---|---|---|---|
| `clk` | in | 1 | — | — | Single clock. Must run at 2× the sample rate when `drz_en = 1`, 1× when `drz_en = 0`. |
| `rst` | in | 1 | — | sampled @posedge | Synchronous, active-high reset. Must be asserted across ≥ 1 rising edge; deassertion must be synchronized to `clk` externally (no internal synchronizer). See §6. |
| `dem_en` | in | 1 | — | sampled @posedge (consumed at capture edges, into the R register) | 1: random-rotation DEM on the MSB/ULSB/LSB segments. 0: R forced to 0 at the next R update → plain thermometer coding. Quasi-static; takes effect at the next capture. |
| `drz_en` | in | 1 | — | combinational into `next_phase`/`data_req`; effect registered @posedge | 1: DEMDRZ phase alternation (signal/DRZ), 1 sample per 2 clk. 0: NRZ, every cycle a signal phase, 1 sample per clk. Quasi-static. |
| `fmt_sel` | in | 1 | — | sampled @posedge, only at capture edges (`data_req = 1`) | 0: `data_in` is offset-binary 0..4095 (v1-compatible; tie low for v1 behavior). 1: `data_in` is two's-complement −2048..+2047, mapped to offset-binary by inverting `data_in[11]`. Applies per captured sample. |
| `data_in` | in | 12 | — | sampled @posedge, only at edges where `data_req = 1` | Input sample; interpretation per `fmt_sel`. Ignored on all other edges. Every 12-bit pattern is legal in both formats. |
| `seed_wr` | in | 1 | — | sampled @posedge | Seed write strobe; one rising edge with `seed_wr = 1` performs one write. May be held high for one write per cycle (see §7, C5). Ignored while `rst = 1`. |
| `seed_addr` | in | 2 | — | sampled @posedge, qualified by `seed_wr` | Target LFSR: `2'b00` = MSB, `2'b01` = ULSB, `2'b10` = LSB, `2'b11` = reserved (write silently ignored). Don't-care when `seed_wr = 0`. |
| `seed_wdata` | in | 16 | — | sampled @posedge, qualified by `seed_wr` | Seed value. `16'h0000` is substituted by the addressed segment's effective parameter seed. Don't-care when `seed_wr = 0`. |
| `data_req` | out | 1 | 0 (forced by `& ~rst`) | combinational (function of the `phase` register, `drz_en`, `rst`) | High during cycles whose ending rising edge captures `data_in`. Exactly: `data_req = (drz_en ? phase : 1'b1) & ~rst`. `data_req = 1` ⇔ this edge captures. |
| `phase` | out | 1 | `1'b0` | driven: reg | 1: `sw_*` currently carry a signal code; 0: `sw_*` carry the DRZ mid-code. This is the FSM state register (§5.4). |
| `sw_msb` | out | 7 | `7'b1010101` | driven: reg, @posedge | MSB-segment switch controls, 512 LSB/element. |
| `sw_ulsb` | out | 7 | `7'b0000000` | driven: reg, @posedge | ULSB-segment switch controls, 64 LSB/element. |
| `sw_lsb` | out | 7 | `7'b0000000` | driven: reg, @posedge | LSB-segment switch controls, 8 LSB/element. |
| `sw_llsb` | out | 7 | `7'b0000000` | driven: reg, @posedge | LLSB-segment switch controls, 1 LSB/element (always plain thermometer, never DEM). |
| `sw_msb_n` | out | 7 | `7'b0101010` | driven: reg (separate flops), @posedge | Bitwise complement of `sw_msb` on every cycle, including reset. Not a wire inversion: dedicated flops in the same output stage. |
| `sw_ulsb_n` | out | 7 | `7'b1111111` | driven: reg (separate flops), @posedge | Bitwise complement of `sw_ulsb`. |
| `sw_lsb_n` | out | 7 | `7'b1111111` | driven: reg (separate flops), @posedge | Bitwise complement of `sw_lsb`. |
| `sw_llsb_n` | out | 7 | `7'b1111111` | driven: reg (separate flops), @posedge | Bitwise complement of `sw_llsb`. |

v1 port-level differences: the v1 port `rst_n` (asynchronous, active-low) is **replaced** by `rst` (synchronous, active-high; MAS decision D1). `fmt_sel`, `seed_wr`, `seed_addr`, `seed_wdata` and the four `sw_*_n` buses are new in v2. All other v1 ports are unchanged in name, width, and timing; with `fmt_sel = 0` and `seed_wr = 0` the block is functionally identical to v1 on all v1 outputs (CFG-003; verified, T-002..T-006/T-017).

## 5. Functional Description

### 5.1 Segmentation and element weights

Each captured 12-bit sample (internal offset-binary code in register `data_q`) is split into four 3-bit fields:

| Segment | Bits of `data_q` | Elements | Weight/element | Encoder |
|---|---|---|---|---|
| MSB | `[11:9]` | 7 | 512 LSB | DEM coder (`u_dem_msb`) |
| ULSB | `[8:6]` | 7 | 64 LSB | DEM coder (`u_dem_ulsb`) |
| LSB | `[5:3]` | 7 | 8 LSB | DEM coder (`u_dem_lsb`) |
| LLSB | `[2:0]` | 7 | 1 LSB | plain `dac_bin2therm` (no DEM, ever) |

During every signal phase the weighted sum of asserted `sw_*` bits equals exactly the captured code: `512·popcount(sw_msb) + 64·popcount(sw_ulsb) + 8·popcount(sw_lsb) + popcount(sw_llsb) = code`. Rotation is value-preserving, so DEM never changes the converted value (REQ-003; verified every signal phase of every test, CHK-03, 30,352 checks).

### 5.2 Input format mapping (`fmt_sel`)

The mapping is a single XOR in front of the capture register:

```
data_int = {data_in[11] ^ fmt_sel, data_in[10:0]};
```

- `fmt_sel = 0`: `data_int = data_in`, offset-binary 0..4095, bit-exact v1 behavior.
- `fmt_sel = 1`: two's-complement value v maps to offset-binary v + 2048. Endpoints: `12'h800` (−2048) → code 0, `12'h000` (0) → code 2048, `12'h7FF` (+2047) → code 4095, `12'hFFF` (−1) → code 2047. Full-scale-preserving; no gain or offset change.

Because the XOR sits before the capture-enabled flop, `fmt_sel` is consumed only at capture edges: the interpretation applied to a sample is the `fmt_sel` value present at that sample's capture, and a sample already held in `data_q` is never reinterpreted (REQ-008; verified, T-007/T-008). Everything downstream of `data_q` operates on offset-binary codes.

### 5.3 DEM coder: LFSR, mod-7, rotation

Each of the three DEM segments contains, inside its `dac_dem_coder` instance:

- A private `dac_lfsr16` (Fibonacci LFSR, feedback `lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]`, i.e. x^16 + x^14 + x^13 + x^11 + 1, period 65,535 — verified by software model, T-020). It advances exactly once per capture, **independent of `dem_en`**, so the PRN timeline is mode-independent.
- `dac_mod7`, reducing `prn[5:0]` to `r_next = prn[5:0] mod 7` via the octal digit-sum identity (`val mod 7 = (val[5:3] + val[2:0]) mod 7`, two conditional subtractions, no divider). The 64 input values map ⌈64/7⌉-balanced onto 0..6 (residue 0 occurs 10 times, residues 1..6 occur 9 times); the long-run R histogram is uniform within ±15% of N/7 per bin (verified, T-018, 14,000 samples per segment).
- The R register: `if (rst) r_q <= 0; else if (capture) r_q <= dem_en ? r_next : 3'd0;`. R updates exactly once per captured sample and is stable for the whole signal phase. `dem_en = 0` forces R = 0 from the next capture → plain thermometer coding (REQ-004).
- `dac_bin2therm` (`therm[i] = 1` iff `bin > i`) followed by `dac_rotator7` (`therm_out[(i+r) mod 7] = therm_in[i]`; the input `r = 7` is treated as 0 but is never produced by `dac_mod7`).

The DRZ mid-code bypasses the rotators and does not consume R. PRN bits `prn[15:6]` are unused (explicitly sunk in `dac_dem_coder`).

### 5.4 Phase sequencer FSM

One FSM: the 1-bit `phase` register (the encoding is the output itself). Next-state logic is separate combinational logic.

| State | Encoding | Meaning |
|---|---|---|
| `PH_DRZ` | `1'b0` | `sw_*` hold the DRZ mid-code |
| `PH_SIG` | `1'b1` | `sw_*` hold a signal code |

| Current state | `drz_en` | Next state |
|---|---|---|
| `PH_DRZ` | 1 | `PH_SIG` |
| `PH_SIG` | 1 | `PH_DRZ` |
| any | 0 | `PH_SIG` |

Equations as implemented:

```
next_phase = drz_en ? ~phase : 1'b1;
capture    = (~next_phase | ~drz_en) & ~rst;   // = (drz_en ? phase : 1'b1) & ~rst
data_req   = capture;
```

Reset state: `PH_DRZ`. There is no lockup state: `next_phase` is a total function of (`phase`, `drz_en`), so any mid-stream `drz_en` toggle reaches a defined state within one cycle.

### 5.5 Capture timing, latency, throughput

A new sample and a new rotation R are loaded at the edge that simultaneously launches a DRZ output (every edge in NRZ mode), so the combinational DEM path settles during the following cycle before the signal-phase edge.

Cycle convention: "cycle N" is the cycle ending at rising edge N; data presented during cycle N with `data_req = 1` is captured at edge N.

| Edge / cycle | DRZ modes (`drz_en = 1`) | NRZ modes (`drz_en = 0`) |
|---|---|---|
| cycle N | `phase = 1`, `data_req = 1`; sample D presented | `data_req = 1`; sample D presented |
| edge N | `data_q ← D`, `r_q` updated, outputs ← DRZ mid-code | `data_q ← D`, `r_q` updated, outputs ← previous sample's code |
| cycle N+1 | `phase = 0` (DRZ mid-code on outputs); DEM path settles | signal phase of the previous sample; DEM path settles |
| edge N+1 | outputs ← signal code of D | outputs ← signal code of D |
| cycle N+2 | `phase = 1`, `sw_*`/`sw_*_n` carry D | `sw_*`/`sw_*_n` carry D |

- **Latency:** presented-cycle → output-cycle = exactly 2 clk cycles, all modes (REQ-027; verified, T-019).
- **Throughput:** 1 sample per 2 clk in DRZ modes (`data_req` high every second cycle); 1 sample per clk in NRZ modes (`data_req` ≡ 1 outside reset), sustained with no stalls or bubbles (verified, T-002/T-004 throughput counters).
- `phase` alternates 1,0,1,0,… in DRZ modes and is constantly 1 in NRZ modes (outside reset).

### 5.6 DRZ mid-code

Every `phase = 0` output cycle carries exactly `sw_msb = 7'b1010101` (MSB elements 1/3/5/7 on = 4 × 512 = 2048 LSB) and `sw_ulsb = sw_lsb = sw_llsb = 7'b0000000`, with complements per the `sw_*_n` invariant — bit-exact regardless of surrounding data, `dem_en`, or seed writes (REQ-022; verified every `phase = 0` cycle, CHK-04).

### 5.7 Seed write interface

A write is a single rising edge with `seed_wr = 1`. Address decode is combinational at the top level; the load mux lives in `dac_lfsr16` with priority **`rst` > `seed_ld` > `en`(advance)**. Zero-write substitution: `seed_eff = (seed_wdata == 16'h0000) ? <effective parameter seed> : seed_wdata`.

| Edge condition | Effect on addressed LFSR | Effect on everything else |
|---|---|---|
| `seed_wr=1`, `seed_addr` ∈ {00,01,10}, `capture=0` | `lfsr_q ← seed_eff` | none |
| `seed_wr=1`, valid addr, `capture=1` (write/advance collision) | write wins: `lfsr_q ← seed_eff`; the natural advance is skipped | `data_q` captures normally; `r_q ← mod7(pre-write PRN)` — the colliding sample's R derives from the pre-write state; the written seed first influences R at the **next** capture |
| next capture edge after the write | first natural advance shifts from the written value | `r_q ← mod7(seed_eff[5:0])` |
| `seed_wr=1`, `seed_addr = 2'b11` | none | none — complete no-op, no error flag |
| `seed_wr=1`, `rst=1` | none (reset priority) | reset behavior, §6 |

Properties (all verified — T-009..T-014 and the T-013 400-cycle random write soak):

- After writing V ≠ 0, the segment's PRN sequence is the reference LFSR sequence from V (REQ-013).
- A write of `16'h0000` behaves identically to writing the segment's effective parameter seed; no LFSR can ever hold `16'h0000` (REQ-015/016 — asserted every cycle of every test).
- A write touches only the addressed `lfsr_q`. Phase sequencing, `data_req` timing, `data_q`, `r_q`, the output registers, and the other two LFSRs are bit-identical to a no-write run (REQ-017/018).
- Writes are accepted every cycle presented; back-to-back writes each take single-cycle effect. While `seed_wr` is held high on a segment, that LFSR never advances naturally (write priority every edge) — its PRN is pinned to `seed_eff` until the strobe drops.
- Reset reloads the parameter seeds regardless of prior writes (REQ-014).
- There is no read-back path.

### 5.8 Output register stage and complementary rail

All 57 output flops (28 true + 28 complement + `phase`) update in a single always block on the same rising edge. The inversion sits **in front of** the `_n` flops: both rails are register outputs of the same MUX result, there is no combinational path from `sw_*` to `sw_*_n` at the block boundary, and `sw_*_n === ~sw_*` holds on every cycle, including DRZ phases and during/after reset (REQ-019/020; complement invariant verified every cycle, CHK-02; same-edge/no-off-edge-change verified by event monitor, CHK-08; the structural "no boundary path" property is by RTL review/lint, not provable by black-box simulation — see §8).

## 6. Reset Behavior

Reset is **synchronous, active-high** (`rst`), a deliberate change from v1's asynchronous active-low `rst_n` (MAS decision D1). Requirements on the integrator:

- `clk` must be running; the block has no defined state before the first rising edge with `rst = 1`.
- Assert `rst` across at least one rising edge (one edge fully resets the design; longer is fine).
- Deassert `rst` synchronously to `clk` (externally synchronized; no internal reset synchronizer).

On every rising edge with `rst = 1` (reset has unconditional priority in every sequential block):

| State | Reset value |
|---|---|
| `phase` | `1'b0` |
| `sw_msb` / `sw_msb_n` | `7'b1010101` / `7'b0101010` (DRZ mid-code = safe near-zero differential) |
| `sw_ulsb`, `sw_lsb`, `sw_llsb` / `_n` | `7'b0000000` / `7'b1111111` |
| `data_q` (internal) | `12'h000` |
| `lfsr_q` ×3 (internal) | `SEED_MSB_EFF` / `SEED_ULSB_EFF` / `SEED_LSB_EFF` |
| `r_q` ×3 (internal) | `3'd0` |

While `rst = 1`: captures, LFSR advances, and seed writes are all suppressed, and `data_req` is forced 0 (the contract "`data_in` is consumed iff `data_req = 1`" holds through reset).

Release sequence with `drz_en = 1` (verified, T-001): the first post-release cycle has `phase = 0` (outputs hold the DRZ mid-code), `data_req = 0`; its edge launches a signal phase carrying the reset `data_q` value (code 0 — all 28 elements off). The second cycle has `phase = 1`, `data_req = 1`, and its edge captures the first real sample; normal 1,0,1,0,… alternation continues. With `drz_en = 0`, `data_req = 1` from the first post-release cycle and one sample is captured per cycle.

## 7. Corner-Case Behavior

All cases below are specified in MAS §5 and verified by the listed tests (`verif/plans/dac_demdrz_top_testplan.md`, all PASS).

| # | Scenario | As-built behavior | Verified by |
|---|---|---|---|
| C1 | Seed write at a non-capture edge | Addressed LFSR loads `seed_eff`; every other flop bit-identical to the no-write run; conversion stream undisturbed | T-009 |
| C2 | Seed write at a capture edge (write/advance collision) | Write wins; advance skipped; colliding sample's R = mod7 of the pre-write PRN; next capture draws R from the written seed | T-010 |
| C3 | Zero-seed write (`seed_wdata = 16'h0000`) | Identical to writing the segment's effective parameter seed; LFSR never 0 | T-011, T-013 soak |
| C4 | Write to reserved address `2'b11` | Complete no-op, cycle-by-cycle bit-identical to no-write; no error flag | T-012, T-013 soak |
| C5 | Back-to-back / held writes | One independent write per cycle; held strobe pins the LFSR (no natural advance) until released; conversion unaffected | T-013 |
| C6 | `fmt_sel` toggled between captures | Each sample uses the `fmt_sel` value at its capture edge; toggles during non-capture cycles have no effect on in-flight samples | T-008 |
| C7 | Two's-complement endpoints | `12'h800`→0, `12'h7FF`→4095, `12'h000`→2048, `12'hFFF`→2047; element-sum-identical to offset-binary v+2048 | T-007 |
| C8 | `dem_en` toggled mid-stream | Takes effect at the next capture (R forced 0 / resumes); in-flight sample keeps its R; PRN timeline unaffected; no value error | T-015 |
| C9 | `drz_en` toggled mid-stream | Defined next state within one cycle (FSM total function); 1→0 makes `data_req` continuously high; 0→1 inserts a DRZ phase next cycle | T-016 |
| C10 | 1-cycle reset mid-stream | Full reset state in one edge; in-flight sample discarded; same end state regardless of history, including prior seed writes | T-001, T-014 |
| C11 | Complement invariant | `sw_*_n === ~sw_*` on every cycle of every test (reset, DRZ, signal, mode changes, write cycles) | CHK-02 |
| C12 | Back-to-back NRZ samples | `data_req ≡ 1`; one sample per clk; each appears exactly 2 cycles after capture; none lost or duplicated | T-004 |
| C13 | Rotation-invariant codes (0 and 7 per segment) | All-off / all-on regardless of R; repeated mid-codes with DEM on show ≥ 2 distinct selections, each summing correctly; LLSB always plain thermometer | T-017 |
| C14 | DRZ pattern exactness | Every `phase = 0` cycle bit-exact `7'b1010101 / 0 / 0 / 0`, including post-reset cycles before the first capture | CHK-04, T-001 |
| C15 | Write during reset | Ignored (reset priority); LFSRs hold parameter seeds after reset | T-014 |
| C16 | Zero seed parameter override | Elaborates; behaves exactly as with the v1 default for that segment; LFSR never 0 | CHK-09 (`dut2`) |
| C17 | v1-equivalence configuration (`fmt_sel = 0`, `seed_wr = 0`) | All v1 outputs match v1 behavior in all four modes (reset connection adapted per MAS M3) | T-002..T-006, T-017 |
| C18 | LFSR vs reference across runtime writes | PRN sequence matches the software reference LFSR every cycle, including across injected writes; state ≠ 0 always | CHK-06, T-020 |

## 8. Restrictions & Known Limitations

1. **Reset scheme is not v1-compatible.** `rst` is synchronous active-high; v1's asynchronous active-low `rst_n` is gone. Outputs are undefined until the first rising `clk` edge with `rst = 1` (no defined state without a running clock). Migrating v1 integrations must invert/adapt the reset connection and guarantee ≥ 1 full-cycle assertion with synchronized deassertion (MAS assumptions M1/M2).
2. **No CDC.** All inputs must be synchronous to `clk`. The block contains no synchronizers.
3. **Quasi-static mode inputs.** `dem_en`, `drz_en`, `fmt_sel` may legally change mid-stream (effects are defined per §7 C6/C8/C9), but no glitch-free output guarantee is given for mid-phase toggling of `dem_en`/`drz_en` (PRD A2).
4. **`data_req` is combinational** (decoded from the `phase` register, `drz_en`, and `rst`). It is glitch-free in steady state but is not a registered output; include the decode in the external timing budget and do not re-register it (that would shift the handshake by one cycle).
5. **Seed interface limitations:** no standard bus protocol, no read-back of seeds or LFSR state, no error/status flags. Address `2'b11` is reserved and silently ignored. `seed_addr`/`seed_wdata` are don't-care when `seed_wr = 0`. Holding `seed_wr` high suppresses the addressed LFSR's natural advance for as long as it is held.
6. **Zero seed parameters are silently substituted**, not rejected: Verilog-2001 has no portable elaboration-time `$error` (MAS decision D4). An integration that overrides a seed to `16'h0000` gets the v1 default for that segment with no warning.
7. **fmax is not characterized** (PRD A8: no numeric target; the paper's reference point is 3.2 GHz clk for 1.6 GS/s, technology-dependent). Not a verification gate.
8. **REQ-020 ("no combinational path `sw_*` → `sw_*_n` at the boundary") is verified by simulation plus analysis only** — same-edge dual-rail updates and the off-edge-change monitor (CHK-08) in simulation, plus RTL review of the separate `_n` flops and the clean lint run. It is not provable by black-box simulation (test plan §4 escalation).
9. **Design review report (D8) is not yet issued** at the time of writing; this document is DRAFT until that review completes. No verification escalations beyond items 7–8 were raised (test plan §4).
10. **Analog scope:** switch drivers, current cells, cascodes, biasing, and element matching are outside this block; the RTL guarantees only the digital switch-control values and their timing.
