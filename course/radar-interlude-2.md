# Radar Interlude 2 — Dwell, CPI, and the Price of Resolution

*Where we are.* You have just finished lesson 10. `freq_meas` is measuring
a simulated hand 3125 times a second, and along the way you derived a law:
observation time buys frequency resolution, and nothing else does. Lesson
10's Radar Connection told you that law has radar names — dwell, CPI,
Doppler bins. This interlude spends a sitting on nothing but that mapping,
because it is the single most load-bearing piece of radar systems
engineering you will ever carry into a proposal. There is no code to
write; the lab equipment for this hour is the numbers you measured in
lesson 10, a pencil, and the habit — which you already have — of refusing
to accept a claim you haven't computed. About 60 minutes.

## The trade you measured, on one page

Start from what your own testbench printed. At EDGES = 64, f_clk = 12 MHz,
f_osc = 200 kHz, `freq_meas` produced `period` = 3840 counts in a 320 µs
window, and the ±1-clock quantization of each window edge made one count
worth about 52 Hz:

```
T  = EDGES / f_osc                       = 64 / 200 kHz   = 320 µs
Δf ≈ f_osc² / (EDGES · f_clk)            = 4e10 / 7.68e8  ≈ 52 Hz
```

Explore 1 had you walk the knob. Tabulate what you found:

```
EDGES    T (window)    period      Δf         T · Δf
  16        80 µs        ~960     ~208 Hz      1/60
  64       320 µs       ~3840      ~52 Hz      1/60
 256      1280 µs      ~15360      ~13 Hz      1/60
```

The right-hand column is the law: for this counter the product T·Δf is a
hardware constant, f_osc/f_clk = 1/60, and EDGES only chooses where on
the curve you sit. Faster answers or finer answers — never both, not from
this clock. Hold that table; the rest of the interlude is the same table
wearing different units.

## Precision is cheap; resolution is not

Before mapping to radar, an honest distinction lesson 10 only gestured at,
because it is exactly the distinction between your instrument and a radar.

Notice something almost scandalous in the table: at T = 320 µs the Fourier
limit says two tones must differ by about 1/T = 3125 Hz to be
*distinguishable* — and that is precisely the resolution direct counting
achieved in lesson 10, because direct counting is a blunt one-bin Fourier
instrument. Yet your reciprocal counter pinned the frequency to 52 Hz in
the same window, sixty times finer than 1/T. Did it beat Fourier?

No — it answered an easier question. The theremin has **one** signal, a
rail-to-rail square wave at enormous SNR, and the only unknown is *what
frequency is it*. That is an **estimation** problem, and estimation
precision improves with SNR and with cleverness (counting the fast clock
against the slow signal) essentially without limit. The Fourier bound
governs a different question: given *two* signals Δf apart — or one
signal and one piece of clutter — can you tell there are two? That is a
**resolution** problem, and no SNR and no cleverness answers it in less
than roughly 1/Δf seconds of observation. You met the resolution wall
personally in lesson 04's Explore 4: a 20 000-clock window (1.67 ms)
could not tell A440 from A441 no matter how exactly the NCO's arithmetic
was known, because 1/T = 600 Hz and the tones differ by one.

Now the punchline. A radar never gets the easy question. Its input is not
one clean square wave; it is an unknown number of echoes — target,
another target, ground clutter, rain — summed together and buried in
noise. Edge counting is meaningless on a sum of sinusoids in noise (whose
edge would you count?), so a radar cannot use your reciprocal trick at
all. It must separate the components first, which is a resolution
problem, which means it pays the full Fourier price: **Δf = 1/T, no
discounts**. Everything in this interlude follows from the fact that the
radar is stuck on the expensive side of the distinction your theremin
gets to avoid.

## The vocabulary: PRI, PRF, dwell, CPI

A pulse-Doppler radar transmits a train of short pulses and listens
between them:

```
 tx:   █           █           █           █           █
       |<-- PRI -->|
       |<------------------ CPI = M · PRI ----------------->|

       █ = transmitted pulse (µs), PRI = pulse repetition interval,
       PRF = 1/PRI, M pulses processed coherently = one CPI
```

- **PRI / PRF** — the pulse repetition interval and its reciprocal. The
  radar's heartbeat, typically kHz.
- **Dwell** — how long the beam stares at one direction before moving on.
- **CPI** — the coherent processing interval: a block of M consecutive
  echoes, phase-aligned and processed together into one measurement. One
  CPI in, one report out.

Each received pulse is also sampled internally by a fast ADC clock, so a
CPI is a two-dimensional grid of samples: **fast time** (sample index
within one PRI — this axis encodes range) and **slow time** (pulse index
across the CPI — this axis encodes Doppler). Keep the axes straight with
one rule: fast time and transmit bandwidth buy *range* resolution; slow
time — dwell — buys *velocity* resolution. This interlude is entirely
about the slow-time axis.

You have already built this structure. Line it up against lesson 10:

```
radar quantity              your freq_meas build
─────────────────────────   ─────────────────────────────────────────
one pulse interval (PRI)    one input period of osc_model (~5 µs)
M pulses per CPI            EDGES = 64 rising edges per window
CPI duration                the 320 µs measurement window
fast ADC clock / fast time  the 12 MHz clock slicing each period
one report per CPI          one 'period' publish + 'valid' strobe
back-to-back CPIs           the closing edge opening the next window
dwell                       how long the hand-measurement stares: EDGES
```

The mapping is not poetic; it is one-to-one. When you set EDGES you were
a radar engineer choosing a CPI length, and the `valid` strobe rate —
3125 per second — was your report rate, dwell's reciprocal.

## Doppler bins and the price list

A radar measures radial velocity by measuring frequency. A target closing
at v compresses each round trip, shifting the echo by the Doppler
frequency

```
f_d = 2 v / λ
```

— the 2 because the wave travels out *and* back, so the path shrinks at
2v. Take the HB100 module waiting at the end of this course: 10.525 GHz,
λ ≈ 2.85 cm, so

```
f_d ≈ 70 Hz per m/s of radial velocity.
```

A walking human (1.5 m/s) is ~105 Hz. A quadcopter crossing at 20 m/s is
~1.4 kHz. A hovering quadcopter's *body* is 0 Hz — park that fact; it
returns at the end.

The CPI processor is a bank of narrow filters (lesson 12 builds the first
such filter; the full bank is an FFT, further down the roadmap), and the
Fourier price fixes the filter width: observing M pulses for CPI seconds
yields M Doppler bins, each

```
Δf_d = 1 / CPI    wide,  covering a total span of  ±PRF/2,
```

which through f_d = 2v/λ becomes the number every radar mode designer
carries tattooed somewhere:

```
Δv = λ / (2 · CPI)
```

Price list at 10.525 GHz:

```
CPI        Δf_d       Δv          could you afford it?
  5 ms     200 Hz     2.85 m/s    fast revisit; drones vs cars only
 20 ms      50 Hz     0.71 m/s    walking-speed separation
100 ms      10 Hz     0.14 m/s    crawl-speed; ten times the stare
```

Same curve as your EDGES table — only the axis labels changed. And a
concrete configuration, to make M do the work EDGES did: PRF = 10 kHz,
M = 64 pulses (your EDGES number). CPI = 6.4 ms; bins are 156 Hz ≈
2.2 m/s wide; the unambiguous span is ±5 kHz ≈ ±71 m/s. Want 0.7 m/s
bins at the same PRF? M = 200: the dwell triples, and nothing else you
can do to *this radar* changes that — the sentence you first said about
EDGES and this counter, verbatim.

One more axis of the price, noted honestly and briefly: PRF itself is a
trade. The Doppler span is ±PRF/2, but the unambiguous *range* is
c/(2·PRF) — echoes from beyond it arrive after the next pulse and
masquerade as close ones. PRF = 10 kHz gives 15 km of clean range and
±71 m/s of clean velocity: comfortable for short-range X-band
counter-UAS work, and genuinely painful for long-range radars, which
must juggle multiple PRFs to un-alias both axes. Your instrument dodges
this entirely — `freq_meas` measures one continuous wave with no pulses
to confuse, and its version of "unambiguous range" is just CNT_BITS = 24
giving `cycle_cnt` headroom to 1.4 s before wrap. Radars are not so
lucky, and the PRF juggling act consumes dwell too.

## Dwell is the budget; everything bids for it

Here is where the law stops being physics and becomes economics.

A surveillance radar must revisit *many* directions. Give a pencil-beam
radar a 2° beam and ask it to cover 360° of azimuth over 30° of
elevation: that is (360/2) × (30/2) = 2700 beam positions. Now buy decent
velocity resolution — the 20 ms CPI from the price list — in every one:

```
frame time = 2700 positions × 20 ms = 54 seconds.
```

A drone at 20 m/s moves over a kilometer between looks. Unacceptable —
so the designer starts trading, and every trade pays out of a different
pocket:

- **Shorten the CPI** → revisit faster, but Δv coarsens; slow targets
  merge into the clutter bin. You are sliding down your own EDGES table.
- **Widen the beam** → fewer positions, but antenna gain falls with beam
  area — detection range shrinks (two-way, so it hurts twice).
- **Form many beams at once** → digital arrays stare everywhere and pay
  the full CPI in every direction simultaneously. Nothing is free here
  either: the price moved into hardware — one receiver chain and one FFT
  bank per simultaneous beam. This is why counter-UAS radar proposals
  are full of digital beamforming, and why they are full of FPGAs.
- **Split the timeline** — search coarsely and fast, then spend long
  dwells only on tracks that earn them. Every real radar's mode logic is
  this: a scheduler auctioning milliseconds.

Notice what the T·Δf law did to the problem: it made *time on target* the
scarcest resource in the system, unpurchasable except by giving up
coverage, gain, or hardware. When a radar engineer says "the timeline is
tight," this arithmetic is what they mean. You have felt a miniature of
it: at EDGES = 256 your theremin measured beautifully and reported only
~780 times a second — resolution bought with responsiveness, the same
pocket a search radar pays coverage from.

The theremin, meanwhile, only ever watches one "beam position" — the
player's hand — which is why EDGES = 64 left it resolution to spare. An
instrument that stares at one target full-time is, in radar terms, a
dedicated track radar with a 100% duty timeline: the luxury configuration.

## What "coherent" is buying

One word in "coherent processing interval" has been doing quiet work.
The M pulses are integrated *coherently*: their phases are preserved and
summed, which is what makes the filter bank narrow — and it has a second
effect the theremin never needed. Adding M echoes in phase grows the
signal amplitude by M while the noise, adding with random phases, grows
only as √M: coherent integration buys an SNR gain of M on top of the
resolution. At M = 64, that is 18 dB — the difference between a drone
echo you can threshold and one you cannot. Edge counting has no such
mechanism; it needs its edges clean *before* counting starts, which is
fine for a Schmitt-trigger oscillator and hopeless at −10 dB SNR.

Coherence has a prerequisite you already own: the radar's local
oscillator must hold a known phase across the whole CPI, or the echoes
won't add up. Lesson 04 named the property — reset the phase accumulator
and you know its phase exactly, forever after. Your `nco.vhd` is, to the
digit, the STALO that makes a CPI coherent; the determinism you verified
with a ±1-edge property is the same determinism a pulse-Doppler radar
stakes its 18 dB on. And lesson 12, next after this interlude's
neighbors, builds the first coherent integrator of the course — the
accumulate-and-dump filter — at which point the chain from "counter that
measures a hand" to "receiver that integrates echoes" closes block by
block.

## The interlude's one idea, restated

Your EDGES generic, a radar's CPI, and a Fourier transform's window are
the same knob, governed by the same law: frequency resolution costs
observation time, at an exchange rate no implementation can improve —
only *evade*, when the problem is estimation of one clean signal rather
than resolution of several buried ones. The theremin lives on the cheap
side of that line. Radar lives on the expensive side, and every radar
architecture you will ever read — filter banks, digital beams, mode
schedulers, PRF ladders — is a machine for paying the bill gracefully.

You did not read this law in a book; you set it with a generic, measured
it four times with requirement tags, and watched ±2 counts of it land
where the derivation said. That is the difference between knowing the
words and owning the trade.

## SBIR Notebook

Talking points earned by the lesson-10 build, for counter-UAS proposals:

- **Velocity resolution sets the timeline, and the timeline sets the
  architecture.** Separating a 1–2 m/s loitering UAS from clutter and
  birds needs sub-m/s Doppler bins, hence CPIs of tens of milliseconds
  (Δv = λ/2CPI: 0.7 m/s takes 20 ms at X-band); multiplied across a
  surveillance volume, single-beam dwell arithmetic fails by an order of
  magnitude — the quantitative case for digitally beamformed, staring
  apertures with per-beam FPGA processing.

- **The hardest UAS is the slow one.** A hovering or drifting quadcopter's
  body return sits within a bin or two of zero Doppler, in the clutter's
  lap — 70 Hz per m/s at X-band puts a 0.3 m/s drift at ~20 Hz. Fine
  Doppler resolution is the entry fee for even *seeing* it as separate
  from ground return; classifying it (rotor micro-Doppler) is a further
  step this course reaches in interlude 4.

- **Kinematics alone do not classify.** Birds occupy the same 5–20 m/s
  envelope as small UAS bodies; dwell buys the resolution to *separate*
  returns, not the label. Proposals should claim discrimination from
  Doppler structure over the CPI, not from velocity gates — and budget
  dwell for the longer classification looks that implies.

- **CPI choices are FPGA resource numbers, one-to-one.** M pulses per CPI
  fixes the slow-time buffer depth and FFT length per beam per range
  gate; doubling velocity resolution doubles BRAM footprint and
  arithmetic throughput. A proposal that presents dwell, bin width, and
  fabric utilization as one coupled budget — the freq_meas EDGES trade,
  costed in LUTs — reads as written by someone who has built the chain.

- **Coherent gain is the small-target detection argument.** Integrating M
  pulses coherently buys M-fold SNR (18 dB at M = 64) against the tiny
  RCS of Group-1 UAS — but only atop a phase-deterministic exciter and a
  disciplined clock architecture. The verified-DDS-plus-measured-CPI
  chain built in lessons 04–10, with requirement-tagged simulation
  evidence, is a credible miniature of exactly that architecture.
