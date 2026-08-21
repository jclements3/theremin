# Radar Interlude 1 — From NCO to Chirp Radar

*Where we are.* Four lessons in, you have a verified numerically controlled
oscillator: `nco.vhd`, fifty-odd lines that turn a frequency control word
into a pitch, with a testbench that proves the frequency property to ±1 edge
for any fcw. Lesson 04 closed by calling that module a radar exciter's
beating heart. This interlude cashes the claim. No code to write, nothing to
run — one sitting with the math, showing that the distance between your
accumulator and the waveform generator of an FMCW radar is *one more
accumulator*, and that every design number you computed in lessons 03 and 04
reappears in a chirp designer's budget under a different name.

## What you own so far

Inventory first, because everything below is built from it:

- **The DDS equation**, derived, not memorized: f_out = fcw · f_clk / 2^W.
  At your numbers (f_clk = 12 MHz, W = 32) that's fcw × 2.794 mHz.
- **A frequency grid** with uniform spacing Δf = f_clk / 2^W ≈ 2.8 mHz —
  the resolution you computed in lesson 04 and hit A440 with, using
  fcw = 157482 for 439.99963 Hz (the constant lesson 03 taught you to
  compute at elaboration time with `math_real`, to zero gates).
- **Phase truncation jitter**: output edges land only on clock edges, each
  early or late by less than one clock period, error never accumulating —
  the 46/47-clock alternation you measured with GTKWave markers at
  fcw = 700.
- **Phase-continuous retuning**: change fcw mid-flight and the accumulator
  just changes slope. No transient, no glitch. Lesson 04 previewed the
  payoff — the finished theremin retunes this NCO about 180 times a second
  without a click.
- **A verification property**: over any K clocks, observed rising edges are
  within ±1 of K · fcw / 2^W, because the phase register is exact integer
  arithmetic and only your view of it (the MSB) is truncated.

Radar needs exactly one thing your theremin doesn't: a frequency that
*sweeps* instead of sits.

## One more accumulator: ramping the ramp

Your NCO integrates frequency into phase: each clock, phase advances by
fcw. To make frequency itself ramp linearly, apply the same trick one level
up — each clock, advance fcw by a constant. Call it the chirp rate word:

```
            chirp rate word (crw)
                    |
                    v
          +---------------------+
   clk -->|  slope accumulator  |     new: fcw <= fcw + crw
          +---------------------+
                    |
                    v   fcw(n) = fcw0 + n*crw
          +---------------------+
   clk -->|  phase accumulator  |     lesson 04's nco.vhd, unmodified —
          +---------------------+     fcw was a port, not a generic,
                    |                 precisely so something upstream
                    v                 could rewrite it every clock
        phase --> (sine LUT, lesson 07) --> DAC --> antenna
```

This is why the dissection made a point of `fcw` being a port: the theremin
rewrites it 180 times a second, a chirp generator rewrites it *every clock
cycle*, and `nco.vhd` cannot tell the difference. The module you typed in is
the bottom box, verbatim.

Now do the math the lesson-04 way — no hand-waving. After n clocks the
frequency word is fcw(n) = fcw0 + n · crw, so the instantaneous output
frequency is linear in time:

```
f(n) = (fcw0 + n*crw) * f_clk / 2**W
```

and the phase is the running sum of the frequency words:

```
p(n) = p0 + sum(fcw0 + k*crw, k = 0 .. n-1)
     = p0 + n*fcw0 + crw * n(n-1)/2        (mod 2**W)
```

Quadratic phase. Compare the textbook linear-FM waveform,
φ(t) = 2π (f₀t + S·t²/2): same shape, with n(n−1)/2 standing in for t²/2.
Two integrators in a row — slope accumulates into frequency, frequency
accumulates into phase — and both are *exact* integer arithmetic. Hold that
word, exact; it is about to become the whole sales pitch.

## Chirp vocabulary: B, T_c, S

Three numbers define a linear FM (LFM) chirp:

```
 f
 |      /|      /|      /|        B   = swept bandwidth (Hz)
 | f1  / |     / |     / |        T_c = chirp (sweep) duration (s)
 |    /  |    /  |    /  |        S   = B / T_c = slope (Hz/s)
 | f0/   |   /   |   /   |
 +---|---|----------------> t     sawtooth: sweep, snap back, repeat
     |<->|
      T_c
```

Design one on your hardware, with your numbers. Sweep B = 1 MHz in
T_c = 10 ms, so S = 10⁸ Hz/s. What crw does that take? Per clock, frequency
must step by S / f_clk = 10⁸ / 12×10⁶ = 8.33 Hz, and each fcw count is
worth Δf = 2.794 mHz, so:

```
crw = S * 2**W / f_clk**2  =  1e8 / 0.033528e6  ≈  2983
```

Sanity-check it like the lesson-04 Run section checked edge counts. The
sweep lasts T_c · f_clk = 120 000 clocks; fcw travels
120 000 × 2983 ≈ 3.58 × 10⁸ counts; times 2.794 mHz per count is
1.0001 MHz. The design closes to a tenth of a percent, and the residual is
pure crw rounding — we'll price that exactly in a moment.

Note what the accumulator does at the top of the sawtooth if you let it run:
fcw wraps mod 2^W, which lesson 04's Explore 2 taught you to read as a
*negative* frequency — the sweep would alias and fold. A real chirp
generator reloads fcw0 at the end of each sweep (a comparator and a mux, in
the fabric you already know how to write) and keeps the whole ramp below
the Nyquist corner, f_clk/2, for exactly the reason your fcw = 2^(W−1)
testbench corner exists.

## Why linearity is the whole game: dechirp

Here is the move that makes FMCW radar work, and it is the same move your
theremin will make in lesson 12: multiply what you sent by what you got
back, and keep the difference frequency.

The echo from a target at range R arrives after a round trip
τ = 2R/c. While it was in flight, the transmitter kept sweeping — so the
received chirp is the transmitted chirp slid right by τ, and at any instant
the two differ in frequency by a *constant*:

```
 f
 |        TX      RX
 |        /       /
 |       /       /
 |      /--f_b--/         constant vertical gap:
 |     /       /
 |    /       /              f_b = S * tau = S * 2R / c
 +---+---+----------> t
     0   tau
```

Mix them (lesson 12 will do this with an XOR gate and an
accumulate-and-dump — the same architecture, one bit wide) and a target at
range R becomes a steady tone at f_b. **Range becomes pitch.** A theremin
turns hand position into a tone; an FMCW radar turns target range into a
tone; the block diagrams differ by a time delay.

Worked numbers, continuing the design above (S = 10⁸ Hz/s): a target at
150 m gives τ = 1.0 µs and f_b = 100 Hz. At 300 m, 200 Hz. Every 150 m of
range is another 100 Hz of beat.

Now, how finely can you resolve that tone? You already know — you proved it
to yourself in lesson 04's Explore 4, when the A440 word at W = 32 produced
0.73 expected edges in a 20 000-clock window and verified almost nothing.
*Observation time buys frequency resolution.* You observe the beat for one
sweep, T_c, so you can resolve beat frequencies no finer than about 1/T_c.
Convert that through f_b = 2RS/c:

```
ΔR = c * Δf_b / (2S)  =  c / (2 * S * T_c)  =  c / (2B)
```

The sweep time cancels. **Range resolution depends only on swept
bandwidth.** For our 1 MHz sweep: ΔR = 3×10⁸ / 2×10⁶ = 150 m — and indeed
1/T_c = 100 Hz of beat resolution is exactly one 150 m step. Want 1 m
cells, enough to separate a drone from the tree line behind it? B = 150 MHz.
Want 0.5 m? 300 MHz. Nobody escapes c/2B; it is the reason radar engineers
spend their lives begging for bandwidth.

One more classical result, free of charge: the receiver compresses the
whole T_c-long transmission into a peak about 1/B wide, a compression
factor of B·T_c — the time-bandwidth product. Our modest design has
B·T_c = 10⁴, i.e. 40 dB of processing gain, which is how a radar spreads
its energy thinly in time (cheap, low peak power) yet resolves sharply in
range. A sine-wave theremin has B·T_c ≈ 1. Sweeping is what buys the
factor of 10 000.

But every bit of that argument leaned on the gap f_b being *constant*,
which required the sweep to be *linear*. If the sweep slope wanders during
the chirp, f_b wanders with it, the target's tone smears across several
resolution cells, peaks drop, sidelobes rise, and the c/2B you paid
bandwidth for is quietly repossessed. Chirp linearity error is range
resolution error. Which brings us back to your accumulator.

## The design grid: what W buys a sweep designer

An analog chirp is a VCO driven by a voltage ramp, and a varactor's
frequency-vs-voltage curve is about as linear as a theremin player's left
hand — real FMCW front ends built that way need measured predistortion or a
closed-loop linearizer to tame it. Your two-accumulator chirp needs
nothing, because it is not *approximately* linear; it is linear by
construction, in exact integer arithmetic, to the granularity of the grid.
The only approximations are quantizations you can enumerate:

- **Frequency grid.** f(n) only visits multiples of Δf = f_clk/2^W =
  2.8 mHz. The "staircase" of our worked chirp climbs in 8.33 Hz per-clock
  steps, each lasting 83 ns — every step 8.3 ppm of the 1 MHz sweep.
- **Slope grid.** crw is an integer, so achievable slopes come in multiples
  of f_clk²/2^W = (12×10⁶)²/2³² ≈ 33.5 kHz/s. Rounding 2982.6 to 2983
  changed our slope by 127 ppm. Note what kind of error that is: the sweep
  is *still perfectly linear*, just at a fractionally different slope — a
  range *scale* error (127 ppm of 150 m is 2 cm, calibrated out in one
  constant), not a smearing nonlinearity. The distinction between "wrong by
  a known scale factor" and "wrong differently at every instant" is the
  distinction between a calibration line item and a ruined point-spread
  function.
- **Phase truncation.** The 46-vs-47-clock jitter you measured is still
  there, and when the top bits of phase address a sine table it becomes
  discrete spurs. Lesson 07 sizes this properly; the radar reading is
  below.

Widen W and both grids shrink together — that is all W does, exactly as the
lesson 04 dissection said ("the one design knob, and it *only* sets
frequency resolution"). It costs one carry chain. This is why real exciter
chips carry 32- and 48-bit accumulators: not because anyone needs
millihertz audio, but because chirp *slope* granularity inherits a factor
of f_clk/2^W and radar range calibration inherits the slope.

## Spurs are false targets

Lesson 04 said it in one line; here is the mechanism, since for a radar it
is the difference between a clean screen and a haunted one. Periodic timing
error in the time domain is discrete spurious tones in the frequency
domain. Your fcw = 700 measurement — half-periods alternating 46, 47, 46,
47 in a repeating pattern — is a deterministic, periodic error signal
riding on the carrier, and its spectrum is spurs at predictable offsets.

In the theremin, a spur 60 dB down is inaudible and nobody cares. In the
dechirp receiver above, *every tone in the IF is read as a target at some
range*. A spur on the transmitted chirp mixes down like any real echo and
paints a target that isn't there — at a range that tracks the spur offset.
A counter-UAS radar hunting small, slow returns near the noise floor
cannot afford ghosts of its own manufacture, so exciter datasheets lead
with spurious-free dynamic range, and the spur budget starts from exactly
the arithmetic you did with two GTKWave markers. The rule of thumb you'll
derive in lesson 07: keeping P bits of phase for the sine lookup puts the
worst truncation spur near −6P dBc — your 10-bit LUT address lands around
−60 dBc — and the budget for how much phase to keep is the second half of
the jitter analysis you already did.

## Verifying a chirp (your ±1 property survives)

A last connection, because this course cares as much about evidence as
about hardware. The lesson 04 testbench never compared against a golden
trace; it proved |edges − K·fcw/2^W| ≤ 1 from the exactness of integer
phase travel. Reread that proof and notice what it did *not* use: it never
assumed fcw was constant. The thresholds are fixed points on the phase
line, and over K clocks the phase travels exactly

```
K*fcw0 + crw*K(K-1)/2
```

so the same interval-counting argument gives, for any chirp, any starting
phase, any window:

```
| edges_observed - (K*fcw0 + crw*K(K-1)/2) / 2**W |  <=  1
```

The property generalizes because the *design* is exact — verification
rides on the same fact that makes the chirp linear. When you eventually
write a chirp generator's testbench, it will be lesson 04's `check_freq`
with one extra term in `expected`, requirement-tagged R1 in the same
DO-254-lite style lesson 02 taught, and it will need no tolerance tuning
for the same reason. Designs built on exact arithmetic hand you their own
proofs; this is not a coincidence, and it is worth saying out loud in any
document a certification-minded reviewer will read.

## Scaling up: from 12 MHz fabric to an exciter

Nothing above needed your clock to be 12 MHz. A commercial DDS exciter
part is your two accumulators (typically W = 32 or 48) plus lesson 07's
sine table plus a fast DAC, clocked at a GHz instead of 12 MHz; its output
chirp is then mixed up to X-band or Ka-band by the heterodyne architecture
you'll build in miniature in lesson 12. The equations don't change —
f_out = fcw·f_clk/2^W, slope grid f_clk²/2^W — only the numbers scale.
And the phase-continuity property you observed when fcw changed mid-sim
becomes an operational feature: a radar can hop carrier frequency, switch
chirp slope between sweeps, or interleave waveforms for different targets,
all without a phase transient, because an accumulator retuned is just an
accumulator with a new slope. The theremin uses that property to avoid
clicks; an agile radar uses it to change its question between one sweep
and the next.

Where this thread goes next in the course: lesson 10 measures frequency
with a gate and meets dwell time as a hardware quantity (interlude 2 turns
that into CPIs and Doppler bins); lesson 12 builds the mixer and dechirp's
multiply becomes something you can simulate; interlude 3 assembles the
full theremin-is-a-CW-radar map. The chirp itself is the one block the
theremin never needs — which is why it got an interlude instead of a
lesson.

## SBIR Notebook

Talking points this material supports, for counter-UAS proposal work:

- **Digitally generated LFM is linear by construction.** A two-accumulator
  DDS chirp has no analog of VCO tuning nonlinearity; residual errors are
  enumerable quantizations (frequency grid f_clk/2^W, slope grid
  f_clk²/2^W) that appear as calibratable scale factors, not
  range-response smearing. This directly protects the c/2B range
  resolution needed to separate small UAS from adjacent clutter, and it is
  an architecture argument, not a component selection.
- **Bandwidth is the price of discrimination.** ΔR = c/2B is
  waveform-design law: sub-meter range cells for group-of-small-UAS
  separation imply hundreds of MHz of swept bandwidth, driving spectrum
  requests, front-end selection, and processing rates. A proposal that
  budgets B against required resolution — and shows the sweep-time
  independence — reads as written by someone who has done the derivation.
- **Exciter spurs are false targets, and they can be budgeted from first
  principles.** Phase-truncation spur levels follow from accumulator and
  LUT word sizes (≈ −6 dBc per retained phase bit), so SFDR against
  small-RCS detection thresholds is a paper calculation before any
  hardware exists — the kind of quantified risk-retirement SBIR reviewers
  reward.
- **Phase-continuous frequency agility is free in a DDS architecture.**
  Slope changes, frequency hops, and waveform interleave incur no settling
  transient, enabling adaptive dwell scheduling against pop-up UAS tracks
  without exciter dead time — a capability claim grounded in the
  accumulator's arithmetic, demonstrable in simulation.
- **Property-based, requirement-tagged verification scales with the
  design.** The ±1-edge frequency property proven for a fixed tone extends
  unchanged to chirps because the arithmetic is exact; evidence of this
  style (requirements → tagged asserts → logged results) maps onto DO-254
  expectations and is producible with a version-pinned open toolchain —
  a credibility line for firmware deliverables.
