# FPGA-GHDL-Emacs: Noob to Pro — the iCE Theremin Course

A self-paced training class that takes you from zero HDL experience to a
working digital theremin on a Lattice iCE40, using VHDL-2008, the open
toolchain (GHDL + Yosys + nextpnr + icestorm), and Emacs — with an explicit
radar-concept thread through every lesson, because a theremin is a CW radar
that sings.

## How to take the class

1. Read the course in this order: lessons 00–04, `radar-interlude-1.md`,
   lessons 05–10, `radar-interlude-2.md`, lessons 11–12,
   `radar-interlude-3.md`, lessons 13–14, `radar-interlude-4.md`, then
   `lesson99.md`. The interludes are one-sitting radar reads with no code
   to run — take them where they fall, while the build they refer to is
   still fresh.
2. For each lesson: create `course/work/lessonXX/`, copy the lesson's code
   blocks into the named files with Emacs, run the given commands, and
   compare your output against the lesson's `Expected output:` blocks.
3. Do the **Explore** exercises before peeking at
   `course/solutions/lessonXX/` — the solutions are the verified reference
   the lessons were built from, there for when you're stuck or done.
4. The **Checkpoint** section at the end of each lesson tells you exactly
   what must be working before moving on.

Lessons 00–14 run entirely on a simulation-only machine (no board, no
admin rights needed). `lesson99.md` is lab day: board flashing and the
analog antenna front end, run on the lab machine.

`course/work/` is yours; it is git-ignored. Everything else in `course/` is
course material.

## Syllabus

| Lesson | Title | You build | Radar thread |
|---|---|---|---|
| 00 | Setup & Hello, World | hello_tb | tool discipline |
| 01 | Entities, Architectures, Signals | registered mux | HDL ≠ software |
| 02 | Testbenches That Check Themselves | counter + TB | verification as evidence |
| 03 | numeric_std & Fixed-Point Thinking | saturating adder | bit growth |
| 04 | The NCO | phase accumulator | DDS / STALO / chirp |
| 05 | From RTL to Bitstream | A440 bitstream | FPGAs for sensor front ends |
| 06 | Sequencers and Control | scale sequencer | SFCW frequency ladders |
| 07 | Sine Tables and Block RAM | quarter-wave sine LUT | waveform memory, spurs |
| 08 | One-Bit DACs | delta-sigma DAC | quantization noise, SFDR |
| 09 | Crossing Clock Domains Safely | 2-FF synchronizer | async sensor interfaces |
| 10 | Measuring Frequency | reciprocal counter | dwell/CPI vs resolution |
| 11 | Telemetry: UART | UART transmitter | instrumentation links |
| 12 | The Heterodyne Heart | XOR mixer + beat | downconversion, IF, images |
| 13 | Pitch Mapping and Musicality | period→pitch mapper | calibration, tracking loops |
| 14 | Integration | theremin_top | system test vs. target models |
| 99 | Lab Day: Hardware Bring-Up | the instrument | a CW radar you can hear |

(Lesson numbers 15–98 are intentionally unused; 99 is the reserved capstone
tag.)

## Pacing: sessions and stopping points

Every lesson is split into sessions of roughly 45–90 minutes, marked
`## Session XX.N` in the lesson file, so no sitting runs past what a tired
brain can absorb and no concept gets rushed to make a longer block "fit".
Each session except a lesson's last ends with a **Stopping point** — a short
list of things you should now be able to explain, phrased as testable
understanding. If you can't explain them, re-read before continuing; if you
can, that's a clean place to close the laptop. The lesson's Checkpoint still
ends the final session, exactly as before.

## Session map

The full reading order, with each lesson's sessions (names from the lesson
files; times are estimates):

- **00 — Setup & Hello, World** (2 sessions): Toolchain, Pipeline, and the
  Emacs Loop (~50 min) · Build, Break, and Verify (~60 min)
- **01 — Entities, Architectures, Signals** (3): Signal Semantics & Delta
  Cycles (~60) · Build & Run the Registered Mux (~60) · Explore &
  Checkpoint (~75)
- **02 — Testbenches That Check Themselves** (3): Anatomy of a
  Self-Checking Testbench (~60) · Build & Run (~75) · Explore &
  Checkpoint (~75)
- **03 — numeric_std & Fixed-Point Thinking** (3): Wrap vs Saturate (~60) ·
  Build & Run (~60) · Explore & Checkpoint (~75)
- **04 — The NCO** (3): The Phase Accumulator (~60) · Dissecting the
  Code (~75) · Run, Break, Measure (~80)
- ▸ **Radar Interlude 1 — From NCO to Chirp Radar** (one sitting, ~60 min)
- **05 — From RTL to Bitstream** (3): The Flow on Paper (~60) · Building
  the Bitstream (~75) · Explore & Checkpoint (~60)
- **06 — Sequencers and Control** (3): Timers, Tables, and the
  Fencepost (~75) · Build and First Green (~90) · Break It on Purpose (~60)
- **07 — Sine Tables and Block RAM** (3): Folding the Sine (~75) · Build &
  Run (~75) · Explore & Checkpoint (~75)
- **08 — One-Bit DACs** (3): Scheduling Ones (~75) · Building the
  Modulator (~60) · Break, Probe, Audit (~60)
- **09 — Crossing Clock Domains Safely** (3): Metastability by the
  Numbers (~60) · Building the Border Checkpoint (~75) · Break It on
  Purpose (~60)
- **10 — Measuring Frequency** (3): The Counting Trade (~75) · Build &
  Run (~90) · Explore & Checkpoint (~75)
- ▸ **Radar Interlude 2 — Dwell, CPI, and the Price of Resolution** (one
  sitting, ~60 min)
- **11 — Telemetry: UART** (3): Designing 8N1 from Nothing (~75) · Build &
  Run (~90) · Explore & Checkpoint (~75)
- **12 — The Heterodyne Heart** (3): Multiplication Moves
  Frequencies (~90) · Build & Run (~90) · Explore & Checkpoint (~75)
- ▸ **Radar Interlude 3 — Your Theremin IS a CW Radar** (one sitting,
  ~60 min)
- **13 — Pitch Mapping and Musicality** (3): Deriving the Map (~75) ·
  Build & Run (~90) · Explore & Checkpoint (~75)
- **14 — Integration** (4): The System View (~75) · Build the
  Instrument (~60) · Prove It: Sim, Fit, Timing (~75) · Explore &
  Checkpoint (~75)
- ▸ **Radar Interlude 4 — From Instrument to Sensor: Toward Counter-UAS**
  (one sitting, ~60 min)
- **99 — Lab Day: Hardware Bring-Up** (4): From Model to Bench (~60) · Lab
  Machine and Smoke Test (~75) · Oscillator Bring-Up and Tuning (~90) ·
  Explore, Exit Criteria, and the Radar Epilogue (~75)

## Ground rules baked into every lesson

- Simulation before synthesis, always. Never flash what hasn't been simulated.
- Self-checking, requirement-tagged testbenches (`R1 pass:` … lines) — the
  lightweight version of DO-254 traceability.
- No black boxes: every provided line of code is explained in the lesson.
- All `Expected output:` blocks were captured from real runs and are
  re-verified by `course/verify.sh`, which extracts every code block from
  the lessons and re-runs it — the same copy-paste workflow you'll use.

## Files

- `CURRICULUM.md` — the design contract the course was built against
  (interfaces, format rules, the finished instrument's block diagram).
- `lesson00.md` … `lesson14.md`, `lesson99.md` — the class.
- `radar-interlude-1.md` … `radar-interlude-4.md` — concept-only radar
  reads slotted into the reading order above (no code to run; each ends
  with an SBIR Notebook of counter-UAS talking points).
- `PACING.md` — the session-split and interlude contract the pacing pass
  was built against.
- `solutions/lessonXX/` — verified reference code + `OUTPUT.log` per lesson.
- `verify.sh` — re-verifies the whole course end to end.
