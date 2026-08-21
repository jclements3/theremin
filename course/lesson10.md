# Lesson 10 — Measuring Frequency

*Where we are.* The synthesis side of the theremin is done: NCO (lesson 04),
sine table (lesson 07), delta-sigma DAC (lesson 08) — give that chain a
frequency control word and it makes a tone. Lesson 09 built the airlock,
`sync_2ff`, that lets the antenna oscillator's asynchronous square wave into
the 12 MHz clock domain at all. This lesson builds the first module that
*listens*: `freq_meas`, a reciprocal period counter that turns the antenna
signal into a number, thousands of times per second. It is also the first
lesson where you simulate hardware that doesn't exist yet — `osc_model`
stands in for the 74HC14 relaxation oscillator you won't breadboard until
lesson 99 — and the lesson where the course's deepest radar idea lands:
*observation time buys frequency resolution*, whether you call it gate time
or a coherent processing interval.

---

## Session 10.1 — The Counting Trade (~75 min)

### Objectives

- Explain direct vs reciprocal frequency counting and compute which wins,
  given f_in and f_clk, at equal measurement time.
- Derive the quantization error of a reciprocal period measurement and
  state why the testbench tolerance is ±2 counts, not a tuned fudge.
- State the gate-time-vs-resolution trade quantitatively and map it onto
  radar dwell / CPI / Doppler resolution with real numbers.
- Explain what `osc_model` is, why it is simulation-only, and why verifying
  against a model of the sensor before the sensor exists is standard
  practice.
- Build `freq_meas` and `osc_model`, and drive them from a self-checking
  testbench that sweeps a simulated hand through the pitch field.

### Concepts

#### The problem: a frequency you can feel

The antenna oscillator free-runs near 200 kHz; an approaching hand adds a
few picofarads and pulls it *down*, a couple of percent at full reach. The
whole instrument reduces to one question — **what is f_osc, right now?** —
answered a few thousand times a second, finely enough that `pitch_map`
(lesson 13) can turn it into an fcw without the result sounding like a
quantized, laggy caricature of the player's hand.

Digitally, "measure a frequency" means exactly one thing: **counting edges
against a time base**. There are two ways to arrange the count, and the
difference between them is the entire lesson.

#### Direct counting: the bench-instrument default

Open a gate for a fixed time T, count how many rising edges of the input
fall inside it, and estimate f = count / T. This is what the display of a
bench frequency counter is doing when it says "GATE 1 s".

The catch is quantization. The gate boundaries don't care where the input's
edges are, so the count is uncertain by ±1 *input* edge, and the frequency
estimate is uncertain by

```
Δf_direct = 1 / T          (one input edge, spread over the gate)
```

Independent of the input frequency — 1 Hz resolution needs a 1-second
gate, full stop. Now price that for the theremin: a responsive instrument
needs fresh pitch a few hundred times per second, and a generous
T = 320 µs gate resolves Δf = 1/320 µs = **3125 Hz**. The hand's entire
range moves the oscillator 20 kHz, so that's six discrete pitch steps from
silence to full reach — a six-key piano. Direct counting fails because it
counts the *slow* signal: 320 µs contains only 64 edges of a 200 kHz
input.

#### Reciprocal counting: count the fast thing instead

Flip it. Instead of counting input edges against the clock, count **clock
cycles against the input edges**: open the window on a rising edge of the
input, close it EDGES rising edges later, and count 12 MHz clock cycles in
between. The count is

```
period = EDGES * f_clk / f_osc      [clock cycles]
```

— with EDGES = 64, f_clk = 12 MHz, f_osc = 200 kHz: 3840 counts in the
same 320 µs. The window still opens and closes with edge-alignment slop,
but the slop is now ±1 *clock* cycle out of 3840, so the relative error is
1/3840 ≈ 0.026%, which in frequency terms is

```
Δf_reciprocal ≈ f_osc / period  =  f_osc² / (EDGES * f_clk)  ≈  52 Hz
```

Same measurement time, same input, **60× finer** — and the factor 60 is no
accident: it is exactly f_clk / f_osc. Direct counting quantizes at one
tick of the *input*; reciprocal counting quantizes at one tick of the
*clock*; the win is the ratio of their rates. The rule that falls out:

> Reciprocal counting wins whenever the input is slower than the reference
> clock; direct counting wins when it's faster. The crossover is
> f_in = f_clk.

Our input is 60× slower than the clock, so `freq_meas` is a reciprocal
counter, and the pinned interface says so: it outputs `period`, in clock
cycles, not a frequency — dividing to get hertz would cost a divider we
don't need, since lesson 13 maps period to pitch directly. (Bench
counters do both: reciprocal below their reference, direct above, which
is why a good one shows the same digit count at 10 Hz and 10 MHz.)

How good is 52 Hz, followed to the ear? One count of `period` becomes,
through lesson 13's `pitch_map` (SHIFT = 6), 2^6 = 64 fcw ticks of lesson
04's 2.8 mHz each: ≈ 0.18 Hz of audible pitch per count — about 1/87 of a
semitone at middle C, roughly a quarter of the ~5-cent threshold
trained ears notice. The measurement is not the weak link, by design, and
you now own every number in that argument.

#### The gate-time trade, stated once, honestly

Both schemes obey the same law: the product of measurement time and
frequency resolution is fixed.

```
T = EDGES / f_osc          (measurement time: you choose EDGES)
Δf ≈ f_osc / period        (resolution: falls as EDGES grows)

T · Δf  ≈  f_osc / f_clk   ...a constant of the hardware, not of EDGES.
```

Doubling EDGES doubles the window and halves Δf; nothing else you can do
to *this counter* changes the product (a faster clock does — that's
buying a better ruler). And beneath all counting schemes lies the Fourier
floor: two tones Δf apart are simply *indistinguishable* in less than
about 1/Δf seconds of observation, no matter how clever the instrument —
you met this in lesson 04's Explore 4, when a 20000-clock window couldn't
tell A440 from A441. Quantization sits on top of that limit, never below
it.

At EDGES = 64 the theremin gets a fresh 52 Hz-resolution measurement
every 320 µs — 3125 per second, an order of magnitude faster than musical
need, with resolution to spare. Explore 1 has you walk both directions
along the trade.

#### The machine: two counters and a fencepost

The datapath is small: an edge detector, an edge counter, a cycle counter.

```
              sig_in ──► [reg sig_q] ──► rising = sig_in & ~sig_q
                                            │
             ┌──────────────────────────────┴───────────────┐
             │ idle: first rising edge opens the window     │
             │ running: count clk cycles; on each rising    │
             │   edge bump edge_cnt; the EDGES-th edge      │
             │   publishes period, strobes valid, and       │
             │   opens the next window itself               │
             └──────────────────────────────────────────────┘
```

Three details carry all the correctness:

- **Edge detection is a registered compare**, `sig_in = '1' and sig_q =
  '0'` — one flop of history, no `'event` on a data signal (that operator
  is for clocks; on data it is neither synthesizable nor meaningful).
  Because detection samples on clk, each detected edge is quantized to a
  clock instant: that's where the ±1-count-per-window-edge error
  physically lives.
- **The fencepost.** EDGES *periods* span EDGES + 1 *edges* (count your
  fingers and the gaps between them). The opening edge is edge zero;
  `edge_cnt` counts the ones after it; the edge that finds
  `edge_cnt = EDGES - 1` is the (EDGES)-th after the opener and closes the
  window. And `cycle_cnt` starts at **1**, not 0, so that when the closing
  edge is detected P clocks later the counter reads exactly P. Off-by-one
  bugs in instruments don't crash; they miscalibrate, forever, quietly —
  get the fencepost right by *argument*, then let R1's exactly-3840 check
  confirm it.
- **No dead time.** The closing edge immediately opens the next window —
  publish, strobe `valid`, reset both counters, keep going. A gap between
  windows would be time the hand moves unobserved. `valid` is a one-clock
  strobe and `period` holds until the next measurement lands — the same
  producer-side handshake shape you'll meet as `stb`/`busy` in lesson 11
  and consume in lesson 13.

#### osc_model: simulating the sensor you don't have

`freq_meas` needs something to measure, and the real something — a 74HC14
Schmitt-trigger relaxation oscillator whose capacitance includes a human
hand — is on a breadboard in lesson 99's future. So we write down what we
*believe* the hardware will do, as a contract:

```
f_osc = BASE_HZ − hand · DELTA_HZ        hand ∈ [0.0, 1.0]
```

`hand = 0.0` is the hand fully away (f_osc = BASE_HZ); `hand = 1.0` is
touching the antenna (maximum added capacitance, frequency pulled down by
the full DELTA_HZ). More capacitance → lower frequency, matching the
physics. The model emits a 50%-duty square wave and re-samples `hand`
every half-cycle, so a moving hand takes effect within microseconds.

Look at what the model is allowed to use: a `real`-valued port, `real`
generics, `wait for` a computed time. None of that exists in silicon —
there is no real-number wire — and yosys would reject every line. That's
fine, and it's *labeled*: the header says SIMULATION-ONLY in capitals,
and the Makefile has no synthesis target to accidentally include it in.
The boundary discipline matters more than the model's sophistication:
`osc_model` may be luxurious VHDL, but `freq_meas` must stay strictly
synthesizable, because only the model gets left behind at the lab bench.

Is a linear frequency-vs-hand law *true*? No — the real C(d) relationship
is an inverse-ish curve, and lesson 13 will be honest about
linearization. It doesn't matter here: `freq_meas`'s job is to report
whatever frequency exists, so the model needs to be accurate about the
*interface* (a square wave whose frequency moves with the hand), not the
physics behind it. Choosing what a model must get right — and saying out
loud what it doesn't — is a professional skill with a name in the radar
world. Which brings us to:

### Radar Connection

This is the deepest radar tie-in of the course. Two ideas, both
load-bearing in every radar you'll ever work on.

#### Dwell, CPI, and Doppler resolution

A CW or pulse-Doppler radar measures target velocity by measuring a
frequency — the Doppler shift f_d = 2v/λ — and it faces *exactly* the law
you just derived: you cannot resolve frequencies Δf apart without
observing for T ≈ 1/Δf. Radar has names for the pieces:

- **Dwell time** — how long the radar stares at one direction/target. Our
  `EDGES` generic *is* the dwell knob: T = EDGES/f_osc.
- **CPI (coherent processing interval)** — the block of M pulses,
  T = M · PRI, processed coherently into one measurement. The mapping is
  one-to-one: M pulses ↔ EDGES input periods, PRI ↔ input period, the
  fast ADC clock slicing each PRI ↔ our 12 MHz clock slicing each 5 µs
  oscillator period. One CPI in, one measurement out, `valid` strobed — a
  radar engineer would call `freq_meas`'s output "one report per CPI".
- **Doppler resolution** — Δf_d = 1/CPI, which through f_d = 2v/λ becomes
  a velocity resolution **Δv = λ / (2 · CPI)**.

Real numbers, using the HB100 module waiting in lesson 99's epilogue:
10.525 GHz, λ ≈ 2.85 cm. A hand drifting at walking-gesture speed,
v = 1 m/s, produces f_d ≈ 70 Hz; resolving it from a stationary
background needs Δf_d well under that — say a 20 ms CPI (Δf_d = 50 Hz,
Δv ≈ 0.7 m/s). Want 0.07 m/s bins to tell fingers from palm? 200 ms of
dwell. Per beam position. Multiply by the directions a surveillance radar
must visit and you see the tyranny: **dwell is the scarcest resource in a
radar timeline**, and Doppler resolution is what it buys. Every mode
design — search vs track, CPIs per beam, coarser velocity bins for faster
revisit — is a walk along the same T·Δf curve as your EDGES generic. The
theremin buys pitch smoothness with it; the radar buys seeing a slow
target crawling next to ground clutter one bin away.

One honest asymmetry: `freq_meas` counts zero crossings, which needs a
signal clean enough that edges *are* edges — fine for a rail-to-rail
Schmitt oscillator. A radar's echo is buried in noise, so it integrates
the whole waveform coherently (an FFT across the CPI — accumulating
phase, not counting edges) and gets an SNR gain of M on top of the 1/T
resolution. Lesson 12's accumulate-and-dump mixer is your first step
toward that; the resolution law itself is identical in both worlds,
because it's Fourier's law, not an implementation detail.

#### Model first, hardware later

`osc_model` is not a workaround for a missing breadboard — it is the
method. No radar signal processor in history met its antenna before
meeting a model of it. The ladder is standard: a mathematical
target-and-clutter model driving the DSP in simulation (this lesson,
exactly); then a hardware target simulator or DRFM-style echo generator
injecting synthetic returns (hardware-in-the-loop); then, last and most
expensive, live targets on a range. The early rungs exist because the
late ones are slow, unrepeatable, and can't do fault injection on demand
— you cannot ask a live target to fly at *exactly* 1.000 m/s four times
in a row, but `hand <= 0.25` does the equivalent every run, in
milliseconds.

The discipline that makes the ladder work is the one this lesson
practices: the model implements a **documented contract**
(f = BASE_HZ − hand·DELTA_HZ, 50% duty, re-sampled per half-cycle — in
the file header), the DUT is verified against the contract, and lab day
tests whether *the hardware honors the same contract*: lesson 99's tuning
procedure is literally measuring the real oscillator's BASE_HZ and
DELTA_HZ. When sim-vs-bench disagrees, the contract tells you which side
to suspect. Keep the model simple, labeled, and written down — the
difference between "it worked in sim" as an engineering statement and as
a punchline.

**Stopping point.** You should now be able to explain:

- why reciprocal counting beats direct counting by exactly f_clk/f_in when
  the input is slower than the reference clock, and where the crossover
  between the two schemes sits.
- why the product T·Δf is a constant of this counter no matter how EDGES is
  chosen, and what a faster clock buys that a longer window cannot.
- how EDGES maps onto a radar's dwell and CPI, and why Δv = λ/(2·CPI) makes
  dwell the scarcest resource in a radar timeline.
- why verifying `freq_meas` against a documented model contract before the
  oscillator exists is standard method, and which side the contract tells
  you to suspect when sim and bench disagree.

---

## Session 10.2 — Build & Run (~90 min)

### Build

Three files plus the Makefile. Solutions live in
`course/solutions/lesson10/` — type the code in rather than copying, and
resist peeking until you've attempted the Explore exercises.

**File: course/work/lesson10/osc_model.vhd**

```vhdl
-- osc_model.vhd — SIMULATION-ONLY behavioural model of the antenna oscillator.
--
-- *** NOT SYNTHESIZABLE — do not include in any synthesis file list. ***
-- Real-valued generics/ports and time-based waits are fine in simulation;
-- yosys would reject every line of this. In hardware this block is the
-- 74HC14 relaxation oscillator on the breadboard (lesson99).
--
-- Model (documented contract, used by freq_meas_tb):
--   osc_out is a 50%-duty square wave at
--     f_osc = BASE_HZ - hand * DELTA_HZ    [Hz]
--   hand = 0.0 means the hand is far away (frequency = BASE_HZ);
--   hand = 1.0 means the hand is touching the antenna (maximum added
--   capacitance, frequency pulled down by the full DELTA_HZ). More hand
--   capacitance -> lower frequency, matching the physical oscillator.
--   'hand' is re-sampled at every output half-cycle, so a change takes
--   effect within one half-period (a few microseconds at these defaults).

library ieee;
use ieee.std_logic_1164.all;

entity osc_model is
  generic (
    BASE_HZ  : real := 200_000.0;  -- frequency with the hand fully away
    DELTA_HZ : real := 0.0         -- frequency pull at hand = 1.0
  );
  port (
    hand    : in  real;       -- 0.0 = far away .. 1.0 = touching the antenna
    osc_out : out std_logic
  );
end entity osc_model;

architecture sim of osc_model is
begin

  -- Free-running toggle: each pass emits one half-cycle at the frequency
  -- implied by the current 'hand', then re-samples.
  toggle : process
    variable f    : real;
    variable half : time;
    variable lvl  : std_logic := '0';
  begin
    f := BASE_HZ - hand * DELTA_HZ;
    assert f > 0.0
      report "osc_model: f_osc <= 0 Hz (check BASE_HZ, DELTA_HZ, hand)"
      severity failure;
    half := (0.5 / f) * 1 sec;
    osc_out <= lvl;
    lvl := not lvl;
    wait for half;
  end process;

end architecture sim;
```

Dissection:

- **The header is the contract** — the exact formula, the direction of the
  hand effect, the re-sampling behavior. The testbench computes expected
  values from this formula; lesson 99 calibrates the real oscillator
  against it. A model whose contract lives only in its author's head is a
  rumor, not a model.
- **A process with no sensitivity list never stops.** It runs to the
  `wait`, sleeps `half`, loops forever — a free-running oscillator in four
  statements, recomputing `f` from the current `hand` each pass ("re-
  sampled every half-cycle"). There is no enable and no way to stop it;
  the testbench will have to deal with that (see `std.env.finish` below).
- **`half := (0.5 / f) * 1 sec`** — real arithmetic times a physical time
  unit yields a `time`, resolved by GHDL to femtoseconds; the truncation
  is parts-per-billion, invisible next to the ±2-count tolerance. `lvl`
  is a variable, not a signal: private in-place state, with only
  `osc_out` visible outside.
- **The guard assert** turns a bad generic combination (DELTA_HZ ≥ BASE_HZ
  with hand at 1.0 → non-positive frequency → `wait for` a non-positive
  time, an infinite loop at frozen simulation time) into an immediate,
  named failure. Models deserve input validation too.

**File: course/work/lesson10/freq_meas.vhd**

```vhdl
-- freq_meas.vhd — reciprocal period counter for the antenna oscillator.
--
-- Counts the number of clk cycles spanning EDGES rising edges of sig_in:
-- the window opens on a rising edge and closes on the EDGES-th rising edge
-- after it, so 'period' = EDGES full input periods measured in clk cycles
-- (nominal: EDGES * f_clk / f_sig). 'valid' strobes for exactly one clk per
-- completed measurement; the closing edge immediately opens the next window,
-- so measurements are back-to-back with no dead time.
--
-- sig_in must already be synchronous to clk (run it through sync_2ff,
-- lesson09, before this block); edge detection here is a plain registered
-- compare, not a synchronizer.
--
-- Requirements this module implements (verified in freq_meas_tb.vhd, which
-- drives it from osc_model with f_osc = BASE_HZ - hand*DELTA_HZ, BASE_HZ =
-- 200 kHz, DELTA_HZ = 20 kHz, f_clk = 12 MHz; each check allows +/-2 counts
-- for edge-sampling quantization):
--   R1: hand = 0.0  -> period ~= EDGES * f_clk / 200.0 kHz
--   R2: hand = 0.25 -> period ~= EDGES * f_clk / 195.0 kHz
--   R3: hand = 0.5  -> period ~= EDGES * f_clk / 190.0 kHz
--   R4: hand = 1.0  -> period ~= EDGES * f_clk / 180.0 kHz
--
-- Radar analog: EDGES is the dwell (integration) time. Doubling EDGES
-- doubles the measurement time and halves the relative quantization error —
-- exactly the dwell-vs-Doppler-resolution trade in a CW radar's CPI.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity freq_meas is
  generic (
    EDGES    : positive := 64;  -- input rising edges per measurement window
    CNT_BITS : positive := 24   -- width of the cycle counter / period output
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;     -- synchronous, active-high
    sig_in : in  std_logic;     -- synchronous input (post-sync_2ff)
    period : out unsigned(CNT_BITS - 1 downto 0);
    valid  : out std_logic      -- 1-clk strobe per completed measurement
  );
end entity freq_meas;

architecture rtl of freq_meas is
  signal sig_q     : std_logic := '0';  -- previous sig_in sample (edge detect)
  signal running   : std_logic := '0';  -- a window is open
  signal edge_cnt  : natural range 0 to EDGES - 1 := 0;  -- edges seen since open
  signal cycle_cnt : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
begin

  measure : process (clk)
    variable rising : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sig_q     <= '0';
        running   <= '0';
        edge_cnt  <= 0;
        cycle_cnt <= (others => '0');
        period    <= (others => '0');
        valid     <= '0';
      else
        valid  <= '0';
        sig_q  <= sig_in;
        rising := sig_in = '1' and sig_q = '0';

        if running = '0' then
          -- Idle: the first rising edge opens the window. cycle_cnt starts
          -- at 1 so that when the closing edge is detected P clocks later,
          -- cycle_cnt reads exactly P.
          if rising then
            running   <= '1';
            edge_cnt  <= 0;
            cycle_cnt <= to_unsigned(1, CNT_BITS);
          end if;
        else
          cycle_cnt <= cycle_cnt + 1;
          if rising then
            if edge_cnt = EDGES - 1 then
              -- EDGES-th edge since the window opened: publish and let this
              -- same edge open the next window (back-to-back measurement).
              period    <= cycle_cnt;
              valid     <= '1';
              edge_cnt  <= 0;
              cycle_cnt <= to_unsigned(1, CNT_BITS);
            else
              edge_cnt <= edge_cnt + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
```

Dissection:

- **`CNT_BITS = 24`** gives headroom to 2^24 − 1 ≈ 16.7 M counts ≈ 1.4 s
  of window at 12 MHz — the nominal 3840 uses 12 bits; the width is sized
  for a detuned or dying oscillator, not the happy path. (If the input
  *stops*, `cycle_cnt` climbs and no `valid` ever strobes — downstream
  keeps the last good period. Explore 4 pokes this.)
- **`valid <= '0'` first, unconditionally** — then the publish branch
  overwrites it. Last-assignment-wins inside a process is the standard
  idiom for a self-clearing one-clock strobe.
- **`rising` is a variable** because it's used in the same clock it's
  computed — a signal would lag a delta and the state machine would act on
  last cycle's edge. Variables for intra-cycle scratch, signals for state:
  lesson 01's rule earning its keep.
- **`edge_cnt` is a ranged natural**, `range 0 to EDGES - 1`: GHDL
  bounds-checks it in simulation (a fencepost bug counting to EDGES
  aborts with a range error rather than silently wrapping) and synthesis
  infers the minimal counter width.
- **The idle state exists for honesty at startup.** Out of reset we may be
  anywhere inside an input period; idle waits for a real edge so even
  measurement #1 is a true EDGES-period window.
- **Trace the fencepost once, on paper.** Opening edge detected at clock
  t₀: `cycle_cnt <= 1`, so it reads 1 during t₀+1 and P during t₀+P; a
  closing edge detected P clocks after the opener captures exactly P. R1
  makes this visible: 200 kHz divides 12 MHz exactly (60 clocks/period),
  so expected = 3840 with *zero* fractional part, and an off-by-one would
  sit at 3839 or 3841 forever — calibration error, not noise. That's why
  an exact-divisor operating point is in the requirement set.

**File: course/work/lesson10/freq_meas_tb.vhd**

```vhdl
-- freq_meas_tb.vhd — self-checking testbench for freq_meas, driven by
-- osc_model (the simulated hand-in-the-pitch-field).
--
-- Verification approach: osc_model (BASE_HZ = 200 kHz, DELTA_HZ = 20 kHz)
-- feeds freq_meas at f_clk = 12 MHz. The hand sweeps 0.0, 0.25, 0.5, 1.0;
-- for each position the TB waits for a valid strobe, discards that first
-- measurement (its window may straddle the hand movement), then checks the
-- next one against expected = EDGES * CLK_HZ / f_osc with f_osc =
-- BASE_HZ - hand*DELTA_HZ. Tolerance is +/-2 counts: each window edge is
-- quantized to a clk sampling instant (up to +/-1 clk between opening and
-- closing edges) and the expected value itself is generally non-integer.
--
-- Requirement tags (R1..R4 from freq_meas.vhd): one per hand position.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity freq_meas_tb is
end entity freq_meas_tb;

architecture sim of freq_meas_tb is
  constant CLK_HZ   : real     := 12_000_000.0;
  constant CLK_PER  : time     := 1 sec / 12_000_000;
  constant EDGES    : positive := 64;
  constant CNT_BITS : positive := 24;
  constant BASE_HZ  : real     := 200_000.0;
  constant DELTA_HZ : real     := 20_000.0;

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal hand   : real      := 0.0;
  signal sig    : std_logic;
  signal period : unsigned(CNT_BITS - 1 downto 0);
  signal valid  : std_logic;
  signal done   : boolean   := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  osc : entity work.osc_model
    generic map (
      BASE_HZ  => BASE_HZ,
      DELTA_HZ => DELTA_HZ
    )
    port map (
      hand    => hand,
      osc_out => sig
    );

  dut : entity work.freq_meas
    generic map (
      EDGES    => EDGES,
      CNT_BITS => CNT_BITS
    )
    port map (
      clk    => clk,
      rst    => rst,
      sig_in => sig,
      period => period,
      valid  => valid
    );

  main : process
    -- Block until the DUT strobes valid. Sampling right after
    -- rising_edge(clk) sees the strobe one clock late, which is harmless:
    -- 'period' holds until the next window completes ~4000 clocks later.
    procedure wait_valid is
    begin
      loop
        wait until rising_edge(clk);
        exit when valid = '1';
      end loop;
    end procedure;

    -- Move the hand, discard the straddling measurement, check the clean one.
    procedure check_hand(tag : string; hand_val : real) is
      variable f_osc    : real;
      variable expected : real;
      variable meas     : natural;
    begin
      hand <= hand_val;
      f_osc    := BASE_HZ - hand_val * DELTA_HZ;
      expected := real(EDGES) * CLK_HZ / f_osc;
      wait_valid;  -- window may straddle the hand movement: discard
      wait_valid;  -- entirely at the new frequency: check
      meas := to_integer(period);
      if abs(real(meas) - expected) <= 2.0 then
        report tag & " pass: hand=" & real'image(hand_val) &
               " period=" & integer'image(meas) &
               " expected~=" & real'image(expected);
      else
        assert false
          report tag & " FAIL: hand=" & real'image(hand_val) &
                 " period=" & integer'image(meas) &
                 " expected=" & real'image(expected)
          severity error;
      end if;
    end procedure;
  begin
    rst <= '1';
    for i in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';

    check_hand("R1", 0.0);   -- 200.0 kHz -> expected 3840.0
    check_hand("R2", 0.25);  -- 195.0 kHz -> expected ~3938.5
    check_hand("R3", 0.5);   -- 190.0 kHz -> expected ~4042.1
    check_hand("R4", 1.0);   -- 180.0 kHz -> expected ~4266.7

    report "freq_meas testbench complete (any FAILs are listed above)";
    -- osc_model free-runs forever (its pinned interface has no enable), so
    -- stopping the clock is not enough to drain the event queue: end the
    -- simulation explicitly.
    done <= true;
    std.env.finish;
  end process;

  -- Whole run is ~3 ms of simulated time; if valid never strobes, stop
  -- instead of hanging forever.
  watchdog : process
  begin
    wait until done for 10 ms;
    assert done
      report "TB FAIL: watchdog timeout - no valid strobe from freq_meas"
      severity failure;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **The stimulus is a model, not a vector list.** Previous testbenches
  wiggled the DUT's inputs directly; this one instantiates a second design
  unit — the plant — and steers it through a physical-ish variable,
  `hand`. That's the structure of every system-level TB from here on
  (lesson 14's integration TB is this one, grown up).
- **`wait_valid`** spins on clock edges until the strobe. It samples
  `valid` right after `rising_edge(clk)` — one delta before the DUT's new
  assignment lands — so it actually sees the strobe one clock late, and
  the comment argues *why that's harmless* (`period` holds for ~4000
  clocks). Same policy as lesson 04: prefer checks robust to a one-cycle
  shift over delta-cycle micromanagement, but write the argument down.
- **Discard-then-check.** `hand` changes at some arbitrary instant inside
  an open window, so that window's count mixes two frequencies —
  meaningless against either expectation. The first `wait_valid` throws it
  away; the second returns a window that lived entirely at the new
  frequency. Real DSP does the same: flush the pipeline after a mode
  change before trusting the output (radar: drop the first CPI after a
  frequency hop).
- **The ±2 tolerance is derived, not tuned**: ±1 count of window-edge
  quantization (opening and closing edges each snap to a clock) plus the
  fact that `expected` is generally non-integer. No slop hiding a real
  bug: an EDGES fencepost error would miss by ~60 counts.
- **`std.env.finish`** — new tool. Every prior TB ended by stopping the
  clock and letting the event queue drain, but `osc_model` schedules its
  own wake-ups forever, clock or no clock; the queue *never* drains.
  VHDL-2008's `std.env.finish` ends the simulation by decree. When the
  stimulus free-runs, the TB must say when it's over.
- **The watchdog** is the other new habit: `wait until done for 10 ms`
  resumes on `done` *or* after 10 ms, and the assert fires only in the
  timeout case. Without it, a DUT that never strobes `valid` leaves
  `wait_valid` spinning until you notice the simulator eating a CPU — and
  a TB that can hang will hang, in a scripted regression, at night.
  Severity `failure` plus the Makefile's `--assert-level=failure` makes
  the timeout halt with a nonzero exit code.

**File: course/work/lesson10/Makefile**

```make
# Lesson 10 — freq_meas + osc_model. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# osc_model is simulation-only and freq_meas is synthesized as part of
# theremin_top in lesson14, not here.

TB         = freq_meas_tb
SRC        = osc_model.vhd freq_meas.vhd freq_meas_tb.vhd
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

The lesson 04 pattern, minus the `wave` target (add one yourself if you
want the waveform — Explore 4 will) and minus synthesis on purpose:
`osc_model` must never reach yosys, and `freq_meas` gets synthesized where
it's used, inside `theremin_top` in lesson 14. `SRC` order is load-bearing
as always: `osc_model.vhd` and `freq_meas.vhd` before the TB that
instantiates them both.

### Run

From `course/work/lesson10/` (with the toolchain environment sourced — the
`fpga` alias from lesson 00 does this):

```bash
make sim
```

Expected output (a `mkdir -p build` line precedes this on the first run):

```text
ghdl -a --std=08 --workdir=build osc_model.vhd freq_meas.vhd freq_meas_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/freq_meas_tb freq_meas_tb
./build/freq_meas_tb --assert-level=failure
freq_meas_tb.vhd:89:9:@642624989718fs:(report note): R1 pass: hand=0.0 period=3840 expected~=3.84e3
freq_meas_tb.vhd:89:9:@1298958312550fs:(report note): R2 pass: hand=2.5e-1 period=3938 expected~=3.9384615384615386e3
freq_meas_tb.vhd:89:9:@1972624968438fs:(report note): R3 pass: hand=5.0e-1 period=4043 expected~=4.0421052631578946e3
freq_meas_tb.vhd:89:9:@2683541623730fs:(report note): R4 pass: hand=1.0 period=4267 expected~=4.266666666666667e3
freq_meas_tb.vhd:112:5:@2683541623730fs:(report note): freq_meas testbench complete (any FAILs are listed above)
simulation finished @2683541623730fs
```

(Your home directory will differ in the shim path.) Read the numbers like
an engineer, not a scoreboard:

- **R1 lands on 3840 exactly** — 200 kHz divides 12 MHz, so the
  expectation has no fractional part and the fencepost gets no hiding
  place.
- **R2–R4 land within 1 count** of non-integer expectations: 3938 vs
  3938.46, 4043 vs 4042.11, 4267 vs 4266.67 — the quantization analysis,
  measured. They don't all round the same way; where the window edges
  fall inside a clock cycle is up to phase, exactly as the ±-analysis
  said.
- **The timestamps** tell the dwell story: each check consumes two full
  windows (discard + check) at ~320–355 µs each; four checks finish at
  2.68 ms simulated. And `simulation finished` — from `std.env.finish` —
  rather than a drained event queue: the oscillator was still ticking
  when the lights went out.

**Stopping point.** You should now be able to explain:

- why `cycle_cnt` starts at 1, not 0, and how R1's exactly-3840 result
  leaves an off-by-one fencepost nowhere to hide.
- why the testbench discards the first measurement after each hand move
  before checking the next one.
- why the ±2-count tolerance is derived from window-edge quantization
  rather than tuned until the run passed.
- why this testbench needs `std.env.finish` and a watchdog when no earlier
  testbench did.

---

## Session 10.3 — Explore & Checkpoint (~75 min)

### Explore

Attempt these before peeking at `course/solutions/lesson10/`.

1. **Walk the dwell trade.** Set the TB's `EDGES` constant to 16 and
   `make sim`: periods near 960, and the same ±2 counts is now 4× the
   *relative* error — ~208 Hz of frequency uncertainty. Try 256: periods
   near 15360, ~13 Hz. Fill in "at EDGES = ___ the theremin measures
   every ___ µs with ___ Hz resolution" for 16/64/256 and check the T·Δf
   product stays put. This is a radar designer picking a CPI length, with
   faster feedback. Restore 64.
2. **Break it: skip the flush.** Delete the first `wait_valid` (the
   discard) in `check_hand`. R1 still passes (the hand starts at 0.0 —
   nothing straddles), but R2–R4 now check windows that straddle the hand
   movement and can land anywhere between the old and new expectations —
   likely FAILs with `period` between 3840 and 4267. Sneaky detail: a
   straddling window *can* pass by luck if the hand moved early in it —
   the check became nondeterministic, which is worse than
   deterministically wrong. Restore the discard.
3. **Find the resolution floor.** Set `DELTA_HZ` to `100.0` (a hand that
   only pulls 100 Hz). Expected periods for hand = 0.0 and hand = 1.0 now
   differ by under 2 counts — inside the tolerance of *each other*. The
   checks still pass, but the instrument can no longer tell far-hand from
   touching: not wrong, *unresolved*, the distinction Concepts insisted
   on. Compute the minimum DELTA_HZ resolvable at EDGES = 64 (Δf ≈ 52 Hz,
   so ~100 Hz for two clean counts), then restore 20_000.0.
4. **Kill the oscillator, meet the watchdog.** Set `BASE_HZ` to `1.0` in
   the TB (64 edges of a 1 Hz "oscillator" would take over a minute). The
   watchdog fires at 10 ms with `TB FAIL: watchdog timeout` and a nonzero
   exit — this is what `freq_meas` sees when the antenna wire falls off,
   and why lesson 99's troubleshooting table starts with "is the
   oscillator oscillating?". Optionally add `--wave=build/$(TB).ghw` to
   the Makefile's run line and watch `cycle_cnt` climb with no `valid` in
   sight. Restore 200_000.0 (and the Makefile).

### Tips & Pitfalls

- **Emacs / vhdl-mode:** with two instantiations to write, `C-c C-p C-w`
  (port-copy) / `C-c C-p C-i` (paste-instance) pays for itself twice —
  copy from inside `entity osc_model`, paste in the TB, repeat for
  `freq_meas`. Afterward `M-x vhdl-beautify-buffer` re-aligns port maps
  and declarations to house style in one stroke.
- **Toolchain gotcha — sim-only files poison synthesis cryptically.** If
  `osc_model.vhd` ever lands in a yosys file list, the error won't say
  "simulation-only model": it'll complain about an unsupported `real`
  port or a `wait for`. Keep sim-only files out of synthesis file lists
  *by construction* (this Makefile simply has none) and keep the NOT
  SYNTHESIZABLE banner for the next reader.
- **Where's `sync_2ff`?** The TB wires `osc_model` straight into
  `freq_meas`, and lesson 09 just told you never to do that. In
  *simulation* it's safe: GHDL resolves every signal to a clean '0' or
  '1' in deterministic delta order — there is no metastability to model.
  In *hardware* it would be a real CDC bug, which is why `freq_meas`'s
  header demands a post-`sync_2ff` input and `theremin_top` puts the
  synchronizer in front. Know which hazards your simulator cannot show
  you: this one you verify by design review, not by sim.
- **`1 sec / 12_000_000` is exact only to the femtosecond.** GHDL
  truncates CLK_PER to 83 333 333 fs (true value 83 333 333.3̄) — the
  simulated clock is ~4 parts per *billion* fast, which is why the output
  timestamps end in odd digits and why the tolerance never had to care.
  Real crystals are ±50 parts per *million*.
- **A strobe is one clock wide — consume it like one.** Logic that reacts
  to `valid = '1'` over multiple cycles (or uses it as a clock) will
  double-count. The TB's `exit when valid = '1'` loop is the correct
  consumer shape; `pitch_map` registers `period` only on the strobe for
  the same reason.

### Checkpoint

Before lesson 11 you must have:

- `course/work/lesson10/` containing `osc_model.vhd`, `freq_meas.vhd`,
  `freq_meas_tb.vhd`, and the `Makefile`, with `make sim` printing
  `R1 pass` through `R4 pass` (periods 3840, 3938, 4043, 4267) and the
  completion message — no `FAIL` lines, ending in `simulation finished`.
- On paper, from memory: the reciprocal-counter resolution
  Δf ≈ f_osc²/(EDGES·f_clk), evaluated at our numbers (≈ 52 Hz), and the
  one-line argument for why reciprocal beats direct counting by f_clk/f_in
  at equal gate time.
- The radar mapping stated without notes: EDGES ↔ pulses per CPI, window
  time ↔ dwell, ±1 clock ↔ measurement quantization, and Δv = λ/(2·CPI)
  with one worked example.
- A one-sentence answer to "why is it fine that osc_model isn't
  synthesizable?" and another to "why is the first measurement after a
  hand move discarded?".

Next: lesson 11 gives the instrument a mouth — a UART transmitter. The
audio chain never uses it, but it stays available as a sideband you can
wire in yourself (lesson 11's Explore 4 stretch shows how) to watch
`period` and pitch decisions stream out of the design as bytes instead
of squinting at waveforms.
