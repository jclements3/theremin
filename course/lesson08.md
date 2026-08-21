# Lesson 08 — One-Bit DACs

*Where we are.* Lesson 07 left you with `sine_lut` producing clean 8-bit
signed samples — a sine wave that exists only as numbers inside the chip.
The iCE40 has no analog output: every pin drives 0 V or 3.3 V, nothing in
between. This lesson builds `dsm_dac`, a first-order delta-sigma modulator
that turns each sample into a stream of single bits whose *average* is the
sample, plus the resistor and capacitor that turn that average into volts.
It is the last new block on the output side of the chain — from lesson 09
onward we turn around and work on the input side, the antenna.

---

## Session 08.1 — Scheduling Ones (~75 min)

### Objectives

- Explain why a digital pin plus an analog low-pass filter is a DAC.
- Derive PWM from first principles, then articulate precisely why
  delta-sigma beats it: not less error, but error moved to frequencies
  the RC can kill.
- Trace the error-feedback loop by hand — accumulator, carry-out,
  residual — and prove the long-run ones-density is exact to within 1/N.
- State the noise-shaping result: quantization noise rises 6 dB/octave, so
  oversampling buys ~1.5 bits of in-band resolution per doubling of clock.
- Compute the RC filter values for lab day and defend them; explain how
  the testbench pins down a mean with a hard tolerance and no golden
  trace.

### Concepts

#### A pin and a capacitor is a DAC

A digital pin driving an RC low-pass filter produces, at the capacitor,
the *average* of what the pin did over the last few RC time constants.
Hold the pin high 75% of the time and the capacitor sits near
0.75 × 3.3 V = 2.475 V. That is the entire trick: the analog world
averages for free, with infinite amplitude resolution. So the design
problem is not "how do I make an analog value" but "how do I schedule 1s
and 0s so that (a) the local average tracks my sample and (b) the
leftover wiggle — the *ripple* — sits at frequencies the RC attenuates
into irrelevance." Every 1-bit DAC is a scheduling policy. There are two
classic policies.

#### Policy 1: PWM

The obvious schedule: chop time into frames of 2^W clocks (256 for
W = 8), drive the pin high for `sample` clocks per frame, low for the
rest — a counter and a comparator:

```
frame:   |<------------ 256 clocks ------------>|
sample=64:  1111...1 (64 ones)  0000........0 (192 zeros)
```

The frame average is exactly sample/256, and the frame rate is
12 MHz / 256 = 46.875 kHz — above audio, so 8-bit PWM would *sort of*
work here. But the pin swings rail to rail in one slab per frame, so
nearly all the error energy sits in a strong component at 46.875 kHz and
harmonics — only one decade above a 4.7 kHz filter pole, so a single
20 dB/decade RC leaves ~10% of rail-to-rail slosh: inaudible, but real
ultrasonic power into your amplifier, ready to intermodulate in anything
nonlinear. And PWM scales catastrophically: each extra bit *doubles* the
frame — 12-bit PWM at 12 MHz frames at 2.9 kHz, inside the audio band.
PWM couples resolution to frame rate because it insists on delivering the
ones in one contiguous burst. That contiguity buys nothing. Drop it.

#### Policy 2: spread the ones — delta-sigma

Same 64-ones-per-256-clocks budget, different schedule: deal the ones out
as evenly as possible.

```
PWM,  sample=64:  111...1000...0   repeats every 256 clocks -> 46.875 kHz
DSM,  sample=64:  0001 0001 0001   repeats every   4 clocks -> 3 MHz
```

Identical average — but the ripple fundamental moved from 46.875 kHz to
3 MHz, nearly three decades higher: almost 60 dB more attenuation through
the same single-pole RC, free. The error energy did not shrink; it was
*relocated* to where the filter is strong. That is noise shaping.

#### The error-feedback loop

The machine that produces the evenly-spread schedule is one accumulator.
First, map the signed sample into **offset binary** — plain unsigned
"fullness" from 0 to 255 — by adding 2^(W−1): −128 → 0, 0 → 128,
+127 → 255. (Adding 2^(W−1) mod 2^W is just inverting the sign bit; the
hardware is one `not` gate.) Call the result `x`. Now, every clock:

```
acc <= residual + x        -- (W+1)-bit add of two W-bit-range values
bit_out = carry out (bit W)
residual = low W bits of acc
```

The residual is the error not yet delivered to the pin. Each clock we add
the demand `x` on top of the outstanding error; when the total crosses 2^W
we emit a 1 — worth exactly 2^W of accumulated demand — and the leftover
stays behind as the new residual. **Nothing is ever thrown away.**

Walk it by hand at W = 3 with x = 3 (we owe the pin a density of 3/8),
starting from residual 0:

```
clock:      1   2   3   4   5   6   7   8
res + x:    3   6   9   4   7  10   5   8
bit_out:    0   0   1   0   0   1   0   1
residual:   3   6   1   4   7   2   5   0
```

Three ones in eight clocks — density exactly 3/8 — and they came out
spread (positions 3, 6, 8), not bunched PWM-style at the front. After 8
clocks the residual returns to 0 and the pattern repeats forever.

The exactness is a two-line proof. Each clock,
`2^W · bit_out = x + residual_before − residual_after`; summed over N
clocks the residual terms telescope, leaving

```
ones · 2^W  =  N·x  +  r_start − r_end
```

Both residuals are less than 2^W, so the measured density `ones/N` differs
from x/2^W by less than **1/N** — not "statistically", bounded, for every
N, every x, every starting state. Hold that bound; it is the foundation of
the testbench.

#### You have already built this machine

Look again: an accumulator that adds a constant every clock and emits its
overflow — lesson 04's phase accumulator. A first-order error-feedback
delta-sigma with a DC input *is* an NCO whose frequency control word is
the sample: the carry fires at rate x/2^W per clock, which is
`f_out = fcw · f_clk / 2^W` read as a pulse density. Lesson 04 called
x/2^W a pitch; today it is a voltage. Same identity, one adder.

#### Where the noise goes

Rewrite the per-clock identity as a signal statement:

```
y[n]  =  x/2^W  +  (r[n-1] − r[n]) / 2^W
```

The error term is the **first difference** of the bounded residual
sequence, and first-differencing is high-pass: frequency response
|1 − e^(−jω)| = 2·sin(πf/f_clk) — near zero at DC, rising 6 dB/octave,
maximal at f_clk/2. The error's total power is fixed (it is what it is
for a 1-bit output), but the loop *shapes* its spectrum: scarce near DC
where the audio lives, piled up near 6 MHz where the RC is 60 dB deep.
(A second-order loop double-differences and shapes at 12 dB/octave —
why audio-grade converters use order 2 and up. We don't need to.)

The accounting: with oversampling ratio OSR = f_clk / (2·f_band), a
first-order modulator's in-band noise power falls as 1/OSR³ — 9 dB, i.e.
1.5 bits, per doubling of OSR. Here OSR = 12 MHz / 40 kHz = 300 ≈ 2^8.2,
so shaping buys ~8.2 × 1.5 ≈ 12 bits over a bare 1-bit quantizer: about
13 effective bits in-band. Our source is 8-bit sine samples — the LUT,
not the DAC, is the bottleneck, and it is the cheap block to widen.

One honest caveat, the first-order loop's famous vice: **idle tones**.
With a DC input the output is perfectly periodic (you watched x = 3 repeat
every 8 clocks), and periodic ripple is a *tone*, not noise. The repeat
period at W = 8 is 256/gcd(x, 256) clocks — worst case 256, so no
spectral line sits lower than 12 MHz/256 = 46.875 kHz: every idle tone
this modulator can produce is ultrasonic, because the clock is fast and W
is small. Run the same loop at 1 MHz, or at W = 16, and tones land
in-band and you need dither or a higher-order loop. Explore 4 audits this
arithmetic.

#### The RC that turns bits into volts

Now the analog half, with lab-day values. To pass: the theremin's pitch
range is clamped (lesson 13) to C3–C6, sine fundamental at most
1046.5 Hz — call the passband "a few kHz". To stop: shaped noise from
~47 kHz up, bulk of it in the MHz.

**Stage 1: R = 1 kΩ, C = 33 nF.** Cutoff f_c = 1/(2πRC) = 4.8 kHz.
Single-pole attenuation is 20·log10(f/f_c) dB well above cutoff:

```
  1 kHz (audio)      ~ −0.2 dB   passes
 47 kHz (worst tone)   −20 dB
  3 MHz (x=64 ripple)  −56 dB
  6 MHz (x=128 ripple) −62 dB
```

A subtlety worth respecting: the shaped noise *rises* at 6 dB/octave
while a single pole falls at 6 dB/octave — one RC flattens the noise
floor rather than rolling it off. Into a powered speaker that is
inaudible and fine; if lab day reveals hiss, cascade **stage 2:
R = 10 kΩ, C = 3.3 nF** — same 4.8 kHz cutoff, impedance 10× stage 1's
so it barely loads the first pole (two *identical* RCs would drag both
cutoffs down). Bench notes: the output rides on a DC offset (midscale =
1.65 V), so **AC-couple** through ~1 µF into the amplifier (into 10 kΩ
that is a 16 Hz high-pass; the lowest note is 130 Hz) — and the amp
input impedance must be ≥10× the final R or it re-tunes the filter. Mark
all values "tune on bench" per lesson 99 custom.

#### Verifying a scheduling policy: the mean-tracking testbench

What should the TB check? Not the exact bit pattern — a golden trace,
brittle and mute about *why*. The contract is R1: *for a DC input held
for N clocks, the ones-density equals the mapped input to within 1/N.*
The TB turns the proven bound into an assert: hold each sample for
N_WIN = 4096 clocks, count the 1s, require the density to match
(sample + 128)/256 within 2%. The bound at N = 4096 is 1/4096 ≈ 0.024% —
two orders of magnitude of margin, which cheaply absorbs the one-clock
window shift from delta-cycle sampling (lesson 04's idiom — worth at most
one count, invisible under 2%).

Five DC points cover the range: −128, −64, 0, +64, +127 — expected
densities 0.0, 0.25, 0.5, 0.75, 255/256 ≈ 0.996. Note the top-end
asymmetry: two's complement has no +128, so full-scale positive is
255/256, not 1.0 — only full-scale *negative* gives a constant rail. R2
is the reset check, done with malice: full-scale positive sample applied
*while reset is asserted*, `bit_out` must stay low for five clocks —
reset must clear the accumulator and mask the input, not merely zero the
output once.

### Radar Connection

This lesson is the transmitter chapter of a radar education, in miniature.

- **Quantization noise is a floor you design, not suffer.** An exciter's
  DAC quantizes the waveform, and that error energy must land *somewhere*
  in the spectrum. Where is a design choice — the choice this lesson made
  twice (PWM vs DSM; first-order vs higher). High-speed RF DACs run
  noise-shaped modulators at GHz rates to push quantization noise out of
  the transmit band, where the analog reconstruction filter — their RC,
  grown up — removes it.
- **SFDR: the spur is a false target.** The number that rules exciter
  selection is spurious-free dynamic range: carrier to tallest spur. Our
  idle-tone analysis *was* an SFDR calculation — enumerate the discrete
  tones (periodic residuals), bound the lowest spur frequency, show every
  one falls out of band. In a radar, an in-band DAC spur transmitted,
  reflected, and received is indistinguishable from a target. Nobody dies
  when a theremin has a spur; the budgeting discipline is identical.
- **Oversampling trades rate for resolution — again.** Lesson 04: watch an
  NCO longer to resolve finer frequency. Lesson 10 trades gate time for
  measurement resolution; radar trades dwell/CPI for Doppler resolution.
  Today: clock rate for amplitude resolution, 1.5 bits per octave.
  Time-bandwidth is the conserved currency of signal processing.
- **The 1-bit transmitter is real.** A radar power amplifier at saturation
  (they all are; efficiency) is a 1-bit output stage: full power or
  nothing, waveform shaping done in timing, not amplitude. Class-D audio
  amps, switching PAs, and `dsm_dac` are one insight at three power
  levels: switches are efficient and linear things are expensive, so
  compute in time, filter in analog.

**Stopping point.** You should now be able to explain:

- why delta-sigma's error energy is no smaller than PWM's, and why
  relocating it to frequencies where the RC is strong is what makes a
  single pin a usable DAC.
- how the telescoping sum bounds the ones-density error by 1/N — for
  every N, every input, every starting residual, not statistically.
- why the quantization error is the first difference of a bounded
  residual sequence, and how that shape buys ~1.5 bits of in-band
  resolution per doubling of the oversampling ratio.
- why every idle tone this modulator can produce at W = 8 and 12 MHz
  lands at or above 46.875 kHz — ultrasonic by arithmetic, not by luck.

---

## Session 08.2 — Building the Modulator (~60 min)

### Build

Three files, byte-for-byte the reference implementation in
`course/solutions/lesson08/` — which you should resist opening until you
have attempted the Explore exercises. Type the code in; the walkthrough
explains every line.

**File: course/work/lesson08/dsm_dac.vhd**

```vhdl
-- dsm_dac.vhd — first-order error-feedback delta-sigma modulator (1-bit DAC).
--
-- Requirements this module implements (verified in dsm_dac_tb.vhd):
--   R1: for a constant (DC) sample, the long-run mean of bit_out equals
--       (sample + 2**(W-1)) / 2**W — i.e. the input mapped to [0, 1) of
--       full scale. The quantization error is pushed to high frequencies
--       (noise shaping), where the external RC filter removes it.
--   R2: synchronous active-high reset clears the error accumulator and
--       holds bit_out at '0' while asserted.
--
-- How it works: the signed sample is first mapped to offset binary
-- (add 2**(W-1), which is just inverting the sign bit). Each clock, the
-- W-bit residual error carried in acc(W-1 downto 0) is added to the input;
-- the carry out of that add — acc(W) — is the output bit, worth exactly
-- 2**W of accumulated input, and the remainder stays behind as the new
-- error. Nothing is ever thrown away, so the ones-density is exact in the
-- long run: this is the error-feedback form of a first-order delta-sigma.
--
-- Radar analog: 1-bit quantization with noise shaping is how exciters and
-- high-speed DACs trade amplitude resolution for oversampling rate; the
-- shaped quantization noise floor is what sets SFDR out of the transmitter.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsm_dac is
  generic (
    W : positive := 8  -- input sample width
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;               -- synchronous, active-high
    sample  : in  signed(W - 1 downto 0);  -- signed audio sample
    bit_out : out std_logic                -- density-modulated 1-bit output
  );
end entity dsm_dac;

architecture rtl of dsm_dac is
  -- acc(W) is the carry (output bit); acc(W-1 downto 0) is the residual error.
  signal acc        : unsigned(W downto 0) := (others => '0');
  signal offset_bin : unsigned(W - 1 downto 0);
begin

  -- signed -> offset binary: adding 2**(W-1) mod 2**W = inverting the MSB.
  offset_bin(W - 1)          <= not sample(W - 1);
  offset_bin(W - 2 downto 0) <= unsigned(sample(W - 2 downto 0));

  modulate : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      else
        -- residual error + input; carry out becomes the output bit.
        acc <= ('0' & acc(W - 1 downto 0)) + offset_bin;
      end if;
    end if;
  end process;

  bit_out <= acc(W);  -- registered: acc is the only state

end architecture rtl;
```

Dissection:

- **Header.** House style: requirements first (R1 the density contract
  with its exact formula, R2 reset), then mechanism, then the radar note.
  Every line below serves R1 or R2.
- **`acc : unsigned(W downto 0)`** — W+1 bits; the comment names the
  split: bit W the carry (the output), bits W−1..0 the residual. One
  register holds the loop's entire state. The `:= (others => '0')` init
  covers time zero before the first reset (NCO convention) — simulation
  convenience, never a substitute for `rst`.
- **The offset-binary mapping is two concurrent assignments,** not an
  adder: adding 2^(W−1) mod 2^W only ever flips the MSB, so the hardware
  is `not sample(W-1)` plus W−1 straight wires. The `unsigned(...)` on
  the low bits is a zero-cost type conversion (lesson 03).
- **The one line that is the whole modulator:**
  `acc <= ('0' & acc(W - 1 downto 0)) + offset_bin;`. Right to left:
  `acc(W - 1 downto 0)` takes the *residual only* — slicing off bit W
  consumes last cycle's output bit, the "− b·2^W" of the telescoping
  proof. `'0' &` zero-extends the residual so the sum has a home for the
  carry: `numeric_std`'s `+` returns the wider operand's width, so the
  (W+1)-bit left operand forces a (W+1)-bit result and the carry lands
  in bit W instead of vanishing. Add the demand, register the result.
- **`bit_out <= acc(W);`** is a wire off a register: glitch-free by
  construction, no logic between flop and pin — and a 1-bit DAC's
  "analog" precision lives entirely in its edge timing, so glitches on
  this net would be distortion. Synthesis makes the whole module one
  (W+1)-bit adder, W+1 flops, a reset mux, and an inverter — cheaper
  than the sine LUT that feeds it. Delta-sigma's exotica is in the
  analysis, not the netlist.

**File: course/work/lesson08/dsm_dac_tb.vhd**

```vhdl
-- dsm_dac_tb.vhd — self-checking testbench for the delta-sigma DAC.
--
-- Verification approach: every assert is tagged with the requirement it
-- verifies (R1..R2 from dsm_dac.vhd).
--   R1 is a mean-tracking property: for a DC input held over N_WIN clocks,
--   the ones-density of bit_out must match (sample + 2**(W-1)) / 2**W
--   within 2%. Because the error-feedback loop discards nothing, the true
--   density error over N_WIN samples is at most ~1/N_WIN, so N_WIN = 4096
--   leaves two orders of margin under the 2% bound. Checked at full-scale
--   negative, -1/2, 0, +1/2, and full-scale positive.
--   R2 checks that synchronous reset clears the accumulator and pins
--   bit_out low, even with a full-scale sample applied.
--
-- Sampling note: bit_out is registered, and the TB samples it immediately
-- after rising_edge(clk) — one delta before the new value propagates — so
-- the counted window is shifted one clock. For a density measurement that
-- moves the count by at most 1, absorbed by the 2% tolerance.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsm_dac_tb is
end entity dsm_dac_tb;

architecture sim of dsm_dac_tb is
  constant W       : positive := 8;
  constant CLK_PER : time     := 83.333 ns;  -- 12 MHz
  constant N_WIN   : positive := 4096;       -- averaging window (clocks)

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';
  signal sample : signed(W - 1 downto 0) := (others => '0');
  signal b      : std_logic;
  signal done   : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.dsm_dac
    generic map (W => W)
    port map (
      clk     => clk,
      rst     => rst,
      sample  => sample,
      bit_out => b
    );

  main : process
    -- R1: hold a DC sample for N_WIN clocks, measure the ones-density of
    -- bit_out, and compare against (s + 2**(W-1)) / 2**W within 2%.
    procedure check_mean(s : integer) is
      variable ones     : natural := 0;
      variable measured : real;
      variable expected : real;
    begin
      rst <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst    <= '0';
      sample <= to_signed(s, W);
      wait until rising_edge(clk);  -- first accumulation of the new sample
      for i in 1 to N_WIN loop
        wait until rising_edge(clk);
        if b = '1' then
          ones := ones + 1;
        end if;
      end loop;
      measured := real(ones) / real(N_WIN);
      expected := (real(s) + 2.0 ** (W - 1)) / 2.0 ** W;
      assert abs(measured - expected) <= 0.02
        report "R1 FAIL: sample=" & integer'image(s) &
               " measured_mean=" & real'image(measured) &
               " expected=" & real'image(expected)
        severity error;
      report "R1 pass: sample=" & integer'image(s) &
             " measured_mean=" & real'image(measured) &
             " expected=" & real'image(expected);
    end procedure;
  begin
    -- R2: synchronous reset clears the accumulator and pins bit_out low,
    -- even with a full-scale positive sample at the input.
    sample <= to_signed(2 ** (W - 1) - 1, W);
    rst    <= '1';
    wait until rising_edge(clk);
    for i in 1 to 5 loop
      wait until rising_edge(clk);
      wait for 1 ns;  -- let post-edge value settle
      assert b = '0'
        report "R2 FAIL: bit_out not held low during reset (cycle " &
               integer'image(i) & ")"
        severity error;
    end loop;
    report "R2 pass: reset clears accumulator and holds bit_out low";

    -- R1 across the DC range: min, -1/2 scale, midscale, +1/2 scale, max.
    check_mean(-2 ** (W - 1));      -- -128: expected mean 0.0
    check_mean(-2 ** (W - 2));      --  -64: expected mean 0.25
    check_mean(0);                  --    0: expected mean 0.5
    check_mean(2 ** (W - 2));       --  +64: expected mean 0.75
    check_mean(2 ** (W - 1) - 1);   -- +127: expected mean 255/256

    report "dsm_dac testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **The header states the verification approach** before any code —
  property, tolerance justification, sampling note — so a reviewer can
  audit the TB's honesty from the header alone.
- **`check_mean` is a procedure declared inside the process** (the
  lesson 04 pattern): it can drive `rst` and `sample` and consume time.
  Each call is self-contained — reset, apply, settle one clock, count —
  so the five checks are order-independent: reorder or delete any and the
  others still pass. Diagnostic, not a fragile script.
- **The extra `wait until rising_edge(clk)` before the loop** lets the
  first accumulation of the new sample happen before counting starts —
  skipping it would count one stale clock, absorbed by the 2% anyway, but
  the TB documents intent by waiting, not by spending slack.
- **The counting loop deliberately does not `wait for 1 ns`** — lesson
  04's delta-cycle stance: the property tolerates a one-clock window
  shift, so the TB reads one delta early and lets the math absorb it. The
  R2 check, outside any hot loop, *does* burn `wait for 1 ns` — the
  readable choice where performance is free.
- **`measured` and `expected` are `real`,** one formula each — no
  per-point magic constants to fat-finger. The pass line prints both, so
  the log is evidence, not just a verdict.

**File: course/work/lesson08/Makefile**

```make
# Lesson 08 — minimal GHDL sim flow. Usage: make sim  (after
# sourcing ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile
# in miniature — same flags, same shim, no synthesis targets.

TB         = dsm_dac_tb
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) dsm_dac.vhd dsm_dac_tb.vhd
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
```

The lesson 00/04 Makefile in minimal form: analyze in dependency order
(DUT before TB — analysis order is load-bearing, lesson 04), elaborate
with the glibc shim, run. Sim-only: `dsm_dac` reaches silicon inside
`theremin_top` in lesson 14. No `--wave=` on the run line this time;
Explore 2 adds it back temporarily.

### Run

From `course/work/lesson08/` (toolchain environment sourced — the `fpga`
alias from lesson 00):

```bash
make sim
```

Expected output:

```text
ghdl -a --std=08 --workdir=build dsm_dac.vhd dsm_dac_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/dsm_dac_tb dsm_dac_tb
./build/dsm_dac_tb --assert-level=failure
dsm_dac_tb.vhd:94:5:@459331500fs:(report note): R2 pass: reset clears accumulator and holds bit_out low
dsm_dac_tb.vhd:76:7:@342040298500fs:(report note): R1 pass: sample=-128 measured_mean=0.0 expected=0.0
dsm_dac_tb.vhd:76:7:@683622265500fs:(report note): R1 pass: sample=-64 measured_mean=2.5e-1 expected=2.5e-1
dsm_dac_tb.vhd:76:7:@1025204232500fs:(report note): R1 pass: sample=0 measured_mean=5.0e-1 expected=5.0e-1
dsm_dac_tb.vhd:76:7:@1366786199500fs:(report note): R1 pass: sample=64 measured_mean=7.5e-1 expected=7.5e-1
dsm_dac_tb.vhd:76:7:@1708368166500fs:(report note): R1 pass: sample=127 measured_mean=9.9609375e-1 expected=9.9609375e-1
dsm_dac_tb.vhd:103:5:@1708368166500fs:(report note): dsm_dac testbench complete (any FAILs are listed above)
```

(A first run also prints `mkdir -p build` at the top.) Read the numbers,
not just the passes: every measured mean is *exactly* the expected value,
because each test point's bit pattern has a period dividing 4096, so the
residual telescopes to precisely zero over the window — and
`9.9609375e-1` is 255/256 on the nose, the two's-complement asymmetry
visible in a log line. Timestamps check out too: five 4096-clock windows
plus resets ≈ 20 500 clocks at 83.333 ns ends at 1.708 ms.

**Stopping point.** You should now be able to explain:

- why the `'0' &` zero-extend is load-bearing — how it forces a
  (W+1)-bit sum so the carry lands in bit W instead of silently
  wrapping away.
- why `bit_out <= acc(W)` is glitch-free with no extra register, and
  why adding one "for safety" would only buy latency.
- why every measured mean in the log is *exactly* the expected value —
  each test point's bit pattern has a period dividing 4096, so the
  residual telescopes to precisely zero over the window.
- why the TB pins down a mean with a hard tolerance instead of diffing
  a golden bit trace, and where the 2% bound's two orders of margin
  come from.

---

## Session 08.3 — Break, Probe, Audit (~60 min)

### Explore

Attempt these before opening `course/solutions/lesson08/`.

1. **Break it: throw away the residual.** Change the accumulate line to
   `acc <= ('0' & offset_bin);` — each clock now quantizes the input alone
   and discards the error, i.e. a plain loop-free 1-bit quantizer.
   Predict, then run. Observed: the carry never fires (offset binary never
   reaches 2^W on its own), measured mean 0.0 everywhere — the −128 point
   still passes, the other four print `R1 FAIL` (each followed by the
   unconditional `R1 pass` progress line with the same numbers — the
   lesson 04 assert/report pairing). The feedback is not a refinement of
   the quantizer; it *is* the DAC. Restore and re-run to green.
2. **See the schedule.** Add `--wave=build/$(TB).ghw` to the run line and
   open the result in GTKWave: in the sample = +64 window `bit_out` ticks
   `0001 0001 ...` — the 3 MHz ripple from Concepts, on screen; at
   sample = 0, a clean `01` alternation (6 MHz). Imagine the PWM
   rendering of the same densities — a 64-clock slab per 256 — and you
   are looking at this lesson's whole argument. Remove the flag
   afterwards.
3. **Probe the 1/N bound.** Set `N_WIN` to 64: all five points still
   pass, but +127 now reads `measured_mean=9.84375e-1` — 63/64, off by
   1.2%, inside 2% but no longer exact (64 clocks can't contain its
   256-clock pattern). Set `N_WIN` to 32: only +127 fails (31/32 ≈
   0.969, off 2.7%) — and the ledger agrees, 1/32 = 3.1% exceeds the 2%
   tolerance, so the *guarantee* is gone; yet the points whose pattern
   periods divide 32 still measure perfectly. The bound is worst-case;
   failure starts at the longest pattern. Restore N_WIN = 4096.
4. **Idle-tone audit (paper).** For DC offset-binary x the pattern
   repeats every 256/gcd(x, 256) clocks (why? — the residual sequence is
   x, 2x, 3x, ... mod 256, first back to start after 256/gcd steps).
   Tabulate period and fundamental for x = 128, 64, 96, 129; confirm the
   slowest fundamental is 46.875 kHz; then find the clock frequency at
   which an idle tone first lands inside a 20 kHz audio band (answer:
   f_clk < 5.12 MHz). We clock at 12 MHz — now you know the *margin* on
   the claim, not just the claim.

### Tips & Pitfalls

- **Emacs / vhdl-mode:** after hand-editing alignment-sensitive code like
  the TB's constant block, run `M-x vhdl-beautify-buffer` (bound to
  `C-c M-b`; `C-c C-b` for the region) — it re-indents and re-aligns
  declarations, port maps, and assignment columns. The solutions are
  formatted that way; beautify before diffing and whitespace noise
  disappears from the comparison.
- **Toolchain gotcha — give the carry a home.** Drop the zero-extend —
  `acc <= acc(W - 1 downto 0) + offset_bin;` — and `numeric_std`'s `+`
  returns a W-bit result; assigning it to the (W+1)-bit `acc` is a length
  mismatch GHDL only catches as a *bound check failure at run time*:
  `<f6>` compiles green, the sim dies at cycle one, and `M-g n` has
  nothing to jump to — read the runtime error's file:line yourself. Had
  the widths happened to match, the add would have silently wrapped and
  eaten the carry: `numeric_std` never warns about overflow. When a carry
  matters, make room for it explicitly — that is what `'0' &` is for.
- **Don't "clean up" the output with an extra flop.** Registering
  `bit_out` "for safety" adds latency for nothing: `acc(W)` *is* a flop
  output already. Know what is registered by construction before adding
  registers by reflex.
- **On the bench, the RC is part of the design.** The correctness claim is
  *joint*: bits with this spectrum plus a filter with that cutoff. Drive a
  speaker straight from the pin and you are listening to MHz ripple
  through whatever accidental filter your wiring is; hang a 100 Ω load on
  the 1 kΩ R and you've built a 10:1 attenuator and moved the cutoff.
  Check the amp's input impedance before blaming the VHDL.

### Checkpoint

Before lesson 09 you must have:

- `course/work/lesson08/` with the three files, and `make sim` printing
  `R2 pass`, five `R1 pass` lines whose measured means are exactly 0.0,
  2.5e-1, 5.0e-1, 7.5e-1, and 9.9609375e-1, the completion message, and
  no `FAIL` lines.
- On paper, from memory: the offset-binary mapping (and why it is one
  inverter), the telescoping argument bounding density error by 1/N, and
  why first-differenced noise is high-pass shaped.
- The lab-day filter in your notes: 1 kΩ + 33 nF (f_c ≈ 4.8 kHz), optional
  second stage 10 kΩ + 3.3 nF, AC-couple ~1 µF into ≥10 kΩ — marked "tune
  on bench".
- A one-sentence answer to "why not PWM?" that says where the error energy
  sits, not just that delta-sigma is fancier.

Next: lesson 09 crosses to the input side of the chain — the antenna
oscillator is asynchronous to everything, and the two-flop synchronizer is
how it enters the 12 MHz domain without taking the design down with it.
