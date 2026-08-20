# Theremin → FPGA DSP → Radar: Learning Roadmap

Target: VHDL on Lattice iCE40 (iCEstick / HX8K-B-EVN), open toolchain only
(GHDL + ghdl-yosys-plugin + Yosys + nextpnr-ice40 + icestorm).
End state: credible authorship of Army SBIR proposals involving FPGA-based
radar/sensor processing, with counter-UAS as the domain focus.

## Phases

Each phase produces working hardware, a self-checking testbench, and a named
radar concept. Do not start phase N+1 until phase N runs on the board.

### Phase 0 — Toolchain bring-up (a weekend)
- Install the YosysHQ **OSS CAD Suite** (dated release tarball; bundles GHDL,
  the ghdl-yosys-plugin, yosys, nextpnr, icestorm, gtkwave).
- **INSTALLED 2026-08-20**: release `2026-08-20` at `~/tools/oss-cad-suite/`
  (GHDL 7.0.0-dev Dunoon, Yosys 0.68+106, nextpnr 0.11.1). Activate per shell
  with `source ~/tools/oss-cad-suite/environment` (it prepends its own
  python3 etc. to PATH, so don't put it in .bashrc — use an alias).
- **glibc workaround**: the suite's GHDL runtime targets glibc >= 2.38 but
  Ubuntu 22.04 has 2.35, so `ghdl -e` link fails on `__isoc23_strtol`. Fix:
  `~/tools/glibc-isoc23-shim.c` (compiled to `.o`, passed via
  `GHDL_ELAB_FLAGS` in phase1/Makefile). Remove after a distro upgrade.
- **Machine split (decided 2026-08-20):** the primary WSL2 box (VALKYRIE)
  has no Windows admin rights, so usbipd-win cannot be installed there. It is
  the dev/simulation machine only; all hardware flashing happens on the lab
  machine. udev rule is already installed on VALKYRIE anyway (harmless).
- Lab-machine setup when the board arrives (everything needed travels with
  this repo in `setup/`):
  - If Windows+WSL2: install usbipd-win from elevated PowerShell
    (`winget install --exact --id dorssel.usbipd-win`), then per plug-in run
    `setup/attach-fpga.sh` (one-time elevated `usbipd bind --busid <id>` on
    first use, which the script prints).
  - Either way (WSL or native Linux): `sudo cp setup/53-lattice-ftdi.rules
    /etc/udev/rules.d/ && sudo udevadm control --reload` so iceprog runs
    unprivileged. Toolchain: same pinned oss-cad-suite 2026-08-20 tarball;
    the glibc shim is only needed if the lab distro's glibc is < 2.38.
- Deliverable: `phase1/` blinks its heartbeat LED via `make sim && make bit && make prog`.
- Radar takeaway: none yet — tool discipline. DO-254 mindset: qualified,
  version-pinned tools; simulation evidence before hardware.

### Phase 1 — NCO / DDS (1–2 weeks) — scaffolded in `phase1/`
- W-bit phase accumulator, MSB out as a square tone (A440 on a piezo),
  heartbeat LED. Testbench proves the frequency property for arbitrary FCW.
- Extend it yourself: FCW selected by the board's buttons/jumpers → a scale.
- **Radar analog:** the NCO *is* the DDS/STALO. f_res = f_clk/2^W is chirp
  step granularity; phase truncation jitter previews spur mechanisms.
- **DO-254 habit:** requirement-tagged asserts (R1/R2/R3 pattern), sim before
  synthesis, zero-warning synthesis (yosys latch/width warnings are defects).

### Phase 2 — Capacitive sensing front end (2–3 weeks)
- Breadboard a 74HC14 Schmitt-trigger relaxation oscillator (~100–500 kHz)
  whose timing capacitor is the antenna; hand proximity adds ~0.1–1 pF and
  lowers f. Feed it into an FPGA pin.
- In fabric: 2-FF synchronizer → reciprocal (period) counter → UART (FTDI
  channel B) → plot on PC. Watch your hand move the number.
- **Radar analog:** the sensor front end. Gate time vs. frequency resolution
  is exactly radar dwell/CPI vs. Doppler resolution: Δf ≈ 1/T_gate.
- **DO-254 habit:** every asynchronous input synchronized and the CDC
  documented; metastability as a named, mitigated hazard.

### Phase 3 — Heterodyne / mixer (2–3 weeks)
- Mix the sensed oscillator against a fixed on-chip reference NCO: XOR mixer
  (1-bit multiplier) + accumulate-and-dump low-pass → beat frequency. This is
  the actual theremin architecture, in digital form.
- **Radar analog:** downconversion LO×RF→IF. You will hit the image response
  (|f_lo−f| and cannot tell sign) — the motivation for quadrature in Phase 5.
- **DO-254 habit:** registered outputs at every module boundary; block
  diagram kept current with the code.

### Phase 4 — Audio synthesis (2 weeks)
- Quarter-wave sine LUT addressed by NCO phase; 1st-order delta-sigma 1-bit
  DAC out a pin + RC filter; map sensed frequency → pitch FCW (linearize the
  1/√C response so equal hand steps ≈ equal semitones).
- **Radar analog:** transmit waveform generation; quantization noise and
  noise shaping (why radar exciters care about DAC spurs/SFDR).
- **DO-254 habit:** fixed-point formats written down (Qm.n per signal).

### Phase 5 — Digital downconverter (3–4 weeks)
- Quadrature NCO (sin+cos), I/Q mixing, CIC decimator, compensating FIR.
  On HX8K multipliers are LUT-built — keep coefficients small or serialize.
- **Radar analog:** the DDC — front half of every modern radar receiver;
  I/Q resolves the Phase 3 image ambiguity (signed Doppler).
- **DO-254 habit:** documented bit-growth analysis per stage (CIC growth =
  N·log2(R·M)); golden-model comparison (NumPy) in the testbench.

### Phase 6 — Spectral processing (4+ weeks)
- Serial radix-2 256-pt FFT, magnitude approximation, CA-CFAR threshold,
  detections over UART. If HX8K gets tight, this is the ULX3S/ECP5 on-ramp.
- **Radar analog:** Doppler FFT + CFAR — the core detection chain of a
  counter-UAS sensor. Understand P_fa vs. threshold from first principles.
- **DO-254 habit:** file-driven testbenches, coverage of corner bins,
  traceability matrix (requirement → test → result).

### Phase 7 — Integration / real radar (stretch)
- (a) Full theremin: pitch + volume antennas, both sensed, delta-sigma audio.
- (b) **HB100 10 GHz Doppler module** (~$6): its IF output is audio-band
  Doppler (~72 Hz per m/s). Comparator or MCP3202 ADC into the FPGA, then
  your Phase 5–6 chain displays target velocity. Same pipeline, real radar —
  this is the SBIR demo artifact.

## Shopping list

| Item | ~Cost |
|---|---|
| iCE40-HX8K-B-EVN breakout (preferred; iCEstick OK through Phase 4) | $70 |
| 74HC14, 2N3904s, passives/trimmer assortment | $20 |
| Telescopic antenna or 3/8" Al rod + banana jack | $8 |
| Breadboard, jumpers, headers | $15 |
| Piezo + small amplified speaker | $10 |
| HB100 Doppler modules ×2 | $15 |
| MCP3202 SPI ADC | $12 |
| FX2-based logic analyzer (sigrok/PulseView) | $15 |
| **Core total** | **~$165** |
| Rigol DHO804 scope (if no access to one; needed from Phase 2) | ~$350 |
| ULX3S 85F (defer to Phase 6 decision point) | ~$180 |

## Workflow habits (every phase)

1. `make sim` before every synthesis. Never flash what you haven't simulated.
2. Read the yosys `stat` output every build — know your LUT/FF/BRAM budget.
3. `make time` (icetime) is your static timing gate; the `--freq 12` arg to
   nextpnr makes timing failures loud.
4. One entity per file; `numeric_std` only (never `std_logic_arith`);
   synchronous resets; clock enables, never gated clocks; single clock domain
   until Phase 2 forces CDC, then 2-FF synchronizers only.
5. Testbench asserts carry requirement tags (R1, R2, …). The report line at
   end of sim is your pass/fail evidence — keep logs.

## Where hobby VHDL diverges from certification-grade (DO-254) practice

Worth knowing for SBIR credibility; adopt the cheap ones now.

- **Requirements before design.** DO-254 flows derive HDL from traced
  requirements; the R-tag testbench pattern here is the lightweight version.
- **Elemental analysis / coverage:** statement+branch+condition coverage of
  RTL in sim, plus verification of every requirement at the elemental level.
  GHDL has code-coverage support via GCC backend; use it from Phase 5 on.
- **Coding standards are enforced, not stylistic:** no latches, no
  combinational feedback, registered I/O, one driver per signal, reset
  strategy uniform across the design. Tools like `vhdl-style-guide` (vsg)
  automate this — add to CI early.
- **Tool assessment:** certification requires assessing/qualifying tools or
  independently verifying their output. Open-source flows are usable in
  DO-254 programs only with independent output verification (e.g., post-PnR
  simulation, equivalence checks) — know this talking point for proposals.
- **CDC and metastability get formal analysis**, not just convention.
- **Traceability artifacts** (req → design → test → result matrices) are
  deliverables. Start faking the discipline now; it's the part reviewers of
  RKV-era firmware will recognize instantly.
