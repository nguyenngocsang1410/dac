# dac_demdrz_top (v2) — Test Plan
| Block | Version | Date | Status | MAS ref |
|---|---|---|---|---|
| dac_demdrz_top | 2.0 | 2026-06-11 | COMPLETE | docs/arch/dac_demdrz_top_mas.md |

## 1. Strategy (reference model / directed checks, what is and isn't covered)

Single self-checking testbench `tb/dac_demdrz_top_tb.v` (Verilog-2001, iverilog).

**Reference model.** The TB keeps a cycle-accurate behavioral mirror of the
architecture as specified by the MAS (not copied from the RTL): capture/phase
equations (MAS §4.1.1), fmt XOR before the capture register (§4.1.2), three
16-bit LFSRs with polynomial x^16+x^14+x^13+x^11+1 and priority
rst > seed-load > advance with zero-write substitution (§4.1.4), R = PRN mod 7
(implemented in the TB as `val % 7`, independently of the RTL's digit-sum
trick), value-preserving rotation, DRZ mux and output stage (§4.1.5).
DUT outputs (`phase`, all `sw_*`) are compared bit-exactly against the model
on **every clock cycle of every test**, in all modes, through resets, mode
toggles and seed writes.

**Independent invariant checkers** (also every cycle, not derived from the
model's rotation math):
- weighted-sum decode: 512/64/8/1 × popcount per segment == captured code on
  every signal phase;
- DRZ phases bit-exact `sw_msb=7'b1010101`, all else 0;
- `sw_*_n === ~sw_*`;
- `data_req` == the MAS capture equation;
- outputs change only at rising clk edges (event-time monitor).

**Structural (hierarchical-reference) checks** — stated per the orchestrator's
note: the LFSR state (`dut.u_dem_*.u_lfsr.lfsr_q`) and the R register
(`dut.u_dem_*.r_q`) of all three segments are compared each cycle against the
TB reference LFSR/mod7 model, and `lfsr_q != 16'h0000` is asserted every
cycle (REQ-015, REQ-011, REQ-010, C18). Seed-write effects are therefore
verified both structurally (state == written value) and behaviorally (the
downstream R sequence and DEM selections come from the model and are checked
bit-exactly on the outputs).

**Auxiliary DUT instances** (same stimulus): `dut2` with `SEED_ULSB=16'h0000`
override (CFG-002/C16 — must elaborate, fall back to 16'h5EED, and be
bit-identical to `dut` on every output every cycle) and `dut3` with three
nonzero overridden seeds (CFG-001 — its LFSRs are mirrored by a second model
instance with the overridden seeds and checked hierarchically every cycle).

**Not covered in simulation (analysis-only, justified):**
- REQ-020 "no combinational path sw_* → sw_*_n": simulation shows same-edge
  updates of both rails plus the off-edge-change monitor; the absence of a
  boundary inversion path is confirmed by RTL review (separate `sw_*_n` flops
  in the same always block) and lint. Not provable by black-box simulation.
- REQ-010 uniformity: checked statistically — R histogram per segment over
  >2000 DEM-on samples in the dedicated window must be within ±15% of N/7 per
  bin (the mod-7 map is ceil(64/7)-balanced; exact uniformity is a math
  property of the model, verified by construction).
- REQ-011 "full period 2^16−1": verified on the software reference model
  (cycle-length count from each seed == 65535); the DUT is locked to that
  model every cycle, so exhaustive 65535-sample DUT runs are not repeated.
- PERF-005 (fmax): no numeric target (PRD A8) — not a simulation gate.
- CFG-003 "v1 testbench passes": the v1 TB's checks (weighted sum, DRZ
  pattern, DEM-off thermometer, DEM variability, four modes) are re-hosted in
  this TB with the new inputs tied inactive during T-002..T-006/T-017 and the
  reset adapted per MAS M3; a literal v1-file rerun is impossible (port list
  changed by design decision D1).

## 2. Tests

Continuous checkers (run during every directed test below):

| Test ID | REQ-ID(s) | Scenario | Stimulus | Pass criteria | Status |
|---|---|---|---|---|---|
| CHK-01 | REQ-001/002/003/004/009/010/021/022/023/024/026/029 | Cycle-exact model compare | all tests | `phase`, `sw_msb/ulsb/lsb/llsb` === model every cycle | PASS |
| CHK-02 | REQ-019 (C11) | Complement rail invariant | all tests | `{sw_*_n} === ~{sw_*}` every cycle incl. reset | PASS |
| CHK-03 | REQ-002/003 (C13) | Weighted-sum decode | all tests | every `phase=1` cycle: Σ(512,64,8,1·popcount) == captured code | PASS |
| CHK-04 | REQ-022 (C14) | DRZ pattern exactness | all tests | every `phase=0` cycle: `sw_msb=1010101`, rest 0 | PASS |
| CHK-05 | REQ-025 | Handshake correctness | all tests | `data_req` == MAS capture equation every cycle; 0 in reset | PASS |
| CHK-06 | REQ-011/013/015 (C18) | LFSR state vs reference, never zero | all tests | hierarchical `lfsr_q` (×3) === model LFSR; ≠ 16'h0000, every cycle | PASS |
| CHK-07 | REQ-010 | R register vs reference, stable per sample | all tests | hierarchical `r_q` (×3) === model R every cycle (updates only at captures) | PASS |
| CHK-08 | REQ-028 (REQ-020 partial) | Registered/glitch-free outputs | all tests | no `phase`/`sw_*`/`sw_*_n` value-change event off a rising clk edge | PASS |
| CHK-09 | CFG-001/CFG-002 (C16) | Parameter override / zero parameter | all tests | `dut2` (SEED_ULSB=0) output-identical to `dut`, its LFSR=16'h5EED-seeded & ≠0; `dut3` (3 nonzero overrides) LFSRs track override-seeded model | PASS |

Directed sequence:

| Test ID | REQ-ID(s) | Scenario | Stimulus | Pass criteria | Status |
|---|---|---|---|---|---|
| T-020 | REQ-011 | LFSR maximal length (software model) | walk reference LFSR from each of the 3 seeds | period == 65535, never 0 | PASS |
| T-001 | REQ-029, CFG-001 (C10) | Reset state & release sequence | sync rst 4+ cycles, release off-edge | during rst: phase=0, sw=DRZ mid-code+complements, data_req=0, LFSRs=param seeds (hier), R=0; post-release: 1 cycle phase=0/req=0, then phase=1 with all-zero signal code & data_req=1 | PASS |
| T-002 | REQ-003/021/024, PERF-001, CFG-003, ERR-003 (C17) | DEMDRZ streaming | dem=1,drz=1; 6000 random cycles (data randomized EVERY cycle incl. non-capture) + full 0..4095 ramp | all CHK; capture count == cycles/2 ±2 | PASS |
| T-003 | REQ-004/024 (C17) | DRZ-only streaming | dem=0,drz=1; 4000 random cycles | all CHK (model gives plain thermometer) | PASS |
| T-004 | REQ-023/024, PERF-002 (C12, C17) | NRZ+DEM back-to-back | dem=1,drz=0; 4000 random cycles | all CHK; capture count == cycle count (1 sample/clk, none lost/duplicated) | PASS |
| T-005 | REQ-004/023/024 (C17) | Plain NRZ | dem=0,drz=0; 2000 random cycles | all CHK | PASS |
| T-006 | REQ-001/002/004 | Directed segmentation/thermometer | dem=0; codes 000,FFF,29C,E2A,924,800,7FF,200,040,008,001 | explicit `sw_* == therm(field)` per segment + weighted sum == code | PASS |
| T-007 | REQ-005/006/007, ERR-003 (C7, A9) | Two's-complement mapping | fmt=1: 800→0, 7FF→4095, 000→2048, FFF→2047; 200 random v | sum == {~v[11],v[10:0]} (== offset-binary v+2048); fmt=0 regression unchanged (T-002..6 ran with fmt=0) | PASS |
| T-008 | REQ-008 (C6) | fmt_sel per-capture semantics | DRZ mode; capture 12'h800 with fmt=0 then fmt=1; toggle fmt during the non-capture (DRZ-launch) cycle of each sample | sums 2048 then 0; mid-flight toggle has no effect (in-flight sample keeps capture-time interpretation) | PASS |
| T-009 | REQ-012/013/017 (C1) | Seed write at non-capture edge | DRZ mode, `seed_wr` 1 cycle to MSB, wdata=16'h1234, at a `data_req=0` cycle | hier LFSR == 16'h1234 right after edge; other 2 LFSRs untouched (CHK-06); conversion stream undisturbed (CHK-01/03/05); later R sequence from 16'h1234 (CHK-07) | PASS |
| T-010 | REQ-013 (C2, A4, D8/M5) | Write/advance collision | write 16'hBEEF to ULSB at a `data_req=1` cycle, dem=1 | write wins: LFSR == 16'hBEEF (advance skipped); colliding sample's `r_q == mod7(pre-write PRN)`; next capture R from 16'hBEEF | PASS |
| T-011 | REQ-015/016, ERR-001 (C3) | Zero-seed write | write 16'h0000 to LSB | LFSR == parameter seed 16'hB10D; never 0 (CHK-06) | PASS |
| T-012 | REQ-018, ERR-002 (C4) | Reserved address | write 16'hDEAD to addr 2'b11 at a non-capture edge | all 3 LFSRs (and per CHK-01 all other state) bit-identical to no-write | PASS |
| T-013 | PERF-004, REQ-016/017/018 (C5) | Back-to-back/held/soak writes | `seed_wr` held 8 cycles (MSB); 3 consecutive writes to 3 segments; 400-cycle random write soak (random addr incl. 2'b11, random data incl. 16'h0000) during DEMDRZ streaming | held: LFSR pinned to written value (no natural advance); each back-to-back write lands same cycle; all CHK pass throughout soak (REQ-017) | PASS |
| T-014 | REQ-014 (C15, C10) | Write during reset; reset after writes | rst=1 with seed_wr=1 (wdata=16'h5555) 2 cycles, after T-013's writes | write ignored; all LFSRs == parameter seeds after reset (runtime writes don't alter defaults) | PASS |
| T-015 | REQ-004/009 (C8) | dem_en mid-stream toggles | DRZ mode, toggle dem_en every 37 cycles ×6 | all CHK; R forced 0 / resumes at next capture per model; PRN timeline unaffected (CHK-06) | PASS |
| T-016 | REQ-021/023 (C9) | drz_en mid-stream toggles | toggle drz_en every 23 cycles ×6 | all CHK; defined next state within 1 cycle, no double-signal/-DRZ beyond defined transition (model) | PASS |
| T-017 | REQ-009 (C13) | Rotation-invariant codes, DEM activity, LLSB no-DEM | dem=1: codes 000 and FFF directed; 60× repeated 12'h924 | 000→all-off, FFF→all-on regardless of R; ≥2 distinct upper-segment selections over the run; `sw_llsb == 0001111` always (plain thermometer); every selection sums to code (CHK-03) | PASS |
| T-018 | REQ-010 | R uniformity (statistical) | NRZ+DEM, 14000 random samples; histogram of R per segment | each of 7 bins within ±15% of N/7, all 3 segments; R stability per sample via CHK-07 | PASS |
| T-019 | REQ-027, PERF-003 | Latency directed | single tagged sample in DRZ and in NRZ mode | weighted sum == tag exactly 2 edges after the capture edge (presented-cycle → output-cycle = 2 clk); intermediate DRZ cycle phase=0 in DRZ mode | PASS |

## 3. Requirement Coverage

| REQ-ID | Covered by | Result |
|---|---|---|
| REQ-001 | T-006, CHK-01 (all tests) | PASS |
| REQ-002 | CHK-03 (every signal phase), T-006 | PASS |
| REQ-003 | CHK-03 in all 4 modes (T-002..T-005, full ramp), T-017 | PASS |
| REQ-004 | T-003, T-005, T-006, T-015, CHK-01 | PASS |
| REQ-005 | T-007 (both mappings of same word) | PASS |
| REQ-006 | T-002..T-006 run with fmt_sel=0 (v1 vectors equivalent), T-007 | PASS |
| REQ-007 | T-007 (endpoints + 200 random equivalence) | PASS |
| REQ-008 | T-008 (C6), CHK-01 through fmt toggles | PASS |
| REQ-009 | T-017 (variability + LLSB plain), CHK-01/CHK-07 | PASS |
| REQ-010 | T-018 (histogram ±15%), CHK-07 (R once per capture, stable) | PASS |
| REQ-011 | T-020 (full period, software model), CHK-06 (DUT locked to model) | PASS |
| REQ-012 | T-009 (target changes, others untouched via CHK-06) | PASS |
| REQ-013 | T-009/T-010 (sequence continues from written value, CHK-06/07) | PASS |
| REQ-014 | T-014 (reset after writes restores parameter seeds) | PASS |
| REQ-015 | CHK-06 nonzero assert every cycle of every test; T-011 | PASS |
| REQ-016 | T-011, zero wdata cases in T-013 soak | PASS |
| REQ-017 | T-009/T-010/T-013 soak with all CHK live | PASS |
| REQ-018 | T-012, reserved-addr writes in T-013 soak | PASS |
| REQ-019 | CHK-02 every cycle of every test (incl. reset, DRZ, writes) | PASS |
| REQ-020 | CHK-08 (same-edge, no off-edge change) + RTL review/lint — partially analysis (see §4) | PASS (sim part) |
| REQ-021 | T-002 (alternation + 1/2-cycle throughput), CHK-01 | PASS |
| REQ-022 | CHK-04 every phase=0 cycle, T-001 post-reset | PASS |
| REQ-023 | T-004/T-005 (capture count == cycles), CHK-01 | PASS |
| REQ-024 | T-002..T-005 (all four dem×drz combinations) | PASS |
| REQ-025 | CHK-05 every cycle; data randomized every cycle incl. data_req=0 cycles (T-002/T-003) | PASS |
| REQ-026 | CHK-01 phase compare every cycle | PASS |
| REQ-027 | T-019 directed; CHK-01/CHK-03 imply it on every sample | PASS |
| REQ-028 | CHK-08 event-time monitor — plus lint/review | PASS (sim part) |
| REQ-029 | T-001, T-014, CHK-01 during reset cycles | PASS |
| PERF-001 | T-002 throughput counter | PASS |
| PERF-002 | T-004 throughput counter | PASS |
| PERF-003 | T-019 | PASS |
| PERF-004 | T-013 (held strobe / back-to-back single-cycle effect) | PASS |
| PERF-005 | Analysis-only (PRD A8: no numeric gate) | N/A |
| CFG-001 | CHK-09 dut3 (overridden seeds tracked by override model); T-001 | PASS |
| CFG-002 | CHK-09 dut2 (SEED_ULSB=0 → 16'h5EED, identical outputs, never 0) | PASS |
| CFG-003 | T-002..T-006/T-017 with fmt_sel=0, seed_wr=0 (v1 checks re-hosted; reset adapted per MAS M3) | PASS |
| ERR-001 | T-011, T-013 soak | PASS |
| ERR-002 | T-012, T-013 soak | PASS |
| ERR-003 | full 0..4095 ramp (T-002), full-range random both formats (T-007) | PASS |
| ERR-004 | By construction (no error ports exist); interface review | N/A |

MAS corner cases: C1→T-009, C2→T-010, C3→T-011, C4→T-012, C5→T-013,
C6→T-008, C7→T-007, C8→T-015, C9→T-016, C10→T-001/T-014, C11→CHK-02,
C12→T-004, C13→T-017, C14→CHK-04, C15→T-014, C16→CHK-09(dut2),
C17→T-002..T-005 (see CFG-003 note), C18→CHK-06/T-020. All 18 exercised.

## 4. Escalations / Uncoverable items

- REQ-020 (no boundary combinational path between rails) and REQ-028
  (registered outputs) are not fully provable by black-box simulation;
  covered by CHK-08 (no off-edge output events, same-edge dual-rail updates)
  plus RTL review (separate `sw_*_n` flops, same always block) and the clean
  lint log. Flagged as sim+analysis.
- PERF-005: no numeric fmax target (PRD A8) — analysis-only, not a gate.
- CFG-003 literal "v1 testbench passes unchanged": impossible verbatim
  because the v1 port `rst_n` was replaced by `rst` (MAS decision D1,
  assumption M3). The v1 checks are re-hosted in this TB with new inputs tied
  inactive. Not a gap; noted for the record.
- No spec ambiguities requiring escalation were found; MAS C1/C2 cycle naming
  ("signal phase" = capture-edge cycle naming by launched output) was
  resolved operationally via `data_req` (=0 for C1 write, =1 for C2 write).
