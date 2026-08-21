# Radar Interlude 3 — Your Theremin IS a CW Radar

*Where we are.* Lesson 12 built `het_mixer`, watched two 100 kHz squares
beat at concert A, and stated the course's thesis: a theremin is a CW
radar. This interlude is one sitting — about an hour, nothing to type,
nothing to run — in which we stop treating that sentence as a slogan and
conduct it as an engineering audit. Every block in the theremin signal
chain you have built through lesson 12 gets lined up against the
corresponding block of a continuous-wave radar receiver, with the actual
module names, generics, and measured numbers from your own runs on one
side and the radar terms of art on the other. Then we push on the two
places where the audit gets interesting: the image ambiguity your
testbench tripped over in lesson 12's Explore 1 (and the I/Q machinery
real radars buy to fix it), and the $6 module in lesson 99's epilogue —
the HB100 — that turns the audit into a bench demonstration.

## The claim, upgraded to an audit

"X is really a Y" claims are cheap. The way to make one expensive — the
way a proposal reviewer or a design authority will actually credit it —
is to map every block, name what each block does in both vocabularies,
and then say precisely where the mapping *breaks*. A mapping with no
stated break is marketing. Ours has exactly one break, it is
well-defined, and finding it will teach you more radar than the parts
that match.

Here is the audit target, drawn once in each vocabulary:

```
CW Doppler radar (homodyne):

  TX osc ──┬──────────► antenna ~~~► target (moving, v)
           │                            │
           │ LO                         │ echo, shifted by f_d = 2v/λ
           ▼                            ▼
        [ mixer ] ◄───────────── RX antenna
           │
           ▼ IF = beat at f_d          (audio band for human-scale v)
      [ LPF / integrator ]
           │
           ▼
      measure / listen  →  velocity


Your theremin (through lesson 12):

  74HC14 sensing osc ◄~~~ hand (position, via ~0.1–1 pF of added C)
  (osc_model in sim)         detunes the oscillator itself
           │
           ▼ RF                       LO
      [ sync_2ff ] ─► [ xor ] ◄── reference NCO
                         │
                         ▼ mix
             [ accumulate-and-dump ]
                         │
                         ▼ if_out = beat at |f_rf − f_lo|
                measure / listen  →  pitch
```

Same LO, same multiplier, same low-pass, same audio-rate IF, same
detection philosophy. The philosophy deserves one paragraph before the
table, because it is the actual transferable idea: in both machines the
information is a *minuscule fractional deviation of an oscillation*. A
70 Hz Doppler shift on a 10.525 GHz carrier is about 7 parts per
billion. Your simulated hand at full reach pulls the 200 kHz antenna
oscillator down 20 kHz — a generous 10% in `osc_model`'s
`DELTA_HZ = 20 kHz` scenario; a real 74HC14 front end with a real
antenna sees a few percent at most, and near the far edge of the pitch
field a small fraction of a percent. No detector reads parts-per-billion
off a carrier directly. So both machines beat the signal against a
reference that shares the carrier: the common part cancels in the
difference term of the product-of-cosines identity, and the deviation —
formerly a rounding error on the carrier — becomes the *entire* output.
Heterodyning is a subtraction performed by physics, and it is the only
known way to make 7 ppb audible.

## The block-for-block mapping

Every row is a module you have built and verified, except the last two.

```
theremin block (lesson)      radar block               shared job
─────────────────────────────────────────────────────────────────────────
antenna + hand               aperture + target         couple the outside
                                                       world into the RF
74HC14 sensing osc           TX oscillator + the       carry the info as a
(osc_model, L10; hardware    target-modulated return   small frequency
in L99)                                                deviation
reference NCO (L04)          LO / STALO                the clean reference
                                                       the deviation is
                                                       measured against
xor gate (L12)               receiver mixer /          multiply; translate
                             product detector          RF ± LO, carrier
                                                       cancels in the
                                                       difference
accumulate-and-dump (L12)    IF filter + integrator    keep the difference,
                             (a 1-stage CIC)           crush the sum
if_out (L12)                 IF / video signal         the deviation,
                                                       relocated to audio
freq_meas (L10)              counting discriminator,   frequency → number,
                             one report per CPI        one report per dwell
sync_2ff (L09)               async front-end CDC       tame the one input
                                                       not on your clock
uart_tx (L11)                instrumentation /         get the numbers off
                             telemetry link            the sensor
pitch_map (L13, next)        calibration curve,        number → meaning
                             Doppler → velocity        (pitch; velocity)
ear / loudspeaker            operator's headphones     the original
                                                       detector
─────────────────────────────────────────────────────────────────────────
```

Walk the rows with your own numbers in hand:

- **Reference NCO ↔ LO/STALO.** Lesson 04's accumulator at W = 32 on a
  12 MHz clock has frequency resolution f_clk/2³² = 2.794 mHz. In lesson
  12 you set two of them 157 482 fcw ticks apart and got 440.0 Hz to
  within a millihertz. A radar's STALO is graded on exactly this axis —
  settability and stability — because any LO error appears, undiluted,
  in the IF. Your beat measurement came out 440.6 Hz vs 440.0 predicted
  not because the NCOs wandered (they cannot; they are arithmetic) but
  because the *measurement* quantized to dump instants. Real radars have
  the same split: exciter error vs signal-processor error, budgeted
  separately.
- **XOR ↔ mixer.** Lesson 12 proved this one as an identity, not an
  analogy: the multiplication table of {+1, −1} is the truth table of
  XNOR, and XOR computes the same product with a global sign. Radar
  front ends use diode rings or Gilbert cells driven hard enough that
  the LO effectively multiplies the RF by ±1 — a hard-switched mixer *is*
  your XOR gate, rendered in Schottky diodes. The harmonic
  cross-products you absorbed with a 5% tolerance are the same spurious
  responses a mixer datasheet tabulates as "m×n products".
- **Accumulate-and-dump ↔ IF filtering.** Your 1024-clock window passes
  440 Hz at gain ≈ 0.998 and holds the ~200 kHz sum product below about
  −35 dB, dumping at 11.72 kHz. That is a matched filter-and-decimate —
  a one-stage CIC — and the CIC is literally the first block inside
  every radar and SDR digital downconverter (fpga/ROADMAP.md Phase 5
  has you cascade them). When lesson 12's Explore 4 stretched the
  window to 16 384 clocks and the 440 Hz beat itself fell below the
  detection threshold, you ran the classic radar design error: an
  integrator longer than the Doppler period erases the Doppler.
- **freq_meas ↔ one report per CPI.** Lesson 10's counter opens on an
  edge, spans EDGES = 64 input periods (nominally 3840 clocks at
  200 kHz), and strobes `valid` once per completed measurement — a
  radar engineer reads that as one dwell, one coherent processing
  interval, one report. The law you measured there, T·Δf ≈ f_osc/f_clk
  (a 320 µs window buying 52 Hz of resolution, 3125 fresh measurements
  per second), is the same law that made Explore 2's 55 Hz beat
  invisible in 280 dumps and visible in 1120: resolving a small
  frequency difference costs observation time, in a counter, in a
  mixer, and in a radar dwell. Interlude 2 dwelt on this; here it is
  again, because it is the one law that never stops applying.
- **The ear ↔ headphones.** Not a joke row. Early CW radar IFs were
  audio, and operators detected targets by listening — a crossing
  aircraft played a falling-then-rising glissando as its radial
  velocity swept through zero. A theremin player executing vibrato and
  a 1940s operator tracking a bomber were performing the same
  signal-processing task on the same class of signal with the same
  wetware detector.

## What the beat encodes: three sensors, one receiver

The receiver front end is now established as common property. What
distinguishes the instruments is the *physical encoder* standing in
front of it — what modulates the RF before the mixer ever sees it.
Three encoders, three sensors:

```
sensor            beat frequency        encodes     via
──────────────────────────────────────────────────────────────────────
theremin          ≈ f_osc · ΔC/C        position    hand capacitance
                                                    detuning the osc
CW Doppler radar  f_d = 2v/λ            velocity    phase rate of the
                                                    moving echo
FMCW radar        f_b = (2R/c) · S      range       round-trip delay
                                        (S = chirp  against a swept LO
                                        slope)
──────────────────────────────────────────────────────────────────────
```

Worked, with honest numbers:

- **Theremin.** The 74HC14 relaxation oscillator's frequency goes as
  1/(RC), so a small added ΔC moves it by Δf ≈ −f·ΔC/C to first order.
  With the antenna node around a dozen pF, the hand's ~0.1–1 pF is a
  percent-scale detuning of 200 kHz: a few hundred Hz to a few kHz of
  beat, sitting exactly in the audio band. Position in, pitch out.
- **CW Doppler.** At 10.525 GHz, λ = c/f ≈ 2.85 cm, so f_d = 2v/λ ≈
  70 Hz per m/s of radial velocity. A walking person at 1.5 m/s beats
  at ~105 Hz; a small drone closing at 10 m/s beats at ~702 Hz — about
  nine cents sharp of F5, if you want to know what a drone sounds like
  through this receiver. Velocity in, pitch out.
- **FMCW.** Sweep the LO at slope S and the echo returns an older
  frequency; the mixer output is the slope times the round-trip delay.
  S = 100 MHz per 1 ms = 10¹¹ Hz/s and a target at R = 150 m
  (τ = 2R/c = 1 µs) gives f_b = 100 kHz. Range in, pitch out.

Same mixer, same filter, same "read the beat" back end — which you now
own in two independently verified forms, `het_mixer` and `freq_meas`.
The whole difference between a musical instrument, a speed sensor, and
an altimeter is which physical quantity got transduced into frequency
before the receiver. This is why the course keeps saying the skills
transfer: the receiver doesn't know what it's measuring. It never does.

## The one structural difference

Here is where the honest audit pays its fee. In a radar, the target
modulates the *echo*: energy leaves the transmitter, bounces, and
returns carrying a delay and a phase rate. Transmitter and target are
separate boxes, and the information rides on a propagating wave. In the
theremin, the target modulates the *transmitter itself*: the hand is a
capacitor plate inside the oscillator's timing network, and "the RF"
never travels anywhere — the antenna is an electrode, not an aperture.
A theremin is a CW radar whose target reaches into the exciter and
retunes it; equivalently, a CW radar is a theremin that plays
range-rate.

Could the theremin's field be doing radar-style Doppler on your moving
hand anyway? Run the number and enjoy it: at 200 kHz, λ = c/f ≈
1500 m. A hand at 1 m/s gives f_d = 2v/λ ≈ 1.3 *milli*hertz — below
even your NCO's 2.794 mHz frequency resolution, never mind audibility.
The capacitive detuning is roughly a million times larger. That
disparity, not designer preference, is why the theremin is a
near-field capacitive sensor and the HB100 is a radar: at 200 kHz the
wavelength makes Doppler negligible and the near field enormous; at
10.525 GHz it is precisely the other way around. Same block diagram,
opposite dominant physics, selected by nothing but carrier frequency.

One more wrinkle worth naming, because it collapses the difference
further: radars in which the echo couples back into the transmitting
oscillator and detunes it are a real and useful class —
*self-mixing* or self-oscillating mixer sensors. The HB100 itself is
in this family's neighborhood: one oscillator serves as both
transmitter and LO, and a mixer diode beats the received echo against
it. The theremin's architecture is not radar's estranged cousin; it is
one of radar's own minimalist branches, operating where the near field
wins.

## The image problem, and why real radars buy two mixers

Lesson 12's Explore 1 staged the failure precisely. You moved FCW_RF
from 35 791 394 to 36 106 358 — the same 157 482 ticks *above* the LO
as the original was below — and the hardware's output was identical to
the femtosecond, while the testbench's signed prediction went to
−26.63 dumps and R1 failed against a perfectly healthy DUT. The
difference term is cos(2π(f₁−f₂)t) and cosine is even: a real mixer
reports |f_rf − f_lo| and destroys the sign. The discarded twin is the
image frequency.

For the theremin this is the mirror pitch field: tune so the hand can
push the variable oscillator through zero beat and the pitch falls to
silence at the null, then *rises again* on the far side. The handoff
documents in this repository draw that fold; you have now failed a
testbench over it, which is a deeper form of understanding. The
instrument survives because the player and the tuning knob conspire to
stay on one side of the null — the ear closes the loop.

A radar has no such conspiracy available, and its version of the
ambiguity is operationally intolerable: +f_d vs −f_d is *approaching
versus receding*. Your 702 Hz drone beats at 702 Hz whether it is
inbound or outbound. A counter-UAS sensor that cannot rank "closing on
the protected asset" above "leaving" is not degraded — it is failing
at its one job.

The fix costs exactly one more copy of hardware you already own. Mix
the RF twice, against two LOs 90° apart — cos(2πf_LO·t) and
sin(2πf_LO·t) — producing two IF channels, I and Q. Together they form
the complex signal:

```
I + jQ = e^(+j2π(f_rf − f_lo)t)     RF above LO: phasor rotates one way,
                                    Q lags I by 90°
I + jQ = e^(−j2π(f_lo − f_rf)t)     RF below LO: rotates the other way,
                                    Q *leads* I by 90°
```

The magnitude beats identically in both cases — that is what the single
real mixer sees, and all it sees. The *rotation direction* — which
channel leads — is the sign the real mixer threw away. And the second
LO is free in your design: lesson 04's NCO exports its full `phase`
port, and a square tapped a quarter-turn ahead (phase + 2³⁰ at W = 32,
then take the MSB) is a 90°-shifted LO costing one adder. Two copies of
lesson 12's mixer fed from the same pair of oscillators, one on the
in-phase LO and one on the quadrature LO, and the pair of `if_out`
streams carries signed frequency. That is Phase 5 of fpga/ROADMAP.md —
the digital downconverter — already sketched in parts you have
verified.

## What the HB100 changes

Lesson 99's epilogue hands you an HB100: a ~$6 X-band Doppler
transceiver — dielectric-resonator oscillator at 10.525 GHz, patch
antennas, and a mixer diode that beats the received echo against the
transmitting oscillator. It is the left-hand diagram from the audit,
shrunk to a postage stamp. Line up what changes and what does not when
it replaces the 74HC14 front end:

- **Carrier: 200 kHz → 10.525 GHz.** Wavelength drops from 1.5 km to
  2.85 cm, so the dominant physics flips per the section above: the
  near-field capacitive coupling becomes irrelevant and Doppler becomes
  the signal. The beat stops encoding position and starts encoding
  velocity — ~70 Hz per m/s.
- **The entire RF section moves inside the module.** Oscillator, LO
  and mixer — the jobs of the 74HC14, the reference NCO, and your XOR
  gate — are done in microwave hardware behind the pins. The IF pin
  outputs the beat directly: audio-band, millivolt-scale, needing
  amplification and then a comparator (into `sync_2ff`, like any async
  input — lesson 09's rule does not care what the source is) or an ADC.
- **Your chain survives untouched from the IF onward.** Beat into
  `sync_2ff` into `freq_meas`, measurement out over `uart_tx`: the
  lesson 09/10/11 pipeline reads target speed with zero modification
  beyond constants. Retuning is arithmetic you have done before: a
  1 m/s target beats at ~70 Hz, so `freq_meas` at EDGES = 64 would
  integrate for 64/70 ≈ 0.9 s — a long dwell; drop EDGES or accept it,
  and you are doing radar mode design, walking lesson 10's T·Δf curve
  with a real target on the other end. Lesson 10 priced the
  alternative: a 20 ms CPI gives Δf_d = 50 Hz, i.e. Δv ≈ 0.7 m/s.
- **The image ambiguity comes along.** The stock module's single IF
  channel is a real mixer output: |f_d|, sign destroyed, inbound and
  outbound identical — the lesson 12 Explore 1 result now standing in
  a driveway watching actual cars. Quadrature-output Doppler modules
  (and, one level up, radar chipsets with I/Q downconverters) exist for
  exactly the reason the previous section derived; when you meet one,
  you already know why it has two IF pins and what to do with them —
  two mixers, one LO pair 90° apart, rotation direction is the sign.
- **What's still missing is the back half.** One target, one beat,
  `freq_meas` suffices. Real scenes have many echoes at once — several
  targets, clutter, a drone body plus its blades — and a counter reads
  only the composite. Separating them takes a filter bank: an FFT
  across the CPI, then a detector that sets thresholds against local
  noise (CFAR). That is Phase 6 of the roadmap, and it is interlude
  4's subject, after lesson 14 gives you the integrated instrument.

The demo this enables is worth stating plainly, because it is the SBIR
demo artifact named in the roadmap: the same FPGA, the same verified
RTL discipline, and a $6 microwave module measuring real target
velocity — your theremin chain, pointed at the world.

## SBIR Notebook

Talking points connecting this interlude to counter-UAS sensing
proposals — written to be lifted:

1. **We have implemented and verified the homodyne CW receiver chain in
   RTL.** XOR product detector, CIC-class integrate-and-dump IF filter,
   and reciprocal frequency discriminator, each with requirement-tagged
   self-checking testbenches and byte-verified reference solutions —
   the front half of a Doppler sensor demonstrated on $70 of FPGA
   hardware, with measured performance (440.0 Hz beat recovered within
   0.13% from 100 kHz carriers) documented in simulation logs.
2. **The image/sign ambiguity is understood at the implementation
   level, with the quadrature fix already staged.** Our testbenches
   demonstrate the |f_rf − f_lo| ambiguity explicitly, and the NCO's
   exported phase port provides a zero-cost 90° LO; the I/Q
   downconverter that discriminates approaching from receding targets —
   the decision that matters for cueing and prioritization in
   counter-UAS — is an incremental build on verified blocks, not new
   science.
3. **Dwell economics are quantified, not hand-waved.** The measured
   T·Δf invariant from the frequency-measurement work maps one-to-one
   onto CPI-vs-Doppler-resolution budgeting (e.g., 20 ms CPI ↔
   ~0.7 m/s velocity resolution at X band) — the trade that governs
   search-vs-track timeline design in any surveillance sensor.
4. **The architecture scales down to attritable, distributed sensing.**
   A COTS 10.525 GHz front end plus this FPGA chain is a complete
   low-power Doppler picket node; the identical processing pipeline
   from capacitive instrument to microwave sensor demonstrates that the
   signal chain is front-end-agnostic — the property that lets one
   verified codebase serve multiple apertures and bands.
5. **Development discipline is certification-shaped.** Version-pinned
   open toolchain, requirement-traced testbenches, simulation evidence
   preceding hardware, documented CDC at every async boundary — DO-254
   habits practiced from the first module, which reviewers of defense
   firmware programs will recognize.

Next: lesson 13, where `pitch_map` turns lesson 10's period counts into
frequency control words — in radar terms, the calibration curve and
tracking-loop smoothing that stand between a raw discriminator and a
usable output.
