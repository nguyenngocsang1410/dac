# Changelog

## [2.0.0] — 2026-06-11

`dac_demdrz_top` v2 — first release through the full deliverables pipeline
(PRD → MAS → RTL → verification → docs → review, per `CLAUDE.md`).
Review verdict: **APPROVED-WITH-WAIVERS** (0 CRITICAL / 1 MAJOR, fixed at
release / 6 MINOR) — `docs/reviews/dac_demdrz_top_review.md`.

### Added
- **Input format select** (`fmt_sel`): 0 = offset-binary (v1-compatible),
  1 = two's-complement, mapped by MSB inversion ahead of the capture
  register; applies per captured sample. (REQ-005..008)
- **Runtime-loadable PRNG seeds** (`seed_wr`, `seed_addr[1:0]`,
  `seed_wdata[15:0]`): single-cycle synchronous write to any of the three
  segment LFSRs; priority rst > load > advance; a zero write substitutes
  the parameter seed so the LFSR can never lock up; address `2'b11`
  reserved (silently ignored). Zero seed *parameters* are likewise
  substituted at elaboration. (REQ-012..018, CFG-002)
- **Complementary switch outputs** (`sw_msb_n/ulsb_n/lsb_n/llsb_n[6:0]`):
  28 additional flops in the same output register stage, exactly
  `~sw_*` on every cycle including reset. (REQ-019..020)
- Full deliverables set: PRD (`docs/prd/`), MAS (`docs/arch/`), test plan
  (`verif/plans/`), regression + lint logs (`verif/results/`), TRM
  (`docs/trm/`), integration guide (`docs/guides/`), design review
  (`docs/reviews/`).
- RTL design harness (`CLAUDE.md`, `.claude/` agents/commands/settings,
  `docs/templates/`).

### Changed
- **Reset scheme**: synchronous active-high `rst` replaces v1's
  asynchronous active-low `rst_n` (MAS decision D1; harness §6 default).
  Assert ≥ 1 clk cycle; deassert synchronously. `data_req` is now forced
  low during reset (D7).
- Testbench rewritten as a REQ-traceable regression: 20 directed tests,
  9 always-on checkers, independent behavioral reference model,
  ~40k cycles. `verif/results/dac_demdrz_top_sim.log`: ALL TESTS PASSED.
- `syn/constraints.sdc` regenerated for the v2 interface (sync `rst` as a
  timed path, seed/format inputs constrained, `sw_*_n` added to the
  skew-matched output group) — closes review finding F-001.
- Behavioral analog-array model moved to `tb/dac_analog_ref.v` (module
  `dac_analog_ref`), per harness layout conventions.

### Unchanged (v1 behavior preserved, re-verified)
- 3+3+3+3 segmentation, 7 unit elements per segment, 512/64/8/1 LSB
  weights; random-rotation DEM on the upper 9 bits with per-segment
  16-bit maximal-length LFSRs and uniform R ∈ {0..6}; DRZ mid-code
  insertion (MSB elements 1/3/5/7 = 2048 LSB) at clk = 2× sample rate;
  dem_en/drz_en mode controls; data_req capture handshake; 2-cycle
  latency; registered outputs with DRZ mid-code reset state.

### Compatibility
- v1 integrations must: rename/invert reset (`rst = ~rst_n`, now
  synchronous), tie `fmt_sel = 0`, `seed_wr = 0` (`seed_addr`,
  `seed_wdata` don't-care), and may leave `sw_*_n` unconnected. With new
  inputs tied inactive, encoding behavior is bit-identical to v1 for the
  same seed parameters. (CFG-003)

## [1.0.0] — 2026-06-11

Initial DEMDRZ encoder RTL modeled on Lin/Huang/Kuo, IEEE JSSC vol. 49
no. 3 (2014): DEM + digital-return-to-zero encoder for a 12-bit segmented
current-steering DAC, with sim-only analog-array model, self-checking
testbench, yosys synthesizability check, and SDC template.
