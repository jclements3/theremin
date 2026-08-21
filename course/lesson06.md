# Lesson 06 — Sequencers and Control

*Where we are.* You can generate a tone (the NCO, lesson 04) and you've
turned one into a bitstream that drones A440 forever (lesson 05). A drone
is a data path with nobody in charge. This lesson builds the *control* — a
sequencer stepping the NCO's frequency control word through a C-major
scale, half a second per note, forever. The parts are humble — a timer, an
index, a table of constants — and so are the bugs: this is the lesson
where you stare the fencepost error in the eye.

One thing before we start: **you may have already met this module.** If you
came to this repo through the `fpga/phase1` roadmap, `scale_seq` is that
phase's exercise — same entity, same testbench, same requirements. Two ways
through, both legitimate:

- **Build path** (you haven't done the phase1 exercise, or stalled on it):
  read Concepts, then implement the architecture yourself against the
  requirements before looking at the Build section's finished version. The
  testbench is the grader; iterate until green.
- **Review path** (your phase1 `scale_seq` already passes): diff your
  implementation against the Build section's, and read Concepts anyway —
  this pass is about being able to *articulate* why the terminal count is
  `NOTE_CLKS - 1`, what the constrained subtype buys, and what each
  testbench check probes. The Explore exercises are new either way.

---

## Session 06.1 — Timers, Tables, and the Fencepost (~75 min)

### Objectives

- Build a dwell timer from a counter, a compare, and a reload, and state
  exactly why the terminal count is `NOTE_CLKS - 1`, not `NOTE_CLKS`.
- Explain what a `natural range 0 to N-1` signal synthesizes to and what
  free checking it buys in simulation.
- Fill a constant table with elaboration-time `math_real` calls and index
  it with a wrapping counter — and say when the free mod-2**N wrap is
  safe to rely on.
- For each requirement R1–R4, point to the testbench code that grades it
  and describe the failure it would print.
- Place sequencers in the theremin/radar picture: control plane vs data
  plane, and where this structure returns later in the course.

### Concepts

#### Control plane, data plane

The NCO is a data-path block: arithmetic every cycle, no idea what note
it's playing — you park a number on `fcw` and it integrates. Everything
that *decides* what number to park, and when, is the control plane. In the
finished theremin that's your hand (via `freq_meas` and `pitch_map`); in
this lesson it's a scheduler with a score: eight notes, in order, equal
time each, repeat.

Strip any scheduler to its skeleton and you find three parts:

```
   +-----------+       +-----------+       +----------------+
   |  timer    |------>|  index    |------>|  table         |
   | "has the  | tick  | "which    |  idx  |  idx -> value  |--> fcw
   |  dwell    |       |  step?"   |       |  (constants)   |
   |  elapsed?"|       +-----------+       +----------------+
   +-----------+
```

A timer measuring the dwell, an index naming the current step, a table
mapping step to output. `scale_seq` is the cleanest possible instance. So
is a UART transmitter (baud timer, bit index, the byte as the table —
lesson 11). So is a stepped-frequency radar's waveform scheduler (see Radar
Connection). Learn the skeleton once, recognize it everywhere.

#### A timer is a counter with an opinion

You built free-running counters in lesson 02. A timer is a counter plus a
decision: count clocks, compare against a terminal value, and on the clock
where the compare hits, reload to zero and emit a tick. The entire
subtlety is the terminal value.

Each note must be held exactly `NOTE_CLKS` clock cycles. A state the
counter *occupies* for one cycle is one cycle of dwell, so the timer must
occupy exactly `NOTE_CLKS` distinct states. Starting from 0, that's
`0, 1, …, NOTE_CLKS - 1` — the terminal count is **`NOTE_CLKS - 1`**,
because 0 is a state too. With the testbench's `NOTE_CLKS = 96`:

```
clock:   1    2    3   ...   95   96 | 97   98  ...
timer:   0    1    2   ...   94   95 |  0    1  ...
idx:     0    0    0   ...    0    0 |  1    1  ...
         <------- 96 clocks -------> | next note
```

The reload and the index advance happen on the *same* rising edge — the one
where `timer = NOTE_CLKS - 1` is true going in. Compare against `NOTE_CLKS`
instead (with an unconstrained counter) and you'd occupy 97 states, 0
through 96: every note 1/96th too long. Nothing crashes, nothing warns;
only a testbench that *counts* — or a listener with a metronome — notices.
This is the fencepost error, named for the fact that a 100-meter fence
with a post every 10 meters has 11 posts, not 10. You will make it for the
rest of your career; the discipline is making it in simulation, against a
testbench that counts.

#### The index counter and the free wrap

The index is a 3-bit `unsigned`. From lesson 03 you know exactly what
`idx + 1` does at 7: wraps to 0, mod 2**3, silently. Here the silence is
the feature — eight notes, eight states, so C5 rolls back to C4 with zero
comparison logic. The wrap is *free precisely because the table length
equals 2**bits.* That alignment is load-bearing: give the sequencer a
6-note table and `idx` happily counts to 6 and 7, indexing entries that
don't exist (in simulation, a bounds crash; see Tips). A sequence length
that isn't a power of two needs an explicit compare-and-clear, same shape
as the timer's. We got lucky on purpose.

#### The note table: elaboration-time math, again

Each note needs the `fcw` that makes a 32-bit NCO at `CLK_HZ` produce its
equal-temperament frequency — lesson 04's formula, `round(f · 2³² / f_clk)`.
Eight magic numbers you could paste in from a calculator. Don't. Lesson03
showed the better way: make the toolchain do the arithmetic at
elaboration time.

```vhdl
function note_fcw(f_hz : real) return unsigned is
begin
  return to_unsigned(integer(round(f_hz * 2.0 ** 32 / real(CLK_HZ))), 32);
end function;

constant SCALE : fcw_table_t :=
  (note_fcw(261.6256), note_fcw(293.6648), ... );
```

`note_fcw` calls `round` from `math_real` — not synthesizable as hardware,
completely legal in a function only called to initialize a `constant`.
GHDL and yosys evaluate it while *building* the design; only eight 32-bit
integers reach the netlist. The source documents the physics (the literals
are the equal-temperament frequencies of C4–C5, checkable against any
tuning reference), and the table retunes itself if `CLK_HZ` changes —
instantiate at 48 MHz and every note is still in tune. One care point:
`integer(round(…))` goes through VHDL's 32-bit simulation integer, so the
trick holds only while the fcw fits in 2**31 − 1 — ours top out below
2**18, comfortable. (Lesson07 scales this up: same pattern, but the
function loops `sin()` 256 times to fill a ROM.)

The lookup itself is one line — `fcw <= SCALE(to_integer(idx));` —
combinational, an 8-way multiplexer of constants that the synthesizer
boils down to a couple of LUTs per output bit (bits that are 0 in all
eight entries cost nothing). `fcw` changes the same cycle `idx` does; the
testbench's "sampled a few clocks in" slack exists so a registered-output
variant would also pass. Both are valid; ours takes the cheap one.

#### Reading the grader: what each R check probes

The testbench is reused **verbatim** from `fpga/phase1/tb/scale_seq_tb.vhd`
and it, not the lesson text, is the authoritative spec. For each tag, find
the teeth:

**R1 (right notes, right order).** `check_note` recovers the frequency your
DUT is actually commanding — `got_hz := fcw · CLK_HZ / 2³²` — and asserts
it within ±0.5 Hz of an *independent* frequency table declared in the
testbench. The TB never calls your `note_fcw`; if your table and its
physics disagree, someone is wrong and the report prints both numbers.
Order is checked by walking an unwrapped `expected` counter through 16
note transitions — two full traversals, so the 7→0 wrap is exercised
twice — comparing `idx` against `expected mod 8` at every step. Notice the
guard before the arithmetic — `assert fcw(31 downto 20) = 0` — that's
lesson 03's word-growth discipline applied to the *testbench*: `to_integer`
on a 32-bit unsigned with high bits set would overflow VHDL's integer and
kill the sim with a confusing error, so the TB checks its own precondition
and fails with a message naming the actual problem.

**R2 (exact dwell).** For each note the TB sits in a `while` loop counting
rising edges until `idx` moves, then asserts `cnt = NOTE_CLKS`, exactly.
Not "about 96" — a 95 or a 97 is a named failure with both numbers
printed. This is the check that catches the fencepost.

**R3 (reset).** Twice: after power-on (idx 0, fcw C4) and mid-sequence — a
reset pulsed with the scale somewhere in the middle must return it to note
0. The second matters because a designer can clear the timer but not the
index, or vice versa; only a mid-flight reset exposes it.

**R4 (enable freeze).** The TB drops `en` mid-note, snapshots `idx` and
`fcw`, and asserts for 50 clocks that neither moves. The subtle
requirement is the *timer*: it must freeze too. The TB can't see it
directly and doesn't need to — the pause happens inside R2's counted
window, so a timer that kept running would shorten the next observed
dwell and fail R2.

Two idioms worth stealing. Every wait is **bounded**: the "wait for the
first transition" loop gives up after `2 · NOTE_CLKS` clocks with a
message suggesting the likely cause ("architecture not implemented
yet?") — an unbounded `wait until idx /= 0` against a dead DUT hangs the
simulator forever; a bounded one turns "it hangs" into a diagnosis. And
the **severity ladder** is policy: value mismatches are `severity error`
— log and continue, so one run harvests *all* the wrong notes — while
hangs and broken preconditions are `severity failure`, which under the
Makefile's `--assert-level=failure` aborts the run, because nothing after
them means anything.

#### Constrained subtypes: exact hardware, free assertions

The timer is declared

```vhdl
signal timer : natural range 0 to NOTE_CLKS - 1 := 0;
```

Two payoffs. In synthesis, the range tells yosys the exact state space:
ceil(log2(NOTE_CLKS)) flip-flops — 23 bits at the hardware default of
6,000,000, 7 bits at the testbench's 96 — instead of the 32 a bare
`natural` implies (yosys would eventually prune the constant-zero high
bits, but say what you mean and the tools don't have to guess). In
simulation, the range is a free, always-on assertion: any assignment
outside 0…NOTE_CLKS-1 is an immediate bounds error naming the line.
Explore 2 weaponizes this — a broken compare that would silently stall
real hardware instead crashes the sim on the exact increment that went
out of range. VHDL's much-mocked strictness, doing free verification
again.

### Radar Connection

**Stepped-frequency ladders.** A stepped-frequency continuous-wave (SFCW)
radar builds a high-resolution range profile without a wideband receiver:
transmit a pure tone at f₀, dwell; step to f₀+Δf, dwell; … N steps up a
frequency ladder, then process the per-step phase samples (an IFFT across
steps) into a synthetic range profile. The waveform scheduler that runs
that ladder is — structurally, exactly — `scale_seq`: a table of DDS
control words (the ladder instead of a scale), a dwell timer, a wrapping
step index feeding an NCO (lesson 04 told you the NCO *is* a DDS). Rename
`note_idx` to `step_idx` and you could ship it.

The lesson's details all map:

- **The dwell is a system requirement.** SFCW dwell must cover the round
  trip to the farthest target plus synthesizer settling, and processing
  assumes every step dwelled equally. A fencepost in the dwell timer is a
  small, systematic timing skew that surfaces much later as degraded
  range sidelobes nobody traces back to an off-by-one for a week. R2's
  "exactly, not about" check is the radar discipline in miniature.
- **The table is calibration data.** Our frequencies come from
  equal-temperament physics evaluated at elaboration time; a radar's
  ladder comes from waveform design evaluated the same way. Either way
  the source encodes *where the numbers came from*, so changing one
  parameter regenerates a consistent table instead of hand-edited
  constants drifting apart.
- **`en` is the hold line.** Radars pause waveform schedulers constantly —
  transmitter protect windows, deconflicting with other emitters. R4's
  demand that the *timer* freezes, not just the outputs, is what makes a
  pause resumable instead of a resync.
- **The grader mirrors acceptance testing.** The TB recovers commanded
  frequency from the control word and checks it against an independent
  reference — the same shape as checking a waveform generator with a
  frequency counter that doesn't share the generator's math.

Lesson12 closes the loop — two NCOs and a mixer show why this theremin
*is* a CW radar. The sequencer you just built is the part such a radar
uses to choose its transmit frequency.

**Stopping point.** You should now be able to explain:

- why a timer that must hold each note for exactly `NOTE_CLKS` cycles
  reloads at `NOTE_CLKS - 1`, not `NOTE_CLKS` — zero is a state too, and
  a compare against `NOTE_CLKS` occupies one state too many.
- why the 3-bit index wraps 7→0 with zero comparison logic, and exactly
  when that free wrap stops being safe (a table whose length is not
  2**bits).
- how `note_fcw`'s `math_real` arithmetic runs at elaboration time and
  never reaches the netlist — and which limit (VHDL's 32-bit simulation
  integer) bounds the trick.
- for each of R1–R4, which testbench mechanism supplies the teeth: the
  independent frequency table, the counted `while` loop asserting
  `cnt = NOTE_CLKS` exactly, the mid-sequence reset, and the pause that
  falls inside R2's counted window.

---

## Session 06.2 — Build and First Green (~90 min)

### Build

Create `course/work/lesson06/` and enter the files below. Build path: type
in the entity and header comment, stop, implement the architecture from
the requirements, then come back and compare. Review path: diff against
your phase1 version — differences in the timer subtype, reset priority,
or terminal count are the interesting ones.

The module. Read the header first: it declares R1–R4, and the file's
whole job is to be the simplest thing that satisfies them.

**File: course/work/lesson06/scale_seq.vhd**

```vhdl
-- scale_seq.vhd — C-major scale sequencer feeding the NCO.
--
-- Requirements this module implements (verified in scale_seq_tb.vhd):
--   R1: fcw steps through the 8 notes of the C major scale, in order,
--       wrapping C4 D4 E4 F4 G4 A4 B4 C5 -> C4 ... Each note's fcw gives
--       an output frequency within +/-0.5 Hz of equal temperament:
--       261.6256, 293.6648, 329.6276, 349.2282, 391.9954, 440.0000,
--       493.8833, 523.2511 Hz. note_idx reports the current position (0-7).
--   R2: while en='1', note_idx advances exactly every NOTE_CLKS clocks.
--   R3: synchronous active-high reset returns the sequencer to note 0
--       (full duration restarts).
--   R4: en='0' pauses everything — note_idx, fcw, and the note timer hold.
--
-- fcw for a note = round(f_note * 2**32 / CLK_HZ), computed at elaboration
-- time with math_real: real math is evaluated before synthesis, so only the
-- eight resulting integer constants reach the netlist. All eight are
-- < 2**18, safely inside integer range.
--
-- Radar analog: a stepped-frequency waveform scheduler — the same
-- structure that steps a DDS through an SFCW radar's frequency ladder.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity scale_seq is
  generic (
    CLK_HZ    : positive := 12_000_000;
    NOTE_CLKS : positive := 6_000_000   -- 0.5 s per note on hardware
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                  -- synchronous, active-high
    en       : in  std_logic;
    fcw      : out unsigned(31 downto 0);      -- to the NCO's fcw port
    note_idx : out unsigned(2 downto 0)        -- current scale position
  );
end entity scale_seq;

architecture rtl of scale_seq is
  type fcw_table_t is array (0 to 7) of unsigned(31 downto 0);

  -- Elaboration-time note -> frequency control word conversion.
  function note_fcw(f_hz : real) return unsigned is
  begin
    return to_unsigned(integer(round(f_hz * 2.0 ** 32 / real(CLK_HZ))), 32);
  end function;

  constant SCALE : fcw_table_t :=
    (note_fcw(261.6256),   -- C4
     note_fcw(293.6648),   -- D4
     note_fcw(329.6276),   -- E4
     note_fcw(349.2282),   -- F4
     note_fcw(391.9954),   -- G4
     note_fcw(440.0000),   -- A4
     note_fcw(493.8833),   -- B4
     note_fcw(523.2511));  -- C5

  signal timer : natural range 0 to NOTE_CLKS - 1 := 0;
  signal idx   : unsigned(2 downto 0)             := (others => '0');
begin

  sequencer : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        timer <= 0;
        idx   <= (others => '0');
      elsif en = '1' then
        if timer = NOTE_CLKS - 1 then
          timer <= 0;
          idx   <= idx + 1;  -- 3 bits: wraps 7 -> 0, C5 back to C4
        else
          timer <= timer + 1;
        end if;
      end if;
    end if;
  end process;

  fcw      <= SCALE(to_integer(idx));
  note_idx <= idx;

end architecture rtl;
```

Structure notes, in the order they bite people. The process checks `rst`
*before* `en` — reset must win even while paused. Everything under
`en = '1'` is the clock-enable idiom from `nco.vhd`: nothing inside
advances when `en='0'`, which is all of R4 — timer, index, and (since
`fcw` is a pure function of `idx`) both outputs, frozen by one `elsif`.
And the terminal-count line is the fencepost from Concepts, in the flesh.

The testbench — **complete, reused verbatim from
`fpga/phase1/tb/scale_seq_tb.vhd`; do not modify it**. On the build path
your job is to make the RTL pass it as-is. You walked through its checks
in Concepts; while typing it in, match each block to its R tag.

**File: course/work/lesson06/scale_seq_tb.vhd**

```vhdl
-- scale_seq_tb.vhd — self-checking testbench for the scale_seq exercise.
-- Complete: do not modify while doing the exercise; make your RTL pass it.
--
-- Grades requirements R1-R4 from rtl/scale_seq.vhd. Uses a short
-- NOTE_CLKS (96) so two full scale traversals simulate in milliseconds.
-- Expected fcw values are computed here independently with math_real —
-- if your table disagrees with the TB by more than +/-0.5 Hz, R1 fails.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity scale_seq_tb is
end entity scale_seq_tb;

architecture sim of scale_seq_tb is
  constant CLK_HZ    : positive := 12_000_000;
  constant NOTE_CLKS : positive := 96;
  constant CLK_PER   : time     := 83.333 ns;

  type freq_table_t is array (0 to 7) of real;
  constant SCALE_HZ : freq_table_t :=
    (261.6256, 293.6648, 329.6276, 349.2282,
     391.9954, 440.0000, 493.8833, 523.2511);
  constant TOL_HZ : real := 0.5;

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal en   : std_logic := '0';
  signal fcw  : unsigned(31 downto 0);
  signal idx  : unsigned(2 downto 0);
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.scale_seq
    generic map (CLK_HZ => CLK_HZ, NOTE_CLKS => NOTE_CLKS)
    port map (clk => clk, rst => rst, en => en, fcw => fcw, note_idx => idx);

  main : process
    -- R1 frequency identity: is fcw within TOL_HZ of note n?
    procedure check_note(n : natural; tag : string) is
      variable got_hz : real;
    begin
      assert fcw(31 downto 20) = 0
        report tag & " R1 FAIL: fcw wildly out of range (top bits set)"
        severity failure;
      got_hz := real(to_integer(fcw)) * real(CLK_HZ) / 2.0 ** 32;
      assert abs(got_hz - SCALE_HZ(n)) <= TOL_HZ
        report tag & " R1 FAIL: note " & integer'image(n) &
               " got " & real'image(got_hz) & " Hz, expected " &
               real'image(SCALE_HZ(n)) & " Hz"
        severity error;
    end procedure;

    variable expected : natural;  -- unwrapped note counter
    variable cnt      : natural;
    variable idx_hold : natural;
    variable fcw_hold : unsigned(31 downto 0);
  begin
    -- Reset, then enable.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    en  <= '1';

    -- R3 (initial): starts at note 0 playing C4. Sampled a few clocks in
    -- to allow registered-output pipelines.
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    assert to_integer(idx) = 0
      report "R3 FAIL: note_idx /= 0 after reset" severity error;
    check_note(0, "post-reset");

    -- Wait for the first transition away from note 0 (bounded).
    cnt := 0;
    while to_integer(idx) = 0 loop
      wait until rising_edge(clk);
      cnt := cnt + 1;
      assert cnt <= 2 * NOTE_CLKS
        report "R1/R2 FAIL: sequencer never leaves note 0 " &
               "(architecture not implemented yet?)"
        severity failure;
    end loop;

    -- R1 order + R2 duration over two full traversals (16 transitions).
    expected := 1;
    for note in 1 to 16 loop
      assert to_integer(idx) = expected mod 8
        report "R1 FAIL: expected note " & integer'image(expected mod 8) &
               ", got " & integer'image(to_integer(idx))
        severity error;
      cnt := 0;
      while to_integer(idx) = expected mod 8 loop
        wait until rising_edge(clk);
        cnt := cnt + 1;
        if cnt = 3 then
          check_note(expected mod 8, "mid-note");
        end if;
        assert cnt <= NOTE_CLKS + 2
          report "R2 FAIL: note " & integer'image(expected mod 8) &
                 " held longer than NOTE_CLKS"
          severity failure;
      end loop;
      assert cnt = NOTE_CLKS
        report "R2 FAIL: note " & integer'image(expected mod 8) &
               " held " & integer'image(cnt) & " clocks, expected " &
               integer'image(NOTE_CLKS)
        severity error;
      expected := expected + 1;
    end loop;
    report "R1 pass: correct notes in correct order, two full scales";
    report "R2 pass: every note held exactly " &
           integer'image(NOTE_CLKS) & " clocks";

    -- R4: pause mid-note; idx and fcw must freeze.
    for i in 1 to NOTE_CLKS / 4 loop wait until rising_edge(clk); end loop;
    en       <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    idx_hold := to_integer(idx);
    fcw_hold := fcw;
    for i in 1 to 50 loop
      wait until rising_edge(clk);
      assert to_integer(idx) = idx_hold and fcw = fcw_hold
        report "R4 FAIL: outputs changed while en='0'"
        severity error;
    end loop;
    en <= '1';
    report "R4 pass: en='0' freezes the sequencer";

    -- R3 (mid-sequence): reset must return to note 0 / C4.
    for i in 1 to 10 loop wait until rising_edge(clk); end loop;
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    assert to_integer(idx) = 0
      report "R3 FAIL: mid-sequence reset did not return to note 0"
      severity error;
    check_note(0, "post-mid-sequence-reset");
    report "R3 pass: reset returns to note 0 (C4)";

    report "scale_seq testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

The Makefile is lesson 03's plus two additions: the run line records a
waveform (`--wave=build/scale_seq_tb.ghw`, GHDL's native GHW format), and
a `wave` target that opens it. The leading `-` on the recursive
`make sim` tells make to continue even if the sim exits nonzero — a
failing assert is precisely when you want the waveform to open, not be
skipped.

**File: course/work/lesson06/Makefile**

```makefile
# Lesson 06 — scale_seq exercise, graded by scale_seq_tb. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# fpga/phase1/Makefile in miniature — same flags, same shim, sim only.

TB         = scale_seq_tb
SRC        = scale_seq.vhd scale_seq_tb.vhd
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure

# Opens the waveform even when the sim fails an assert — that's when you
# most need it. The '-' keeps make going past sim's nonzero exit.
wave:
	-$(MAKE) sim
	gtkwave build/$(TB).ghw &

build:
	mkdir -p build

clean:
	rm -rf build
```

### Run

From `course/work/lesson06/` (with the `fpga` alias already sourced in your
shell):

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build scale_seq.vhd scale_seq_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/scale_seq_tb scale_seq_tb
./build/scale_seq_tb --wave=build/scale_seq_tb.ghw --assert-level=failure
scale_seq_tb.vhd:114:5:@136207788500fs:(report note): R1 pass: correct notes in correct order, two full scales
scale_seq_tb.vhd:115:5:@136207788500fs:(report note): R2 pass: every note held exactly 96 clocks
scale_seq_tb.vhd:132:5:@142541096500fs:(report note): R4 pass: en='0' freezes the sequencer
scale_seq_tb.vhd:145:5:@143791091500fs:(report note): R3 pass: reset returns to note 0 (C4)
scale_seq_tb.vhd:147:5:@143791091500fs:(report note): scale_seq testbench complete (any FAILs are listed above)
```

(The `mkdir -p build` line appears only on the first run; your home
directory will appear in the shim path instead of `/home/clementsj`.)

Sanity-check the timestamps like an engineer: R1/R2 report at ~136 µs.
Two traversals ≈ 16 transitions × 96 clocks ≈ 1536 clocks at 83.333 ns ≈
128 µs, plus the reset preamble and the first full note — it adds up.
Also notice `CLK_PER = 83.333 ns` is *not* exactly 1/12 MHz. The TB
doesn't care: every check counts edges, none measures wall-clock time —
itself a testbench lesson (grade in cycles, and rounding in the clock
constant can't create phantom failures).

Then look at the sequencer as a picture: `make wave`, and in GTKWave add
`fcw`, `idx`, `en`, `rst`. `fcw` is a staircase of eight levels marching
upward, snapping back down at each 7→0 wrap; the flat shelf where `en`
drops is R4, and the cliff back to the bottom step at the second `rst`
pulse is R3.

**Stopping point.** You should now be able to explain:

- why the process checks `rst` before `en` — reset must win even while
  paused — and why everything under one `elsif en = '1'` is all of R4:
  timer, index, and (since `fcw` is a pure function of `idx`) both
  outputs frozen at once.
- why the Makefile's `wave` target puts a `-` in front of its recursive
  `make sim` — a failing assert is exactly when you want the waveform to
  open, not be skipped.
- why the R1/R2 reports landing at ~136 µs is the right order of
  magnitude, and why the rounded `CLK_PER = 83.333 ns` can't create a
  phantom failure — every check counts edges, none measures wall-clock
  time.

---

## Session 06.3 — Break It on Purpose (~60 min)

### Explore

Do these before peeking at `course/solutions/lesson06/` — especially on
the review path.

1. **Break it on purpose — plant the classic fencepost.** Change the
   terminal-count compare to `timer = NOTE_CLKS - 2` and predict, before
   running: how many clocks is each note held, and which assert catches
   it? `make sim` shows sixteen
   `R2 FAIL: note N held 95 clocks, expected 96` lines — `severity error`,
   so the run continues and proves the failure systematic. Now read the
   *end* of the log: the `R1 pass`/`R2 pass` lines still print, because
   `report` statements are unconditional narration, not verdicts — the
   final line even warns you ("any FAILs are listed above"). A run's
   verdict is *zero FAIL lines*, never the presence of the happy-path
   summary. Grep, don't skim. Restore and re-run to green.

2. **Break it the other way — meet the subtype cop.** Now try
   `timer = NOTE_CLKS`. Predict first: the subtype is
   `natural range 0 to NOTE_CLKS - 1`, so the compare can never be true —
   what happens at the 96th clock? Run it: GHDL halts with a bound check
   failure at the `timer <= timer + 1` line, the moment the increment
   tries to write 96. On silicon with an unconstrained counter this bug
   is far worse: the compare never fires and the sequencer plays C4
   forever — which the TB's bounded "never leaves note 0" failure exists
   to catch. Widen the subtype to `natural range 0 to NOTE_CLKS`, keep
   the bad compare, run again: 97-clock notes. Work out why 0..96 is 97
   states, then restore the file. Two adjacent wrong terminal counts,
   three distinct failure modes — that's why timers get counted checks.

3. **Play something else.** Retune the table to the A-minor scale from A4:
   440.0000, 493.8833, 523.2511, 587.3295, 659.2551, 698.4565, 783.9909,
   880.0000 Hz. `make sim` now fails R1 — read one `mid-note` failure line
   closely: it prints the frequency your fcw *actually* encodes next to
   the one the spec demands, because the TB derives Hz from the control
   word independently. The grader caught a DUT that is internally
   consistent and simply playing the wrong song. Tempted to "fix" it by
   editing `SCALE_HZ` in the TB? That's a requirements change, not a
   verification pass — the TB is the spec, and when design and spec
   disagree on purpose, both files move together. Restore C major.

4. **Feel why generics exist.** The hardware dwell is
   `NOTE_CLKS = 6_000_000`; the TB overrides it to 96. Estimate the cost
   of a full-rate run: two traversals ≈ 16 × 6 M = 96 M clocks ≈ 8
   simulated seconds — roughly a million times the 136 µs run you just
   did, to verify logic that 96-clock notes prove identically, because
   nothing in the sequencer's *logic* depends on the dwell's magnitude.
   That's the pattern for every timer in this course (UART baud dividers,
   `freq_meas` gates): make time constants generic, verify scaled, ship
   full-rate.

### Tips & Pitfalls

- **Reset priority is a requirement, not a style choice.** `rst` is tested
  before `en`, so reset works while paused. Swap the nesting
  (`if en = '1' then if rst = '1' ...`) and everything passes *except* a
  reset delivered during `en='0'` — which no check in this TB happens to
  throw at you. Two lessons in one: follow the house pattern (rst-then-en,
  as in `nco.vhd`), and remember a green TB proves the checks it contains,
  nothing more. Verification is evidence, not proof.
- **`to_integer(idx)` is safe only by construction.** A 3-bit `idx` is
  always 0–7 and the table has exactly indices 0–7. Shrink the table
  without constraining the counter and GHDL rewards you with an index
  bound check failure two notes past the end. Table length, index width,
  and wrap behavior are one design decision wearing three declarations —
  change one, revisit all three.
- **Elaboration-time math still uses 32-bit integers.** `note_fcw`
  funnels through `integer(round(...))`; our largest fcw is ~187,000,
  fine. Reuse the trick for a 6 MHz ladder step and the intermediate
  exceeds 2**31 − 1: elaboration dies with an overflow, GHDL naming the
  line. Same word-growth rule as lesson 03's testbench tip — elaboration
  integers don't grow just because your hardware words did.
- **Emacs/vhdl-mode: let the mode manage sensitivity lists.**
  `M-x vhdl-update-sensitivity-list-buffer` rescans each process and
  rewrites its sensitivity list from the signals actually read. Our
  clocked process needs only `(clk)` — the mode knows the `rising_edge`
  idiom — but when later lessons bring combinational processes with real
  sensitivity lists, a stale hand-maintained list is a classic
  sim-vs-synthesis mismatch, and this command retires it.
- **Toolchain gotcha: GHW beats VCD here.** GHDL's native `--wave=*.ghw`
  records every signal with full type information — GTKWave shows `idx`
  as 0–7 and `fcw` as an integer, no radix fiddling. VCD flattens types
  to bit vectors; use GHW unless another tool forces VCD on you.

### Checkpoint

Before lesson 07, you must have:

- `make sim` in `course/work/lesson06/` printing the four `R* pass` lines
  and `scale_seq testbench complete`, with zero `FAIL` lines.
- Explore 1 and 2 done: you have seen the terminal count wrong in both
  directions, and can state from memory why the compare is against
  `NOTE_CLKS - 1` and what a compare against `NOTE_CLKS` does (crash with
  the constrained subtype; 97-clock notes without it).
- The habit installed: a testbench's verdict is the absence of FAIL
  lines, not the presence of a final summary report.
- For each of R1–R4, you can point to the testbench code that grades it —
  and name the one behavior this TB does *not* check (reset while
  `en='0'`).
- A one-sentence answer to: in the finished theremin, what replaces this
  lesson's timer-and-table as the thing that decides `fcw`?
