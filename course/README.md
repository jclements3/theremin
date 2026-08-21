# FPGA-GHDL-Emacs: Noob to Pro — the iCE Theremin Course

A self-paced training class that takes you from zero HDL experience to a
working digital theremin on a Lattice iCE40, using VHDL-2008, the open
toolchain (GHDL + Yosys + nextpnr + icestorm), and Emacs — with an explicit
radar-concept thread through every lesson, because a theremin is a CW radar
that sings.

## How to take the class

1. Read `lessonXX.md` in order, starting at `lesson00.md`.
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
- `solutions/lessonXX/` — verified reference code + `OUTPUT.log` per lesson.
- `verify.sh` — re-verifies the whole course end to end.
