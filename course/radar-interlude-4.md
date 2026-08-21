# Radar Interlude 4 — From Instrument to Sensor: Toward Counter-UAS

*Where we are.* Lesson 14 left you holding a finished instrument: 495
logic cells, 168 flip-flops you can name from memory, a 27.98 ns critical
path in an 83.3 ns budget, and a black-box system sign-off that agrees
with three composed module contracts to a tenth of a percent. Interlude 3
argued that this instrument already *is* a CW radar. This interlude asks
the harder question: what separates the radar you have from a radar that
could sit on a rooftop and call out small drones? The answer is shorter
than you'd guess — two new blocks and one new intuition — and every one
of them is a direct extension of hardware you have already built,
simulated, and audited. No code today; one sitting of reading and
arithmetic. The goal is that when `fpga/ROADMAP.md` says "Phase 6: FFT +
CFAR," you see not a wall of new material but the last mile of a road
you are most of the way down.

## The sensor you already own

Take inventory in radar vocabulary. Everything on the left you have
built and verified (one row awaits lesson 99's bench); everything on the
right is what the same block is called in a counter-UAS sensor's block
diagram:

```
  what you built                          what a radar engineer calls it
  ---------------------------------      -------------------------------
  74HC14 osc + antenna (lesson 99)       RF front end (transducer)
  sync_2ff            (lesson 09)        async-domain border checkpoint
  freq_meas, EDGES=64 (lesson 10)        dwell/CPI engine, 1 report/CPI
  pitch_map           (lesson 13)        calibration curve + alpha tracker
  nco                 (lesson 04)        DDS / STALO
  sine_lut            (lesson 07)        waveform memory
  dsm_dac             (lesson 08)        exciter DAC (noise-shaped)
  het_mixer           (lesson 12)        receiver mixer + boxcar LPF
  uart_tx             (lesson 11)        instrumentation / data link
  osc_model + system TB (lesson 14)      target generator + range sign-off
```

That is not a loose analogy — you priced each row when you built it.
`freq_meas` delivers a fresh measurement every 320 µs with ~52 Hz of
resolution, 3125 reports per second, and lesson 10 proved the product
T·Δf is a constant of the hardware. `het_mixer` downconverts by XOR and
low-passes by accumulate-and-dump over 1024 clocks, publishing at
12 MHz/1024 = 11.72 kHz, and lesson 12 handed you its sinc frequency
response and its blindness to sign — the image problem. Lesson 14 taught
you to sign off the whole chain against a target model through the pins
alone. Keep all of it. Nothing gets thrown away.

What the chain lacks is exactly this: it can measure **one frequency**,
and it reports that frequency as a **pitch**, to a human. A sensor must
measure a **spectrum** — many frequencies at once — and report
**detections**, to a machine, with a false-alarm rate somebody signed
their name to. Those two gaps are the FFT bank and CFAR.

## One number is not a spectrum

Why can't `freq_meas` do the job? Because it doesn't measure frequency —
it measures *period*, by timestamping edges, and "the period of the
signal" is only a meaningful phrase when the signal is one periodic
thing. Point an HB100 (the $6 X-band Doppler module from the ROADMAP
shopping list, first met in lesson 12) at a room containing one walker
and your chain works today: the IF is a single audio-band tone at about
70 Hz per m/s of target speed, a comparator squares it up, and
`sync_2ff → freq_meas` measures gait instead of hand position.

Now add a second mover. The IF becomes the *sum* of two tones, and the
zero crossings of a sum of tones are not the zero crossings of either
one — they wander, merge, and vanish as the two components beat against
each other. Your edge counter doesn't degrade gracefully; it reports a
period that belongs to neither target. The theremin never met this
problem because a theremin has one hand-capacitance by construction. A
surveillance sensor's whole job is the many-signal case: two drones, a
drone and a bird, a drone and swaying foliage clutter.

```
     |X(f)|      what freq_meas assumes        what the rooftop gives you
        │
        │              █                          clutter   bird?  drone
        │              █                          ▄▄                █
        │              █                         ▐██▌   ▂▄▂   ▁    █▁▂
        └──────────────┴─────── f              ──┴──┴───┴─┴───┴────┴──── f
                 "the" frequency                  which one is "the"?
```

The fix is to stop asking "what is the frequency" and ask "how much
energy is at *each* frequency" — to estimate the spectrum. That is the
FFT's job, and you already own its core idea.

## The FFT bank: 256 copies of your mixer

Look at what one bin of a discrete Fourier transform computes over an
N-sample window:

```
X[k] = sum over n of  x[n] · e^(-j·2π·k·n/N)
```

Read it as hardware, not as math: multiply the input by a local
oscillator at bin frequency k·fs/N, then sum over the window —
**downconvert and accumulate-and-dump**. That is lesson 12's `het_mixer`,
verbatim, with two upgrades: the LO is complex (a sine *and* a cosine —
interlude 3's I/Q fix for the image problem, ROADMAP Phase 5), and there
are N of them in parallel, one per bin. A DFT is a bank of N copies of
the mixer you already built, each tuned one bin apart, each with the
same sinc response you computed for the 440 Hz beat. The FFT is "only"
the observation that the N mixers share almost all of their work: N²
multiplies collapse to (N/2)·log₂N butterflies.

Run the numbers on hardware rates you already own. Suppose the HB100's
IF is sampled at your accumulate-and-dump rate of 11.72 kHz (Phase 7's
MCP3202 ADC, or the dump stream itself) and you take N = 256 samples per
transform:

```
sample rate     fs   = 12 MHz / 1024        = 11.72 kHz
window (CPI)    T    = 256 / 11.72 kHz      = 21.8 ms
bin width       Δf   = fs / 256 = 1/T       = 45.8 Hz
uncertainty     T·Δf                        = 1        (lesson 10's law)
wavelength      λ    = c / 10.525 GHz       = 28.5 mm
Doppler slope   2/λ                         = 70.2 Hz per m/s
velocity bin    Δv   = λ / (2·T)            = 0.65 m/s
span (real fs)  0 .. fs/2 = 5.86 kHz        = 0 .. 83 m/s, sign unknown
```

Three things to sit with. First: T·Δf = 1 *still*. The FFT does not
cheat lesson 10's uncertainty product — 21.8 ms of observation buys
45.8 Hz of resolution, exactly what the law allows. What the FFT buys
that `freq_meas` cannot is **parallelism**: one 21.8 ms window is spent
on all 256 frequencies simultaneously instead of on one. Same dwell,
256 answers. That is why lesson 10 called dwell the scarcest resource
and why the FFT is how radar spends it.

Second: this is your CPI design, made real. Lesson 10's worked example
wanted a ~20 ms CPI for ~50 Hz Doppler bins; here it is, falling out of
a divider ratio you chose in lesson 12 for entirely different reasons,
giving 0.65 m/s velocity bins — fine enough to separate a walking
courier from a Group 1 quadcopter crossing at 15 m/s.

Third: the "sign unknown" line. With a real-valued input the spectrum is
mirror-symmetric and approaching folds onto receding — the image
problem, surviving intact from lesson 12. The cure is the same one named
there: quadrature. Phase 5's DDC (I/Q NCO, CIC decimator, compensating
FIR) makes the samples complex *before* the FFT, the spectrum becomes
one-sided, and Doppler gets its sign back: −83 .. +83 m/s.

And the cost? A serial radix-2 256-point FFT needs (256/2)·log₂256 =
1024 butterflies per transform. One time-shared butterfly datapath at
12 MHz does that in ~85 µs — against a 21.8 ms window. The FFT engine
for this problem *loafs*, running 250× faster than real time; a single
butterfly and a state machine suffice. Storage is 256 complex samples —
at 16 bits per component, 8 kbit, two of the iCE40's 4-kbit BRAMs — plus
a twiddle ROM that is nothing but `sine_lut` wearing a different job
title (lesson 07's quarter-wave fold works on twiddles too). The real
pinch on iCE40 is the butterfly's complex multiply: no hard multipliers,
so a 16×16 multiply is built from LUT4s and carry chains at a cost of
hundreds of logic cells — order of half your entire theremin, per
multiplier. That is the honest reason ROADMAP Phase 6 names the ECP5 on
a ULX3S as the on-ramp: same open toolchain, same Makefile shape, but
hard 18×18 multipliers and bigger BRAM, so the butterfly costs one DSP
block instead of half an instrument. Your hx8k build sits at 6%
utilisation; the fabric was never the obstacle — the missing multiplier
primitive is.

## CFAR: a threshold that budgets its own false alarms

An FFT per CPI gives you 256 magnitude numbers, 46 times a second. A
detector's job is to turn those into a short list of "target at bin k"
declarations — which means comparing each bin against a threshold. The
naive move is a constant: `if mag > 900 then detect`. Every part of your
training should now object. Against *what* noise floor? The floor moves
with receiver gain, temperature, and — fatally, outdoors — with clutter:
foliage in wind puts real, fluctuating energy in the low-velocity bins.
A constant threshold tuned on a quiet Tuesday hallucinates all Thursday.

You have met this problem twice and solved it the fixed way both times:
`pitch_map`'s clamps are constants because the curriculum could *pin*
the scenario (P_REF = 3840 assumes exactly 200 kHz and EDGES = 64), and
lesson 14's ±2% tolerance was a budget you could write down because
every error term was owned and bounded. A rooftop offers no pinned
scenario. The threshold must be **measured from the data itself** — that
is Constant False Alarm Rate detection, and the cell-averaging (CA-CFAR)
version is almost embarrassingly small:

```
 bin index →
 ..│ r │ r │ r │ r │ r │ r │ r │ r │ g │CUT│ g │ r │ r │ r │ r │ r │ r │ r │ r │
    └──────────────┬──────────────┘        └──────────────┬──────────────┘
       leading reference cells                trailing reference cells

    noise estimate  Z = mean power of the 2·(N/2) = N reference cells
    detection rule:     declare a target in CUT iff  power(CUT) > α·Z
```

For each cell under test (CUT), average the N neighboring bins — the
reference cells — skipping a guard cell or two on each side so a strong
target doesn't leak into its own noise estimate, then compare the CUT
against α times that local average. A moving average, two guards, one
multiply, one compare: `pitch_map`-sized hardware. The entire
sophistication lives in one question — *what is α?* — and the answer is
the most first-principles calculation in this course.

Model the noise in a target-free bin as complex Gaussian, so its power
(square-law detected) is exponentially distributed, and assume the N
reference cells are independent samples of the same noise. Then the
false-alarm probability per cell works out in closed form:

```
P_fa = ( 1 + α/N )^(-N)      ⇒      α = N · ( P_fa^(-1/N) − 1 )
```

Worked, for N = 16 reference cells:

```
P_fa = 1e-4 :  α = 16·(10^(4/16) − 1) = 16·0.778 = 12.45   (11.0 dB)
P_fa = 1e-6 :  α = 16·(10^(6/16) − 1) = 16·1.371 = 21.94   (13.4 dB)
```

Sanity-check the first line against a genie who *knows* the true noise
power exactly: the genie's threshold for P_fa = 1e-4 is −ln(P_fa) = 9.2
(9.6 dB). CFAR's 11.0 dB sits about 1.3 dB above — that gap is **CFAR
loss**, the rent you pay for estimating the floor from only 16 noisy
cells instead of knowing it. More reference cells shrink the loss but
widen the window, and a wide window flunks the *homogeneity* assumption:
a clutter edge (parking lot to tree line) halfway through your reference
cells poisons the estimate. Small window, honest statistics, high loss;
big window, low loss, lying statistics. You have been here — it is
lesson 13's smoothing tradeoff (responsiveness vs jitter) wearing a
detection-theory uniform, and just like SMOOTH_SHIFT, the window size is
an engineering *choice* you defend with numbers, not a constant you
inherit.

Note what P_fa buys you rhetorically: 256 bins × 45.8 CPIs/s ≈ 11,700
threshold tests per second. At P_fa = 1e-4 that is a false alarm every
~0.85 seconds — useless. At 1e-6, one every ~85 seconds — and now you see
why fielded systems chain CFAR with M-of-N confirmation across CPIs, the
same "drop the first measurement, believe the trend" discipline your
lesson 10 testbench used. A detector without a stated P_fa isn't a
detector; it's a mood.

## Micro-Doppler: the target that modulates itself

Everything so far treats a target as one number: a body velocity, one
line in the spectrum. A drone refuses to be that simple, and the refusal
is the best thing about it.

A small quadcopter is a slow body carrying very fast parts. Take a
5-inch (0.127 m) propeller at 10,000 RPM:

```
blade tip speed    v_tip = π · 0.127 m · (10000/60 s⁻¹)  ≈ 66 m/s
tip Doppler swing  ±66 m/s · 70.2 Hz/(m/s)               ≈ ±4.7 kHz
blade-pass rate    2 blades · 10000/60                    ≈ 333 Hz
body line (15 m/s) 15 · 70.2                              ≈ 1.1 kHz
```

Each blade sweeps its tip from +66 m/s (advancing toward you) to
−66 m/s (retreating) every revolution, so the echo is not a tone — it is
a carrier *modulated* by the rotors: a bright body line flanked by a
±4.7 kHz smear of blade energy, organized into discrete modulation lines
spaced at the 333 Hz blade-pass rate. You already have the right
intuition for this from the instrument itself: a theremin player's
vibrato — the hand wobbling a few times a second around a pitch — puts
FM sidebands on the audio tone. The drone plays vibrato on your radar at
10,000 RPM, and it cannot stop: the moment the rotors stop modulating,
it is no longer flying. Plot successive CPIs as a waterfall (46 columns
per second, 45.8 Hz rows — each column one FFT, the whole picture just
lesson 10's dwell law tiled in time) and the signature draws itself:

```
   Doppler ▲
   +5.8 kHz┤ ·  ·   · ·  ·  · ·      blade-tip extent (body + 4.7 kHz)
           │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
           │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  ←  rotor modulation lines, 333 Hz apart
   +1.1 kHz┤ ━━━━━━━━━━━━━━━━━━  ←  body line, 15 m/s
           │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
          0┼─────────────────────▶ time (one column per 21.8 ms CPI)
```

The bins are fine enough to resolve the structure (333 Hz line spacing
against 45.8 Hz bins), and the tip swing rides *on top of* the body
line: 1.1 + 4.7 = 5.8 kHz, which fits the ±5.86 kHz complex-sampled span
with about one bin to spare. Margin that thin gets written into the
design record, not discovered on the roof — lesson 14's habit. The
numbers you derived two sections ago were secretly a micro-Doppler
design, and its envelope has an edge.

This signature is the counter-UAS discriminator, because the two hard
confusions both fail it. A **bird** at the same range, speed, and radar
cross-section shows a body line plus *wingbeat* modulation at a few
hertz with tip speeds of a few m/s — narrow, slow, fleshy sidebands,
nothing rigid, nothing at hundreds of hertz. A **hovering drone** — the
classic trap for naive moving-target logic, since its body Doppler is
zero and a body-line detector files it under "building" — still can't
hide the rotors: zero body line, full sideband structure. The
information that separates "quadcopter" from "crow" from "plastic bag"
is not in *where* the energy is; it is in *how the energy dances*, and
the FFT-per-CPI waterfall is the instrument that sees the dance. One
honest caveat belongs in your notebook next to the enthusiasm: blade
returns from centimeter-scale props are tens of dB below the body
return, so micro-Doppler classification is a signal-to-noise fight —
which is why dwell, integration, and noise-shaped exciters (lessons 10,
12, 08) never stop mattering.

## The road there

Read `fpga/ROADMAP.md` Phases 5–7 again with today's eyes:

- **Phase 5 — DDC.** Quadrature NCO (your `nco` plus a cosine tap off
  the same `sine_lut`), I/Q mixing, CIC decimation, compensating FIR.
  This buys signed Doppler — the image problem's funeral — and the
  decimation that sets fs for everything downstream.
- **Phase 6 — FFT + CFAR.** One serialized butterfly, two BRAMs, a
  twiddle ROM, then the CA-CFAR window and α you just derived,
  detections out `uart_tx` — lesson 11's block, unchanged, now carrying
  target reports instead of pitch telemetry. This is the phase where the
  ECP5/ULX3S swap happens, for the multiplier reason priced above.
- **Phase 7 — HB100.** The $6 module *is* the RF front end: 10.525 GHz
  oscillator, patch antennas, mixer — lesson 12 in a stamped-metal can.
  Its IF into an MCP3202, and the chain above turns walking speeds, and
  eventually rotor blades, into detections on a serial port.

The discipline travels unchanged: requirement-tagged testbenches, a
target generator per lesson 14 (`osc_model` grows into an I/Q echo
model with programmable body Doppler and rotor modulation — you know
exactly how to write it, and exactly what its envelope clause must say),
budgets written down, sign-off through the pins. The instrument was
never the point. The instrument was the excuse.

## SBIR Notebook

- **Micro-Doppler is the counter-UAS discriminator.** Small UAS are
  slow, low, and small — weak body returns in heavy clutter — but their
  rotors impose compulsory modulation (blade-pass lines at hundreds of
  Hz, tip-Doppler spread of kilohertz at X band) that separates a
  quadcopter from a bird or a hovering target from a building. A
  proposal should lead with the signature, not the range equation.
- **The detection chain is small enough to be honest about.** CW/FMCW
  front end → I/Q DDC → N-point FFT per CPI → CA-CFAR → M-of-N
  confirmation fits in commodity FPGA fabric with one time-shared
  butterfly and BRAM-resident state; at audio-band IFs the DSP runs
  hundreds of times faster than real time. Cost and SWaP claims can be
  backed by cell-level resource audits, not vendor estimates.
- **False-alarm rate is a first-principles deliverable.** CA-CFAR's
  threshold multiplier follows in closed form from P_fa and window size
  (α = N(P_fa^(−1/N) − 1)), with CFAR loss and clutter-edge behavior as
  quantified, testable tradeoffs — a detector spec a reviewer can check
  by hand, versus "tuned threshold" hand-waving.
- **Dwell is the budget everything else spends.** Velocity resolution is
  Δv = λ/(2·CPI); resolving rotor modulation sets a floor on CPI, and
  CPI times beam positions is the surveillance timeline. Framing mode
  design as an explicit T·Δf budget is the systems-engineering language
  Army evaluators fund.
- **Verification discipline is the credibility story.** The prototype
  chain was developed sim-first on version-pinned open tools with
  requirement-tagged self-checking testbenches, model-based system
  sign-off against target generators, and stated model envelopes —
  DO-254-shaped evidence, cheap, and directly traceable in a proposal's
  test section.
