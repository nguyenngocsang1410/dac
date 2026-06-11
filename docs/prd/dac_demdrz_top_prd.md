# dac_demdrz_top (v2) — Product Requirements Document
| Block | Version | Date | Status | Author |
|---|---|---|---|---|
| dac_demdrz_top | 2.0 | 2026-06-11 | APPROVED | prd-writer |

## 1. Purpose & Scope

`dac_demdrz_top` is the digital encoder core of a 12-bit segmented current-steering DAC using the DEMDRZ technique (dynamic element matching + digital return-to-zero), modeled on Lin/Huang/Kuo, IEEE JSSC vol. 49, no. 3, 2014. It converts a 12-bit sample stream into 28 registered unit-element switch controls, with random-rotation DEM on the upper three segments and an optional DRZ mid-code phase between samples.

Version 2 preserves all v1 behavior and adds three features:
1. **Input format select** — offset-binary (v1 behavior) or two's-complement input coding.
2. **Runtime-loadable PRNG seeds** — a small synchronous write interface to reprogram the three 16-bit LFSR seeds.
3. **Complementary switch outputs** — registered `sw_*_n` outputs, exactly inverted from `sw_*`, for differential switch drivers.

In scope: the synthesizable digital encoder only. Out of scope: all analog circuitry (switch drivers, current cells, biasing) and the microarchitecture (left to the MAS).

## 2. Use Cases

- **UC1 — DEMDRZ operation:** high-speed DAC with both DEM and RTZ decorrelation; `clk` at 2× the sample rate; one signal phase + one DRZ phase per sample.
- **UC2 — Mode comparison / characterization:** DRZ-only, NRZ+DEM, and plain NRZ modes for silicon evaluation (paper Fig. 14).
- **UC3 — Signed data sources:** upstream DSP delivering two's-complement samples drives the DAC without an external format converter.
- **UC4 — Seed reprogramming:** system controller rewrites the per-segment PRNG seeds at runtime (test repeatability, decorrelation across multiple DAC instances).
- **UC5 — Differential switch drivers:** analog switch drivers requiring true and complement control rails with matched timing.

## 3. Functional Requirements

### 3.1 Core encoding (v1 behavior preserved)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-001 | The block SHALL segment each captured 12-bit sample as 3+3+3+3 bits: MSB = bits [11:9], ULSB = [8:6], LSB = [5:3], LLSB = [2:0]. | For directed samples, each segment's element count equals the corresponding 3-bit field value. |
| REQ-002 | The block SHALL drive 7 thermometer-coded unit-element controls per segment (28 total), with element weights 512 / 64 / 8 / 1 LSB for MSB / ULSB / LSB / LLSB respectively. | Weighted sum of asserted `sw_*` bits during a signal phase equals the captured sample's offset-binary value. |
| REQ-003 | During every signal phase, the weighted sum of the asserted switch controls SHALL equal exactly the captured sample value (DEM rotation never changes the converted value). | Checked for every signal phase across full-range random stimulus in all four modes. |
| REQ-004 | When `dem_en = 0`, each segment's selection SHALL equal the plain thermometer code (elements 1..k asserted for code k). | Bit-exact compare against a thermometer reference with DEM off. |

### 3.2 Input format select (new)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-005 | The block SHALL provide a format-select input choosing between offset-binary and two's-complement interpretation of `data_in`. [ASSUMPTION A1: select = 0 → offset-binary (v1-compatible default when tied low), select = 1 → two's-complement.] | Same physical input word produces the two documented mappings depending on the select. |
| REQ-006 | In offset-binary mode, `data_in` SHALL be interpreted as an unsigned value 0..4095, identical to v1. | v1 regression vectors pass unchanged with the select tied to offset-binary. |
| REQ-007 | In two's-complement mode, `data_in` SHALL be interpreted as a signed value −2048..+2047 and mapped to the internal code (value + 2048), preserving the full-scale range with no gain or offset change relative to offset-binary mode. | For all v: encode(two's-comp v) is element-sum-identical to encode(offset-binary v + 2048); endpoints −2048 → 0 and +2047 → 4095 verified. |
| REQ-008 | The format select SHALL take effect per captured sample: the interpretation applied to a sample is the select value present at that sample's capture. [ASSUMPTION A2: the select is expected to be quasi-static; mid-stream changes are legal but apply only from the next capture.] | Toggle the select between captures; each signal phase reflects the select value at its capture. |

### 3.3 DEM and PRNG (v1 behavior preserved)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-009 | When `dem_en = 1`, the MSB, ULSB and LSB segments SHALL each apply random-rotation DEM (rotated thermometer selection); the LLSB segment SHALL never apply DEM. | With DEM on, repeated identical codes select differing unit cells in the upper three segments; LLSB selection is always the plain thermometer code. |
| REQ-010 | Each DEM segment's rotation step R SHALL be drawn uniformly from {0..6} and SHALL update exactly once per captured sample (R is stable for the whole signal phase, and the DRZ code does not use R). | Long-run histogram of R per segment is uniform within statistical bounds; R is constant within each sample period. |
| REQ-011 | Each of the three DEM segments SHALL use a private 16-bit maximal-length LFSR as its pseudo-random source (period 2^16 − 1). | LFSR sequence matches a reference model from the same seed; full period verified by model. |

### 3.4 Runtime-loadable PRNG seeds (new)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-012 | The block SHALL provide a synchronous write interface through which each of the three 16-bit LFSR seeds (MSB, ULSB, LSB) can be independently reloaded at runtime. [ASSUMPTION A3: a simple native interface — segment address/select, 16-bit write data, write strobe — not a standard bus protocol.] | Writing a seed to one segment changes that segment's subsequent PRN sequence to the sequence generated from the written seed; the other two segments are unaffected. |
| REQ-013 | A seed write SHALL load the addressed LFSR with the written value such that the next PRNG advance continues from that value. [ASSUMPTION A4: if a write coincides with a normal LFSR advance in the same cycle, the write wins.] | After a write, the segment's PRN output sequence matches a reference LFSR started from the written seed. |
| REQ-014 | The existing parameters (`SEED_MSB`, `SEED_ULSB`, `SEED_LSB`) SHALL remain the seed values loaded at reset; runtime writes do not alter the reset defaults. | After any sequence of writes followed by a reset, the LFSRs restart from the parameter values. |
| REQ-015 | No LFSR SHALL ever occupy the all-zero (lock-up) state, including after any write. | Assertion/check over all stimulus: PRN state is never 16'h0000. |
| REQ-016 | A write of the all-zero value SHALL be converted to a defined nonzero seed. [ASSUMPTION A5: a zero write loads the addressed segment's reset-default parameter seed instead.] | Writing 16'h0000 results in the segment behaving as if its parameter seed had been written. |
| REQ-017 | A seed write SHALL NOT disturb sample conversion: phase sequencing, `data_req` timing, and the value-correctness of every signal phase (REQ-003) hold across writes at arbitrary times. | Random writes injected during streaming; all phase/value checks still pass. |
| REQ-018 | A write asserted toward an unmapped/invalid segment address SHALL have no effect on any state. [ASSUMPTION A6.] | State before and after such a write is identical. |

### 3.5 Complementary registered outputs (new)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-019 | The block SHALL provide complementary outputs `sw_msb_n`, `sw_ulsb_n`, `sw_lsb_n`, `sw_llsb_n` (7 bits each), each the exact bitwise inverse of the corresponding `sw_*` output at all times, including during DRZ phases and after reset. | `sw_*_n === ~sw_*` checked on every clock cycle of every test. |
| REQ-020 | The `sw_*_n` outputs SHALL be registered in the same output stage as `sw_*`: both rails update on the same clock edge with no derived combinational path from `sw_*` to `sw_*_n` at the block boundary. | Both rails transition in the same cycle in simulation; review/lint confirms both are register outputs. |

### 3.6 DRZ, modes, handshake (v1 behavior preserved)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-021 | When `drz_en = 1`, the block SHALL insert one DRZ mid-code phase between every two consecutive samples, with `clk` running at 2× the sample rate (one signal phase + one DRZ phase per sample). | Phase alternation 1,0,1,0,… observed; throughput = 1 sample per 2 clk. |
| REQ-022 | The DRZ mid-code SHALL assert MSB elements 1, 3, 5, 7 only (4 × 512 = 2048 LSB), with all other 24 elements deasserted. | Every DRZ phase outputs exactly `sw_msb = 7'b1010101`, all other `sw_*` = 0 (and complements per REQ-019). |
| REQ-023 | When `drz_en = 0`, the block SHALL operate NRZ: every clk cycle is a signal phase and one sample is converted per clk. | `phase` is constantly 1; one new sample consumed per cycle. |
| REQ-024 | The block SHALL support the four mode combinations of `dem_en` × `drz_en`: DEMDRZ, DRZ-only, NRZ+DEM, NRZ. | All REQ-003/004/021–023 checks pass in each of the four modes. |
| REQ-025 | The block SHALL provide a `data_req` output asserted during cycles whose rising clk edge captures `data_in`; `data_in` SHALL be captured only on such edges. | Samples driven only when `data_req = 1` are all converted exactly once; data changed while `data_req = 0` has no effect. |
| REQ-026 | The block SHALL provide a registered `phase` output: 1 when `sw_*` carry a signal code, 0 when they carry the DRZ mid-code. | `phase` correctly classifies every output cycle against the reference model. |

### 3.7 Reset and latency (behavioral)

| ID | Requirement (SHALL/SHOULD/MAY) | Acceptance Criterion |
|---|---|---|
| REQ-027 | The latency from sample capture to the corresponding signal phase on `sw_*`/`sw_*_n` SHALL be 2 clk cycles. | Measured capture-to-output delay is exactly 2 cycles for every sample, all modes. |
| REQ-028 | All `sw_*`, `sw_*_n`, and `phase` outputs SHALL be registered (glitch-free at the block boundary). | Outputs change only at rising clk edges in simulation; lint/review confirms registered outputs. |
| REQ-029 | The block SHALL have fully defined reset behavior: after reset the outputs hold the DRZ mid-code (REQ-022 pattern, with complements per REQ-019), `phase = 0`, and the LFSRs hold their parameter seeds. The reset scheme (polarity, sync/async) is an architecture decision deferred to the MAS. | Post-reset output state matches the DRZ mid-code and complements; first PRN values derive from parameter seeds. |

## 4. Interface Requirements (behavioral)

Behavioral signal set — names indicative, exact ports defined in the MAS:

- **Clock/reset:** single clock `clk` (2× sample rate when `drz_en = 1`, 1× otherwise); one reset meeting REQ-029 (scheme per MAS).
- **Mode controls:** `dem_en`, `drz_en`, and the input-format select (REQ-005). [ASSUMPTION A2] all three are quasi-static; changes take effect cleanly only at sample boundaries, and no glitch-free guarantee is required for mid-phase toggling of `dem_en`/`drz_en`.
- **Data path:** `data_in[11:0]` with `data_req` capture handshake (REQ-025); no backpressure from the block other than `data_req` timing.
- **Seed write interface (new):** synchronous, single-cycle write — segment address/select, 16-bit write data, write strobe (REQ-012). No read-back path is required [ASSUMPTION A7].
- **Outputs:** `phase`, `sw_msb/ulsb/lsb/llsb[6:0]`, and new `sw_msb_n/ulsb_n/lsb_n/llsb_n[6:0]` — all registered.
- All inputs are assumed synchronous to `clk`; no CDC inside the block.

## 5. Performance Requirements

| ID | Metric | Target |
|---|---|---|
| PERF-001 | Throughput, DRZ modes | 1 sample per 2 clk cycles, sustained |
| PERF-002 | Throughput, NRZ modes | 1 sample per clk cycle, sustained |
| PERF-003 | Latency, capture → signal phase | exactly 2 clk cycles (REQ-027) |
| PERF-004 | Seed write | accepted every cycle it is presented; single-cycle effect (REQ-013) |
| PERF-005 | Max clock | No numeric target stated [ASSUMPTION A8: no worse than v1; paper reference point is 3.2 GHz clk for 1.6 GS/s DEMDRZ, technology-dependent, not a verification gate] |

## 6. Configuration / Parameterization Requirements

| ID | Requirement | Acceptance Criterion |
|---|---|---|
| CFG-001 | Parameters `SEED_MSB`, `SEED_ULSB`, `SEED_LSB` (16-bit) SHALL set the reset-default LFSR seeds; defaults SHALL be distinct and nonzero (v1 values 16'hACE1 / 16'h5EED / 16'hB10D retained). | Parameter override changes reset-time PRN sequences accordingly. |
| CFG-002 | A parameter value of zero SHOULD be rejected or substituted at elaboration/reset so REQ-015 holds even under misconfiguration. | Instantiating with a zero seed never yields a locked LFSR. |
| CFG-003 | With the new inputs tied inactive (format select = offset-binary, write strobe = 0) the block SHALL be functionally identical to v1 on all v1 outputs. | v1 testbench checks pass against v2 in this configuration. |

## 7. Error Handling Requirements

- **ERR-001:** Zero-seed writes — handled per REQ-015/REQ-016 (never lock up; defined substitution).
- **ERR-002:** Invalid seed-interface address — silently ignored per REQ-018; no error flag is required [ASSUMPTION A6].
- **ERR-003:** There are no illegal `data_in` values: every 12-bit pattern is a valid sample in both formats.
- **ERR-004:** No error/status reporting outputs are required; the block has no detectable runtime error conditions beyond the above.

## 8. Non-Goals

- Analog circuitry: switch drivers, current cells, cascodes, biasing, layout/matching (sim model only, out of RTL scope).
- A standard register bus (APB/AHB/AXI) for the seed interface — native simple interface only.
- Seed/state read-back, PRN observability ports, or BIST.
- CDC or synchronizers — all inputs are assumed in the `clk` domain.
- Glitch-free dynamic mode switching of `dem_en`/`drz_en` mid-stream beyond what REQ-008's per-capture semantics imply.
- Any change to segmentation, weights, LFSR polynomial, DRZ mid-code value, or latency relative to v1.
- Specifying the reset scheme, pipeline structure, FSM design, or encoding — MAS scope.

## 9. Assumptions ([ASSUMPTION] items collected here)

| # | Assumption |
|---|---|
| A1 | Format select polarity: 0 = offset-binary (v1-compatible when tied low), 1 = two's-complement. |
| A2 | Mode inputs (`dem_en`, `drz_en`, format select) are quasi-static; the format select applies per captured sample (REQ-008), and no glitch-free mid-phase mode-switch guarantee is required. |
| A3 | Seed write interface is a simple native synchronous interface (segment address/select + 16-bit data + write strobe), not a standard bus protocol. |
| A4 | If a seed write coincides with a normal LFSR advance in the same cycle, the write takes priority. |
| A5 | A write of 16'h0000 loads the addressed segment's reset-default parameter seed instead (the defined nonzero substitution of REQ-016). |
| A6 | Writes to unmapped/invalid addresses are silently ignored; no error flag. |
| A7 | No read-back of seeds or LFSR state is required. |
| A8 | No numeric fmax target is imposed; v2 should not degrade timing relative to v1, but this is not a verification gate. |
| A9 | The two's-complement mapping is value + 2048 (equivalent to inverting the input MSB); full-scale endpoints map −2048 → code 0 and +2047 → code 4095. |
| A10 | The block keeps the name `dac_demdrz_top` and replaces v1 (no side-by-side v1 module); v1 behavior is recovered by tying the new inputs inactive (CFG-003). |

## 10. Open Questions

None blocking — the PRD gate was auto-approved by the user. Assumptions A1–A10 above should be confirmed at release; any rejection reopens the affected REQ IDs.
