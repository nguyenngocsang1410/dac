# dac_demdrz_top (v2) — Microarchitecture Specification
| Block | Version | Date | Status | PRD ref |
|---|---|---|---|---|
| dac_demdrz_top | 2.0 | 2026-06-11 | APPROVED | docs/prd/dac_demdrz_top_prd.md |

## 1. Overview & Block Diagram

`dac_demdrz_top` v2 is the digital encoder of a 12-bit segmented current-steering
DAC with the DEMDRZ technique (Lin/Huang/Kuo, IEEE JSSC vol. 49, no. 3, 2014).
It reuses the proven v1 microarchitecture unchanged — 3+3+3+3 segmentation,
per-segment DEM coder (binary-to-thermometer + 7-bit barrel rotator + private
16-bit maximal-length LFSR + octal-digit-sum mod-7), DRZ mid-code MUX, single
output register stage, 2-cycle capture-to-output latency — and adds:

1. **Input format select** (`fmt_sel`): two's-complement input is mapped to the
   internal offset-binary code by inverting `data_in[11]` at the capture
   register. Zero added latency; the entire downstream datapath is unchanged.
2. **Runtime seed write interface** (`seed_wr`, `seed_addr[1:0]`,
   `seed_wdata[15:0]`): a single-cycle synchronous load into the addressed
   LFSR, with write-over-advance priority and zero-value substitution.
3. **Complementary outputs** (`sw_*_n[6:0]`): a second bank of 28 flops in the
   same output register stage, loaded with the inverted MUX value on the same
   clock edge.

One deliberate deviation from v1: the reset is changed from **asynchronous
active-low (`rst_n`)** to **synchronous active-high (`rst`)** per CLAUDE.md §6
(decision D1, §6).

```
                       fmt_sel ──┐
 data_in[11:0] ──────────────────▼──────────────────────────────────────────────
              │  bit11 ^ fmt_sel │ bits[10:0] pass    (combinational, sampled
              └──────────►┌──────┴──────┐              only at capture edges)
                          │  data_q[11:0] reg, EN = capture                   │
                          └──┬─────┬─────┬─────┬──────────────────────────────┘
                 [11:9]      │[8:6]│[5:3]│[2:0]│
                  ┌──────────▼┐ ┌──▼───┐ ┌─▼────┐ ┌──▼────────┐
   seed if  ───►  │ DEM coder │ │ DEM  │ │ DEM  │ │ bin2therm │   (LLSB: no DEM)
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

**File / module structure** (one module per file, top name unchanged):

| File | Module | v1 → v2 change |
|---|---|---|
| `rtl/dac_demdrz_top.v` | `dac_demdrz_top` | + `fmt_sel`, seed interface + decode, `sw_*_n` flops, sync active-high reset, zero-parameter substitution localparams |
| `rtl/dac_dem_coder.v` | `dac_dem_coder` | + seed load ports plumbed to LFSR; sync active-high reset |
| `rtl/dac_lfsr16.v` | `dac_lfsr16` | + load port with write priority and zero-substitution; sync active-high reset |
| `rtl/dac_bin2therm.v` | `dac_bin2therm` | unchanged (combinational) |
| `rtl/dac_rotator7.v` | `dac_rotator7` | unchanged (combinational) |
| `rtl/dac_mod7.v` | `dac_mod7` | unchanged (combinational) |

## 2. Interface

### 2.1 Parameters

| Name | Default | Legal range | Description |
|---|---|---|---|
| `SEED_MSB` | `16'hACE1` | 16-bit; nonzero intended | Reset/default seed, MSB-segment LFSR. A zero override is substituted at elaboration (see below). |
| `SEED_ULSB` | `16'h5EED` | 16-bit; nonzero intended | Reset/default seed, ULSB-segment LFSR. Zero substituted at elaboration. |
| `SEED_LSB` | `16'hB10D` | 16-bit; nonzero intended | Reset/default seed, LSB-segment LFSR. Zero substituted at elaboration. |

Zero-parameter substitution (CFG-002, REQ-015): the top level derives effective
seeds as `localparam`s and passes only those down:

```
localparam [15:0] SEED_MSB_EFF  = (SEED_MSB  != 16'h0000) ? SEED_MSB  : 16'hACE1;
localparam [15:0] SEED_ULSB_EFF = (SEED_ULSB != 16'h0000) ? SEED_ULSB : 16'h5EED;
localparam [15:0] SEED_LSB_EFF  = (SEED_LSB  != 16'h0000) ? SEED_LSB  : 16'hB10D;
```

So a misconfigured zero parameter silently falls back to the v1 default for
that segment, and every `dac_lfsr16` instance is guaranteed a nonzero `SEED`
parameter. The "reset-default parameter seed" referenced everywhere below means
the **effective** seed `SEED_*_EFF`.

Other constants (`localparam`, not overridable): `DRZ_MSB = 7'b1010101`,
`DRZ_LOW = 7'b0000000`; seed address map values (§4.1.4); LFSR polynomial
x^16 + x^14 + x^13 + x^11 + 1 (unchanged from v1).

### 2.2 Ports

All inputs are synchronous to `clk` and sampled on the rising edge; no CDC
inside the block. "Driven: reg" means the output comes directly from a flop.

| Name | Dir | Width | Timing | Description |
|---|---|---|---|---|
| `clk` | in | 1 | — | Single clock. 2× sample rate when `drz_en=1`, 1× when `drz_en=0`. |
| `rst` | in | 1 | sampled @posedge | **Synchronous, active-high** reset (decision D1). Must be asserted for ≥ 1 full clk cycle (≥ 1 rising edge while high). While high, every flop loads its reset value on each rising edge. |
| `dem_en` | in | 1 | sampled @posedge (at R-update edges) | 1: random-rotation DEM on MSB/ULSB/LSB segments; 0: plain thermometer (R forced to 0 at the next R update). Quasi-static (PRD A2). |
| `drz_en` | in | 1 | combinational into `next_phase`/`data_req`; effect registered @posedge | 1: DEMDRZ phase alternation; 0: NRZ (every cycle a signal phase). Quasi-static (PRD A2). |
| `fmt_sel` | in | 1 | sampled @posedge, **only at capture edges** | 0: `data_in` is offset-binary 0..4095 (v1-compatible; tie low for v1 behavior). 1: `data_in` is two's-complement −2048..+2047 (PRD A1). Applies per captured sample (REQ-008). |
| `data_in` | in | 12 | sampled @posedge, only at edges where `data_req=1` | Input sample, interpretation per `fmt_sel`. |
| `seed_wr` | in | 1 | sampled @posedge | Seed write strobe; a single cycle high performs one write. May be held high for repeated writes (one per cycle). Ignored while `rst=1`. |
| `seed_addr` | in | 2 | sampled @posedge (qualified by `seed_wr`) | Target LFSR: `2'b00`=MSB, `2'b01`=ULSB, `2'b10`=LSB, `2'b11`=reserved (write ignored, REQ-018). Don't-care when `seed_wr=0`. |
| `seed_wdata` | in | 16 | sampled @posedge (qualified by `seed_wr`) | Seed value. `16'h0000` is substituted by the addressed segment's effective parameter seed (REQ-016, PRD A5). Don't-care when `seed_wr=0`. |
| `data_req` | out | 1 | combinational (from `phase` reg, `drz_en`, `rst`) | High during cycles whose rising edge captures `data_in`. `data_req = capture & ~rst`, so `data_req=1` ⇔ this edge captures (REQ-025). |
| `phase` | out | 1 | driven: reg | 1: `sw_*` carry a signal code; 0: DRZ mid-code. Reset value 0. |
| `sw_msb` | out | 7 | driven: reg | MSB switch controls, 512 LSB/element. Reset value `7'b1010101`. |
| `sw_ulsb` | out | 7 | driven: reg | ULSB switch controls, 64 LSB/element. Reset value `7'b0000000`. |
| `sw_lsb` | out | 7 | driven: reg | LSB switch controls, 8 LSB/element. Reset value `7'b0000000`. |
| `sw_llsb` | out | 7 | driven: reg | LLSB switch controls, 1 LSB/element. Reset value `7'b0000000`. |
| `sw_msb_n` | out | 7 | driven: reg (separate flops) | Bitwise complement of `sw_msb`, every cycle incl. reset. Reset value `7'b0101010`. |
| `sw_ulsb_n` | out | 7 | driven: reg | Complement of `sw_ulsb`. Reset value `7'b1111111`. |
| `sw_lsb_n` | out | 7 | driven: reg | Complement of `sw_lsb`. Reset value `7'b1111111`. |
| `sw_llsb_n` | out | 7 | driven: reg | Complement of `sw_llsb`. Reset value `7'b1111111`. |

v1 port-level differences (CFG-003 note): `rst_n` (async, active-low) is
**replaced** by `rst` (sync, active-high); all other v1 ports are unchanged in
name, width, and timing. The v1 testbench passes against v2 with new inputs
tied inactive (`fmt_sel=0`, `seed_wr=0`, `seed_addr/seed_wdata` don't-care)
after adapting only the reset connection/polarity (assumption M3).

## 3. Clocking & Reset

- **Single clock domain** `clk`. All sequential logic on `posedge clk` only.
  Frequency: 2× sample rate for DRZ modes, 1× for NRZ modes; no numeric fmax
  gate (PERF-005, PRD A8).
- **Reset: synchronous, active-high `rst`** (decision D1; deviation from v1's
  async active-low — see §6). Every flop in the design is reset. Minimum
  assertion: one full clk cycle (the design needs exactly one rising edge with
  `rst=1` to reach the reset state). `rst` must be deasserted synchronously to
  `clk` (assumption M1 — the integrator provides a clean, synchronized reset;
  there is no internal synchronizer).
- **State at/after reset** (REQ-029): on every rising edge with `rst=1`:
  - `phase <= 1'b0`
  - `sw_msb <= 7'b1010101`, `sw_ulsb/sw_lsb/sw_llsb <= 7'b0000000` (DRZ mid-code)
  - `sw_msb_n <= 7'b0101010`, `sw_ulsb_n/sw_lsb_n/sw_llsb_n <= 7'b1111111`
    (exact complements — REQ-019 holds during and after reset)
  - `data_q <= 12'h000` (internal offset-binary code 0)
  - each `lfsr_q <= SEED_*_EFF`; each `r_q <= 3'd0`
- **Behavior while `rst=1`:** seed writes, captures, and LFSR advances are all
  suppressed (reset has unconditional priority in every sequential block).
  `data_req` is forced 0 by the `& ~rst` gating, so the capture contract
  "`data_in` is consumed iff `data_req=1`" holds even through reset.
- **Behavior immediately after deassertion** (with `drz_en=1`): cycle 1 after
  release has `phase=0` (outputs hold the DRZ code), `next_phase=1`,
  `data_req=0`; its edge launches a signal phase carrying the reset value of
  `data_q` (= code 0, i.e. all 28 elements off). Cycle 2 has `phase=1`,
  `data_req=1` and captures the first real sample; normal 1,0,1,0,…
  alternation continues from there. With `drz_en=0`, `data_req=1` from the
  first post-release cycle and one sample is captured per cycle. (Identical
  sequencing to v1.)

## 4. Microarchitecture

### 4.1 Datapath

#### 4.1.1 Phase / capture / handshake timing (unchanged from v1)

```
next_phase = drz_en ? ~phase : 1'b1;       // phase the output regs will hold next
capture    = (~next_phase | ~drz_en) & ~rst;
data_req   = capture;                       // combinational output
```

`capture` is high during the cycle whose edge launches a **DRZ** output (or
every cycle in NRZ mode): the new sample and the new rotation R are loaded
while the DRZ code occupies the outputs, so the whole combinational DEM path
(b2t → rotator, with R already registered) settles during the following cycle
before the signal-phase edge. This gives:

- DRZ modes: `phase` = 1,0,1,0,…; `data_req` high every second cycle
  (the `phase=1` cycles); throughput 1 sample / 2 clk (PERF-001, REQ-021).
- NRZ modes: `phase` ≡ 1, `data_req` ≡ 1 (outside reset); 1 sample / clk
  (PERF-002, REQ-023).
- Latency: capture edge N loads `data_q`/R; edge N+1 loads the output
  registers with the signal code; the code is visible on `sw_*`/`sw_*_n`
  during cycle N+2 ⇒ **exactly 2 clk cycles** capture→output, all modes
  (REQ-027, PERF-003).

The only state element in this control path is the 1-bit `phase` register —
documented as the 2-state FSM in §4.2.

#### 4.1.2 Input format mapping (new — REQ-005..008)

Two's-complement value v maps to internal offset-binary code v + 2048, which
is exactly an inversion of bit 11 (PRD A9). The mapping is applied
**combinationally in front of the capture register**, and is therefore sampled
at precisely the capture edges and nowhere else:

```
wire [11:0] data_int = {data_in[11] ^ fmt_sel, data_in[10:0]};

always @(posedge clk) begin
    if (rst)          data_q <= 12'h000;
    else if (capture) data_q <= data_int;
end
```

- `fmt_sel=0`: `data_int = data_in` — bit-exact v1 behavior (REQ-006, CFG-003).
- `fmt_sel=1`: −2048 (`12'h800`) → code 0; 0 (`12'h000`) → code 2048;
  +2047 (`12'h7FF`) → code 4095. Full-scale-preserving, no gain/offset change
  (REQ-007).
- Per-capture semantics for free (REQ-008): `fmt_sel` is consumed only when
  `capture=1`; toggling it in non-capture cycles has no effect, and a sample
  already held in `data_q` is never reinterpreted. Everything downstream of
  `data_q` operates on offset-binary codes exactly as in v1.

#### 4.1.3 Segmentation, DEM coders, LLSB (unchanged from v1)

`data_q` splits as MSB = `data_q[11:9]`, ULSB = `data_q[8:6]`,
LSB = `data_q[5:3]`, LLSB = `data_q[2:0]` (REQ-001); element weights
512/64/8/1 LSB (REQ-002). MSB/ULSB/LSB each instantiate `dac_dem_coder`
(REQ-009/011); LLSB uses a bare `dac_bin2therm` (no DEM, ever — REQ-009).

Inside each `dac_dem_coder` (per segment):
- `dac_lfsr16` (private, distinct seed) advances once per `capture`
  (i.e. once per captured sample) — **independent of `dem_en`**, exactly as
  in v1, so the PRN stream timeline is mode-independent.
- `dac_mod7` reduces `prn[5:0]` to `r_next` ∈ 0..6 via the octal digit-sum
  identity (uniform per v1 analysis, REQ-010 — the 64 input values map
  ⌈64/7⌉-balanced onto 0..6; verified by reference model).
- R register: `if (rst) r_q <= 3'd0; else if (capture) r_q <= dem_en ? r_next : 3'd0;`
  R updates exactly once per sample and is stable for the whole signal phase
  (REQ-010); `dem_en=0` degenerates to plain thermometer (REQ-004).
- Rotation is value-preserving (`dac_rotator7` is a pure barrel rotation), so
  the weighted element sum always equals the captured code (REQ-003).

#### 4.1.4 Seed write interface (new — REQ-012..018), cycle-by-cycle

**Address decode** (top level, combinational):

```
wire seed_wr_msb  = seed_wr & (seed_addr == 2'b00);
wire seed_wr_ulsb = seed_wr & (seed_addr == 2'b01);
wire seed_wr_lsb  = seed_wr & (seed_addr == 2'b10);
// seed_addr == 2'b11: no strobe asserted -> write silently ignored (REQ-018)
```

Each per-segment strobe and the shared `seed_wdata[15:0]` are plumbed through
`dac_dem_coder` (new ports `seed_ld`, `seed_in[15:0]`) into `dac_lfsr16`.

**LFSR register, priority order** (inside `dac_lfsr16`, new ports
`seed_ld`/`seed_in`):

```
wire [15:0] seed_eff = (seed_in == 16'h0000) ? SEED : seed_in;  // REQ-016 / A5

always @(posedge clk) begin
    if (rst)          lfsr_q <= SEED;          // parameter (effective) seed
    else if (seed_ld) lfsr_q <= seed_eff;      // write wins over advance (A4)
    else if (en)      lfsr_q <= {lfsr_q[14:0], fb};
end
```

(`SEED` here is the effective nonzero seed passed from the top, §2.1.)

**Cycle-by-cycle protocol.** A write is a single rising clk edge with
`seed_wr=1` and a valid `seed_addr`:

| Edge | Condition | Effect on addressed LFSR | Effect on everything else |
|---|---|---|---|
| N | `seed_wr=1`, `addr` ∈ {00,01,10}, `capture=0` | `lfsr_q <= seed_eff` | none |
| N | `seed_wr=1`, valid `addr`, `capture=1` (collision, A4/REQ-013) | **write wins**: `lfsr_q <= seed_eff`; the natural advance is skipped | `data_q` captures normally; `r_q <= mod7(prn_old)` — the R for the sample captured at edge N derives from the **pre-write** PRN state (the rotator R was always sampled from the pre-edge PRN; the write does not retroactively change it) |
| N+k (next `capture` edge after the write) | — | first natural advance **shifts from the written value**: next state = shift(seed_eff) | `r_q <= mod7(seed_eff[5:0])` — the first R drawn from the new seed |
| any | `seed_wr=1`, `addr = 2'b11` | none | none — zero state change anywhere (REQ-018) |
| any | `seed_wr=1`, `rst=1` | none (reset priority) | reset behavior §3 |

Properties guaranteed by construction:
- After a write of value V (≠0), the segment's PRN sequence is exactly the
  reference LFSR sequence started from V: V, shift(V), shift²(V), … (REQ-013).
- A write of `16'h0000` behaves identically to a write of the segment's
  effective parameter seed (REQ-016); combined with nonzero effective
  parameters and the maximal-length polynomial, **no LFSR can ever reach
  16'h0000** (REQ-015) — there is no other load path.
- A write touches **only** the addressed `lfsr_q`. It does not touch `phase`,
  `data_q`, `r_q`, the output registers, or the other two LFSRs, so phase
  sequencing, `data_req` timing, and value correctness are unconditionally
  undisturbed (REQ-012 isolation, REQ-017). The only observable effect is the
  future R sequence — which never affects converted values (REQ-003).
- Writes are accepted every cycle they are presented; back-to-back writes
  (same or different segments) each take single-cycle effect (PERF-004). Note:
  while a segment is written on a `capture` edge its natural advance is
  consumed by the write (priority), which is the intended A4 semantics.
- Runtime writes never alter the reset defaults: `rst` always reloads
  `SEED_*_EFF` (REQ-014); the parameters live only in the reset/substitution
  terms, never in a writable register.

#### 4.1.5 DEMDRZ MUX + output register stage, complementary rail (REQ-019/020/022/028)

Single always block, all 57 output flops (28 true + 28 complement + `phase`)
updating on the same edge:

```
always @(posedge clk) begin
    if (rst) begin
        phase     <= 1'b0;
        sw_msb    <=  DRZ_MSB;   sw_msb_n  <= ~DRZ_MSB;
        sw_ulsb   <=  DRZ_LOW;   sw_ulsb_n <= ~DRZ_LOW;
        sw_lsb    <=  DRZ_LOW;   sw_lsb_n  <= ~DRZ_LOW;
        sw_llsb   <=  DRZ_LOW;   sw_llsb_n <= ~DRZ_LOW;
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
```

- Both rails are register outputs fed from the same MUX result; the inversion
  is **in front of** the `_n` flops, so there is no combinational path from
  `sw_*` to `sw_*_n` at the block boundary (REQ-020) and `sw_*_n === ~sw_*`
  holds on every cycle, including DRZ phases and during/after reset (REQ-019).
- All `sw_*`, `sw_*_n`, `phase` change only on rising clk edges — glitch-free
  at the boundary (REQ-026, REQ-028).
- DRZ phases output exactly `sw_msb=7'b1010101`, all other true-rail bits 0,
  complements accordingly (REQ-022); the DRZ code bypasses the rotators and
  does not consume R (REQ-010).
- The four-mode matrix `dem_en` × `drz_en` falls out of `next_phase` and the
  R-forcing term with no extra logic (REQ-024).

### 4.2 FSMs

One FSM: the **phase sequencer**, a single-bit register (`phase`).

| Property | Value |
|---|---|
| States | `PH_DRZ = 1'b0` (outputs hold DRZ mid-code), `PH_SIG = 1'b1` (outputs hold signal code) |
| Encoding | 1-bit, value = the `phase` output itself |
| Reset state | `PH_DRZ` (sync, `rst=1`) |
| Transitions | `next_phase = drz_en ? ~phase : 1'b1` — `drz_en=1`: strict alternation DRZ↔SIG; `drz_en=0`: go to / stay in `PH_SIG` from any state |
| Outputs (Moore on state, plus decode) | `phase` = state; `data_req = (~next_phase | ~drz_en) & ~rst` (high in `PH_SIG` cycles when `drz_en=1`, every non-reset cycle when `drz_en=0`); output-register select = `next_phase` |

There is no lockup state: `next_phase` is a total function of
(`phase`, `drz_en`), so any mid-stream `drz_en` toggle yields a defined next
state within one cycle (see corner case C9). The seed interface is
strobe-driven with no FSM. Next-state logic is separate combinational
(`assign`), state register separate, per CLAUDE.md §6.

### 4.3 Pipelining & Hazards

Two register stages (identical to v1):

| Stage | Registers | Loaded when | Combinational logic feeding the next stage |
|---|---|---|---|
| S0 — capture | `data_q[11:0]`, `r_q[2:0]` ×3, `lfsr_q[15:0]` ×3 | `capture=1` (LFSR also on `seed_ld`) | format XOR is **before** S0; b2t ×4, rotator ×3, mod7 ×3, DRZ MUX are between S0 and S1 |
| S1 — output | `phase`, `sw_*` ×4, `sw_*_n` ×4 | every cycle | — (direct outputs) |

Hazard analysis:
- **R vs. data alignment:** `r_q` and `data_q` load on the same `capture`
  edge, so the rotation applied to a sample is always the R drawn for that
  sample — no skew possible.
- **LFSR-write vs. R sampling:** at a collision edge, `r_q` samples
  `mod7(prn)` of the *old* LFSR state while `lfsr_q` loads the written seed;
  the written seed first influences R at the *next* capture (§4.1.4). No race:
  both are nonblocking same-edge updates reading pre-edge values.
- **`fmt_sel`/`data_in` setup:** both are ordinary synchronous inputs to the
  S0 capture mux; no multicycle or false paths.
- **NRZ back-to-back:** with `capture` ≡ 1 the S0→S1 pipe accepts one sample
  per cycle with no stall, bubble, or reuse hazard — `data_q` is fully
  overwritten each cycle and the output register consumes the previous
  sample's settled code on the same edge.
- Critical path (unchanged in kind from v1): `data_q` → b2t → rotator → DRZ
  MUX → `sw_*` flops, in parallel `lfsr_q[5:0]` → mod7 → `r_q`. The added v2
  logic (one XOR before S0, a 2-bit decode and 16-bit 2:1 mux before the
  LFSRs, the inverters before `_n` flops) touches no existing path through
  the rotators (PRD A8).

## 5. Corner-Case Behavior (each becomes a directed test)

| # | Scenario | Specified behavior |
|---|---|---|
| C1 | **Seed write during a signal phase** (DRZ mode, `capture=0`, no advance) | Addressed `lfsr_q` loads `seed_eff` at that edge; `phase`/`data_req`/`sw_*`/`sw_*_n`/`data_q`/`r_q` and the other two LFSRs are bit-identical to the no-write run for that edge. Current and next signal-phase values unchanged (R for the in-flight sample already registered). |
| C2 | **Seed write during a DRZ-output/capture cycle = same-cycle write+advance collision** (`seed_wr=1`, `capture=1`) | Write wins (A4): `lfsr_q <= seed_eff`, the natural shift is skipped. The sample captured at that edge gets `r_q = mod7(pre-write prn)`. The next capture edge gives `r_q = mod7(seed_eff[5:0])` and shifts the LFSR from `seed_eff`. Value correctness (REQ-003) holds for both samples. |
| C3 | **Zero-seed write** (`seed_wdata=16'h0000`, valid addr) | Identical in every respect to writing `SEED_*_EFF` of the addressed segment. Post-write PRN sequence = reference sequence from the effective parameter seed. LFSR ≠ 0 always. |
| C4 | **Write to reserved address** (`seed_addr=2'b11`, `seed_wr=1`) | Complete no-op: every flop in the design equals the no-write run, cycle by cycle. No error flag (ERR-002). |
| C5 | **Back-to-back writes** — consecutive cycles, (a) same segment, (b) different segments, (c) `seed_wr` held high many cycles | Each cycle performs one independent write; last-written value stands; with `seed_wr` held high on a segment, that LFSR never advances naturally (write priority every edge) — its PRN is pinned to `seed_eff` until the strobe drops. Conversion stream unaffected throughout (REQ-017, PERF-004). |
| C6 | **`fmt_sel` toggles between captures** | Sample captured at edge N uses the `fmt_sel` value at edge N; a toggle during non-capture cycles (e.g. during the signal-output cycle in DRZ mode) has zero effect on the in-flight or previous samples (REQ-008). Test: same `data_in=12'h800` captured with `fmt_sel=0` → code 2048 (MSB seg = 4), with `fmt_sel=1` → code 0 (all elements off). |
| C7 | **Two's-complement endpoints & midscale** | `fmt_sel=1`: `12'h800`(−2048)→ sum 0; `12'h7FF`(+2047)→ sum 4095 (all 28 on); `12'h000`(0)→ sum 2048; `12'hFFF`(−1)→ sum 2047. Element-sum-identical to `fmt_sel=0` with `data_in+2048` (REQ-007). |
| C8 | **`dem_en` toggles mid-stream** | Takes effect at the next R-update (capture) edge: 1→0 forces R=0 for subsequent samples (plain thermometer); 0→1 resumes random R. The sample in flight keeps the R it was captured with. No value error in any cycle. LFSRs advance identically regardless of `dem_en` (PRN timeline mode-independent). |
| C9 | **`drz_en` toggles mid-stream** | 0→1 while `phase=1`: `next_phase=0`, the next cycle is a DRZ phase, then strict alternation — no double-signal or double-DRZ irregularity beyond the defined transition. 1→0: `next_phase=1` from then on; `data_req` goes continuously high; first NRZ sample captured at the next edge. Sequencing is defined from any state in one cycle (no glitch-free guarantee required, PRD A2). |
| C10 | **Reset asserted mid-stream, 1 cycle long** | On the (single) edge with `rst=1`: outputs → DRZ mid-code + complements, `phase`→0, `data_q`→0, LFSRs→`SEED_*_EFF`, R→0; in-flight sample discarded; `data_req=0` during the reset cycle. Release sequence then proceeds per §3 (first signal phase carries code 0 = all elements off; first real capture on the following `data_req=1` edge). Same end state regardless of prior history, including prior seed writes (REQ-014). |
| C11 | **`sw_*_n` complement invariant** | `sw_*_n === ~sw_*` checked on **every** clock cycle of **every** test (reset cycles, DRZ phases, signal phases, mode changes, write cycles) and both rails transition on the same edge (REQ-019/020). |
| C12 | **Back-to-back NRZ samples** | `drz_en=0`: `data_req` ≡ 1, a new sample every clk, each appearing exactly 2 cycles after its capture; no sample lost or duplicated over a long random burst (REQ-023, REQ-027, PERF-002). |
| C13 | **Rotation-invariant codes** | `data_in` giving segment codes 0 (`12'h000`) and 7 (`12'hFFF`), DEM on: outputs are exactly all-0s / all-1s per segment regardless of R (rotation of 0000000/1111111 is itself). Repeated mid-codes (e.g. segment code 4) with DEM on must show ≥ 2 distinct selection patterns over a run while every selection sums to 4 (REQ-003/009). |
| C14 | **DRZ pattern exactness** | Every `phase=0` output cycle (including the post-reset cycles before the first capture): `sw_msb=7'b1010101`, `sw_ulsb=sw_lsb=sw_llsb=7'b0000000`, complements inverted — bit-exact, all modes with `drz_en=1`, regardless of surrounding data, `dem_en`, or seed writes (REQ-022). |
| C15 | **Write during reset** | `seed_wr=1` while `rst=1`: ignored; LFSR holds `SEED_*_EFF` after reset. |
| C16 | **Zero seed parameter** (CFG-002) | Build with `SEED_ULSB=16'h0000` override: block elaborates and behaves as with `SEED_ULSB=16'h5EED`; LFSR never zero. (Directed compile-time + sim check.) |
| C17 | **v1 equivalence configuration** (CFG-003) | `fmt_sel=0`, `seed_wr=0`: all v1 outputs (`data_req`, `phase`, `sw_*`) bit-match the v1 golden vectors in all four modes (reset connection adapted per M3). |
| C18 | **LFSR full behavior vs reference** | Each segment's PRN sequence matches a software reference LFSR (same polynomial/seed) over a long run, including across an injected runtime write (REQ-011/013); state ≠ 16'h0000 asserted every cycle (REQ-015). |

## 6. Design Decision Log

| # | Decision | Rationale | Alternatives rejected |
|---|---|---|---|
| D1 | **Reset = synchronous, active-high `rst`** (v1 had async active-low `rst_n`). | The PRD defers the scheme to the MAS. This is a single-clock, purely digital encoder with no need to define outputs without a clock; sync reset is the project default (CLAUDE.md §6), keeps the lint/verification flow on the supported path, eliminates reset-recovery/removal timing closure on 98+ flops at multi-GHz-class clocks, and removes the reset net from the async-pin balancing problem near the skew-matched `sw_*` bank. Cost: outputs are defined only after the first clk edge with `rst=1`, and the analog side sees the (safe) DRZ mid-code only once clocks run — acceptable because the switch drivers are inert without clocking anyway, and the mid-code reset value makes the first defined state a near-zero differential. For ASIC integration, the chip-level reset must be synchronized/deasserted cleanly in the `clk` domain (assumption M1); if a future integration target hard-requires async assertion, that is a one-line-per-block, MAS-revision change. | (a) Keep v1 async active-low: rejected — deviates from project default without a driving requirement, adds recovery/removal closure burden, and the "defined outputs without clock" benefit is not needed by any REQ. (b) Async-assert/sync-deassert hybrid: rejected — nonstandard for this flow, complicates lint, and buys nothing the sync scheme lacks here. |
| D2 | **Format conversion = `data_in[11] ^ fmt_sel` in front of the capture register.** | One XOR; exact A9 mapping (v+2048 ⇔ MSB inversion); per-capture semantics (REQ-008) fall out of placing it before the capture-enabled flop; zero latency change; entire v1 datapath untouched, so REQ-006/CFG-003 are structural. | (a) Convert after `data_q` (store raw + registered `fmt_sel`): rejected — an extra flop and two points of truth for no benefit. (b) Adder `+2048`: rejected — same result, more logic. |
| D3 | **Seed interface = `seed_wr` + `seed_addr[1:0]` + shared `seed_wdata[15:0]`; decode at top; load port added to `dac_lfsr16`; priority rst > load > advance.** | Matches PRD A3 (native, not a bus); 2-bit address is the minimal encoding for 3 targets + naturally yields a reserved code for REQ-018; the load mux lives where the state lives (one writable register per LFSR, no shadow copies), making REQ-014/015 arguments local and airtight; priority order implements A4 literally. | (a) Three separate strobes (no address): equivalent, but an address bus matches controller-style masters better and gives REQ-018 a concrete target. (b) Shadow seed registers + apply-at-sample-boundary: rejected — more flops, delayed effect contradicts REQ-013's "next advance continues from the written value", and A4 already defines the collision. (c) APB-lite: rejected — PRD Non-Goal. |
| D4 | **Zero handling in two layers: elaboration-time `SEED_*_EFF` localparams at top (CFG-002) + runtime `seed_eff` substitution mux inside `dac_lfsr16` (REQ-016).** | Each `dac_lfsr16` instance then provably has a nonzero reset value and a nonzero-only load path ⇒ REQ-015 holds by construction, no runtime checker needed. Substituting the *parameter* seed (A5) reuses an existing constant — no second magic number. | (a) Map zero write to `16'h0001` or to `~0`: rejected — PRD A5 names the parameter seed. (b) Reject (ignore) zero writes: rejected — REQ-016 says *converted*, not ignored. (c) `generate`-time `$error` on zero parameter: not expressible portably in Verilog-2001; silent substitution chosen and documented. |
| D5 | **Complementary rail = 28 additional flops in the same output always block, loaded with the inverted MUX value.** | REQ-020 demands register outputs on both rails with no boundary inversion; same always block + same source expression makes same-edge updating and the `~` relationship reviewable in one place. Reset values are the complements of the DRZ code, so REQ-019 holds during reset too. | (a) `assign sw_msb_n = ~sw_msb`: rejected — violates REQ-020 (combinational boundary path, mismatched output timing arcs). (b) Inverting the flop clock/output in a library cell: out of RTL scope. |
| D6 | **Keep v1 hierarchy and file split; extend `dac_dem_coder`/`dac_lfsr16` ports rather than restructure.** | v1 microarchitecture is silicon-proven per the paper and verified in-repo; every v2 feature attaches at a register boundary (S0 capture mux, LFSR load, S1 inverted rail) without touching the DEM math. Minimizes re-verification surface; CFG-003 becomes near-trivial. | Flattening into one module: rejected — loses per-segment instancing clarity and one-module-per-file convention. |
| D7 | **`data_req = capture & ~rst`** (v1: `data_req = capture`, could be high during reset in NRZ). | Makes the REQ-025 contract exact: `data_req=1` ⇔ this edge captures. During sync reset no capture occurs (reset priority), so `data_req` must be 0 then. One gate; combinational `data_req` retained from v1 (REQ-028 does not require it registered). | Registering `data_req`: rejected — would shift the handshake a cycle relative to v1 and break CFG-003 timing. |
| D8 | **R-vs-write collision semantics: at a colliding edge R derives from the pre-write PRN; the written seed first affects R at the next capture.** | This is the natural nonblocking-assignment behavior (both flops read pre-edge values), needs zero extra logic, never produces a non-uniform or stale-misaligned R for any sample, and keeps REQ-013's observable contract (advances continue from the written value). | Forwarding `seed_eff` combinationally into `r_next` at the colliding edge: rejected — adds a 16-bit bypass mux on the R path for no requirement; REQ-013 constrains the LFSR sequence, not the colliding-edge R. |

## 7. Requirement Traceability

| REQ-ID | MAS section(s) |
|---|---|
| REQ-001 | §4.1.3 |
| REQ-002 | §2.2 (`sw_*` ports), §4.1.3 |
| REQ-003 | §4.1.3, §4.1.4 (write isolation), §5 C2/C13 |
| REQ-004 | §4.1.3 (R forced 0), §5 C8 |
| REQ-005 | §2.2 (`fmt_sel`), §4.1.2 |
| REQ-006 | §4.1.2 (`fmt_sel=0` path), §5 C17 |
| REQ-007 | §4.1.2, §5 C7 |
| REQ-008 | §4.1.2 (sampled at capture), §5 C6 |
| REQ-009 | §4.1.3 |
| REQ-010 | §4.1.3 (R update once per capture), §4.1.5 (DRZ bypasses rotators) |
| REQ-011 | §4.1.3, §2.1 (polynomial), §5 C18 |
| REQ-012 | §2.2 (seed ports), §4.1.4 |
| REQ-013 | §4.1.4 (priority + protocol table), §5 C2/C18 |
| REQ-014 | §4.1.4 (reset reloads `SEED_*_EFF`), §5 C10 |
| REQ-015 | §2.1 (effective seeds), §4.1.4, §6 D4, §5 C3/C18 |
| REQ-016 | §4.1.4 (`seed_eff` mux), §5 C3 |
| REQ-017 | §4.1.4 (isolation properties), §5 C1/C2/C5 |
| REQ-018 | §4.1.4 (decode, reserved `2'b11`), §5 C4 |
| REQ-019 | §4.1.5, §3 (reset values), §5 C11 |
| REQ-020 | §4.1.5, §6 D5 |
| REQ-021 | §4.1.1, §5 C14 |
| REQ-022 | §4.1.5 (DRZ constants), §5 C14 |
| REQ-023 | §4.1.1, §5 C12 |
| REQ-024 | §4.1.5 (mode matrix), §4.2 |
| REQ-025 | §4.1.1, §2.2 (`data_req`), §6 D7 |
| REQ-026 | §4.1.5, §4.2 |
| REQ-027 | §4.1.1 (latency derivation), §4.3, §5 C12 |
| REQ-028 | §4.1.5, §2.2 (driven: reg) |
| REQ-029 | §3, §6 D1, §5 C10 |
| PERF-001 | §4.1.1 |
| PERF-002 | §4.1.1, §5 C12 |
| PERF-003 | §4.1.1, §4.3 |
| PERF-004 | §4.1.4, §5 C5 |
| PERF-005 | §4.3 (critical path note), §3 |
| CFG-001 | §2.1 |
| CFG-002 | §2.1 (`SEED_*_EFF`), §6 D4, §5 C16 |
| CFG-003 | §2.2 (v1 differences note), §4.1.2, §5 C17, assumption M3 |
| ERR-001 | §4.1.4, §5 C3 |
| ERR-002 | §4.1.4, §5 C4 |
| ERR-003 | §4.1.2 (every 12-bit pattern valid in both formats) |
| ERR-004 | §2.2 (no error/status ports) |

All PRD requirement IDs are mapped; no gaps.

## 8. Assumptions

Inherited from the PRD (restated, binding on this MAS): A1 (`fmt_sel` polarity,
0 = offset-binary), A2 (quasi-static mode inputs, per-capture effect, no
glitch-free mid-phase guarantee), A3 (native seed interface), A4 (write wins
over same-cycle advance), A5 (zero write → parameter seed), A6 (invalid
address silently ignored), A7 (no read-back), A8 (no fmax gate), A9
(two's-complement mapping = MSB inversion), A10 (replaces v1, same top name).

New in this MAS:

| # | Assumption |
|---|---|
| M1 | [ASSUMPTION] The integrator delivers `rst` synchronized to `clk` (clean synchronous deassertion); no internal reset synchronizer is provided. ASIC chip-level reset distribution handles assertion-while-clocks-stopped concerns outside this block. |
| M2 | [ASSUMPTION] Minimum reset assertion is one clk cycle (one rising edge with `rst=1` fully resets the design). |
| M3 | [ASSUMPTION] CFG-003 "v1 testbench passes unchanged" is read as: unchanged stimulus/checks with only the reset connection adapted (`rst = ~rst_n`, held through ≥1 rising edge), since the reset scheme change (D1) was explicitly delegated to the MAS by REQ-029. |
| M4 | [ASSUMPTION] `seed_addr` and `seed_wdata` are don't-care whenever `seed_wr=0`; no stability requirement between writes. |
| M5 | [ASSUMPTION] At a write/advance collision edge, the R registered for the simultaneously-captured sample derives from the pre-write PRN state (decision D8); REQ-013 constrains only the LFSR state sequence, which continues from the written value. |
| M6 | [ASSUMPTION] `data_req` remains combinational (as in v1) and is additionally forced low while `rst=1` (decision D7); REQ-028's registered-output requirement applies to `sw_*`, `sw_*_n`, `phase` only, per its text. |
