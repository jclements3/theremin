# FPGA-GHDL-Emacs: Noob to Pro — Curriculum Contract

The design authority for the lesson series in this directory. Lesson authors
and reviewers: follow this exactly. Students: this is the syllabus; the
lessons themselves are `lesson00.md` … `lesson14.md` and `lesson99.md`
(99 is the reserved number for the lab-day capstone).

**Course goal.** Starting from zero HDL experience, build a working digital
theremin on a Lattice iCE40 using VHDL-2008 and the open toolchain (GHDL +
Yosys + nextpnr + icestorm), developing radar-transferable signal-processing
intuition along the way. Every lesson runs on a simulation-only machine; only
lesson99 requires the physical board and lab bench.

**Student profile.** Senior systems engineer; strong software background
(Python/C/Rust/Haskell); knows what registers and state machines are; new to
writing HDL. Explain from first principles but never condescend. No black
boxes: every line of provided code must be explainable from the lesson text.

**Editor workflow.** The student reads lessonXX.md, copies code blocks into
files with Emacs (vhdl-mode; `<f6>` = recompile, `M-g n` = next-error), runs
the given commands, and compares against the lesson's expected output.

## Lesson format (mandatory template)

Each lesson markdown uses exactly these sections, in order:

1. `# Lesson XX — <Title>` then a one-paragraph *Where we are* orienting the
   student in the course arc.
2. `## Objectives` — 3–6 bullets, checkable.
3. `## Concepts` — the teaching. First-principles explanations, diagrams as
   ASCII/fenced text where they help.
4. `## Radar Connection` — the explicit theremin↔radar mapping for this
   lesson's material. Every lesson has one.
5. `## Build` — the code. **Every file the student creates appears as a
   complete fenced code block, immediately preceded by a bold line:**
   `**File: course/work/lessonXX/<name>**` (student's working copy path).
   No fragments that can't be pasted verbatim; if a file evolves during the
   lesson, show the complete final version last and say so.
6. `## Run` — commands in ```bash blocks (assume `fpga` alias exists and
   cwd = `course/work/lessonXX/`), each followed by
   `Expected output:` and a ```text block containing REAL output captured
   from an actual run — never typed from memory. Trim only boilerplate
   (`make: Entering…` lines may be elided with `[...]`), never invent.
7. `## Explore` — 2–4 exercises modifying the build, with what-to-observe.
   At least one "break it on purpose" exercise per early lesson.
8. `## Tips & Pitfalls` — including at least one Emacs/vhdl-mode tip and
   one toolchain gotcha where relevant.
9. `## Checkpoint` — bullet list: what the student must have working before
   the next lesson, phrased as verifiable facts ("`make sim` prints …").

Tone: direct, technical, occasionally wry. US letter-style prose, no
marketing language. Code comments follow repo house style (see CLAUDE.md):
lowercase keywords, 2-space indent, numeric_std only, synchronous active-high
resets, clock enables, requirement-tagged testbench asserts (R1, R2, …).

## Verified-solutions rule

`course/solutions/lessonXX/` holds the reference implementation of every
lesson's Build files plus a `Makefile` (pattern: fpga/phase1/Makefile in
miniature; sim target mandatory, synth targets where the lesson synthesizes)
and `OUTPUT.log` capturing the real `make sim` output. Lesson code blocks
must be byte-identical to the solution files (verify by extraction + diff).
The student is told solutions exist and to resist peeking until attempting
the Explore exercises.

GHDL flags everywhere: `--std=08 --workdir=build`; elaboration adds
`-Wl,$(HOME)/tools/glibc-isoc23-shim.o` (see fpga/ROADMAP.md Phase 0; on
hosts with glibc >= 2.38 the shim is unnecessary but harmless if present —
lessons note this once, in lesson00).

## The finished instrument (designed first, taught backwards)

Signal chain of `theremin_top` (lesson14, flashed in lesson99):

```
antenna --> [74HC14 relaxation osc, ~200 kHz]   (hardware, lesson99;
                     |                           osc_model.vhd in sim)
             osc_in  v
      +----------------------------------------------------------+
      | sync_2ff --> freq_meas --> pitch_map --> nco --> sine_lut |
      |  (L09)        (L10)          (L13)      (L04)     (L07)   |
      |                                                    |      |
      |                                     dsm_dac <------+      |
      |                                      (L08)                |
      +----------------------------------------|-----------------+
                                     audio_out v  --> RC filter --> amp
```

12 MHz clock domain throughout; the antenna oscillator is the only async
input. Lesson12's heterodyne mixer is a standalone physics-authentic
alternative path (XOR mix against a reference NCO), taught for the radar
insight; theremin_top uses the measurement path above.

## Pinned module interfaces

Authors implement EXACTLY these entities (generics may gain defaults, not
change names/types). Existing verified code is reused where noted.

- **nco** — reuse `fpga/phase1/rtl/nco.vhd` verbatim (copy into solutions).
- **scale_seq** — lesson06 guided build; same entity as
  `fpga/phase1/rtl/scale_seq.vhd` (the phase1 exercise skeleton); TB reuse
  `fpga/phase1/tb/scale_seq_tb.vhd` verbatim.
- **sine_lut** (L07):
  `generic (PHASE_BITS : positive := 10; DATA_BITS : positive := 8)`
  `port (clk : in std_logic; phase : in unsigned(PHASE_BITS-1 downto 0); data : out signed(DATA_BITS-1 downto 0))`
  Quarter-wave folded table (2^(PHASE_BITS-2) entries) built by an
  elaboration-time function (math_real); registered output, 1-cycle latency.
- **dsm_dac** (L08):
  `generic (W : positive := 8)`
  `port (clk, rst : in std_logic; sample : in signed(W-1 downto 0); bit_out : out std_logic)`
  First-order error-feedback delta-sigma.
- **sync_2ff** (L09):
  `port (clk : in std_logic; async_in : in std_logic; sync_out : out std_logic)`
- **freq_meas** (L10) — reciprocal period counter:
  `generic (EDGES : positive := 64; CNT_BITS : positive := 24)`
  `port (clk, rst : in std_logic; sig_in : in std_logic; period : out unsigned(CNT_BITS-1 downto 0); valid : out std_logic)`
  `period` = clk cycles spanning EDGES rising edges of sig_in; `valid`
  strobes 1 clk per completed measurement.
- **osc_model** (L10, SIMULATION-ONLY, marked as such):
  `generic (BASE_HZ : real := 200_000.0; DELTA_HZ : real := 0.0)`
  `port (hand : in real; osc_out : out std_logic)` — square wave at
  BASE_HZ - hand*DELTA_HZ... authors: define precisely, document the model.
- **uart_tx** (L11):
  `generic (CLK_HZ : positive := 12_000_000; BAUD : positive := 115_200)`
  `port (clk, rst : in std_logic; data : in std_logic_vector(7 downto 0); stb : in std_logic; busy : out std_logic; txd : out std_logic)`
  8N1.
- **het_mixer** (L12):
  `generic (ACC_LOG2 : positive := 10)`
  `port (clk, rst : in std_logic; rf_in, lo_in : in std_logic; if_out : out unsigned(ACC_LOG2 downto 0); if_stb : out std_logic)`
  XOR mixer, accumulate-and-dump over 2^ACC_LOG2 clocks.
- **pitch_map** (L13):
  `generic (CNT_BITS : positive := 24; SHIFT : natural := 6; P_REF : positive := 3840; FCW_BASE : positive := 93640; FCW_MIN : positive := 46820; FCW_MAX : positive := 374561)`
  `port (clk, rst : in std_logic; period : in unsigned(CNT_BITS-1 downto 0); valid : in std_logic; fcw : out unsigned(31 downto 0))`
  fcw = clamp(FCW_BASE + ((P_REF - period) shifted left SHIFT)); linear in
  period (approximation stated honestly in the lesson), clamped to
  [FCW_MIN, FCW_MAX]; simple exponential smoothing allowed if taught.
  Defaults assume the integration scenario: 12 MHz clock, 200 kHz nominal
  antenna oscillator, EDGES=64 (so P_REF = 64 * 12e6/200e3 = 3840) and
  FCW_BASE = C4 (261.6256 Hz -> 93639.45, pinned at 93640, ~1.5 mHz sharp —
  the pinned integers here are contract values, stated to within counts of
  exact in lesson13); clamps = one octave below C4 to two
  above. theremin_top instantiates with these defaults — integration and
  module authors must not diverge from them.
- **theremin_top** (L14):
  `port (clk12 : in std_logic; osc_in : in std_logic; audio_out : out std_logic; led_hb : out std_logic)`
  Wires the chain per the diagram; includes POR (pattern from
  fpga/phase1/rtl/top.vhd). Must synthesize for BOTH icestick (hx1k) and
  hx8k with `make bit` / `make BOARD=hx8k bit` and pass icetime at 12 MHz.
  Integration TB drives osc_model with a moving "hand" and checks audio
  fundamental tracks it (self-checking, requirement-tagged).

Demo modules for L01–L03 (self-contained per lesson, author's choice of
detail, entities small): L01 a 2:1 registered mux; L02 an 8-bit wrapping
counter with enable; L03 a saturating adder. Each with a self-checking TB.

## Lesson list and scope

- **lesson00 — Setup & Hello, World.** Toolchain install recap (pointer to
  fpga/ROADMAP.md for the full install; assume done), `fpga` alias, Emacs
  workflow (dir-locals trust prompt, M-x compile, <f6>, M-g n), hello_tb
  (reuse tutorial/hello.vhd content), red/green/next-error drills.
  Radar: tool discipline & pinned versions.
- **lesson01 — Entities, Architectures, Signals.** Structure of a VHDL
  design; signal semantics & delta cycles vs software variables;
  combinational vs registered processes; the registered mux. Radar: why
  hardware description is not programming.
- **lesson02 — Testbenches That Check Themselves.** Clock/stimulus
  processes, assert/report/severity ladder, requirement tags; GTKWave
  basics (surfer optional aside). Counter + TB. Radar: verification as
  evidence, DO-254 lite.
- **lesson03 — numeric_std and Fixed-Point Thinking.** unsigned/signed,
  resize, wrap vs saturate, constants & elaboration-time math. Saturating
  adder. Radar: word growth through a signal chain.
- **lesson04 — The NCO.** Phase accumulators from first principles;
  frequency resolution; jitter; dissect nco.vhd + nco_tb.vhd (reused).
  Radar: DDS/STALO/chirp generation.
- **lesson05 — From RTL to Bitstream.** yosys/nextpnr/icestorm anatomy,
  PCF files, resource reports, icetime; top.vhd + POR; A440 bitstream
  (build only; flashing deferred to lesson99). Radar: FPGAs vs CPUs/GPUs
  for sensor front ends.
- **lesson06 — Sequencers and Control.** Guided build of scale_seq against
  the existing TB; timers, indices, fencepost bugs. NOTE: the student may
  have already attempted this as the phase1 exercise — the lesson says so
  and offers it as build-or-review. Radar: SFCW frequency ladders.
- **lesson07 — Sine Tables and Block RAM.** Quarter-wave symmetry, LUT
  sizing, BRAM inference and how to read the yosys stat line. sine_lut +
  TB. Radar: waveform memory, DDS spur floor.
- **lesson08 — One-Bit DACs.** PWM vs delta-sigma; noise shaping intuition;
  the RC that turns bits into volts. dsm_dac + TB (mean-tracking check).
  Radar: quantization noise, SFDR, why exciters care.
- **lesson09 — Crossing Clock Domains Safely.** Metastability physics,
  2-FF synchronizer, CDC rules-of-the-road. sync_2ff + TB. Radar: every
  real sensor is async to your DSP clock.
- **lesson10 — Measuring Frequency.** Reciprocal vs direct counting, gate
  time vs resolution; freq_meas + osc_model + TB sweeping a simulated
  hand. Radar: dwell/CPI vs Doppler resolution — the course's deepest
  radar tie-in; do it justice.
- **lesson11 — Telemetry: UART.** Serial framing, baud division, busy/strobe
  handshakes. uart_tx + decoding TB. Radar: instrumentation links.
- **lesson12 — The Heterodyne Heart.** Mixing from first principles; XOR as
  a 1-bit multiplier; sum/difference products; accumulate-and-dump as LPF;
  the image problem, discovered in the TB. het_mixer + TB with two NCOs a
  few hundred Hz apart. Radar: downconversion, IF, why quadrature exists.
  This is the lesson that explains why a theremin IS a CW radar.
- **lesson13 — Pitch Mapping and Musicality.** Period→pitch mapping,
  linearization honesty, clamping, smoothing; pitch_map + TB
  (monotonicity + range + smoothing step response). Radar: calibration
  curves and tracking-loop smoothing.
- **lesson14 — Integration.** theremin_top: wiring verified blocks,
  registered boundaries, resource budget on hx1k vs hx8k, end-to-end TB
  with a moving hand, both-board synthesis + timing. Radar: system-level
  test against target models before hardware exists.
- **lesson99 — Lab Day: Hardware Bring-Up.** On the lab machine: clone,
  toolchain, usbipd/udev (fpga/setup/), flash lesson05's A440 first, then
  74HC14 relaxation-oscillator front end on breadboard (design values
  derived in-lesson from the datasheet formula, marked tune-on-bench),
  theremin_top flash, tuning procedure, troubleshooting table (no tone /
  wrong pitch / jitter). Epilogue: HB100 Doppler module — same chain, real
  radar; pointers to ECP5/FFT/CFAR as the next course. No fabricated
  outputs: hardware-dependent results are described, not faked, and marked
  "observe on bench".

## Verification harness

`course/verify.sh` (bash): for each lesson with solutions, (1) extract every
`**File: course/work/lessonXX/<name>**`-tagged block from lessonXX.md into a
temp dir, (2) diff against course/solutions/lessonXX/ — byte-identical
required, (3) run `make sim` in the solutions dir and diff against
OUTPUT.log, (4) `emacs --batch` visits each extracted .vhd and reports the
major mode as a vhdl-mode smoke test. Exit nonzero on any mismatch. Lessons
without code (none currently) and lesson99's hardware-only sections are
skipped explicitly, not silently.
