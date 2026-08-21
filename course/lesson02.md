# Lesson 02 — Testbenches That Check Themselves

*Where we are.* In lesson 01 you wrote your first real hardware — a registered
mux — and ran it against a testbench that was handed to you. This lesson
makes you the author of that machinery. You'll build an 8-bit counter (the
counting idiom behind the NCO's phase accumulator, the frequency meter, and
the UART's baud divider) and, more importantly, a testbench that *states its
requirements, checks them itself, and prints evidence*. You'll also meet
GTKWave, the oscilloscope of this course.

## Objectives

- Write a complete testbench from scratch: clock generator, stimulus process,
  clean shutdown — no template pasting.
- Use the `assert` / `report` / `severity` ladder deliberately, and predict
  what GHDL does at each severity level.
- Tag every check with a requirement ID (`R1`, `R2`, …) that traces to the
  DUT's header comment — DO-254 traceability in miniature.
- Dump a `.ghw` waveform, open it in GTKWave, add signals, switch a bus to
  decimal, zoom, place markers, and reload after a re-run.
- Diagnose a deliberately seeded bug twice: once from the console FAIL lines,
  once from the waveform.

---

## Session 02.1 — Anatomy of a Self-Checking Testbench (~60 min)

### Concepts

#### A testbench is a lab bench

A testbench is a VHDL entity with **no ports**. Nothing outside the simulator
ever connects to it — it is the closed room in which the device under test
(DUT) lives. Inside it you build three things you'd recognize from any
electronics bench:

```
  +-------------------------------------------------------+
  |  testbench (count8_tb)                                |
  |                                                       |
  |  clock process        DUT              stimulus/check |
  |  (signal gen) ---> [ count8 ] <--- (waveform gen +    |
  |       clk           rst,en |         scope + notebook)|
  |                            +----> count ----> asserts |
  +-------------------------------------------------------+
```

The clock generator is the signal generator, the stimulus process is your
hands on the switches, and the asserts are the lab notebook — except this
notebook slaps you when a reading is wrong.

#### Generating a clock (and stopping it)

One line makes a clock:

```vhdl
clk <= not clk after CLK_PER / 2 when not done else '0';
```

This is a *concurrent conditional signal assignment* — it lives in the
architecture body, outside any process, and re-evaluates whenever `clk` or
`done` changes. As long as `done` is false, every transition schedules the
next one half a period later: a self-perpetuating square wave.

The `when not done else '0'` clause matters more than it looks. A VHDL
simulation doesn't end when your stimulus process finishes — it ends when
**no future events are scheduled**. A bare `clk <= not clk after ...` keeps
scheduling events forever, and the simulation never terminates. So the
stimulus process sets `done <= true` as its final act; the clock line then
stops re-arming, the event queue drains, and GHDL exits on its own. This is
the house pattern for every testbench in the course (compare
`fpga/phase1/tb/nco_tb.vhd` — same line, verbatim).

`CLK_PER` is 83.333 ns — 12 MHz, the iCEstick's oscillator. We simulate at
the target clock rate from day one so timestamps in lesson 02 mean the same
thing they'll mean in lesson 14.

#### Sampling after the edge: the `wait for 1 ns` idiom

Recall from lesson 01 that a signal assignment inside a clocked process takes
effect one delta cycle *after* the edge. So if your testbench does

```vhdl
wait until rising_edge(clk);
assert count = i ...   -- WRONG: reads the value from BEFORE the edge
```

the assert executes in the same simulation instant as the edge, one delta
before the DUT's new value lands — you check stale data. The cure, used
throughout the course:

```vhdl
wait until rising_edge(clk);
wait for 1 ns;          -- let post-edge deltas settle, then look
assert count = i ...
```

One nanosecond is far past any delta-cycle activity and far short of the
next edge (41.7 ns away): you sample the settled post-edge world.

#### The assert / report / severity ladder

The full form of the checking statement:

```vhdl
assert <condition that must be TRUE>
  report <string printed if it is FALSE>
  severity <note | warning | error | failure>;
```

Read `assert` as a claim: *"I assert that count equals i."* If the claim
holds, nothing prints; if not, the report string prints, tagged with the
severity. A bare `report "...";` with no `assert` prints unconditionally —
that's how the `pass` lines work.

The four severities form a ladder of intent:

| severity  | meaning                                     | typical use                          |
|-----------|---------------------------------------------|--------------------------------------|
| `note`    | information; not a problem                  | progress markers, measured values    |
| `warning` | suspicious but the test can continue        | tolerances nearly exceeded           |
| `error`   | a requirement was violated; keep testing    | almost every functional check        |
| `failure` | the run is meaningless past this point      | protocol wedged, config nonsensical  |

Where the simulator *stops* is a separate knob: our Makefiles run the sim
with `--assert-level=failure`, meaning only `failure` halts the run —
`error`-severity violations print and the test keeps going, so one run gives
you the complete damage report instead of dying at the first scratch. When
you *want* stop-on-first-error (bisecting a mess), run with
`--assert-level=error` instead. You'll try both in Explore.

Building useful messages needs two conversions you'll type hundreds of times:

```vhdl
integer'image(i)                    -- integer -> string
integer'image(to_integer(count))    -- unsigned -> integer -> string
```

`'image` is an attribute every scalar type carries; `to_integer` is
numeric_std. Put the *expected* and the *observed* value in every FAIL
message — a report that says "R1 FAIL" without numbers is a mystery novel
with the last page torn out.

#### Requirement tags: DO-254 with the paperwork shrunk to comments

Certification-grade hardware (DO-254 is the airborne-electronics standard)
lives and dies by **traceability**: every requirement maps to design elements
that implement it and verification cases that prove it, and an auditor can
walk the chain in either direction. We keep the skeleton of that discipline
at a cost of roughly zero:

1. The DUT's header comment **numbers its requirements** (R1..Rn) in plain
   language.
2. Code lines that implement a requirement carry the tag in a comment
   (`cnt <= cnt + 1;  -- R1`).
3. Every testbench assert names the requirement it verifies, in both the
   FAIL string and the pass report.

Now `grep R3 *.vhd` shows you the requirement, the implementing line, and
the check, and the sim log *is* the test evidence: a `R3 pass:` line proves
the R3 check actually executed and held. That last point is subtle — a
silent testbench might mean "all good" or might mean "my checks never ran."
Printing positive evidence closes that hole. (It has one trap, which the
break-it exercise in Explore will spring on you.)

#### GTKWave: when the console isn't enough

Asserts tell you *that* something is wrong; waveforms show you *what
happened around it*. GHDL dumps its native GHW format:

```
./build/count8_tb --assert-level=failure --wave=build/count8.ghw
```

GHW (unlike the older VCD format) preserves VHDL types — an `unsigned(7
downto 0)` arrives as a bus GTKWave can render in decimal, not eight
anonymous wires. The tour, which you'll do for real in the Run section:

- **Launch**: `gtkwave build/count8.ghw &`. The left panel is the SST
  (Signal Search Tree) — the design hierarchy. Expand `top`, click
  `count8_tb`; its signals (`clk`, `rst`, `en`, `count`, `done`) appear in
  the pane below, and the `dut` instance is there too if you want to probe
  inside the counter.
- **Add signals**: select `clk`, `rst`, `en`, `count` and press `Append`
  (or drag them into the black wave area).
- **Read the bus**: `count` shows as hex by default. Right-click it →
  `Data Format` → `Decimal`. Click the `+` beside it to unfold individual
  bits — do it once to see that "a bus" is just wires with a label.
- **Zoom**: the toolbar magnifiers zoom in/out; the bracketed magnifier is
  **Zoom Fit** (whole run in one screen — do this first, always). Ctrl +
  scroll wheel zooms around the pointer in most builds.
- **Markers**: left-click in the wave area drops the primary marker; the
  header shows its exact time. The `Markers` menu adds named markers and a
  baseline for delta readouts — poke at it during the Explore exercise.
- **Reload**: GTKWave does *not* watch the file. After you re-run the sim
  (which rewrites the `.ghw`), use `File` → `Reload Waveform` to pick up
  the new run; your signal list and zoom survive.

Optional aside: the OSS CAD Suite also ships **surfer**, a newer viewer
(`surfer build/count8.ghw`) — same ideas, different ergonomics; the course
standardizes on GTKWave, but nothing stops you.

#### The DUT: an 8-bit counter with enable

The counter itself is four requirements and one process — read the header
of `count8.vhd` in Build first, then the process. Two design points:

- **Wrapping is specified, not accidental.** `cnt + 1` on an
  `unsigned(7 downto 0)` is mod-256 by the definition of numeric_std
  arithmetic. Here that's requirement R2, on purpose — the NCO in lesson 04
  is *built* on exactly this wrap. Lesson03 covers the cases where wrap is
  the bug and saturation is the spec.
- **`en` is a clock enable, not a gated clock.** The clock reaches the
  flip-flops on every edge; `en` merely decides whether the D input is
  `cnt + 1` or `cnt`. Gating the clock itself (`if rising_edge(clk and en)`
  -style crimes) creates glitch and skew hazards and will eventually earn
  you a lecture from nextpnr. The `rst > en` priority inside one clocked
  process is the house pattern for every sequential block to come.

### Radar Connection

DO-254 exists because avionics — radar signal processors very much included
— must arrive with *evidence*, not vibes. When a radar board is certified,
nobody asks "did it seem to work?"; they ask for the requirements document,
the verification matrix mapping each requirement to a test, and the test
results proving each check ran and passed. The artifact that convinces the
certification authority is a *traceable log*, which is exactly what your
testbench just learned to produce: `R1 pass: ...` lines are a verification
matrix row and its result, fused.

The deeper habit this builds: **self-checking beats eyeballing, at scale.**
A radar signal chain has dozens of blocks and thousands of regression runs;
no human re-inspects waveforms after every change. Waveforms are for
*diagnosis* — asserts are for *verdicts*. Write the requirement once, encode
the check once, and every `make sim` re-testifies. When lesson 10's frequency
meter feeds lesson 13's pitch mapper and something warbles, you'll re-run
every TB in the chain in seconds and know exactly which requirement broke —
the same triage a radar integration lab does when the range display lies.

**Stopping point.** You should now be able to explain:

- why a bare `clk <= not clk after ...` keeps a simulation running forever,
  and how setting `done` lets the event queue drain so GHDL exits on its own.
- why an assert placed immediately after `wait until rising_edge(clk)` reads
  the pre-edge value, and what `wait for 1 ns` buys you.
- which severities halt the run under `--assert-level=failure`, and why a
  printed `R3 pass:` line is evidence the check *executed*, not merely that
  nothing failed.
- why `en` selects the flip-flop's D input instead of gating the clock, and
  why the 255 → 0 wrap is a requirement here rather than a bug.

---

## Session 02.2 — Build & Run (~75 min)

### Build

Create `course/work/lesson02/` and the three files below. Type them — the
finger-memory for the assert idiom is the point of the lesson. (Solutions
exist in `course/solutions/lesson02/`; earn them first.)

The counter. Note the header: requirements first, code second.

**File: course/work/lesson02/count8.vhd**

```vhdl
-- count8.vhd — 8-bit wrapping up-counter with clock enable.
--
-- Requirements this module implements (verified in count8_tb.vhd):
--   R1: with en = '1', count increments by exactly 1 each rising clock edge.
--   R2: the counter wraps: 255 -> 0 (natural mod-2**8 unsigned arithmetic).
--   R3: en = '0' holds the count (clock enable, never a gated clock).
--   R4: synchronous active-high reset clears the count to zero, and wins
--       over en when both are asserted.
--
-- Teaching point: "cnt + 1" on an unsigned wraps silently — here that is
-- the feature, not a bug. The priority order rst > en inside one clocked
-- process is the house pattern for every sequential block in this course.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity count8 is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- synchronous, active-high
    en    : in  std_logic;  -- clock enable
    count : out unsigned(7 downto 0)
  );
end entity count8;

architecture rtl of count8 is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin

  advance : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');  -- R4
      elsif en = '1' then
        cnt <= cnt + 1;          -- R1; wraps 255 -> 0 (R2)
      end if;                    -- else: hold (R3)
    end if;
  end process;

  count <= cnt;

end architecture rtl;
```

The testbench. Walk through it against the Concepts section: the clock line
with its `done` guard; the reset-first stimulus; the `wait for 1 ns`
sampling after every checked edge; a tagged assert plus a tagged pass report
per requirement. Two details worth noticing: R2 is reached by *counting all
the way there* (10 held + 245 more = 255), so the entire sequence is
exercised rather than just the corner; and `hold` is a process **variable**
(immediate assignment with `:=`, private to the process) — the right tool
for "grab this value now and compare later," where a signal's
one-delta-later update would be a nuisance.

**File: course/work/lesson02/count8_tb.vhd**

```vhdl
-- count8_tb.vhd — self-checking testbench for count8.
--
-- Verifies (tags match the header of count8.vhd):
--   R1: count follows 1, 2, ..., 10 — one increment per enabled clock.
--   R2: the 255 -> 0 wrap (reached by actually counting there, so the
--       whole sequence is exercised, not just the corner).
--   R3: en = '0' freezes the count.
--   R4: synchronous reset clears the count, including mid-count with
--       en still asserted (reset priority).
--
-- Sampling note: checks wait 1 ns after the clock edge so the DUT's
-- post-edge value has settled (same pattern as fpga/phase1/tb/nco_tb.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity count8_tb is
end entity count8_tb;

architecture sim of count8_tb is
  constant CLK_PER : time := 83.333 ns;  -- 12 MHz, as on the target board

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal count : unsigned(7 downto 0);
  signal done  : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.count8
    port map (
      clk   => clk,
      rst   => rst,
      en    => en,
      count => count
    );

  main : process
    variable hold : unsigned(7 downto 0);
  begin
    -- R4: synchronous reset clears the count.
    rst <= '1'; en <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R4 FAIL: count not cleared by synchronous reset"
      severity error;
    report "R4 pass: synchronous reset clears count to 0";
    rst <= '0';

    -- R1: exactly one increment per enabled clock.
    en <= '1';
    for i in 1 to 10 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      assert count = i
        report "R1 FAIL: after " & integer'image(i) &
               " enabled clocks, count=" & integer'image(to_integer(count))
        severity error;
    end loop;
    report "R1 pass: count follows 1,2,...,10 - one increment per enabled clock";

    -- R3: en='0' freezes the count.
    en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    hold := count;
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert count = hold
      report "R3 FAIL: count advanced while en='0'"
      severity error;
    report "R3 pass: en='0' holds count at " & integer'image(to_integer(hold));

    -- R2: count the rest of the way to 255, then one more clock wraps to 0.
    en <= '1';
    for i in 1 to 245 loop  -- 10 held + 245 more = 255
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert count = 255
      report "R2 setup FAIL: expected count=255, got " &
             integer'image(to_integer(count))
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R2 FAIL: 255 + 1 should wrap to 0, got " &
             integer'image(to_integer(count))
      severity error;
    report "R2 pass: 255 -> 0 wrap (mod-256 arithmetic)";

    -- R4 again: reset must win over enable mid-count.
    for i in 1 to 3 loop  -- count = 3
      wait until rising_edge(clk);
    end loop;
    rst <= '1';  -- en is still '1' — reset has priority
    wait until rising_edge(clk);
    wait for 1 ns;
    assert count = 0
      report "R4 FAIL: reset did not override enable"
      severity error;
    report "R4 pass: reset overrides enable mid-count";
    rst <= '0';

    report "count8 testbench complete: R1-R4 checked (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

The Makefile — the tutorial Makefile with two files instead of one. Note
`--assert-level=failure` on the run line: that's the "print every error,
stop only for catastrophe" policy from Concepts.

**File: course/work/lesson02/Makefile**

```make
# Lesson 02 — GHDL sim flow. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors tutorial/Makefile — same
# flags, same shim, no synthesis targets.

TB         = count8_tb
SRC        = count8.vhd count8_tb.vhd
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
```

### Run

Activate the toolchain and run the sim (cwd = `course/work/lesson02/`):

```bash
fpga
make sim
```

Expected output:

```text
ghdl -a --std=08 --workdir=build count8.vhd count8_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/count8_tb count8_tb
./build/count8_tb --assert-level=failure
count8_tb.vhd:52:5:@125999500fs:(report note): R4 pass: synchronous reset clears count to 0
count8_tb.vhd:65:5:@959329500fs:(report note): R1 pass: count follows 1,2,...,10 - one increment per enabled clock
count8_tb.vhd:79:5:@1459327500fs:(report note): R3 pass: en='0' holds count at 10
count8_tb.vhd:97:5:@21959245500fs:(report note): R2 pass: 255 -> 0 wrap (mod-256 arithmetic)
count8_tb.vhd:109:5:@22292577500fs:(report note): R4 pass: reset overrides enable mid-count
count8_tb.vhd:112:5:@22292577500fs:(report note): count8 testbench complete: R1-R4 checked (any FAILs are listed above)
```

Read one line fully, once: `count8_tb.vhd:52:5` is the file, line, and
column of the `report` statement that printed; `@125999500fs` is simulation
time (GHDL keeps femtosecond resolution — 83.333 ns doesn't divide evenly,
hence the unlovely digits); `(report note)` is the severity. Your timestamps
should match these *exactly* — the sim is deterministic.

Now re-run the built testbench by hand with a waveform dump (make already
built the binary; no need to recompile):

```bash
./build/count8_tb --assert-level=failure --wave=build/count8.ghw
```

Expected output:

```text
count8_tb.vhd:52:5:@125999500fs:(report note): R4 pass: synchronous reset clears count to 0
count8_tb.vhd:65:5:@959329500fs:(report note): R1 pass: count follows 1,2,...,10 - one increment per enabled clock
count8_tb.vhd:79:5:@1459327500fs:(report note): R3 pass: en='0' holds count at 10
count8_tb.vhd:97:5:@21959245500fs:(report note): R2 pass: 255 -> 0 wrap (mod-256 arithmetic)
count8_tb.vhd:109:5:@22292577500fs:(report note): R4 pass: reset overrides enable mid-count
count8_tb.vhd:112:5:@22292577500fs:(report note): count8 testbench complete: R1-R4 checked (any FAILs are listed above)
```

Open it:

```bash
gtkwave build/count8.ghw &
```

Expected output:

```text
(no terminal output — the GTKWave window opens)
```

Do the tour from Concepts now, in order: expand the SST to `count8_tb`,
append `clk`, `rst`, `en`, `count`; Zoom Fit; set `count` to Decimal. The
whole story fits one screen: the reset window, a short staircase to 10, a
flat shelf while `en` is low, one long ramp to 255 crashing to 0, the final
mid-count reset. Zoom into the first staircase until clock edges are visible
and watch `count` step *only* on rising edges with `en` high. That picture
is R1, R3, and R4 — the asserts just say it in text.

**Stopping point.** You should now be able to explain:

- why your log's timestamps match the expected output digit-for-digit — the
  sim is deterministic, and the femtosecond digits come from 83.333 ns not
  dividing evenly.
- what each field of a line like `count8_tb.vhd:52:5:@125999500fs:(report
  note)` tells you, and how that prefix lets Emacs jump to the source line.
- why GHW lets GTKWave render `count` as a decimal bus while a re-run's new
  dump only appears after `File → Reload Waveform`.
- how the wave picture — reset window, staircase, shelf, ramp-and-wrap,
  mid-count reset — is the same evidence the R1–R4 asserts state in text.

---

## Session 02.3 — Explore & Checkpoint (~75 min)

### Explore

Solutions are in `course/solutions/lesson02/` — attempt these first.

1. **Waveform reading (do not skip).** In GTKWave, answer with markers, then
   verify each answer against the console log's timestamps:
   (a) Find the R3 shelf where `count` holds at 10. Place the primary marker
   on the falling edge of `en` and read the time; place it on the rising edge
   where `en` returns and read again. How many clock periods is the gap, and
   why is it six when the TB's hold loop runs five iterations? (Count the
   `wait until rising_edge` statements in the R3 section.)
   (b) Find the exact moment `count` goes 255 → 0 and read the marker time.
   It should sit just before the `R2 pass` line's `@21959245500fs`. While
   zoomed there, unfold `count`'s bits: at the wrap, all eight flip at once
   — in lesson 04 those upper bits become the NCO's output square waves.
2. **Break it on purpose.** In `count8.vhd`, change `cnt <= cnt + 1;` to
   `cnt <= cnt + 2;` and `make sim`. Predict the output before running.
   Four things to observe, two of them traps: the R1 asserts print ten
   `(assertion error)` FAIL lines with observed values 2,4,6,…; **the
   `R1 pass` report still prints right after them** (it's an unconditional
   `report` — execution evidence, not a verdict; the FAILs above it are the
   verdict); the R2 *setup* assert fails too (`R2 setup FAIL: expected
   count=255, got 254` — counting by twos from an even start lands only on
   even values, so the count never touches 255); and yet **the R2 wrap
   assert still genuinely passes** (254 + 2 wraps to 0 just as 255 + 1
   does — a check can be true for the wrong reason, which is exactly why
   the TB asserts the setup value instead of trusting the corner alone).
   Also note `make` exits successfully — see Tips. Re-dump the wave,
   `File → Reload Waveform` in the still-open GTKWave, and watch the
   staircase climb by twos. Revert and confirm `make sim` is clean.
3. **Ride the severity ladder.** With the bug from (2) still in place, run
   `./build/count8_tb --assert-level=error` (rebuild first: `make sim` will
   rebuild and run; then run the binary by hand with the new flag). The sim
   now halts at the *first* R1 violation with a nonzero exit code — the
   stop-on-first-error policy. Then change the R1 assert's severity from
   `error` to `failure` in the TB and run plain `make sim`: same halt, but
   now it's the *testbench author's* choice instead of the *runner's*.
   Decide which knob you'd want in a nightly regression and why. Revert both.
4. **Stretch: a fifth requirement.** Specify R5 yourself — "a single-cycle
   `en` pulse increments count by exactly 1" — add it to `count8.vhd`'s
   header, and append a tagged TB check: drive `en` high one clock, low
   three, repeat four times, assert count advanced by exactly 4. No DUT
   change should be needed — a new requirement doesn't always mean new
   hardware, but it always means a new check.

### Tips & Pitfalls

- **Emacs: let the compile buffer drive GTKWave-free debugging.** GHDL's
  runtime assert messages carry the same `file:line:col` prefix as its
  compile errors, so if you run the sim with `<f6>` (M-x compile → `make
  sim`), `M-g n` jumps your cursor from FAIL line to FAIL line *into the
  testbench source* at the assert that fired. Fix, `<f6>`, repeat — the
  red/green loop from lesson 00 works for simulation failures too.
- **Toolchain gotcha: `make sim` "succeeds" with errors in the log.** With
  `--assert-level=failure`, GHDL exits 0 even when `error`-severity asserts
  fired — only a `failure` (or a crash) makes the exit code nonzero. So
  never judge a run by make's silence; read the log, or grep it:
  `make sim 2>&1 | grep -c FAIL` should print 0. The course's `verify.sh`
  compares the whole log against the expected output for exactly this
  reason.
- **Forgot `done <= true;` (or the final `wait;`)?** Without `done` the
  clock schedules events forever and the sim never exits (Ctrl-C it);
  without the final `wait;` the process loops and re-runs your stimulus
  forever. Safety net while developing: `--stop-time=25ms` on the run line.
- **GTKWave shows the old run.** The `.ghw` is rewritten only when you
  re-run the simulation binary with `--wave=`, and GTKWave only rereads it
  on `File → Reload Waveform`. If the wave contradicts the console, you're
  almost certainly looking at a stale dump: re-run, then reload.
- **Hex vs decimal.** `count` displays in hex until you set Data Format →
  Decimal (per-signal). Ten minutes of confusion about why the counter
  "jumps from 9 to A" is a rite of passage you are hereby spared.

### Checkpoint

Before lesson 03, all of the following are true:

- `make sim` in `course/work/lesson02/` prints the five `pass` lines and the
  `count8 testbench complete: R1-R4 checked` line, with no `FAIL` anywhere
  in the log.
- `./build/count8_tb --assert-level=failure --wave=build/count8.ghw`
  produces `build/count8.ghw`, and you can open it in GTKWave, add signals,
  display `count` in decimal, Zoom Fit, and place a marker on a named event
  (e.g. the 255 → 0 wrap) and read its time.
- You ran the `cnt + 2` sabotage, saw the ten R1 FAIL lines plus the
  `R2 setup FAIL` at 254, can explain why `R1 pass` printed anyway and why
  the R2 wrap assert still passed even though the setup assert failed, and
  have reverted it (`make sim` clean again).
- You can state from memory what each of `note`, `warning`, `error`,
  `failure` does under `--assert-level=failure`, and which flag makes
  `error` halt the run.
