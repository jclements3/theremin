# Lesson 04 — The NCO

*Where we are.* Lessons 01–03 gave you the mechanics: entities and signals,
self-checking testbenches, and `numeric_std` arithmetic that wraps or
saturates on your orders. Now you meet the first module that goes into the
finished theremin: the numerically controlled oscillator, the box in the
signal chain that turns a number into a pitch. Everything downstream — the
sine LUT (lesson 07), the delta-sigma DAC (lesson 08), the pitch mapper
(lesson 13) — exists to feed this module or consume its output. If you saw
this code in `fpga/phase1`, treat it as new anyway: this time we derive
every line, and the derivations are what the rest of the course reuses.

---

## Session 04.1 — The Phase Accumulator (~60 min)

### Objectives

- Derive `f_out = fcw * f_clk / 2**W` from the geometry of a wrapping
  accumulator, with no hand-waving.
- State the frequency resolution of an NCO and compute the frequency
  control word for any target pitch.
- Explain phase-truncation jitter: why output edges land only on clock
  boundaries, and why the error is bounded by one clock period.
- Prove the ±1 edge-count property and explain why the testbench checks
  frequency as a *property* rather than against a golden trace.
- Read every line of `nco.vhd` and `nco_tb.vhd` and explain what it does
  and why it is written that way.

### Concepts

#### A number on a circle

Forget hardware for a moment. Phase is an angle: a point on a circle,
running from 0 to 2π and wrapping. An oscillator is nothing but a phase
that advances at a constant rate; frequency *is* that rate,
f = dφ/dt ÷ 2π.

Represent the angle as a W-bit unsigned integer. The value 0 means angle 0;
the value 2^W means... 2^W doesn't exist in W bits — it wraps to 0, exactly
what an angle does at 2π. A W-bit unsigned with wrapping arithmetic is a
*perfect* model of a circle divided into 2^W ticks — no approximation, no
corner cases; lesson 03's modular arithmetic does the wrapping for free.

Now make the phase advance. Every clock edge, add a constant:

```
acc <= acc + fcw;   -- mod 2**W, courtesy of numeric_std unsigned
```

`fcw` is the **frequency control word**: the number of phase ticks to
advance per clock. That's the entire oscillator. Three signals, one adder.

#### Deriving f_out

Per clock cycle, the phase advances by `fcw` ticks out of 2^W per full
circle. So it completes

```
fcw / 2**W          cycles per clock
```

and the clock delivers f_clk edges per second, so

```
f_out = fcw * f_clk / 2**W
```

That's the fundamental DDS equation. Derived, not memorized: cycles per
clock, times clocks per second.

At our numbers — f_clk = 12 MHz, W = 32:

```
f_out = fcw * 12e6 / 4294967296  =  fcw * 0.0027940 Hz
```

Want concert A, 440 Hz? fcw = round(440 · 2^32 / 12e6) = **157482**, which
gives 439.99963 Hz — 0.4 millihertz low. Want C4, 261.6256 Hz? The same
arithmetic gives 93639.45. The course actually uses **93640** — 0.55
counts above the exact value, 261.6271 Hz, about 1.5 mHz sharp — as the
pinned `FCW_BASE` default of the `pitch_map` module you'll build in
lesson 13, where that deliberate offset is priced in the open (it's four
orders of magnitude below a semitone). Hold that number: now you know
where it comes from, to the half-count.

#### Frequency resolution

The smallest frequency step is one LSB of fcw:

```
Δf = f_clk / 2**W  =  12e6 / 2**32  ≈  2.8 mHz
```

Compare the obvious alternative, a divide-by-N counter: f = f_clk / 2N.
Its steps are *non-uniform* — enormous at high frequencies (N=2 to N=3 is
a 50% jump) — and it only ever hits integer submultiples of the clock.
The NCO's grid is uniform, 2.8 mHz everywhere, and hits 439.99963 Hz
without asking the clock for permission. That uniformity is why every
synthesizer, radar exciter, and software-defined radio of the last forty
years uses a phase accumulator.

The price of the fine grid: the *period* is generally not an integer number
of clocks, which brings us to jitter.

#### Phase truncation jitter

The square output is just the MSB of the accumulator — high while the phase
is in the top half of the circle, low in the bottom half. That's a ~50%
duty square wave at f_out.

But the accumulator only changes on clock edges, so output edges can only
land on clock edges. The ideal period is 2^W / fcw clocks — usually not an
integer. Take the testbench's fcw = 700 with W = 16: the ideal half-period
is 2^15/700 = 46.8 clocks. The hardware can't do 46.8; it produces
half-periods of 46 and 47 clocks, interleaved in just the right pattern
that the *average* is exactly 46.8. Each edge is early or late by less
than one clock period — 83 ns at 12 MHz — and the error never
accumulates, because the phase register itself is exact; only your *view*
of it (the MSB) is truncated.

Is 83 ns of jitter audible on a 440 Hz tone? That's 37 ppm of the period —
about 1/1000 of a semitone, once per cycle, in alternating directions. No.
But jitter in the time domain is *spurs* in the frequency domain, and when
we tap the top 10 bits of this accumulator to address a sine table in
lesson 07, the truncation from 32 bits to 10 sets the spur floor of the
synthesized sine. Same mechanism, and we'll size it then.

#### The ±1 edge-count property (why the TB is honest)

How do you *verify* a frequency in a testbench? Amateurs dump a waveform
and eyeball it. The professional move is to find a property that must hold
exactly, and assert it.

Here's ours. Think of the phase as an unbounded running sum
p(n) = p₀ + n·fcw (the accumulator is this value mod 2^W). The MSB rises
exactly when the phase crosses into the top half of the circle — i.e. when
p(n) passes a threshold of the form 2^(W-1) + m·2^W. Those thresholds are
spaced exactly 2^W apart on the phase line.

Over K clocks the phase travels exactly K·fcw — *exactly*, because the
accumulator is integer arithmetic with no rounding anywhere. An interval of
length K·fcw contains either ⌊K·fcw / 2^W⌋ or ⌈K·fcw / 2^W⌉ thresholds,
depending only on where it starts. Therefore, for **any** fcw, **any**
starting phase, **any** window of K clocks:

```
| edges_observed  −  K·fcw / 2**W |  ≤  1
```

No tolerance tuning, no golden trace that silently encodes the bug it was
generated from. If the DUT drops a single count anywhere, a long window
turns that into a large edge deficit and the assert fires. This is R1 in
the testbench, and it's checked at four operating points including both
corners of the range (fcw = 1 and fcw = 2^(W-1)).

One subtlety the property also absorbs for free: the TB samples `sq` right
after `rising_edge(clk)`, one delta cycle before the DUT's new value has
propagated, so it effectively observes a window shifted by one clock.
Shifting a K-clock window moves at most one threshold in or out — still
within the ±1.

#### Nyquist and the corners

fcw = 2^(W-1) is the Nyquist corner: half a circle per clock, MSB toggling
every clock, f_out = f_clk/2. Push fcw above that and the output *aliases*
— the MSB can't toggle faster than once per clock, so you observe the
image frequency instead (you'll do this to yourself, on purpose, in
Explore). At the other end, fcw = 1 is the slowest note: one wrap per 2^W
clocks. The testbench visits both ends.

### Radar Connection

The NCO's datasheet name is **DDS** — direct digital synthesis — and it is
the beating heart of every modern radar exciter.

- **STALO.** A coherent radar needs every pulse launched with a known
  phase relative to the receiver's local oscillator, so echoes can be
  integrated across pulses and Doppler extracted. The classical stable
  local oscillator was heroic analog engineering; the modern one is this
  lesson's module with a bigger W and a faster clock. The killer feature
  is *determinism*: reset the accumulator and you know the phase, exactly,
  forever after. Analog oscillators drift; counters don't.
- **Chirp generation.** An FMCW radar transmits a linear frequency ramp.
  With an NCO that's one more accumulator: ramp `fcw` itself, and f_out
  ramps linearly. The frequency step granularity of the chirp is exactly
  this lesson's Δf = f_clk/2^W, which bounds chirp linearity error — and
  chirp nonlinearity smears range resolution.
- **Phase-continuous switching.** Look at what happens when `fcw` changes
  mid-flight: nothing bad. The accumulator keeps its value and simply
  advances at the new rate — frequency steps are *phase-continuous*, with
  no transient glitch. That is precisely why the theremin can retune the
  NCO 180 times a second (lesson 13) without clicks, and why FSK radars
  and frequency-hopping waveforms use DDS: an analog PLL slews and rings
  when retuned; an accumulator just changes slope.
- **Spurs are false targets.** Phase-truncation spurs in the exciter show
  up in the receive spectrum as targets that don't exist. The jitter
  analysis you just did is the first half of a radar spur budget; lesson
  07 does the second half.

The theremin is using the DDS as its *voice*. A radar uses it as its
*ruler*. Same module.

**Stopping point.** You should now be able to explain:

- why a W-bit wrapping unsigned adder is an exact model of phase on a
  circle, and how f_out = fcw·f_clk/2^W follows from "cycles per clock,
  times clocks per second".
- why the NCO's frequency grid is uniform at Δf = f_clk/2^W while a
  divide-by-N counter's steps are neither uniform nor fine.
- why each output edge can be early or late by up to one clock period yet
  the error never accumulates.
- why, over any window of K clocks, the observed rising-edge count must
  land within ±1 of K·fcw/2^W — for any fcw and any starting phase.

---

## Session 04.2 — Dissecting the Code (~75 min)

### Build

Three files. The code below is the reference implementation — the same
`nco.vhd` that ships in `fpga/phase1/rtl/` and will be instantiated
unchanged inside `theremin_top` in lesson 14. Solutions live in
`course/solutions/lesson04/`; since this is a dissection lesson the code is
given, but type it in rather than copying the files — the typos you make
and chase down with `<f6>` / `M-g n` are half the value.

**File: course/work/lesson04/nco.vhd**

```vhdl
-- nco.vhd — Numerically controlled oscillator (phase accumulator DDS core).
--
-- Requirements this module implements (verified in tb/nco_tb.vhd):
--   R1: average output frequency f_out = fcw * f_clk / 2**W, with per-edge
--       timing jitter bounded by one clock period (inherent to a truncated
--       phase accumulator).
--   R2: synchronous active-high reset clears the phase accumulator to zero.
--   R3: when en = '0' the phase holds (clock-enable style; no gated clocks).
--
-- Radar analog: this is a DDS / stable local oscillator (STALO). The
-- frequency resolution f_clk / 2**W is the same quantity that sets chirp
-- step granularity in an FMCW waveform generator. The 'phase' output port
-- is the future address bus for a sine LUT (Phase 4) and the phase input
-- to a quadrature mixer (Phase 5).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco is
  generic (
    W : positive := 32  -- phase accumulator width
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                 -- synchronous, active-high
    en     : in  std_logic;                 -- clock enable
    fcw    : in  unsigned(W - 1 downto 0);  -- frequency control word
    phase  : out unsigned(W - 1 downto 0);  -- current phase (test point / LUT address)
    sq_out : out std_logic                  -- MSB of phase: square wave at f_out
  );
end entity nco;

architecture rtl of nco is
  signal acc : unsigned(W - 1 downto 0) := (others => '0');
begin

  accumulate : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      elsif en = '1' then
        acc <= acc + fcw;  -- wraps naturally mod 2**W: one full wrap = one output cycle
      end if;
    end if;
  end process;

  phase  <= acc;
  sq_out <= acc(W - 1);

end architecture rtl;
```

Dissection, top to bottom:

- **Header comment.** House style: every module opens by listing the
  requirements it implements, by tag, and where they're verified — R1–R3
  are the contract the testbench enforces. (The "Phase 4/5" references are
  the older `fpga/` roadmap's names for lessons 07 and 12 material; the
  file is reused verbatim, comments and all.)
- **`generic (W : positive := 32)`.** The accumulator width is the one
  design knob, and it *only* sets frequency resolution (f_clk/2^W). It
  costs one carry chain, so 32 bits is cheap; the default matches the
  pinned interface in the curriculum, and the TB will override it smaller.
- **`rst`** is synchronous and active-high — sampled inside
  `rising_edge(clk)`, never in the sensitivity list. One flavor of reset
  in the whole codebase means one thing fewer to check in review.
- **`en`** is a clock enable, not a gated clock. Gating the clock itself
  (`clk and en` feeding a clock pin) creates glitches and ruins timing
  analysis; a synchronous enable is free — synthesis maps it onto the
  enable pin every iCE40 flip-flop already has.
- **`fcw` is a port, not a generic.** This is load-bearing: the whole
  instrument works by *rewriting the frequency while the oscillator runs*.
  `pitch_map` will drive this port with a new word per measurement.
- **`phase` out.** The full accumulator, exported. In lesson 07 its top
  bits become the sine-table address; in the TB it's a test point for the
  reset and enable checks. Costs nothing — it's just wires off the
  register.
- **`signal acc ... := (others => '0')`.** The init value covers
  simulation time zero, before the first reset; on the real iCE40, global
  set/reset zeroes flops at configuration anyway, but we never *rely* on
  that — `rst` is the mechanism the requirement names.
- **The process.** Priority order: reset beats enable; enable guards the
  accumulate. `acc + fcw` on `unsigned` operands of equal width wraps
  modulo 2^W — the lesson 03 semantics doing exactly what the circle needs.
  Nothing else in the process, so it synthesizes to W flip-flops, one
  W-bit adder, and the enable/reset plumbing. You'll see precisely that in
  the yosys report in lesson 05.
- **The concurrent assigns.** `phase <= acc` is wiring. `sq_out <=
  acc(W - 1)` is the entire "output stage": the MSB is high exactly while
  the phase is in the top half of the circle, giving the ~50% duty square
  wave whose edges we counted in the Concepts section.

**File: course/work/lesson04/nco_tb.vhd**

```vhdl
-- nco_tb.vhd — self-checking testbench for the NCO.
--
-- Verification approach (DO-254 flavor): every assert is tagged with the
-- requirement it verifies (R1..R3 from rtl/nco.vhd). The frequency check is
-- a *property*, not a golden trace: for any fcw, the number of output rising
-- edges observed over K clocks must satisfy |edges - K*fcw/2**W| <= 1,
-- which follows from the accumulator being exact (error is pure phase
-- truncation, bounded by one wrap). Run with a small W so corner cases are
-- reachable in simulation.
--
-- Sampling note: the TB samples sq_out immediately after rising_edge(clk),
-- i.e. one delta before the DUT's new value propagates — the observed edge
-- sequence is shifted one clock, which the +/-1 tolerance absorbs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco_tb is
end entity nco_tb;

architecture sim of nco_tb is
  constant W       : positive := 16;
  constant CLK_PER : time     := 83.333 ns;  -- 12 MHz

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal fcw   : unsigned(W - 1 downto 0) := (others => '0');
  signal phase : unsigned(W - 1 downto 0);
  signal sq    : std_logic;
  signal done  : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst,
      en     => en,
      fcw    => fcw,
      phase  => phase,
      sq_out => sq
    );

  main : process
    -- R1: count output rising edges over n_clks clocks and compare against
    -- the exact expected count n_clks * fcw / 2**W.
    procedure check_freq(fcw_val : natural; n_clks : positive) is
      variable edges    : natural := 0;
      variable expected : real;
      variable last     : std_logic;
    begin
      rst <= '1'; en <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      fcw <= to_unsigned(fcw_val, W);
      en  <= '1';
      wait until rising_edge(clk);
      last := sq;
      for i in 1 to n_clks loop
        wait until rising_edge(clk);
        if sq = '1' and last = '0' then
          edges := edges + 1;
        end if;
        last := sq;
      end loop;
      expected := real(n_clks) * real(fcw_val) / 2.0 ** W;
      assert abs(real(edges) - expected) <= 1.0
        report "R1 FAIL: fcw=" & integer'image(fcw_val) &
               " edges=" & integer'image(edges) &
               " expected=" & real'image(expected)
        severity error;
      report "R1 pass: fcw=" & integer'image(fcw_val) &
             " edges=" & integer'image(edges) &
             " expected~=" & real'image(expected);
    end procedure;

    variable phase_hold : unsigned(W - 1 downto 0);
  begin
    -- R2: synchronous reset clears the phase.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;  -- let post-edge value settle
    assert phase = 0
      report "R2 FAIL: phase not cleared by synchronous reset"
      severity error;
    report "R2 pass: reset clears phase";

    -- R1 across the operating range, including corners:
    check_freq(700,          20000);       -- arbitrary non-power-of-two
    check_freq(1024,         20000);       -- exact divisor: period = 64 clocks
    check_freq(2 ** (W - 1), 64);          -- Nyquist corner: toggles every clock
    check_freq(1,            3 * 2 ** W);  -- slowest: 3 full wraps -> 3 edges

    -- R3: en='0' freezes the phase.
    en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    phase_hold := phase;
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert phase = phase_hold
      report "R3 FAIL: phase advanced while en='0'"
      severity error;
    report "R3 pass: clock-enable holds phase";

    report "NCO testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **`constant W : positive := 16`.** The TB shrinks the accumulator so
  corners are reachable: the fcw = 1 test needs 3·2^W clocks — 196 608 at
  W = 16 (16.4 ms simulated, seconds of wall clock) but 12.9 *billion* at
  W = 32. Reduced-W verification is legitimate here because nothing in the
  design's logic depends on W's value — the property is width-generic.
- **The clock line.** A concurrent conditional assignment:
  `clk <= not clk after CLK_PER/2 when not done else '0'`. Every event
  schedules the next one, half a period out — until `done` goes true, at
  which point the chain stops, event-driven simulation runs out of events,
  and GHDL exits. That's how a testbench with no `--stop-time` ends
  cleanly. (83.333 ns is 12 MHz to a picosecond-ish; the femtosecond
  timestamps you'll see in the output come from GHDL resolving CLK_PER/2.)
- **Direct entity instantiation.** `entity work.nco` — no component
  declaration, no default binding rules to think about. VHDL-2008 style
  used throughout the course.
- **`check_freq` is a procedure declared inside the process.** It can
  therefore drive the process's signals (`rst`, `en`, `fcw`) and consume
  simulation time with `wait` — a procedure declared in a package could do
  neither without signal parameters. This is the standard way to make a
  reusable stimulus-plus-check block; you'll write your own in lesson 10.
- **Reset sequencing inside `check_freq`.** Each call starts from a clean
  reset (two clocks, belt and braces), then releases reset, applies the
  fcw, enables, and waits one edge before capturing `last := sq`. That
  priming read is the classic edge-detector idiom: compare each new sample
  against the previous one, count the `0 → 1` transitions.
- **Why sample `sq` "one delta early"?** The process resumes at
  `rising_edge(clk)` in the same simulation cycle that triggers the DUT's
  process — but the DUT's new `acc` (hence `sq`) is only *scheduled*, not
  yet visible. So the TB reads pre-edge values and its observation window
  is effectively shifted one clock. Rather than fighting delta cycles with
  `wait for 1 ns` in the hot loop, the TB leans on the math: a shifted
  window changes the count by at most one, and the property already
  tolerates ±1. Know which battles not to fight.
- **`expected` is `real`.** 20000·700/65536 is not an integer, and forcing
  it into one would smuggle a rounding choice into the check. Compute the
  exact expectation in floating point, compare with the proven tolerance.
- **The assert / report pair.** The `assert ... severity error` fires only
  on violation; the `report` after it prints *unconditionally* as a
  progress line. So if a check fails you'll see both an `R1 FAIL`
  (assertion error) and an `R1 pass` line with identical numbers — the
  FAIL is the verdict, which is why the final message says "any FAILs are
  listed above". You'll see this first-hand in Explore.
- **The four operating points.** 700 exercises the general case (46.8
  clocks per half-period — the jitter case from Concepts); 1024 divides
  2^16 exactly (a clean 64-clock period, zero jitter); 2^15 is the Nyquist
  corner where `sq` toggles every clock; fcw = 1 is the slowest possible
  output, run for exactly 3 wraps to expect exactly 3 edges. Corners are
  where accumulators die; test them by name.
- **R2 and R3** sample `phase` (not `sq`) because they are statements about
  the register itself. Both use `wait for 1 ns` after the edge — here,
  outside any loop, burning a nanosecond to hop past the delta cycle is
  the simple and readable choice. R3 captures the phase, sits through ten
  clocks with `en = '0'`, and demands bit-exact stillness.
- **`done <= true; wait;`** stops the clock and parks the process forever;
  without the final `wait`, the process would loop back to the top —
  processes have no implicit end. Say what you mean.

**File: course/work/lesson04/Makefile**

```make
# Lesson 04 — NCO simulation. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile in
# miniature — same flags, same shim, sim only.

TB         = nco_tb
SRC        = nco.vhd nco_tb.vhd
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

The lesson 00 Makefile plus three things worth noting: `ghdl -a` takes
both sources in one call, `nco.vhd` first because the TB instantiates it;
`--wave=` makes every sim leave a `.ghw` behind whether you wanted one or
not (disk is cheap, re-running a 20-second sim for the wave you forgot is
not); and `--assert-level=failure` halts only on severity `failure`, so
our `error`-severity asserts print and *keep going* — one run reports the
verdict on every requirement instead of dying at the first.

**Stopping point.** You should now be able to explain:

- why `fcw` is a port rather than a generic, and which part of the
  finished instrument depends on rewriting it while the oscillator runs.
- why `en` is a synchronous clock enable and what goes wrong if you gate
  the clock instead.
- why `check_freq` is declared inside the testbench process — what a
  procedure gains there that a package-level procedure would lack.
- why the testbench shrinks W to 16, and why reduced-width verification is
  legitimate for this design.

---

## Session 04.3 — Run, Break, Measure (~80 min)

### Run

From `course/work/lesson04/` (with the toolchain environment sourced —
the `fpga` alias from lesson 00 does this):

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build nco.vhd nco_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/nco_tb nco_tb
./build/nco_tb --wave=build/nco_tb.ghw --assert-level=failure
nco_tb.vhd:92:5:@125999500fs:(report note): R2 pass: reset clears phase
nco_tb.vhd:77:7:@1667034998500fs:(report note): R1 pass: fcw=700 edges=214 expected~=2.13623046875e2
nco_tb.vhd:77:7:@3333944997500fs:(report note): R1 pass: fcw=1024 edges=313 expected~=3.125e2
nco_tb.vhd:77:7:@3339528308500fs:(report note): R1 pass: fcw=32768 edges=32 expected~=3.2e1
nco_tb.vhd:77:7:@19723712771500fs:(report note): R1 pass: fcw=1 edges=3 expected~=3.0
nco_tb.vhd:112:5:@19724630434500fs:(report note): R3 pass: clock-enable holds phase
nco_tb.vhd:114:5:@19724630434500fs:(report note): NCO testbench complete (any FAILs are listed above)
```

(The `mkdir -p build` line appears only on the first run.) Sanity-check
the numbers against the theory: fcw = 700 predicts 20000·700/65536 =
213.62 edges, count is 214 — inside the ±1. fcw = 1024 predicts 312.5,
lands on 313. Nyquist counts one edge per two clocks: 32 in 64. Even the
timestamps check out: the fcw = 1 test alone spans 3·65536 clocks
≈ 16.4 ms, which is why the last lines sit near 19.7 ms.

```bash
make wave
```

opens GTKWave on the recorded waveform (same sim output first, then the
GUI). Add `clk`, `rst`, `en`, `fcw`, `sq`, and `phase`; set `phase`'s data
format to Analog → Step and you will see the sawtooth — phase climbing
linearly and wrapping, with `sq` as its MSB. That sawtooth *is* this
lesson.

### Explore

Attempt these before peeking at anything in `course/solutions/`.

1. **Break it: tap the wrong bit.** In `nco.vhd`, change `sq_out <=
   acc(W - 1)` to `acc(W - 2)` and `make sim`. Predict first, then run.
   You should see every R1 check fail — fcw = 700 counts 427 edges
   (double; bit W−2 wraps twice per full circle) and the Nyquist case
   counts **0** (adding 2^15 never changes bit 14 at all — work out why).
   Note that each `R1 FAIL` assertion line is followed by an `R1 pass`
   progress line with the same numbers; that's the unconditional `report`
   from the dissection. Restore the code and re-run to green.
2. **Alias yourself.** Add `check_freq(2 ** W - 1024, 20000);` after the
   Nyquist check. The formula predicts ~19688 edges; the sim counts ~313 —
   exactly the fcw = 1024 result, because adding 2^16 − 1024 *is*
   subtracting 1024 mod 2^16: a negative frequency, whose MSB square wave
   is indistinguishable from the positive one. This is Nyquist folding,
   met as an assertion failure instead of a textbook figure. Remove the
   line afterwards (the solutions/OUTPUT.log don't include it).
3. **Measure the jitter.** `make sim` (clean), then `make wave`; zoom in on
   `sq` during the fcw = 700 segment (before 1.7 ms) and measure several
   consecutive half-periods with the two marker cursors. Confirm they
   alternate between 46 and 47 clocks, averaging 46.8 — the truncation
   jitter from Concepts, on screen. Then check the fcw = 1024 segment: all
   half-periods identical (32 clocks), zero jitter, because 1024 divides
   2^16.
4. **Resolution costs observation time.** Set the TB's `W` to 32 and
   replace the four checks with `check_freq(157482, 20000);` — the A440
   word. It passes with 0 or 1 edges observed, which verifies almost
   nothing: expected is only 0.73 edges. To *resolve* a frequency to Δf
   you must watch for on the order of 1/Δf seconds; a 20000-clock window
   can't tell A440 from A441. Estimate how long the fcw = 1 test would run
   at W = 32 (3·2^32 clocks ≈ 18 minutes of simulated time) and appreciate
   why the TB shrinks W instead. Restore W = 16 and the four original
   checks. This trade — observation time buys frequency resolution —
   returns as gate time in lesson 10 and as dwell/CPI vs Doppler
   resolution in radar.

### Tips & Pitfalls

- **Emacs / vhdl-mode:** stop typing port maps by hand. Put point inside
  `entity nco`, hit `C-c C-p C-w` (vhdl-port-copy), switch to the TB
  buffer, and `C-c C-p C-i` (vhdl-port-paste-instance) drops a complete
  `port map (clk => clk, ...)` skeleton with every port named. Also useful
  now that files hold multiple design units: `C-M-a` / `C-M-e` jump to the
  beginning/end of the enclosing unit.
- **Toolchain gotcha — analysis order.** `ghdl -a` processes files left to
  right into the work library; if you list `nco_tb.vhd` before `nco.vhd`
  you'll get *"unit 'nco' not found in library 'work'"* at the
  instantiation. The Makefile's `SRC` order is load-bearing. (Same rule
  bites harder in lesson 14 with seven files; the Makefiles always list
  dependencies first.)
- **`--assert-level` is a policy choice.** `failure` = report every
  violation and keep going; `error` = stop at the first one. This course
  pins `failure` so one run gives the verdict on all requirements; a
  fail-fast regression script might choose otherwise.
- **Don't "fix" the delta-cycle sampling.** The temptation is to sprinkle
  `wait for 1 ns` inside `check_freq`'s counting loop. It would work — and
  it would clutter the idiom and paper over the real lesson: the *property*
  was chosen to be robust to a one-clock shift. Prefer checks that don't
  care over checks that must be exactly aligned.
- **`2 ** W` in the TB is integer math and can overflow.** Fine at
  W = 16 (`3 * 2 ** W` = 196 608), but at W ≥ 30 such expressions blow
  past VHDL `integer` range and GHDL flags a bound check. That's one
  reason the `expected` computation uses the real-valued `2.0 ** W`.

### Checkpoint

Before lesson 05 you must have:

- `course/work/lesson04/` containing `nco.vhd`, `nco_tb.vhd`, and the
  `Makefile`, with `make sim` printing `R2 pass`, four `R1 pass` lines
  (edges 214, 313, 32, 3), `R3 pass`, and the completion message — no
  `FAIL` lines.
- `make wave` opening GTKWave and showing the phase sawtooth with `sq` as
  its MSB.
- On paper, from memory: the derivation of f_out = fcw·f_clk/2^W, the
  frequency resolution at f_clk = 12 MHz / W = 32 (≈ 2.8 mHz), and the fcw
  for A440 (157482).
- A one-sentence explanation of why the TB tolerates ±1 edge and why the
  tolerance needs no tuning.

Next: lesson 05 pushes a design through yosys/nextpnr/icestorm to a real
bitstream — and the design it pushes is this NCO, pinned to A440.
