# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A hands-on FPGA learning project: building a digital theremin in VHDL on Lattice iCE40 hardware as a structured path toward radar-relevant DSP blocks (NCO/DDS, mixers, CIC/FIR, FFT, CFAR) and eventual Army SBIR credibility in FPGA-based sensor processing. The full phased plan, hardware list, and DO-254 discipline notes live in `fpga/ROADMAP.md` — read it before making design decisions.

Layout:
- `fpga/` — the active project. `ROADMAP.md` (phases, toolchain pins, machine setup), `phase1/` (NCO/DDS module, testbench, Makefile, board constraints), `setup/` (udev rule and WSL USB-attach script for hardware machines).
- `theremin.html`, `diagrams/`, `floorplan.txt` — earlier standalone educational artifacts explaining theremin physics (heterodyne zero-beat, capacitive pitch field). Self-contained presentation pieces; keep them dependency-free if edited.
- `d-lev-design-files/` — third-party reference: Eric Wallin's D-Lev digital theremin design files (see its `LICENSE.txt`). Reference material only — do not modify.

## Two-machine workflow

Development toggles between two machines, synced **only through this git repo** (github.com/jclements3/theremin):

- **Home laptop** (WSL2 Ubuntu 22.04 on Windows host "VALKYRIE"): simulation and synthesis only. The Windows account has no admin rights, so usbipd-win cannot be installed — **never attempt board flashing or elevated Windows installs here**; surface any admin-requiring step to Jim instead.
- **Lab machine** (native Ubuntu): hardware work — board flashing (`make prog`) and anything needing USB. Setup steps are in `fpga/ROADMAP.md` Phase 0; everything needed travels in `fpga/setup/`.

When finishing work on either machine, commit and push so the other machine can pull; assume uncommitted work is invisible to the other machine.

## Toolchain

Pinned: YosysHQ OSS CAD Suite release **2026-08-20** (GHDL 7.0.0-dev, Yosys 0.68, nextpnr 0.11.1), installed per-machine at `~/tools/oss-cad-suite/`. Activate per shell with `source ~/tools/oss-cad-suite/environment` (do not put in `.bashrc` — it shadows system python3). On hosts with glibc < 2.38 (e.g., Ubuntu 22.04), GHDL elaboration needs the `__isoc23_*` shim at `~/tools/glibc-isoc23-shim.o` (source and instructions in `fpga/ROADMAP.md`; wired in via `GHDL_ELAB_FLAGS` in the Makefile).

## Commands (from `fpga/phase1/`)

- `make sim` — analyze/elaborate/run the self-checking testbench. **Always run before synthesis; never flash what hasn't been simulated.**
- `make wave` — sim + open `build/nco_tb.ghw` in GTKWave.
- `make synth` / `make bit` — netlist / bitstream. Default `BOARD=icestick`; use `make BOARD=hx8k bit` for the HX8K breakout.
- `make time` — icetime static timing check.
- `make prog` — flash (lab machine only; run `../setup/attach-fpga.sh` first if on WSL).

## Conventions

- VHDL-2008, `numeric_std` only (never `std_logic_arith`). One entity per file. Synchronous active-high resets; clock enables, never gated clocks; registered outputs at module boundaries. All asynchronous inputs get 2-FF synchronizers.
- Testbenches are self-checking with requirement-tagged asserts (`R1 FAIL: ...` pattern — see `phase1/tb/nco_tb.vhd`). New RTL modules list their requirements in a header comment and get a testbench verifying each.
- Zero-warning synthesis: yosys latch/width warnings are defects, not noise.
- Build outputs stay out of git (`.gitignore` covers `build/`, `*.o`, `*.ghw`, work libraries).
- Preserve physics accuracy in the explainer artifacts (the audible note is the *difference* of two RF oscillators; the hand is a capacitor plate; octave count comes from the oscillator circuit, not antenna height).
