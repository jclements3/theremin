# Lesson 12 — The Heterodyne Heart

*Where we are.* The instrument you are building measures its antenna
oscillator with a counter (lesson 10) and will map the count to pitch in
lesson 13 — a fine, modern, digital design. Leon Theremin had no counter.
His 1920 instrument did something with more physics in it: it ran *two*
radio-frequency oscillators — one fixed, one detuned by the player's hand —
multiplied them together, and let a loudspeaker play the difference. This
lesson steps off the integration path to build that circuit digitally:
`het_mixer`, an XOR mixer with an accumulate-and-dump filter, fed by two
NCOs a few hundred hertz apart. It is the course's thesis lesson. When the
testbench measures a 440 Hz beat between two 100 kHz squares neither of
which you could hear, you will be looking at the front end of every radio
receiver and every CW radar ever built — and at the argument, made
precise, that a theremin *is* one.

---

## Session 12.1 — Multiplication Moves Frequencies (~90 min)

### Objectives

- Derive, from the product-of-cosines identity, why multiplying two tones
  produces exactly a sum frequency and a difference frequency, and why
  that means multiplication *moves information between frequency bands*.
- Prove that XOR is a true multiplier for square waves — not an analogy,
  an isomorphism — and state what the leftover sign flip does.
- Explain accumulate-and-dump as a boxcar low-pass filter plus decimator;
  compute its gain at the difference (440 Hz) and sum (~200 kHz) products
  and show the numbers justify "keep one, crush the other".
- State the image problem — a real mixer outputs |f_rf − f_lo| and destroys
  the sign — locate where the testbench trips over it, and explain how
  quadrature mixing repairs it.
- Build `het_mixer` and verify both of its personalities: beat-frequency
  generator (offset inputs) and phase detector (equal inputs).

### Concepts

#### The problem mixing solves

The hand's information is a frequency deviation: the antenna oscillator
sits near 200 kHz and the hand pulls it by a couple of percent at most —
near the far edge of the pitch field, by a small fraction of a percent.
That deviation is real, but it lives on top of a huge carrier. You cannot
hear 200.000 kHz vs 199.560 kHz (you cannot hear either), and no
loudspeaker cares about the difference between them. The information is
fine; it is just *in the wrong band*.

Lesson 10 solved this by measurement: count the frequency, get a number,
synthesize a new tone from scratch. The heterodyne solution is more
elegant and much older: subtract the carrier *physically*. Take a second
oscillator at almost the same frequency and multiply the two signals.
Multiplication — this is the whole lesson — performs frequency
translation:

```
cos(2πf₁t) · cos(2πf₂t) = ½·cos(2π(f₁−f₂)t) + ½·cos(2π(f₁+f₂)t)
```

Sum and difference, nothing else. Feed a multiplier 100.000 kHz and
100.440 kHz and out come 440 Hz and 200.440 kHz. The common 100 kHz —
which carried no information — has vanished from the difference term; the
440 Hz *is* the deviation, relocated from radio frequency to the middle
of the audible band, wearing concert-A's clothes. Low-pass away the sum
term and you are done. Every radio receiver ("superheterodyne" — you own
the word now), every radar front end, and every theremin is this identity
plus a filter. The two inputs have names you should start using: the
signal port is **RF**, the reference oscillator is the **LO** (local
oscillator), and the difference output is the **IF** (intermediate
frequency — here, audio).

One footnote that will matter in hardware someday: any *nonlinearity*
mixes. A diode, a saturating amplifier, an overdriven transistor all
generate products at f₁±f₂ (and worse). Multiplication is the clean ideal
that makes only the two you asked for; real mixer design is the art of
approximating it.

#### XOR is a multiplier — exactly

We have no analog multiplier on an iCE40, and we don't need one. Our
oscillators are the NCOs' square-wave outputs — one bit each — and for
one-bit signals, multiplication collapses into a gate.

Read a square wave as a ±1 signal in disguise: map bit B to the value
s = (−1)^B, so '0' ↦ +1 and '1' ↦ −1. Multiply two of them:

```
s₁ · s₂ = (−1)^B₁ · (−1)^B₂ = (−1)^(B₁+B₂) = (−1)^(B₁ xor B₂)
```

The product of the ±1 values is the ±1 value of the XOR. Not an
approximation, not an analogy: the multiplication table of {+1, −1} and
the truth table of XOR are the same table. (Choose the opposite mapping,
'1' ↦ +1, and the identity lands on XNOR instead; XOR then computes
*minus* the product. A global sign on the product only flips which
voltage means "agree", i.e. the DC sense of the output — Explore 3 makes
this visible as a number.) So the entire RF multiplier of our heterodyne
receiver is:

```vhdl
mix <= rf_in xor lo_in;
```

Squares aren't cosines — they carry odd harmonics at 3f, 5f, … — so the
gate also produces harmonic cross-products. Every one of them lands
either near RF (where the filter below kills it) or on odd multiples of
the beat (a little edge on the beat waveform, absorbed by the testbench's
5% tolerance). The fundamental behaves exactly per the identity.

There is a second way to see the same gate, and it's the one to hold in
your head while reading waveforms. XOR asks "do the inputs disagree?".
Two squares at the *same* frequency, offset in phase by φ cycles (φ ≤ ½),
disagree for exactly 2φ of every cycle: the XOR output is a pulse train
whose *duty cycle* is proportional to phase offset. Now detune one input
by df: the phase offset is no longer constant — it slews continuously at
df cycles per second — so the duty cycle sweeps 0 → 1 → 0, tracing a
triangle wave at the difference frequency:

```
phase offset:  0 … ¼ … ½ … ¾ … 1 … (cycles, slewing continuously at df)
XOR duty:      0%  50% 100% 50% 0% …

duty  100% ┤   /\      /\      /\
           │  /  \    /  \    /  \        the beat: a full-scale
           │ /    \  /    \  /    \       triangle at df
        0% ┤/      \/      \/      \  → time   (period = 1/df)
```

"Multiply then low-pass" and "watch the disagreement duty cycle" are the
same computation. The second version tells you what to expect on the
scope: our beat will be a triangle, not a sine — and it hands you the
filter design for free, because *duty cycle over a window* is something a
counter can measure.

#### Accumulate-and-dump: a low-pass filter you already know how to build

The low-pass that keeps 440 Hz and crushes 200 kHz could be an RC on a
pin — that's lesson 08's trick, and Theremin's. Digitally we do something
that looks naive and is actually a filter with a name: count how many of
the last 2^ACC_LOG2 = 1024 clock cycles had `mix = '1'`, publish the
count, clear, repeat. Accumulate and dump.

Why that's a filter: summing N consecutive samples is convolution with a
boxcar (a length-N FIR whose taps are all 1), and dumping once per window
decimates by N. A boxcar's frequency response is the sinc-shaped
`sin(πfNT)/ (N·sin(πfT))` — a main lobe at DC, nulls at every multiple of
the dump rate f_clk/N = 12 MHz/1024 = **11.72 kHz**. Run our two products
through it:

- **440 Hz difference:** πfT_win = π·440·85.33 µs ≈ 0.118 rad; gain
  ≈ 0.998. Passes essentially untouched.
- **~200.44 kHz sum:** 17 nulls up the sinc skirt; envelope bounded by
  1/(πfT_win) ≈ 0.019, about **−35 dB**, before decimation even helps.
  One clock of it more or less per window is quantization fuzz, not
  signal.

And decimation *does* help, in a way worth internalizing: the boxcar's
nulls sit exactly on the multiples of the output rate — precisely the
frequencies that would alias onto DC when you keep one sample per window.
The filter is matched to its own decimator. Cascade a few of these and
you have a CIC filter, the workhorse decimator in front of essentially
every radar and SDR ADC; ours is a one-stage CIC, built from one adder.

The implementation details are all fenceposts, and lesson 10 trained you
for them. The window counter `cnt` free-runs and wraps mod 1024, so
windows are back-to-back — no dead time, the mixer is always listening.
On the last cycle of a window the accumulator's final increment and the
publish happen in the same clock (`acc + 1` when `mix = '1'`), so every
cycle is counted exactly once. And `if_out` is **ACC_LOG2 + 1 = 11 bits**
wide, not 10: a window of all-ones sums to exactly 2^10 = 1024, which
does not fit in 10 bits. Declare it one bit narrow and full-scale wraps
to zero — the beat's peaks would notch to nothing, silently.

So: dumps arrive at 11.72 kHz, each a number 0..1024, tracing the beat
triangle. The testbench predicts the beat period in *dumps*:

```
beat = (FCW_LO − FCW_RF) · f_clk/2³²  =  157482 · 2.794 mHz  ≈ 440.0 Hz
dumps per beat = 2³² / ((FCW_LO − FCW_RF) · 1024)  ≈  26.63
```

R1 measures that with a hysteresis detector — arm below ¼ scale, fire at
¾ scale — because a full-scale triangle crosses midscale cleanly but any
single threshold without hysteresis would chatter on the quantization
fuzz riding the ramps.

#### Two frequencies make a beat; one frequency makes a phase detector

Set FCW_LO = FCW_RF and the phase offset stops slewing: the XOR duty
cycle freezes at 2φ and `if_out` goes DC, proportional to the phase
difference. The mixer hasn't broken — it has degenerated into a **phase
detector**, the component at the heart of every PLL (and of lesson 08's
delta-sigma intuition: measure disagreement, average it). R2 pins this
down by releasing the LO's reset 15 clocks after the RF's: at 120 clocks
per 100 kHz cycle that is a ⅛-cycle offset, duty 2·⅛ = ¼, predicted DC
level 1024/4 = **256 counts**. The run output lands on it exactly.

This degenerate case has a name you've met: **zero beat**. It is the
theremin's null — hand at rest, both oscillators tuned identical, beat
frequency zero, silence. The handoff documents in this repository spend
pages on that null; you have now built the circuit that defines it.

#### The image problem: the mixer can't tell up from down

Look once more at the identity. The difference term is cos(2π(f₁−f₂)t),
and cosine is *even*: cos(−x) = cos(x). An RF at 440 Hz *below* the LO
and an RF at 440 Hz *above* it produce byte-for-byte the same output.
The mixer reports |f_rf − f_lo| and destroys the sign. The discarded
twin is called the **image frequency**, and our testbench contains its
fingerprint: the R1 prediction

```vhdl
constant BEAT_DUMPS : real :=
  2.0 ** W / (real(FCW_LO - FCW_RF) * real(WIN));
```

is *signed* arithmetic — the TB knows which oscillator is higher. The
hardware's output does not. Move the RF to the mirror frequency on the
far side of the LO (Explore 1) and the mixer's output is *identical* —
same beat, same timestamps — while the TB's signed prediction goes
negative and R1 fails against it. The testbench discovers, by
disagreeing with a perfectly healthy DUT, that it computed a quantity
the physical circuit cannot know.

For the theremin this is a real, audible phenomenon: if the instrument
is tuned so the hand can push the variable oscillator *through* zero
beat, the pitch falls to silence and then **rises again on the far
side** — the pitch field folds into a mirror image around the null.
Players know this failure mode; now you know its name. For radar it is
much worse than a tuning quirk, and it is where the Radar Connection
must pick up the story.

### Radar Connection

Put the two block diagrams side by side and stop being polite about it:

```
CW Doppler radar:                         Theremin:

 TX osc ──┬────────► antenna ~~►  target   fixed osc ──┬─────────► (nothing)
          │                        │ ~~ echo,          │
          │                        ▼    shifted        │   variable osc,
          │                   RX antenna               │   detuned by the
          │                        │                   │   hand's capacitance
          ▼                        ▼                   ▼         │
        [ mixer ] ◄────────────────┘                 [ mixer ] ◄─┘
            │  beat = 2v/λ  (Doppler)                    │  beat = k·ΔC(hand)
            ▼                                            ▼
        audio out → operator's headphones            audio out → loudspeaker
```

Same LO, same mixer, same audio-rate IF, same *detection philosophy*:
an oscillation carries a minuscule fractional deviation (a 70 Hz Doppler
shift on a 10 GHz carrier is 7 parts per *billion*), so you beat it
against a reference and the common carrier cancels, leaving the
deviation as the entire output signal. Both are **homodyne** receivers —
LO at (essentially) the RF frequency, mixing straight to baseband. Early
CW radar operators literally listened on headphones, and a target
crossing the beam played a glissando: the theremin experience, down to
the sound. The HB100 module waiting in lesson 99's epilogue is this
diagram at 10.525 GHz — its IF pin outputs the beat directly, and you
will wire it into *this same chain*.

Be honest about the one real difference, because it's the difference
between the instruments, not the receivers. What the beat *encodes*
differs: the Doppler radar's beat is 2v/λ — **velocity**, via the phase
rate of the moving echo; the theremin's beat is k·ΔC — **position**, via
capacitive detuning of the oscillator; an FMCW radar's beat is
(2R/c)·chirp-slope — **range**, via round-trip delay against a swept LO.
Three different physical encoders in front of the *same heterodyne
receiver*. That receiver-front-end sameness is why this course keeps
claiming radar transfer: you have now built, verified, and characterized
the block that all of them share. A theremin is a CW radar whose target
modulates the transmitter instead of the echo — or, if you prefer it the
other way, a CW radar is a theremin that plays range-rate.

Superheterodyne, in one breath, since you own the pieces: homodyne is
simple but fragile — every amplifier imperfection and all the 1/f noise
lives right at your output frequency — so real receivers mix to a fixed
IF first, do their filtering and gain there, then mix again. Two
heterodyne hearts in series; the identity applied twice.

And the image problem is why **quadrature** exists. A radar that can't
tell +f_d from −f_d can't tell approaching from receding — operationally
catastrophic. The fix: mix twice, against two LOs 90° apart, cos(2πf_LO·t)
and sin(2πf_LO·t), producing two IF channels called **I** and **Q**.
Together they form the complex signal I + jQ = e^(j2π(f₁−f₂)t), a phasor
whose rotation *direction* — which channel leads — is the sign the single
real mixer threw away. Half the reason lesson 04's NCO exports its full
`phase` port is sitting right here: a second square tapped a quarter-turn
ahead (`phase + 2^(W−2)`, then take the MSB) is a free 90°-shifted LO,
and two copies of this lesson's mixer would give you I and Q. The
theremin never bothers — the player's ear closes the loop, and proper
tuning keeps the hand on one side of the null — but when the HB100 shows
up with *its* two output pins, you'll know why there are two.

**Stopping point.** You should now be able to explain:

- why multiplying two tones produces exactly a sum frequency and a
  difference frequency, and why the difference term carries the hand's
  detuning into the audible band with the carrier cancelled out.
- why XOR on two square waves is a true ±1 multiplication rather than an
  analogy, and why the leftover global sign only flips the DC sense of
  the output.
- why a 1024-clock accumulate-and-dump passes the 440 Hz difference at
  ~0.998 gain but bounds the ~200 kHz sum below about −35 dB, and why
  its nulls land exactly on the frequencies that would alias onto DC
  after decimation.
- what quantity the mixer's |f_rf − f_lo| output destroys, and how mixing
  against two LOs 90° apart recovers it.

---

## Session 12.2 — Build & Run (~90 min)

### Build

Three files plus the Makefile. `nco.vhd` is lesson 04's file, reused
verbatim — copy your lesson 04 copy rather than retyping it; it must be
identical. Solutions live in `course/solutions/lesson12/`; type the new
code in and resist peeking until you've attempted the Explore exercises.

**File: course/work/lesson12/nco.vhd**

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

Unchanged since lesson 04 — that's the point. Two NCO instances at
different `fcw` values are our RF and LO "transmitters"; the same core
that was a tone generator in lesson 04 and a STALO in the radar analogy
is both at once here.

**File: course/work/lesson12/het_mixer.vhd**

```vhdl
-- het_mixer.vhd — heterodyne mixer: XOR product detector + accumulate-and-dump.
--
-- Requirements this module implements (verified in het_mixer_tb.vhd):
--   R1: with rf_in and lo_in square waves offset in frequency by df, if_out
--       oscillates at the beat (difference) frequency df: it is the count of
--       clocks in each 2**ACC_LOG2-clock window during which rf_in /= lo_in,
--       which sweeps 0..2**ACC_LOG2 as the RF/LO phase difference slews.
--   R2: with rf_in and lo_in at the same frequency, if_out settles to a
--       constant proportional to their phase difference (no beat — the mixer
--       degenerates into a phase detector).
--
-- Why XOR: a square wave is a +/-1 signal in disguise ('0' = -1, '1' = +1),
-- and for such signals multiplication IS exclusive-nor; XOR gives the same
-- product with a sign flip, which only inverts the DC sense of if_out.
-- Multiplying two tones yields sum and difference frequencies; the
-- accumulate-and-dump window is a boxcar low-pass that crushes the ~2*f_rf
-- sum product and keeps the audio-rate difference. if_out needs
-- ACC_LOG2 + 1 bits because a window of all-ones counts to exactly
-- 2**ACC_LOG2.
--
-- rf_in/lo_in are sampled directly in the clk domain: in this lesson both
-- come from on-chip NCOs. A real antenna oscillator would pass through
-- sync_2ff (lesson09) first.
--
-- Radar analog: this is downconversion to an IF, the front half of every
-- superheterodyne receiver — and the reason a theremin is a CW radar: the
-- audible note IS the IF of a hand-tuned oscillator beaten against a
-- reference.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity het_mixer is
  generic (
    ACC_LOG2 : positive := 10  -- accumulate-and-dump window = 2**ACC_LOG2 clocks
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;  -- synchronous, active-high
    rf_in  : in  std_logic;  -- "antenna" oscillator (RF port)
    lo_in  : in  std_logic;  -- reference oscillator (LO port)
    if_out : out unsigned(ACC_LOG2 downto 0);  -- dumped window sum, 0..2**ACC_LOG2
    if_stb : out std_logic   -- 1-clk strobe: if_out just updated
  );
end entity het_mixer;

architecture rtl of het_mixer is
  constant WIN_LAST : unsigned(ACC_LOG2 - 1 downto 0) := (others => '1');

  signal mix      : std_logic;
  signal cnt      : unsigned(ACC_LOG2 - 1 downto 0) := (others => '0');
  signal acc      : unsigned(ACC_LOG2 downto 0)     := (others => '0');
  signal if_out_r : unsigned(ACC_LOG2 downto 0)     := (others => '0');
  signal if_stb_r : std_logic := '0';
begin

  mix <= rf_in xor lo_in;  -- the 1-bit multiplier

  accumulate_and_dump : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt      <= (others => '0');
        acc      <= (others => '0');
        if_out_r <= (others => '0');
        if_stb_r <= '0';
      else
        if cnt = WIN_LAST then
          -- dump: publish the window sum (including this final clock's
          -- contribution) and restart the accumulator.
          if mix = '1' then
            if_out_r <= acc + 1;
          else
            if_out_r <= acc;
          end if;
          if_stb_r <= '1';
          acc      <= (others => '0');
        else
          if mix = '1' then
            acc <= acc + 1;
          end if;
          if_stb_r <= '0';
        end if;
        cnt <= cnt + 1;  -- wraps naturally mod 2**ACC_LOG2: window cadence
      end if;
    end if;
  end process;

  if_out <= if_out_r;
  if_stb <= if_stb_r;

end architecture rtl;
```

Dissection:

- **The header carries the argument, not just the interface** — R1/R2 in
  measurable terms, the XOR-is-multiplication claim, the width fencepost,
  and the sync_2ff caveat. This module will be read by someone holding an
  HB100 someday; the *why* travels with the file.
- **One combinational gate, one clocked process.** `mix` is the entire
  RF section. The process is lesson 10's shape again: a free-running
  window counter (`cnt` wraps mod 2^ACC_LOG2 — compare `freq_meas`,
  where the window was defined by the *signal's* edges; here it's defined
  by the clock, because the mixer must keep integrating even at zero
  beat when the inputs stop disagreeing entirely).
- **The dump cycle counts too.** On `cnt = WIN_LAST` the publish adds the
  final cycle's contribution (`acc + 1` if `mix = '1'`) rather than
  dropping it — 1024 cycles per window, each counted exactly once. Write
  the two-branch publish out; "publish then clear" as two sequential
  statements would be a software instinct, and both assignments happen
  on the same edge anyway.
- **`if_out_r` holds between dumps; `if_stb_r` is one clock wide** — the
  producer handshake shape of lessons 10 and 11, so downstream logic (or
  a testbench) samples each measurement exactly once.

**File: course/work/lesson12/het_mixer_tb.vhd**

```vhdl
-- het_mixer_tb.vhd — self-checking testbench for the heterodyne mixer.
--
-- Setup: two NCOs (lesson04's nco.vhd, W = 32, 12 MHz clock) drive the RF
-- and LO ports as square waves at ~100.000 kHz and ~100.440 kHz. The
-- difference is ~440 Hz — concert A, made audible by mixing two radio-rate
-- signals neither of which you could hear. Requirement tags (R1, R2 from
-- het_mixer.vhd):
--
--   R1: if_out oscillates at the beat frequency. Measured by hysteresis
--       threshold crossings of the dumped-sample sequence (arm below 1/4
--       scale, fire at 3/4 scale — the beat envelope is a full-scale
--       triangle, so midscale-with-hysteresis is unambiguous). The mean
--       crossing-to-crossing spacing must match the fcw-predicted beat
--       period within 5%.
--   R2: with equal fcw on both NCOs (LO reset released 15 clocks late to
--       give a fixed ~1/8-cycle phase offset), if_out settles to a constant
--       near WIN/4 — spread <= 64 counts, no beat. Zero offset would give a
--       constant too, but a boring all-zero one; the offset shows the mixer
--       acting as a phase detector.
--
-- Timing note: dumps are caught with 'wait until rising_edge(clk) and
-- if_stb = '1''. if_stb is registered and 1 clk wide, so the wait fires on
-- the clock edge AFTER the dump edge, when if_out has been stable for a
-- full cycle — each dump is sampled exactly once.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity het_mixer_tb is
end entity het_mixer_tb;

architecture sim of het_mixer_tb is
  constant W        : positive := 32;         -- NCO phase width
  constant CLK_PER  : time     := 83.333 ns;  -- 12 MHz
  constant ACC_LOG2 : positive := 10;
  constant WIN      : natural  := 2 ** ACC_LOG2;  -- 1024 clks = 85.3 us/dump

  -- fcw = f_out * 2**32 / 12 MHz, rounded to nearest integer.
  constant FCW_RF : natural := 35791394;  -- ~100.000 kHz
  constant FCW_LO : natural := 35948876;  -- ~100.440 kHz
  -- Predicted beat period, in dumps: 2**32 / ((FCW_LO - FCW_RF) * WIN).
  constant BEAT_DUMPS : real :=
    2.0 ** W / (real(FCW_LO - FCW_RF) * real(WIN));

  constant LO_THR : natural := WIN / 4;      -- hysteresis arm level
  constant HI_THR : natural := 3 * WIN / 4;  -- hysteresis fire level

  signal clk     : std_logic := '0';
  signal rst_rf  : std_logic := '1';
  signal rst_lo  : std_logic := '1';
  signal rst_mix : std_logic := '1';
  signal lo_word : unsigned(W - 1 downto 0) := (others => '0');
  signal sq_rf   : std_logic;
  signal sq_lo   : std_logic;
  signal ph_rf   : unsigned(W - 1 downto 0);
  signal ph_lo   : unsigned(W - 1 downto 0);
  signal if_out  : unsigned(ACC_LOG2 downto 0);
  signal if_stb  : std_logic;
  signal done    : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  nco_rf : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst_rf,
      en     => '1',
      fcw    => to_unsigned(FCW_RF, W),
      phase  => ph_rf,
      sq_out => sq_rf
    );

  nco_lo : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst_lo,
      en     => '1',
      fcw    => lo_word,
      phase  => ph_lo,
      sq_out => sq_lo
    );

  dut : entity work.het_mixer
    generic map (ACC_LOG2 => ACC_LOG2)
    port map (
      clk    => clk,
      rst    => rst_mix,
      rf_in  => sq_rf,
      lo_in  => sq_lo,
      if_out => if_out,
      if_stb => if_stb
    );

  main : process
    variable sample   : natural;
    variable armed    : boolean;
    variable n_cross  : natural;
    variable first_x  : natural;
    variable last_x   : natural;
    variable avg_d    : real;
    variable beat_hz  : real;
    variable vmin     : natural;
    variable vmax     : natural;
    variable vsum     : natural;
  begin
    ----------------------------------------------------------------------
    -- R1: offset frequencies -> if_out beats at the difference frequency.
    ----------------------------------------------------------------------
    rst_rf  <= '1';
    rst_lo  <= '1';
    rst_mix <= '1';
    lo_word <= to_unsigned(FCW_LO, W);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst_rf  <= '0';  -- both NCOs start at phase 0: beat envelope starts
    rst_lo  <= '0';  -- at 0 and rises as the phase difference slews.
    rst_mix <= '0';

    armed   := true;
    n_cross := 0;
    first_x := 0;
    last_x  := 0;
    for d in 1 to 280 loop  -- 280 dumps ~ 23.9 ms ~ 10.5 beat periods
      wait until rising_edge(clk) and if_stb = '1';
      sample := to_integer(if_out);
      if armed and sample >= HI_THR then
        if n_cross = 0 then
          first_x := d;
        end if;
        last_x  := d;
        n_cross := n_cross + 1;
        armed   := false;
      elsif (not armed) and sample <= LO_THR then
        armed := true;
      end if;
    end loop;

    assert n_cross >= 3
      report "R1 FAIL: only " & integer'image(n_cross) &
             " threshold crossings; no beat visible"
      severity error;
    avg_d   := real(last_x - first_x) / real(n_cross - 1);
    beat_hz := 1.0 / (avg_d * real(WIN) * 83.333e-9);
    report "R1 measured beat period = " & real'image(avg_d) &
           " dumps = " & real'image(avg_d * real(WIN) * 83.333e-9 * 1000.0) &
           " ms (beat ~= " & real'image(beat_hz) & " Hz, " &
           integer'image(n_cross) & " crossings)";
    assert abs(avg_d - BEAT_DUMPS) <= 0.05 * BEAT_DUMPS
      report "R1 FAIL: measured " & real'image(avg_d) &
             " dumps/beat, expected " & real'image(BEAT_DUMPS) &
             " (tolerance 5%)"
      severity error;
    report "R1 pass: beat period within 5% of expected " &
           real'image(BEAT_DUMPS) & " dumps (440 Hz)";

    ----------------------------------------------------------------------
    -- R2: equal frequencies -> if_out is a constant (phase detector mode).
    ----------------------------------------------------------------------
    rst_rf  <= '1';
    rst_lo  <= '1';
    rst_mix <= '1';
    lo_word <= to_unsigned(FCW_RF, W);  -- LO now equals RF
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst_rf  <= '0';
    rst_mix <= '0';
    for i in 1 to 15 loop  -- hold LO 15 clks: ~1/8 cycle offset at 120
      wait until rising_edge(clk);  -- clks/cycle -> XOR duty ~1/4
    end loop;
    rst_lo <= '0';

    for d in 1 to 2 loop  -- discard dumps straddling the staggered resets
      wait until rising_edge(clk) and if_stb = '1';
    end loop;
    vmin := WIN;
    vmax := 0;
    vsum := 0;
    for d in 1 to 60 loop
      wait until rising_edge(clk) and if_stb = '1';
      sample := to_integer(if_out);
      if sample < vmin then vmin := sample; end if;
      if sample > vmax then vmax := sample; end if;
      vsum := vsum + sample;
    end loop;

    report "R2 dc level = " & integer'image(vsum / 60) &
           " counts (min=" & integer'image(vmin) &
           " max=" & integer'image(vmax) & ", full scale " &
           integer'image(WIN) & ")";
    assert vmax - vmin <= 64
      report "R2 FAIL: if_out spread " & integer'image(vmax - vmin) &
             " counts with equal frequencies; expected a constant"
      severity error;
    report "R2 pass: equal frequencies give constant if_out (no beat), " &
           "spread = " & integer'image(vmax - vmin) & " <= 64 counts";

    report "het_mixer testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **The stimulus is two instances of a verified module.** No hand-drawn
  waveforms: the NCOs' behavior was nailed down by lesson 04's TB, so
  frequency errors here indict the mixer, not the sources. Building
  testbenches out of already-verified blocks is how verification scales.
- **The fcw constants are the lesson's numbers made exact:**
  round(100 000·2³²/12 MHz) = 35 791 394 and round(100 440·…) =
  35 948 876; their difference, 157 482 fcw ticks, is 440.00 Hz to within
  a millihertz. `BEAT_DUMPS` re-derives the expected beat period in dump
  units — a *predicted* value, not a measured-then-frozen one.
- **Hysteresis, then averaging.** R1 doesn't check individual samples
  against a triangle template (the fuzz on the ramps would make that a
  tolerance-tuning nightmare); it extracts one robust feature — ¾-scale
  crossings with a ¼-scale re-arm — and averages 10 beat periods'
  spacing. Feature extraction plus averaging beats sample-by-sample
  comparison whenever the waveform is noisy-by-design.
- **The R2 stagger is stimulus engineering.** Equal frequencies with
  *equal* phase would hold `if_out` at a constant, boring zero.
  Releasing the LO reset 15 clocks late plants a known ⅛-cycle offset,
  so R2's "constant" is the informative 256, proving the phase-detector
  personality rather than merely "XOR of identical signals is 0".
- **`wait until rising_edge(clk) and if_stb = '1'`** — a VHDL-2008
  condition doing lesson 10's `wait_valid` in one line. The header's
  timing note argues why each dump is seen exactly once: the strobe is
  registered, so the wait fires one edge after the dump, when `if_out`
  has been stable a full cycle.
- **The first two R2 dumps are discarded** — the discard-then-check
  policy from lesson 10, because windows straddling the staggered resets
  mix pre- and post-reset behavior and test nothing.

**File: course/work/lesson12/Makefile**

```make
# Lesson 12 — het_mixer (the heterodyne heart). Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# het_mixer is the standalone physics-authentic path; theremin_top
# (lesson14) uses the measurement path instead.

TB         = het_mixer_tb
SRC        = nco.vhd het_mixer.vhd het_mixer_tb.vhd
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

The lesson 10 pattern exactly, including *no synthesis target* — but for
a different reason this time, stated in the header: everything here is
synthesizable, but `het_mixer` is the standalone physics-authentic path,
and `theremin_top` (lesson 14) uses the measurement path instead. `SRC`
order is load-bearing as always: the TB instantiates both other files.

### Run

From `course/work/lesson12/` (with the toolchain environment sourced —
the `fpga` alias from lesson 00 does this):

```bash
make sim
```

Expected output (a `mkdir -p build` line precedes this on the first run):

```text
ghdl -a --std=08 --workdir=build nco.vhd het_mixer.vhd het_mixer_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/het_mixer_tb het_mixer_tb
./build/het_mixer_tb --assert-level=failure
het_mixer_tb.vhd:148:5:@23893446092500fs:(report note): R1 measured beat period = 2.66e1 dumps = 2.2698575872 ms (beat ~= 4.405562735032895e2 Hz, 11 crossings)
het_mixer_tb.vhd:157:5:@23893446092500fs:(report note): R1 pass: beat period within 5% of expected 2.6633545421063996e1 dumps (440 Hz)
het_mixer_tb.vhd:190:5:@29184341595500fs:(report note): R2 dc level = 256 counts (min=255 max=259, full scale 1024)
het_mixer_tb.vhd:198:5:@29184341595500fs:(report note): R2 pass: equal frequencies give constant if_out (no beat), spread = 4 <= 64 counts
het_mixer_tb.vhd:201:5:@29184341595500fs:(report note): het_mixer testbench complete (any FAILs are listed above)
```

(Your home directory will differ in the shim path.) Read the numbers:

- **R1: 26.6 dumps measured vs 26.6335 predicted** — 440.6 Hz vs 440.0.
  The 0.13% miss is exactly what averaging quantized crossings buys you:
  each crossing snaps to a dump instant, first-to-last spans 10 beat
  periods, so the residual is a fraction of a dump spread over 10 beats.
  Concert A, recovered from two signals at 100 kHz. Say it out loud once.
- **R2: 256 counts dead on WIN/4** — the ⅛-cycle stagger analysis,
  measured. The min/max spread of 4 is honest quantization, and worth
  understanding: 1024 clocks is *not* a whole number of 120-clock input
  cycles (8.533…), so each window slices the frozen XOR pulse pattern at
  a different phase and the count wobbles a few clocks. The assert's
  ≤ 64 bound allows any such slicing; a *beat* would sweep the full
  0–1024 and miss it by an order of magnitude.
- **The timestamps**: R1 finishes at 23.9 ms simulated — 280 windows of
  85.3 µs. In that time roughly 2 400 cycles of 100 kHz RF got folded
  down to ten and a half cycles of concert A.

**Stopping point.** You should now be able to explain:

- why `if_out` needs ACC_LOG2 + 1 bits, and what silently happens to the
  beat's peaks if it is declared one bit narrow.
- why the publish on the window's last cycle adds the final clock's
  contribution (`acc + 1` when `mix = '1'`), so every one of the 1024
  clocks is counted exactly once.
- why R1 measures the beat with hysteresis threshold crossings averaged
  over ten periods rather than comparing samples against a triangle
  template, and why R2's 15-clock reset stagger predicts a DC level of
  exactly 256 counts.
- why `BEAT_DUMPS` is computed live from the fcw constants instead of
  frozen as 26.63, and what that buys the Explore edits.

---

## Session 12.3 — Explore & Checkpoint (~75 min)

### Explore

Attempt these before peeking at `course/solutions/lesson12/`.

1. **Find the image.** Set `FCW_RF` to `36106358` — about 100.880 kHz,
   the same 157 482 fcw ticks *above* the LO as the original was below
   it. Run. The mixer's output is *identical* — same beat report, same
   crossings, same femtosecond timestamps — but R1 now FAILs: the signed
   prediction `BEAT_DUMPS` went negative (−26.63) while the measurement
   stayed +26.6. Sit with what that means: the testbench knows which
   oscillator is higher and the hardware provably cannot. That is the
   image problem, demonstrated rather than asserted — and the reason the
   Radar Connection's I/Q machinery exists. Restore 35791394.
2. **Creep up on the null.** Set `FCW_LO` to `35811079` — a beat of only
   ~55 Hz, a hand hovering near the zero-beat point. R1 FAILs with
   `only 1 threshold crossings; no beat visible`, then reports `-nan`
   dumps (garbage statistics from one crossing — note the misleading
   unconditional "R1 pass" report line that still prints after the FAIL;
   the *FAIL lines* are the verdict, which is why the completion message
   says what it says). Nothing is broken: 280 dumps is 23.9 ms, and a
   55 Hz beat needs ~18 ms *per period* — the observation window sees
   barely one. Lesson 10's law again, wearing mixer clothes: resolving a
   small frequency difference costs observation time, T ≈ 1/Δf, in a
   counter, a mixer, or a radar dwell. Widen the R1 loop from 280 to
   1120 dumps and it passes: ~213.25 dumps/beat measured vs
   2³²/(19 685 · 1024) = 213.07 predicted from the fcw difference — the
   same crossing-quantization residual as the main run's R1 — ~55.0 Hz
   either way. Restore both.
3. **Break it: the wrong sign.** Change `mix <= rf_in xor lo_in;` to
   `xnor`. R1 still passes — the beat envelope inverts top-for-bottom,
   but an inverted triangle still crosses the hysteresis thresholds at
   the same rate — while R2's DC level lands at **768** = ¾ scale
   instead of 256: duty of *agreement* instead of disagreement. This is
   the "global sign only flips the DC sense" claim from Concepts, paid
   in full. Restore `xor`.
4. **Break it: filter the signal away.** Set the TB's `ACC_LOG2`
   constant to 14 (the generic follows it): windows of 16 384 clocks =
   1.37 ms, *longer than half the 2.27 ms beat period*. The boxcar's
   rolloff now cuts the 440 Hz beat itself to about half amplitude — the
   triangle never reaches the ¾-scale threshold — and R1 dies with
   `only 0 threshold crossings`, followed by a GHDL
   `bound check failure at het_mixer_tb.vhd:147`: with `n_cross = 0` the
   statistics code computes `n_cross - 1` on a `natural` and underflows.
   Two lessons for one edit: the LPF cutoff must sit *above* the IF you
   mean to keep (a radar that integrates longer than its Doppler period
   erases the Doppler), and TB math needs guarding against
   zero-evidence cases — this one crashed usefully only because
   `natural` bounds-checks. Restore 10.

### Tips & Pitfalls

- **Emacs / vhdl-mode:** the TB instantiates `nco` twice. Write `nco_rf`
  (or port-copy/paste it with `C-c C-p C-w` / `C-c C-p C-i` as in lesson
  10), copy the whole instantiation, edit the label and three signal
  names, then run `M-x vhdl-beautify-region` on the second copy — it
  re-aligns the `=>` columns so a mis-edited association jumps out
  visually instead of hiding in ragged whitespace.
- **Toolchain gotcha — severity `error` does not stop the run.** The
  Makefile's `--assert-level=failure` halts only on `failure` (like
  lesson 10's watchdog). R1/R2 asserts use `error`, so a failing
  requirement prints FAIL and *keeps simulating* — and unconditional
  `report` lines after it (including ones that say "pass") still print,
  as Explore 2 shows. The verdict discipline: **grep for FAIL**; that's
  what "any FAILs are listed above" is telling you.
- **The width fencepost is a silent killer.** `if_out : unsigned
  (ACC_LOG2 downto 0)` — that extra bit exists because a full window
  sums to exactly 2^ACC_LOG2. Write the habitual `ACC_LOG2-1 downto 0`
  and nothing errors: the beat's peaks wrap 1024 → 0 and the triangle
  grows notches. numeric_std wraps by design (lesson 03); *you* carry
  the width proof.
- **Registered sources make a clean gate.** `mix` is combinational, but
  both its inputs are register outputs (NCO phase MSBs), so it glitches
  only in the delta-cycle sense and is sampled by a flop anyway. Feed it
  from a real antenna oscillator without `sync_2ff` (lesson 09) and
  you'd have a genuine CDC bug — same rule as lesson 10, restated in the
  module header because this block is where an async input would arrive.
- **Keep predictions in constants, derived from other constants.**
  `BEAT_DUMPS` is computed from `FCW_*` and `WIN`, so Explore edits
  cascade correctly — change a frequency and the expectation follows.
  A hand-frozen `26.63` would have made Explore 1's discovery
  impossible: the TB would have *passed* on the image, which is the
  worst outcome in verification — a wrong design blessed by a stale
  expectation. (It failed usefully precisely because the prediction was
  live and signed.)

### Checkpoint

Before lesson 13 you must have:

- `course/work/lesson12/` containing `nco.vhd`, `het_mixer.vhd`,
  `het_mixer_tb.vhd`, and the `Makefile`, with `make sim` printing the
  R1 beat report (~26.6 dumps, ~440 Hz, 11 crossings), `R1 pass`,
  `R2 dc level = 256`, `R2 pass`, and the completion message — no FAIL
  lines.
- On paper, from memory: the product-to-sum identity; the two-line proof
  that XOR multiplies ±1 signals; and the beat arithmetic — fcw
  difference 157 482 → 440 Hz → 26.63 dumps at a 11.72 kHz dump rate.
- The image problem in two sentences: what a real mixer discards, and
  how an I/Q pair recovers it — plus where a free 90° LO would come from
  in this design (the NCO's phase port).
- The thesis, stated without notes, both directions: why a theremin is a
  CW radar, and what the beat encodes in the theremin, the CW Doppler
  radar, and the FMCW radar respectively.

Next: lesson 13 rejoins the integration path — `pitch_map` turns lesson
10's period measurements into frequency control words, and the
linearization honesty promised there comes due.
