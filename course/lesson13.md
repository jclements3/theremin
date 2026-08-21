# Lesson 13 — Pitch Mapping and Musicality

*Where we are.* Every block of the instrument now exists and is verified in
isolation: the synthesis chain (NCO → sine table → delta-sigma DAC, lessons
04/07/08) turns a frequency control word into sound, and the measurement
chain (`sync_2ff` → `freq_meas`, lessons 09/10) turns the antenna
oscillator into a stream of period measurements, ~3000 a second. Lesson 12
showed what an *analog* theremin does between those two points — it mixes
and lets physics set the pitch. This lesson builds what *our* theremin does
instead: `pitch_map`, thirty lines of arithmetic that decide what the
instrument sounds like. It is the smallest module in the signal chain and
the only one whose requirements are partly aesthetic — which is exactly why
every choice in it has to be made in the open, with numbers.

## Objectives

- Derive every generic default in `pitch_map` — P_REF, FCW_BASE, FCW_MIN,
  FCW_MAX, the slope 2^SHIFT — from the system's clock, oscillator, and
  tuning, with no magic numbers left.
- State honestly what the linear-in-period map approximates, where the real
  nonlinearities live (hand→capacitance, oscillator, the log-frequency
  ear), and why the approximation is musically acceptable here.
- Explain why the subtraction must be signed, why clamping precedes
  smoothing, and what each clamp bound protects against.
- Recognize exponential smoothing as a first-order tracking loop, compute
  its time constant at the measurement rate, and explain the 1-LSB nudge
  that makes an integer implementation converge exactly.
- Build `pitch_map` and verify monotonicity, range clamping, and the
  smoothing step response with exact-equality, requirement-tagged asserts.

## Concepts

### The last translation

`freq_meas` hands us `period` — clock cycles per 64 antenna edges — and the
NCO wants `fcw` — phase ticks per clock. Between them sits a translation
with four requirements you can hear:

1. **In tune**: hand at rest → a known note, repeatably.
2. **Monotonic**: hand moves one way, pitch moves one way. Always.
3. **Bounded**: no glitch, mis-tuning, or dropped antenna wire may send
   the pitch to 0 Hz or 90 kHz. The instrument stays an instrument.
4. **Stable but live**: measurement jitter must not warble the pitch, yet
   the hand must not feel like it's dragging the note through syrup.

Those four requirements are, in order: an offset, a slope with a fixed
sign, a clamp, and a low-pass filter. That is the whole module.

### Choosing the map: every constant from first principles

Lesson 04 gave you the NCO tick: one fcw count is f_clk / 2^32 =
12 MHz / 2^32 ≈ 2.794 mHz of output pitch. So tuning is a multiplication:

```
fcw(f) = f · 2^32 / 12 MHz

C4 = 261.6256 Hz  →  93639.45   →  FCW_BASE = 93640   (+0.55 count ≈ 1.5 mHz sharp)
C3 = 130.8128 Hz  →  46819.72   →  FCW_MIN  = 46820   (+0.28 count ≈ 0.8 mHz sharp)
C6 = 1046.5023 Hz →  374557.76  →  FCW_MAX  = 374561  (+3.24 counts ≈ 9 mHz sharp)
```

Recompute those on your own calculator — you should get 93639.45, and
notice that two of the pinned integers are *not* the nearest rounding:
round() would say 93639 and 374558. The pins are the curriculum's contract
values, shared byte-for-byte by this module, `theremin_top`, and both
testbenches, and they sit 0.55 / 0.28 / 3.24 counts sharp of exact. Price
that offset before objecting to it: 1.5–9 mHz, twenty to a hundred times
smaller than the 0.18 Hz a single period count will move the pitch
(below), and four orders below the ~16 Hz semitone at C4. The derivation
tells you where each constant comes from and lands you within a handful
of counts; the contract tells you the exact integer. "Derived, then
pinned" is how
every constant in a fielded system should read — the derivation kills the
magic, the pin kills the drift.

P_REF is lesson 10's headline number: a free-running 200 kHz oscillator
measured over EDGES = 64 gives period = 64 · 12 MHz / 200 kHz = **3840**.
The map anchors there — hand away, `period = P_REF`, and the instrument
plays C4 — then moves linearly:

```
fcw = FCW_BASE + (P_REF − period) · 2^SHIFT        then clamp to [FCW_MIN, FCW_MAX]
```

SHIFT = 6 makes the slope 64 fcw counts per period count, i.e. one count
of measurement moves the pitch 64 · 2.794 mHz ≈ **0.18 Hz** — the number
lesson 10 used to argue the measurement isn't the weak link. Now follow
the hand through it. Full reach pulls the oscillator to 180 kHz
(`osc_model`'s contract), so period rises to 4267 and

```
fcw = 93640 − 427·64 = 66312   →   185.3 Hz  ≈  F♯3
```

A tritone of playable range, C4 down to F♯3, spread over the arm's reach —
deliberately conservative; each +1 on SHIFT doubles it, and Explore 4
prices that. Note the direction: hand approaches → oscillator slows →
period grows → **pitch falls**. Our fcw tracks the antenna frequency
itself. A classical theremin plays the *difference* against a reference,
which inverts the sense (hand in, pitch up). That's a one-sign design
choice, pinned here as-is; Explore 3 flips it and shows you what the
testbench thinks of unilateral spec changes.

Where do the clamps sit relative to all this? FCW_MIN (C3) is reached at
period = 3840 + 46820/64 ≈ 4572 — an oscillator at 168 kHz, well past
full reach. FCW_MAX needs period ≈ −550, which no counter will ever
produce: at the default slope even the absurd period = 1 maps to 339336,
still under the clamp. So in normal play neither clamp engages — they are
guard rails, not walls, and the testbench has to work to prove the top one
even exists.

### What the linear map pretends, stated honestly

The map is linear in period. Nothing in the physics is. Walk the chain:

- **Hand → capacitance.** The hand-antenna capacitance grows roughly like
  1/d as distance d shrinks — steepening violently near the rod. (The
  handoff diagrams in this repo draw exactly this: iso-pitch shells
  bunching near the antenna.)
- **Capacitance → period.** Our 74HC14 relaxation oscillator charges C
  through R, so period ≈ k·R·C — linear in C, one honest stage. A
  classical *LC* theremin instead has f = 1/(2π√(LC)): frequency goes as
  1/√C, another curve entirely. Same instrument concept, different
  front-end law — a reminder that "the" theremin response is a property
  of the oscillator you build, not of theremins.
- **Period → fcw.** Frequency is 1/period; our map is linear in period.
  Near P_REF that's the tangent line — the error term is the curvature of
  1/p, which is smaller than the linear term by (period − P_REF)/P_REF, at
  most 427/3840 ≈ 11% at full reach. Not a wrong note anywhere, just a
  scale slightly compressed toward the near-hand end.
- **fcw → perceived pitch.** The ear hears log-frequency: a semitone is a
  *ratio* (2^(1/12)). A linear map spends 87 period counts on the semitone
  above C4 but only 62 on the semitone above F♯3 — more compression, in
  the same direction.

So why ship a linear map? First, its errors are *static and smooth*: they
warp the spacing of notes in space but never break monotonicity or
repeatability, and a theremin player — who has no frets anyway — closes
the loop by ear, exactly as on the concert instrument, whose response is
no straighter. Second, the alternative costs a divider (for 1/period) plus
a log (for musical spacing) against a benefit the player can't hear.
Third — the digital theremin's quiet superpower — the *steepness* is now a
free parameter. Lesson 12's analog beat note moves ≈ 52 antenna-Hz per
period count near P_REF; wired straight to the ear, the hand's 20 kHz pull
would sweep the whole audible spectrum in one arm's length, which is why
analog theremins need delicate tuning of near-equal oscillators. The
measurement path decouples music from physics: 0.18 Hz per count because
we *chose* it, not because two coils agreed. The linear map isn't the
truth — it's a documented, bounded approximation whose knobs we own. Say
that sentence in a design review and nobody can hurt you.

### Clamping: signed first, then bounded

Requirement 3 has a trap in it. `period` is unsigned, and a hand-near
period (4267) is *bigger* than P_REF (3840). Compute `P_REF - period` in
unsigned arithmetic and numeric_std will cheerfully wrap it to a number
near 16.7 million; shifted left 6, that's a nonsense fcw about 30 bits
wide — during *normal play*, not in some corner case. So the difference is
computed signed, one bit wider than period, and widened again *before* the
shift so no intermediate can overflow — the width arithmetic is written
out in the module header; it's lesson 03's word-growth drill applied for
real. Only after clamping is the value provably in [46820, 374561] and
narrowed to the 32-bit unsigned the NCO wants.

Two details worth their sentences. The clamp brackets the *mapped target*,
before smoothing — so even a wild glitch (period = 2^24 − 1 from a dying
oscillator) becomes a bounded disturbance, tugging the filter toward C3 at
a civilized rate instead of slamming a 24-bit transient into it. And reset
preloads fcw with FCW_BASE, so the instrument wakes up *on pitch* instead
of sweeping up from silence — a small courtesy, audible every power-up.

### Smoothing: a one-pole tracking loop, in integers

`period` carries ±1–2 counts of quantization jitter (lesson 10), which the
map amplifies to ±0.2–0.4 Hz of pitch, re-rolled 3000 times a second.
Played raw, that's not vibrato, it's *fizz*. The fix is the oldest filter
there is — each measurement, move part of the way to the target:

```
fcw ← fcw + (target − fcw) / 2^SMOOTH_SHIFT
```

First-order exponential smoothing, running at the *measurement* rate, not
the clock rate: one update per `valid` strobe. With SMOOTH_SHIFT = 3 the
error shrinks to 7/8 of itself per measurement; the time constant is
−1/ln(7/8) ≈ 7.5 measurements, which at lesson 10's 320 µs cadence is
about 2.4 ms — nearer 2.7 ms at full reach, where the slower oscillator
stretches the measurement window. Either way: white measurement jitter
comes out with its variance cut by α/(2−α) ≈ 15×, while a hand gesture —
which lives at 1–10 Hz — passes through essentially untouched. The filter
gives the instrument a whisper of portamento between measurements, which
is not a bug; it's the sound.

Integer division has one dirty habit that would spoil requirement 1:
`shift_right` on a signed value rounds toward −∞. For a negative
remaining error that's fine — the step is always at least −1, and the
filter walks all the way down. But a *positive* error smaller than
2^SMOOTH_SHIFT shifts to a step of 0, and the filter parks forever a few
LSBs flat of the target — a deadband, the fixed-point cousin of an IIR
filter's limit cycle. The cure is one line: if the step truncated to zero
and the error is positive, step by +1. With it, the loop converges to the
target *exactly*, from both directions, and the testbench can use exact
equality instead of tolerances. When an integer filter lets you assert
`=`, take the gift — it means the arithmetic has no residue to hide.

## Radar Connection

`pitch_map` is two radar staples wearing a music costume: a calibration
curve and an alpha filter.

**Calibration curves.** No sensor reports engineering units. A radar
altimeter reports a counter value; a monopulse receiver, a voltage ratio;
our antenna, clock counts per 64 edges. In every case a *calibration
function* — polynomial, spline, or lookup table, fitted about the
operating point, often stored per serial number — turns raw counts into
meters, degrees, or hertz, and its residual error is not apologized for
but *budgeted*: characterized over the envelope, documented, signed off
against the requirement. Our linear map with its ≤11% scale warp at full
reach is exactly such a budget line. So is the clamping: downstream
consumers (a track filter, a weapons cue — or an NCO) get inputs
guaranteed inside a stated envelope, because "the mapper can never command
that" is a safety argument you make by construction, not by hoping. Even
reset-to-FCW_BASE has a counterpart: initializing a tracker at beam center
rather than zero, so the first update refines a sane state instead of
rescuing an absurd one.

**Alpha-beta kinship.** The smoother is, verbatim, the position half of
the alpha-beta tracking filter: x̂ ← x̂ + α(z − x̂), with α = 1/2^SMOOTH_SHIFT
= 1/8. Track-while-scan radars run this exact loop per target, one update
per measurement (per scan or per CPI — like us, in measurement time, not
wall-clock time), and tune α on exactly our trade: small α buries
measurement noise but lags a maneuvering target; large α follows the
maneuver and passes the jitter. A full alpha-beta filter adds a velocity
state (β) so a *constant-velocity* target is tracked with zero lag — the
natural next octave of this design, since a musician's hand mid-gesture is
nothing if not a constant-velocity target: our position-only filter trails
a moving hand by a beat, and β is how you'd buy that back without
surrendering jitter rejection. The 1-LSB nudge has a radar name too:
fixed-point trackers that can stall a few LSBs off the measurement exhibit
deadband and limit cycles, and production filters carry exactly this kind
of guaranteed-minimum-step or dither logic. The theremin version is just
small enough to prove convergent by staring at it.

## Build

Two files plus the Makefile. Solutions live in `course/solutions/lesson13/`
— type the code in rather than copying, and resist peeking until you've
attempted the Explore exercises.

**File: course/work/lesson13/pitch_map.vhd**

```vhdl
-- pitch_map.vhd — period-to-frequency-control-word mapper with clamping and
-- exponential smoothing (the "musicality" block between freq_meas and nco).
--
-- Requirements this module implements (verified in pitch_map_tb.vhd):
--   R1: with period = P_REF, fcw settles to exactly FCW_BASE; synchronous
--       reset also preloads FCW_BASE, so the instrument wakes up on pitch.
--   R2: fcw is strictly monotonically decreasing in period over the
--       unclamped range, following fcw = FCW_BASE + (P_REF - period)*2**SHIFT
--       exactly once smoothing has settled.
--   R3: the mapped value is clamped to [FCW_MIN, FCW_MAX]; an extreme period
--       (hand far away, oscillator glitch) can never push the NCO out of
--       the instrument's range.
--   R4: each valid strobe moves fcw toward the clamped target by
--       delta/2**SMOOTH_SHIFT (never less than 1 LSB), i.e. first-order
--       exponential smoothing at the measurement rate; the step response
--       converges to the target exactly, with no residual offset.
--
-- Signedness: period can exceed P_REF (hand far -> lower antenna frequency
-- -> longer period), so (P_REF - period) is computed in signed arithmetic,
-- CNT_BITS+1 bits wide, then widened to W_CALC bits BEFORE the left shift
-- so no intermediate can overflow. Only after clamping is the result known
-- to be positive and narrowed back to 32-bit unsigned.
--
-- The mapping is LINEAR in period, which is an approximation twice over:
-- true frequency is 1/period, and musical pitch is log-frequency. Over the
-- theremin's narrow period swing the linear map plays fine, and it costs
-- one subtract and one shift instead of a divider. The lesson text owns
-- this approximation explicitly.
--
-- Radar analog: a calibration curve (raw measurement -> engineering units)
-- followed by an alpha filter — the same smoothing a track-while-scan loop
-- uses to trade responsiveness against measurement jitter.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pitch_map is
  generic (
    CNT_BITS : positive := 24;      -- width of the period input (matches freq_meas)
    SHIFT    : natural  := 6;       -- slope: fcw counts per period count = 2**SHIFT
    P_REF    : positive := 3840;    -- period giving FCW_BASE (64 edges of 200 kHz at 12 MHz)
    FCW_BASE : positive := 93640;   -- C4, 261.6256 Hz, for a 32-bit NCO at 12 MHz
    FCW_MIN  : positive := 46820;   -- C3 — one octave below base
    FCW_MAX  : positive := 374561   -- C6 — two octaves above base
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                        -- synchronous, active-high
    period : in  unsigned(CNT_BITS - 1 downto 0);  -- from freq_meas
    valid  : in  std_logic;                        -- 1-clk strobe qualifying period
    fcw    : out unsigned(31 downto 0)             -- to the NCO
  );
end entity pitch_map;

architecture rtl of pitch_map is
  -- Wide enough for FCW_BASE + (P_REF - period)*2**SHIFT at full input
  -- range: a CNT_BITS+1-bit signed difference shifted left by SHIFT plus a
  -- sign/growth bit — and never narrower than 34 so the 31-bit-max FCW
  -- constants always fit with margin.
  constant W_CALC : positive := maximum(CNT_BITS + 1 + SHIFT + 1, 34);

  -- Smoothing strength: per valid strobe, fcw closes 1/2**SMOOTH_SHIFT of
  -- the remaining distance to the target. At the default integration's
  -- ~3 kHz measurement rate (EDGES=64, 200 kHz oscillator) that is a time
  -- constant of about 2.7 ms — fast enough to feel immediate, slow enough
  -- to bury single-count period jitter.
  constant SMOOTH_SHIFT : natural := 3;

  signal fcw_r : unsigned(31 downto 0) := to_unsigned(FCW_BASE, 32);
begin

  map_and_smooth : process (clk)
    variable diff   : signed(CNT_BITS downto 0);
    variable summed : signed(W_CALC - 1 downto 0);
    variable target : unsigned(31 downto 0);
    variable delta  : signed(32 downto 0);
    variable step   : signed(32 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        fcw_r <= to_unsigned(FCW_BASE, 32);
      elsif valid = '1' then
        -- signed difference: period > P_REF must go negative, not wrap.
        diff   := to_signed(P_REF, CNT_BITS + 1) - signed('0' & period);
        summed := to_signed(FCW_BASE, W_CALC)
                  + shift_left(resize(diff, W_CALC), SHIFT);
        if summed < FCW_MIN then
          target := to_unsigned(FCW_MIN, 32);
        elsif summed > FCW_MAX then
          target := to_unsigned(FCW_MAX, 32);
        else
          target := resize(unsigned(summed), 32);  -- in range, hence non-negative
        end if;
        -- exponential smoothing toward the clamped target. shift_right on
        -- signed rounds toward -inf, so any negative delta still steps by
        -- at least -1; a small positive delta would truncate to 0 and
        -- stall, so nudge it to +1. Both directions therefore land on the
        -- target exactly instead of parking a few LSBs away.
        delta := signed('0' & target) - signed('0' & fcw_r);
        step  := shift_right(delta, SMOOTH_SHIFT);
        if step = 0 and delta > 0 then
          step := to_signed(1, step'length);
        end if;
        fcw_r <= resize(unsigned(signed('0' & fcw_r) + step), 32);
      end if;
    end if;
  end process;

  fcw <= fcw_r;

end architecture rtl;
```

Read it against the Concepts section — every branch should now be a
sentence you've already heard. Details worth a second look:

- **The generics are the pinned integration defaults** from the curriculum;
  `theremin_top` (lesson 14) instantiates `pitch_map` with no generic map
  at all. Change your tuning by all means — in Explore — but the shipped
  defaults are contract.
- **`W_CALC` is computed, not guessed**: the widest intermediate is a
  (CNT_BITS+1)-bit signed difference shifted left SHIFT with one growth
  bit, floored at 34 so the fcw constants (31 bits max) always fit with
  sign margin. Lesson 03's rule — size for the worst case, in a constant,
  derivation in a comment — not a hopeful 32.
- **Variables, on purpose.** `diff → summed → target → delta → step` must
  complete inside one clock edge; variables update immediately in
  sequence, exactly the semantics wanted (signals would compute this
  edge's step from *last* edge's target). In synthesis they are wires in
  one combinational cloud feeding the `fcw_r` register — not state.
- **Everything happens under `valid`** — the house-style clock enable.
  Between strobes the module holds fcw; the NCO never sees a
  mid-computation value.

**File: course/work/lesson13/pitch_map_tb.vhd**

```vhdl
-- pitch_map_tb.vhd — self-checking testbench for pitch_map.
--
-- Verification approach: every assert is tagged with the requirement it
-- verifies (R1..R4 from pitch_map.vhd). Expected values are recomputed in
-- the TB with plain integer math (the map is exactly linear-then-clamped),
-- so the checks are exact equalities, not tolerances — the smoothing
-- converges to the target with zero residual, and we hold each period long
-- enough (many valid strobes) for it to get there.
--
-- Two DUT instances: `dut` uses the pinned generic defaults throughout.
-- With those defaults the FCW_MAX clamp is unreachable — the steepest
-- physical case (period = 1) maps to 339336, still below FCW_MAX = 374561;
-- the top clamp is headroom, not an active limit. To prove the clamp logic
-- itself, `dut_hi` overrides only SHIFT (6 -> 8), steepening the slope so
-- period = 1 maps far above FCW_MAX. Both instances share all stimulus.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pitch_map_tb is
end entity pitch_map_tb;

architecture sim of pitch_map_tb is
  -- pinned generic defaults, restated for the TB's own expected-value math
  constant CNT_BITS : positive := 24;
  constant SHIFT    : natural  := 6;
  constant P_REF    : positive := 3840;
  constant FCW_BASE : positive := 93640;
  constant FCW_MIN  : positive := 46820;
  constant FCW_MAX  : positive := 374561;
  constant SHIFT_HI : natural  := 8;  -- dut_hi only: makes FCW_MAX reachable

  constant CLK_PER : time := 83.333 ns;  -- 12 MHz

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal period : unsigned(CNT_BITS - 1 downto 0) := (others => '0');
  signal valid  : std_logic := '0';
  signal fcw    : unsigned(31 downto 0);
  signal fcw_hi : unsigned(31 downto 0);
  signal done   : boolean := false;

  -- the ideal map: linear in period, then clamped. Callers keep
  -- period_val small enough that the integer math cannot overflow.
  function expected(period_val : natural; shift_val : natural) return natural is
    variable t : integer;
  begin
    t := FCW_BASE + (P_REF - period_val) * 2 ** shift_val;
    if t < FCW_MIN then
      t := FCW_MIN;
    end if;
    if t > FCW_MAX then
      t := FCW_MAX;
    end if;
    return t;
  end function;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.pitch_map  -- pinned defaults, as theremin_top will use
    port map (
      clk    => clk,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw
    );

  dut_hi : entity work.pitch_map  -- steeper slope: exercises the FCW_MAX clamp
    generic map (SHIFT => SHIFT_HI)
    port map (
      clk    => clk,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw_hi
    );

  main : process
    -- one measurement: valid high for 1 clk, then a 3-clk gap, mimicking
    -- freq_meas strobes (spread out, never back-to-back).
    procedure pulse_valid(n : positive) is
    begin
      for i in 1 to n loop
        valid <= '1';
        wait until rising_edge(clk);
        valid <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;  -- let the last post-edge value settle
    end procedure;

    -- apply a period and give the smoothing n measurements to converge
    procedure settle(period_val : natural; n : positive) is
    begin
      period <= to_unsigned(period_val, CNT_BITS);
      wait until rising_edge(clk);
      pulse_valid(n);
    end procedure;

    variable prev_fcw : natural;
    variable exp_fcw  : natural;
    variable steps    : natural;
  begin
    -- ------------------------------------------------------------------
    -- R1: period = P_REF -> fcw = FCW_BASE (reset preload and settled).
    -- ------------------------------------------------------------------
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert fcw = FCW_BASE
      report "R1 FAIL: reset did not preload fcw with FCW_BASE"
      severity error;
    rst <= '0';
    settle(P_REF, 8);
    assert fcw = FCW_BASE
      report "R1 FAIL: period=P_REF gave fcw=" & integer'image(to_integer(fcw)) &
             " expected FCW_BASE=" & integer'image(FCW_BASE)
      severity error;
    report "R1 pass: reset preloads FCW_BASE and period=" & integer'image(P_REF) &
           " holds fcw=" & integer'image(FCW_BASE);

    -- ------------------------------------------------------------------
    -- R2: strictly decreasing fcw for increasing period, exact linear
    -- law, across an unclamped sweep straddling P_REF.
    -- ------------------------------------------------------------------
    prev_fcw := natural'high;
    for p in 16 to 22 loop  -- periods 3200, 3400, ... 4400
      settle(p * 200, 150);
      exp_fcw := expected(p * 200, SHIFT);
      assert to_integer(fcw) = exp_fcw
        report "R2 FAIL: period=" & integer'image(p * 200) &
               " fcw=" & integer'image(to_integer(fcw)) &
               " expected=" & integer'image(exp_fcw)
        severity error;
      assert to_integer(fcw) < prev_fcw
        report "R2 FAIL: fcw not strictly decreasing at period=" &
               integer'image(p * 200)
        severity error;
      report "R2 pass: period=" & integer'image(p * 200) &
             " fcw=" & integer'image(to_integer(fcw)) & " (exact, decreasing)";
      prev_fcw := to_integer(fcw);
    end loop;

    -- ------------------------------------------------------------------
    -- R3: clamping. A huge period (hand far / glitch) pins the default
    -- instance at FCW_MIN; the arithmetic survives period >> P_REF because
    -- the difference is signed. The steep dut_hi instance proves FCW_MAX.
    -- ------------------------------------------------------------------
    settle(2 ** CNT_BITS - 1, 250);
    assert fcw = FCW_MIN
      report "R3 FAIL: extreme period gave fcw=" & integer'image(to_integer(fcw)) &
             " expected clamp FCW_MIN=" & integer'image(FCW_MIN)
      severity error;
    report "R3 pass: period=" & integer'image(2 ** CNT_BITS - 1) &
           " clamps fcw at FCW_MIN=" & integer'image(FCW_MIN);

    settle(1, 250);
    exp_fcw := expected(1, SHIFT);  -- 339336: below FCW_MAX, top clamp is headroom
    assert to_integer(fcw) = exp_fcw
      report "R3 FAIL: period=1 gave fcw=" & integer'image(to_integer(fcw)) &
             " expected unclamped " & integer'image(exp_fcw)
      severity error;
    assert fcw_hi = FCW_MAX
      report "R3 FAIL: period=1 at SHIFT=8 gave fcw=" &
             integer'image(to_integer(fcw_hi)) &
             " expected clamp FCW_MAX=" & integer'image(FCW_MAX)
      severity error;
    report "R3 pass: period=1 stays unclamped at default slope (fcw=" &
           integer'image(exp_fcw) & "), clamps at FCW_MAX=" &
           integer'image(FCW_MAX) & " with SHIFT=" & integer'image(SHIFT_HI);

    -- ------------------------------------------------------------------
    -- R4: smoothing step response. From a settled FCW_BASE, step the
    -- period; the first measurement must move fcw only part way (proof of
    -- smoothing), then the trajectory must be monotonic and converge to
    -- the new target exactly.
    -- ------------------------------------------------------------------
    settle(P_REF, 250);
    exp_fcw := expected(P_REF + 200, SHIFT);  -- step target: 80840
    settle(P_REF + 200, 1);                   -- exactly one measurement
    assert to_integer(fcw) < FCW_BASE and to_integer(fcw) > exp_fcw
      report "R4 FAIL: first measurement after step gave fcw=" &
             integer'image(to_integer(fcw)) &
             " (expected strictly between " & integer'image(exp_fcw) &
             " and " & integer'image(FCW_BASE) & ")"
      severity error;
    prev_fcw := to_integer(fcw);
    steps    := 1;
    while to_integer(fcw) /= exp_fcw and steps < 200 loop
      pulse_valid(1);
      steps := steps + 1;
      assert to_integer(fcw) <= prev_fcw and to_integer(fcw) >= exp_fcw
        report "R4 FAIL: non-monotonic step response, fcw=" &
               integer'image(to_integer(fcw)) & " after " &
               integer'image(steps) & " measurements"
        severity error;
      prev_fcw := to_integer(fcw);
    end loop;
    assert to_integer(fcw) = exp_fcw
      report "R4 FAIL: did not converge to " & integer'image(exp_fcw) &
             " within 200 measurements (fcw=" &
             integer'image(to_integer(fcw)) & ")"
      severity error;
    report "R4 pass: step to period=" & integer'image(P_REF + 200) &
           " converged exactly to fcw=" & integer'image(exp_fcw) &
           " in " & integer'image(steps) &
           " measurements, first step partial";

    report "pitch_map testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Verification decisions worth naming, because you'll reuse them:

- **Exact equality, no tolerances.** Lesson 10 needed ±2 counts because it
  measured an asynchronous oscillator through quantizing windows.
  `pitch_map` is pure synchronous integer arithmetic — if it's off by one
  LSB, it's *wrong*, and the `expected()` function recomputes the spec's
  math independently so the DUT is checked against the requirement, not
  against itself.
- **Two DUTs, one honest reason.** With the pinned defaults the FCW_MAX
  clamp is unreachable — period = 1 maps to 339336, under the clamp — so a
  single-instance TB would ship an untested `elsif`. Rather than bend the
  defaults, `dut_hi` overrides only SHIFT (6→8) to steepen the slope until
  period = 1 lands far above FCW_MAX. Coverage of dead-in-config logic by
  generic override is a standard trick; the alternative (delete the
  "unreachable" clamp) is how designs die the day someone retunes SHIFT.
- **Stimulus mimics the producer.** `pulse_valid` spaces strobes out,
  never back-to-back, because `freq_meas` never emits them back-to-back;
  `settle` grants the smoother enough measurements to converge — 150 for
  the sweep, 250 before clamp checks — sized from the time constant
  (~8·ln(Δ) measurements for a step of Δ), not by trial and error.
- **R4 proves smoothing three ways**: the first post-step measurement must
  land strictly *between* old and new pitch (catches a filter that isn't
  there), the trajectory must be monotonic (catches overshoot), and it
  must reach the target exactly (catches the deadband the nudge kills) —
  with the step count reported so you can eyeball it against theory.

**File: course/work/lesson13/Makefile**

```make
# Lesson 13 solutions — pitch_map. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# pitch_map is synthesized as part of theremin_top in lesson14, not here.

TB         = pitch_map_tb
SRC        = pitch_map.vhd pitch_map_tb.vhd
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

The lesson 10 pattern exactly, minus one source file. No synthesis targets
on purpose: `pitch_map` is synthesized where it's used, inside
`theremin_top` in lesson 14. `SRC` order is load-bearing as always —
`pitch_map.vhd` before the TB that instantiates it twice.

## Run

From `course/work/lesson13/` (with the toolchain environment sourced — the
`fpga` alias from lesson 00 does this):

```bash
make sim
```

Expected output (a `mkdir -p build` line precedes this on the first run):

```text
ghdl -a --std=08 --workdir=build pitch_map.vhd pitch_map_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/pitch_map_tb pitch_map_tb
./build/pitch_map_tb --assert-level=failure
pitch_map_tb.vhd:125:5:@2875988500fs:(report note): R1 pass: reset preloads FCW_BASE and period=3840 holds fcw=93640
pitch_map_tb.vhd:145:7:@52959121500fs:(report note): R2 pass: period=3200 fcw=134600 (exact, decreasing)
pitch_map_tb.vhd:145:7:@103042254500fs:(report note): R2 pass: period=3400 fcw=121800 (exact, decreasing)
pitch_map_tb.vhd:145:7:@153125387500fs:(report note): R2 pass: period=3600 fcw=109000 (exact, decreasing)
pitch_map_tb.vhd:145:7:@203208520500fs:(report note): R2 pass: period=3800 fcw=96200 (exact, decreasing)
pitch_map_tb.vhd:145:7:@253291653500fs:(report note): R2 pass: period=4000 fcw=83400 (exact, decreasing)
pitch_map_tb.vhd:145:7:@303374786500fs:(report note): R2 pass: period=4200 fcw=70600 (exact, decreasing)
pitch_map_tb.vhd:145:7:@353457919500fs:(report note): R2 pass: period=4400 fcw=57800 (exact, decreasing)
pitch_map_tb.vhd:160:5:@436874252500fs:(report note): R3 pass: period=16777215 clamps fcw at FCW_MIN=46820
pitch_map_tb.vhd:174:5:@520290585500fs:(report note): R3 pass: period=1 stays unclamped at default slope (fcw=339336), clamps at FCW_MAX=374561 with SHIFT=8
pitch_map_tb.vhd:210:5:@623790171500fs:(report note): R4 pass: step to period=4040 converged exactly to fcw=80840 in 60 measurements, first step partial
pitch_map_tb.vhd:215:5:@623790171500fs:(report note): pitch_map testbench complete (any FAILs are listed above)
```

(Your home directory will differ in the shim path.) Read the numbers, not
just the word "pass":

- **R2's fcw values fall by exactly 12800 per line** — 200 period counts ×
  2^6. The linear law, visible as a constant first difference; any
  curvature here would mean the arithmetic isn't the spec.
- **R4 converges in 60 measurements** against a naïve geometric estimate
  of log(12800)/log(8/7) ≈ 71: the floor-toward-−∞ shift steps slightly
  harder than delta/8 on negative errors (it's a ceiling on the
  magnitude), so real convergence beats the idealized filter. Rounding
  direction is *visible in the step count* — integer DSP in one number.
- **The whole run simulates 624 µs.** Lesson 10 waited out real 320 µs
  measurement windows; this TB strobes `valid` every 4 clocks, because the
  smoother counts *measurements*, not time. Testing at the interface
  contract rather than at physical rate is why unit TBs stay fast —
  lesson 14's integration TB pays the real-time price exactly once.

## Explore

Attempt these before peeking at `course/solutions/lesson13/`.

1. **Turn the smoothing knob.** Set `SMOOTH_SHIFT` to 0 and `make sim`:
   R4's first assert fails, because the first measurement lands *on* the
   target — with α = 1, the filter isn't there, and the TB was built to
   notice a missing filter, not just a broken one. Now try 6 (α = 1/64):
   R4 fails differently — "did not converge... within 200 measurements",
   since a 12800-count step at α = 1/64 needs ≈ log(12800)/log(64/63)
   ≈ 600 measurements ≈ 0.2 s of real playing time. You'd hear that as an
   instrument that swims. Somewhere between "fizz" (0) and "syrup" (6)
   sits 3; restore it.
2. **Break it: remove the nudge.** Delete the three-line
   `if step = 0 and delta > 0` fix and predict before running: the first
   *upward* settle is R2's period = 3200 (target 134600, approached from
   93640 below), and the filter will park where the positive error first
   shifts to zero — at delta = 7, so fcw = 134593. Run: `R2 FAIL:
   period=3200 fcw=134593 expected=134600`. Seven LSBs flat, forever —
   about 20 mHz of pitch, inaudible, and exactly the kind of "harmless"
   deadband that becomes a limit cycle in a filter with feedback gain.
   Restore the nudge.
3. **Flip the sign, meet the contract.** Make the instrument respond like
   a classical theremin (hand in, pitch *up*) by swapping the difference:
   `diff := signed('0' & period) - to_signed(P_REF, CNT_BITS + 1);`.
   R1 still passes — at period = P_REF the sign is invisible — then R2
   fails instantly (fcw = 52680 at period 3200, rising thereafter). A
   unilateral spec change looks exactly like a bug, which is the point:
   direction-of-response is a contract with `theremin_top` and lesson 99's
   tuning procedure, not a private aesthetic. Restore, and note what a
   real change request touches: curriculum, module, TB — in that order.
4. **Steepen the slope, hit the wall.** Change SHIFT's default to 7 in
   `pitch_map.vhd` *and* the TB constant to match, then predict the new
   R2 line values (first differences become 25600) before running — all
   checks still pass, because `expected()` recomputes the spec including
   the clamp, and the last sweep line now reads fcw=46820: period 4400
   maps to 21960, and the clamp caught it. Find the wall on paper: at
   SHIFT = 7, FCW_MIN is reached at period = 3840 + 46820/128 ≈ 4206,
   *inside* the hand's physical range (full reach ≈ 4267) — the last
   stretch of reach plays a constant C3. Steeper slope buys range and
   spends headroom; the clamps silently became part of the playable
   instrument. Restore 6.

## Tips & Pitfalls

- **Emacs / vhdl-mode:** this lesson's identifiers are long and repetitive
  (`SMOOTH_SHIFT`, `FCW_BASE`, `prev_fcw`…). `M-/` (dabbrev-expand)
  completes any of them from what's already in the buffer — type `SM`,
  hit `M-/`, done; hit it again to cycle candidates. Faster than
  vhdl-mode's stored templates for names you just wrote three lines up,
  and it works in comments too, where the requirement tags live.
- **Toolchain gotcha — `maximum` is VHDL-2008.** The `W_CALC` constant
  uses the 2008 predefined `maximum` function. Compile without `--std=08`
  (say, by invoking ghdl by hand and forgetting the flag the Makefile
  always passes) and GHDL stops with `no declaration for "maximum"` —
  the course's standing reminder that the flags are part of the design.
- **numeric_std subtraction wraps, silently, by design.** `P_REF - period`
  with both operands unsigned is legal, compiles clean, simulates without
  warnings, and is catastrophically wrong for half the input range. There
  is no lint for "you meant that signed"; the defense is the habit this
  module models — at every subtraction, ask *can the true answer be
  negative?*, and if yes, widen into signed before, not after.
- **The TB's `wait for 1 ns` is load-bearing.** After the last clock edge
  of a stimulus, asserting immediately would read fcw's *pre-edge* value —
  the process and the DUT saw the same edge in the same delta cycle. The
  1 ns settle steps past the edge so asserts sample what the hardware
  actually registered.
- **Smooth after the clamp, not before** (and not on `period`). The
  orderings are equivalent in normal play, but only clamp-then-smooth
  bounds what a glitch can do to the filter state: target is provably in
  [FCW_MIN, FCW_MAX] before it touches fcw. Filter placement around
  nonlinearities is a real design decision, not refactoring noise.

## Checkpoint

Before lesson 14 you must have:

- `course/work/lesson13/` containing `pitch_map.vhd`, `pitch_map_tb.vhd`,
  and the `Makefile`, with `make sim` printing `R1 pass` through
  `R4 pass` (R2 sweeping fcw 134600 down to 57800, R4 converging to
  80840 in 60 measurements) and the completion message — no `FAIL` lines.
- On paper, from memory: fcw(f) = f·2^32/f_clk evaluated at C4 (93639.45,
  pinned as FCW_BASE = 93640, ≈ 1.5 mHz sharp),
  and the slope chain: 1 period count → 2^SHIFT fcw counts → ≈ 0.18 Hz.
- The honesty paragraph in one breath: which stages of hand→pitch are
  nonlinear (hand→C, 1/period, the log ear), what the linear map's error
  looks like (smooth scale compression, ≤ ~11% at full reach, never
  non-monotonic), and why that's acceptable in this instrument.
- The smoothing loop as α-filter: α = 1/8, τ ≈ 7.5 measurements ≈ 2.4 ms,
  and a one-sentence explanation of why the +1 nudge exists.
- The radar mapping stated without notes: calibration curve ↔ pitch map
  (with residual error budgeted, not hidden), alpha filter ↔ smoothing,
  deadband/limit cycle ↔ the stalled integer filter of Explore 2.

Next: lesson 14 — no new arithmetic, no new concepts, just the hard part:
wiring seven verified modules into `theremin_top`, watching an integration
TB move a simulated hand, and making the whole instrument fit, time, and
sing on both boards.
