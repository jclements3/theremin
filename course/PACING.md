# Pacing Contract — Sessions and Radar Interludes (phase-2 pass)

Applied AFTER the initial 16-lesson build verifies. This is the binding spec
for the session-split and interlude agents. Reviewers of the initial build:
ignore this file — the base lessons are not yet expected to comply.

## Goals (Jim's words)

A working theremin, plus understanding of (1) FPGA/GHDL coding, (2) the
Emacs-integrated workflow, (3) radar. Sessions exist so no sitting exceeds
~90 minutes and no concept is rushed.

## Session splitting rules

For each lessonXX.md (00–14 and 99):

- Insert session boundaries at natural seams — typically Concepts /
  Build & Run / Explore & Checkpoint. 2–4 sessions per lesson (lesson00 may
  be 1–2). Each session sized 45–90 minutes.
- Boundary format: a `---` rule, then `## Session XX.N — <short name> (~NN min)`.
  The lesson's existing `##` sections become `###` subsections inside their
  session where needed; content ORDER is preserved.
- Each session except the last ends with:
  `**Stopping point.** You should now be able to explain:` followed by 2–4
  bullets phrased as testable understanding ("why the accumulator's wrap is
  the output period", not "the NCO").
- The lesson's final Checkpoint section remains the end of the last session.
- MUST NOT change: code blocks, `**File:**` tags, Run commands, expected
  output, requirement text, or any technical claim. This is a structural
  edit; `course/verify.sh` must still pass byte-identical extraction
  afterward — run it for your lesson before finishing.

## Radar interludes

New concept-only files, no VHDL code blocks (ASCII diagrams and worked math
encouraged), 200–400 lines each, same tone as the lessons:

- `radar-interlude-1.md` — after lesson04. "From NCO to chirp radar":
  DDS → LFM chirp generation, frequency resolution vs sweep design, why the
  student's 32-bit accumulator is the same part in an FMCW exciter.
- `radar-interlude-2.md` — after lesson10. "Dwell, CPI, and the price of
  resolution": gate time ↔ frequency resolution just measured, mapped to
  radar dwell/CPI/Doppler bins; the uncertainty tradeoff as engineering
  budget, with worked numbers from the lesson10 build.
- `radar-interlude-3.md` — after lesson12. "Your theremin IS a CW radar":
  complete block-for-block mapping (antenna/target, sensing osc/RF front
  end, reference NCO/LO, XOR mixer/receiver mixer, beat/IF, pitch/Doppler),
  the image problem and why real radars use I/Q, what the HB100 changes.
- `radar-interlude-4.md` — after lesson14. "From instrument to sensor:
  toward counter-UAS": what an FFT bank and CFAR add to the chain the
  student now owns, micro-Doppler intuition, and the roadmap (ECP5, FFT,
  CFAR) from fpga/ROADMAP.md.

Each interlude: anchored concretely to hardware the student has already
built ("the counter you wrote in lesson10 ..."), and ends with an
`## SBIR Notebook` section — 3–5 crisp talking points connecting the
material to counter-UAS sensing proposals.

Each interlude is one sitting (~60 min read/think, no code to run). Every
physics claim held to the same accuracy bar as the lessons.

## After splitting

- README.md syllabus gains a session map (lesson → session count and names)
  and shows interlude placement in the reading order.
- Reading order becomes: 00 … 04, R1, 05 … 10, R2, 11, 12, R3, 13, 14, R4, 99.
- course/verify.sh must pass end-to-end; interludes are verified for
  markdown/link sanity only (no code extraction).
