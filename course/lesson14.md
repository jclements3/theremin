# Lesson 14 — Integration

*Where we are.* Thirteen lessons ago you compiled "hello". Since then you
have built and verified, in isolation, every organ of the instrument: an
NCO (04), a sine table (07), a delta-sigma DAC (08), a synchronizer (09),
a frequency counter (10), a UART you'll want on the bench (11), a mixer
that taught you why a theremin is a CW radar (12), and a pitch mapper (13).
Today there is no new arithmetic and no new VHDL. Today you wire a
six-module chain of verified blocks into `theremin_top` — the seventh
verified file, `osc_model`, stays on the testbench side, playing the
antenna — prove the *system* end-to-end against a simulated hand, and make it fit and meet timing on both boards. This is
the lesson where you discover that a pile of correct modules is not yet a
correct instrument — and that the gap between the two has its own
engineering discipline, with its own tests, budgets, and failure modes.
Lesson 99 flashes the result onto hardware; everything before that moment
happens here, in simulation.

---

## Session 14.1 — The System View (~75 min)

### Objectives

- Wire the six-module verified chain into `theremin_top` exactly per the
  curriculum signal chain, with a power-on reset and registered boundaries,
  and explain why system timing then decomposes module-by-module.
- Run an end-to-end **system test**: black-box stimulus and checking
  through the DUT's four real pins, with `osc_model` standing in for the
  antenna hardware and the audio fundamental recovered from the 1-bit
  delta-sigma stream itself.
- Derive the testbench's settling time (25 ms) and tolerance (2%) from
  numbers you already own — measurement cadence, smoothing time constant,
  quantization — instead of guessing them.
- Read and defend the resource budget: yosys statistics, nextpnr
  utilisation on hx1k (495/1280) vs hx8k (495/7680), all 168 flip-flops
  accounted for by hand, and why `ICESTORM_RAM` reads 0.
- Read the icetime critical path — `period` register, through `pitch_map`'s
  arithmetic, into `fcw_r` — and state the timing margin at 12 MHz.

### Concepts

#### Integration is a discipline, not a chore

Every module you are about to instantiate has a green, requirement-tagged
testbench. So what is left to get wrong? Plenty — and none of it lives
*inside* a module:

- **Interface mistuning.** `freq_meas` with EDGES=64 and `pitch_map` with
  P_REF=3840 are each individually correct for *any* generic values; only
  the pair (P_REF = EDGES · f_clk / f_osc) makes the instrument play C4.
  A unit TB cannot see that coupling. Explore 1 breaks it and watches the
  units stay green while the system goes musically wrong.
- **Wiring and width errors.** Which 10 of the NCO's 32 phase bits feed the
  sine table decides whether you get 261 Hz or a 5 MHz buzz. Both are
  "correct" VHDL.
- **Start-up.** No unit TB tests what happens when *everything* comes out
  of configuration at once with no reset pin on the board.
- **Physical budgets.** Fit, pins, and timing exist only at the top level.
  495 logic cells and a 28 ns critical path are properties of the
  *integration*, not of any module.

So this lesson's deliverables are exactly those four things: a top-level
netlist of verified parts, a system test, a start-up story, and a
fit/timing report for both boards. The curriculum's signal chain, one more
time, now with everything built:

```
antenna --> [74HC14 relaxation osc, ~200 kHz]   (hardware, lesson99;
                     |                           osc_model.vhd in sim)
             osc_in  v
      +----------------------------------------------------------+
      | sync_2ff --> freq_meas --> pitch_map --> nco --> sine_lut |
      |  (L09)        (L10)          (L13)      (L04)     (L07)   |
      |                                                    |      |
      |                                     dsm_dac <------+      |
      |                                      (L08)                |
      +----------------------------------------|-----------------+
                                     audio_out v  --> RC filter --> amp
```

One 12 MHz clock domain end to end. The antenna oscillator is the only
asynchronous input, and it crosses the border exactly once, through
`sync_2ff` — nothing else in the design is allowed to touch `osc_in`.

#### Registered boundaries, and why timing composes

Look down the chain and notice a deliberate pattern: **every module's
output comes from a register.** `freq_meas` registers `period` and
`valid`; `pitch_map` registers `fcw_r`; the NCO's `phase` *is* its
accumulator register; `sine_lut` registers `data`; `dsm_dac`'s `bit_out`
is a bit of its accumulator register. Consequence: any combinational path
in the whole system runs from one module's output register, through at
most *one* module's cloud of logic, into that module's own register. No
path threads combinationally through three entities; no module's internal
sloppiness can conspire with a neighbor's to blow the clock period.

That is what makes system timing *compose*: the system's f_max is simply
the slowest single module cloud, and you already know which one it is.
Lesson 13's `pitch_map` computes map → clamp → smooth — a 34-bit shifted
subtract, two magnitude compares, and a 33-bit add — in one clock, under a
`valid` that strobes once per 320 µs. It burns one lavish combinational
cloud where it can afford to (the data changes 3000 times a second, not
12 million), and icetime will shortly show you exactly that cloud as the
critical path: launched from the `period` register in `u_meas`, landing in
`u_map.fcw_r`, ~28 ns, one registered boundary crossed. Everything else in
the design is carry chains a fraction of that length.

The discipline costs latency — one clock per boundary — and here that is
the best bargain on the board: five extra clocks of pipeline against an
audio period of 46,000 clocks. When you integrate designs where latency
*does* matter (lesson 12's mixer chain, or any radar signal path), the
same rule holds; you just count the boundary registers into the range/
Doppler bookkeeping instead of ignoring them.

#### Waking up with no reset button

Neither board has a reset pin wired to anything. After configuration,
every register wakes in its init value and the design must sort itself
out. `theremin_top` reuses the phase-1 pattern: a 4-bit power-on-reset
counter holds `rst` high for the first 15 clocks, then releases it
forever. Fifteen clocks is not a magic number — one would nearly do — it
is simply long enough to guarantee every module sees at least one full
clock of coherent reset after configuration, and short enough (1.25 µs) to
be invisible.

Two start-up details are worth naming because the integration TB checks
them. First, `rst` is a combinational decode of `por_cnt` fanned out to
four modules — nextpnr will notice the load and promote it to a global
buffer; you'll see `promoting rst [reset] (fanout 129)` — the tool's own
tally of the reset network — and `SB_GB: 2` in the log. Second, remember lesson 13's courtesy: `pitch_map` resets `fcw_r`
to FCW_BASE, so the instrument wakes *playing C4* rather than sweeping up
from DC while the first measurements arrive. R1 in the testbench is the
whole story in one assert: within 2 ms of power-up, with no reset pin, the
delta-sigma bitstream must already be alive.

#### The integration testbench is a system test

The unit testbenches you have written probe wires a bench cannot reach.
This one deliberately does not. `theremin_top_tb` touches the DUT only
through its four real pins — `clk12`, `osc_in`, `audio_out`, `led_hb` —
which is exactly the access lesson 99's bench will have. On the input
side, `osc_model` (lesson 10's simulation-only target model, reused
verbatim) plays the antenna: a square wave at 200 kHz − hand · 20 kHz. The
TB moves `hand` through 0.0 → 0.5 → 1.0 and demands that the *audio
output* track it. Three problems must be solved to make that a real test.

**1. Recovering audio from a 1-bit stream.** `audio_out` is delta-sigma
noise at 12 MHz; the sine lives in its local ones-density. The TB reuses
lesson 12's accumulate-and-dump trick: sum the bitstream over BLK = 256
clocks (21.3 µs) and dump. The block sum is a boxcar low-pass filter —
audio at ~200–260 Hz sails through, the shaped quantization noise up near
megahertz is crushed — so the sine re-emerges as a slowly wobbling count
around 128. A comparator with ±32 counts of hysteresis around midscale
turns that into a clean square (`audio_hi`), immune to noise chatter near
the crossing, and timing N whole cycles of that square measures the
fundamental. This is a software RC filter plus a Schmitt trigger — the TB
contains a model of the *listener's* hardware, just as it contains a model
of the antenna's.

**2. Independent expected values.** What should the audio frequency *be*?
The TB never asks the DUT — it recomputes the answer in real arithmetic
from the module contracts you verified in lessons 10, 13, and 04:

```
period  = EDGES · f_clk / f_osc              (freq_meas contract, L10)
fcw     = FCW_BASE + (P_REF − period)·2^SHIFT (pitch_map contract, L13)
f_audio = fcw · f_clk / 2^32                  (nco contract, L04)

hand=0.0: f_osc=200 kHz → period=3840.0 → fcw=93640  → 261.6 Hz  (C4)
hand=0.5: f_osc=190 kHz → period=4042.1 → fcw≈80705  → 225.5 Hz
hand=1.0: f_osc=180 kHz → period=4266.7 → fcw≈66333  → 185.3 Hz
```

Three module contracts composed into one system prediction — if any wiring
error, width slip, or generic mismatch breaks the composition, measurement
and prediction part company. (A white-box tap on `fcw` via a VHDL-2008
external name would be the other legitimate probe; this GHDL build
miscompiles external names into sibling instances, so the TB stays
strictly black-box — the header says so, honestly.)

**3. A budgeted tolerance.** The checks allow ±2%. Not a shrug — a sum of
terms you own: `freq_meas` quantizes period to ±2 counts (lesson 10),
which the map amplifies to ±128 fcw ≈ 0.15% of pitch; the recovered
square's crossings quantize to one 21.3 µs block against ~4 ms audio
periods (≈0.5% worst case over two cycles); and the smoother dithers a few
fcw counts around its converged value. Everything else — and this is the
point — is *exact*: same clock, same contracts. 2% covers the budget with
margin while remaining far tighter than a semitone (6%), so a mistuned
integration cannot hide. Compare Explore 1's failure: 605 Hz against an
expected 262 — interface bugs miss by octaves, not percent.

**Settling, derived not guessed.** After each hand move the TB waits
25 ms. From lesson 13: the smoother closes 1/8 of the error per `valid`
strobe, strobes arrive every 320–356 µs here (64 antenna periods), so
25 ms ≈ 70 strobes ≈ 9 time constants — the worst-case 13 k-count fcw jump
decays to under 2 counts. Then `measure_audio` times two full cycles of
the recovered square, first rising crossing to last. And because the DUT
could in principle produce *no* crossings (that is one of the failure
modes worth detecting — see Explore 1's cousin, a phase-slice typo), a
watchdog process kills the run with a loud `severity failure` at 500 ms of
simulated time rather than letting `wait until` hang forever. A system
test that can hang is not a test; it's a vigil.

One cost to name out loud: this TB simulates ~110 *milliseconds* of a
12 MHz system — over a million clocks with a free-running real-time
oscillator model — and takes minutes of wall clock, not lesson 13's
sub-second. That is the price of testing at physical rate through physical
interfaces, and you pay it *once, at the system boundary*: unit TBs remain
your inner loop, the integration TB is the gate a change passes before you
call it done. Regression discipline in one sentence.

#### The resource budget: reading your own footprint

Yosys's statistics for `theremin_top` (you'll reproduce this in Run):

```
228   SB_CARRY      424   SB_LUT4
 33   SB_DFF          4   SB_DFFE
 87   SB_DFFESR      44   SB_DFFSR
```

First, the flip-flop audit — 33+4+87+44 = **168 flops**, and you can
account for every one from the entity declarations, module by module:

```
theremin_top  por_cnt 4 + hb_cnt 24                          =  28
sync_2ff      meta_ff + sync_ff                              =   2
freq_meas     sig_q 1 + running 1 + edge_cnt 6
              + cycle_cnt 24 + period 24 + valid 1           =  57
pitch_map     fcw_r                                          =  32
nco           acc                                            =  32
sine_lut      data                                           =   8
dsm_dac       acc                                            =   9
                                                          -- ----
                                                             168
```

Do this audit on every design you synthesize. It is five minutes of
arithmetic, it catches replicated or vanished state instantly, and it is
the habit that later lets you glance at a 40 k-LUT radar build and say
"that's 30% high" before opening a single report. The flavors tell their
own story — DFFESR is enable+sync-reset (fcw_r, the counters under rst),
DFFE is enable-only, plain DFF is the reset-less synchronizer and LUT
pipeline — the house style (sync resets, clock enables) reads straight
back out of the netlist.

After packing, nextpnr reports **495/1280 logic cells — 38% of the
iCEstick's hx1k**. The instrument fits the small board with headroom, and
the same netlist is 6% of the hx8k. That factor-of-six spare fabric is
lesson 99's insurance and next-course's invitation (the HB100 epilogue
wants an FFT).

And one line you must not skim: **ICESTORM_RAM: 0/16**. Lesson 07 sized
the sine table to fit a BRAM — where did it go? The yosys log answers, in
one line you'll find in Run: `using FF mapping for memory
theremin_top.u_lut.:223`. iCE40 BRAM only has a *synchronous* read port,
so yosys can infer one only if it can merge a register into the read
itself. Our `sine_lut` reads the ROM, then negates through a mux, *then*
registers — the negation sits between the array read and the flop, so the
merge is illegal and yosys honestly spends ~10% of the hx1k (~130 LCs) in
LUTs and flops instead — lesson 07's standalone synthesis put the exact
number at 132 SB_LUT4. At 495 LCs we can afford the rent; the day you
can't, the fix is architectural (register the raw ROM read, negate a
cycle later),
not a synthesis switch. The stat line is where you *notice*; lesson 07
told you to read it, this is why.

#### The timing story

Both boards place-and-route at 12 MHz with the same verdict from all three
graders (nextpnr post-place, nextpnr post-route, icetime): about **36 MHz
f_max against a 12 MHz requirement** — 3× margin. icetime's critical path
report reads like the design review writing itself: launch from a flop
holding `period[3]` (that's `freq_meas`'s output register), 94 logic
levels of `u_map.fcw_r_...` nets — the subtract-shift-clamp-smooth cloud
you wrote in lesson 13 — landing on `fcw_r`'s D input at 27.98 ns. One
module's cloud, one boundary crossed, exactly as the registered-boundary
argument promised. The 83.3 ns clock budget means nobody has to pipeline
anything today; Explore 3 measures how much of that margin is real by
asking nextpnr for 36 MHz and watching it fail honestly.

### Radar Connection

This lesson is the theremin edition of the most expensive question in
radar development: **how do you test a sensor before its world exists?**
You cannot fly a target through a lab. So every serious radar program
builds the world first, as models, and signs off the system against them:

- **Target and scene simulators.** Digital target generators synthesize
  returns with programmed delay, Doppler, amplitude, and clutter, and
  inject them at RF or IF into the *real* receiver chain — hardware in the
  loop, stimulus at the same port the antenna would drive. `osc_model` is
  precisely this instrument's target generator: `hand` is target position,
  `osc_in` is the injection port, and the whole production signal path
  downstream of that port is the real, synthesizable article.
- **Test at the ports, judge at the ports.** A range test cannot probe a
  flying radar's internal `fcw` equivalent; it sees what comes out the
  antenna and the data link. Our TB imposes the same honesty on itself —
  four pins, no internal taps — so the sign-off it produces is the same
  *kind* of evidence the bench will produce, and lesson 99 inherits a
  known-good chain rather than a pile of hopeful units. When the physical
  instrument misbehaves, the first diagnostic split is already made:
  the DSP chain is proven from `osc_in` to `audio_out`; suspect the
  breadboard oscillator, the RC, the wiring — the parts the model stood
  in for.
- **An independent truth model.** Ranges score a radar's track against
  GPS truth on the target, never against the radar's own telemetry. The
  TB's expected values are its truth source: module contracts composed in
  real arithmetic, computed without reading the DUT. Verifying a system
  against its own internals is how self-consistent nonsense passes test.
- **Error budgets, rolled up.** The ±2% tolerance is a miniature of a
  radar accuracy budget: quantization terms, filter-settling terms, each
  owned by a subsystem, summed with margin, and *written down* — so when a
  measurement lands outside the line, you know which line item to
  interrogate.
- **Models have envelopes.** A target simulator validated for 0–2 Mach
  proves nothing at Mach 3. Explore 2 pushes `osc_model` past the mapping
  range the truth model covers, and the TB's own math — not the DUT —
  goes wrong: a sign-off against a model is a sign-off *within that
  model's envelope*, a sentence that has ended more than one flight-test
  argument.

The dwell-time, mixing, and tracking physics came in lessons 10, 12, and
13. What this lesson adds is the systems-engineering layer radar shares
with every serious sensor program: integration against modeled targets,
budgets instead of vibes, and hardware bring-up as *confirmation* of a
simulation sign-off rather than discovery.

**Stopping point.** You should now be able to explain:

- why every module registering its output means the system's f_max is set
  by the slowest single module cloud — and which cloud that is here, and
  why it can afford to be lavish.
- how the testbench predicts the audio frequency without ever reading the
  DUT — three module contracts composed in real arithmetic — and which
  three quantization/settling terms the ±2% tolerance budgets for.
- where all 168 flip-flops live, module by module, and why
  `ICESTORM_RAM` reads 0 even though lesson 07 sized the sine table for a
  BRAM.
- why `osc_model` is this instrument's target generator in the
  radar sense, and why a sign-off against it is only valid inside the
  model's envelope.

---

## Session 14.2 — Build the Instrument (~60 min)

### Build

Nine VHDL files, two constraint files, and the Makefile. Seven of the
eleven you have already written and verified — they are reused here
**byte-identical** to their home lessons, which is the entire point:
integration adds wiring, never sneaky edits. Copy them from your earlier
work directories:

```bash
cd course/work/lesson14
cp ../lesson09/sync_2ff.vhd ../lesson10/{freq_meas,osc_model}.vhd \
   ../lesson13/pitch_map.vhd ../lesson05/nco.vhd \
   ../lesson07/sine_lut.vhd ../lesson08/dsm_dac.vhd .
```

They are reproduced in full below anyway (the lesson's standing rule: every
file, complete, pasteable), so a `diff` against your copies doubles as a
check that your earlier work is what you think it is. Solutions live in
`course/solutions/lesson14/`; resist peeking until you have attempted the
Explore exercises.

The six reused synthesis modules first, in Makefile analysis order:

**File: course/work/lesson14/sync_2ff.vhd**

```vhdl
-- sync_2ff.vhd — two-flip-flop synchronizer for a single async input bit.
--
-- Requirements this module implements (verified in sync_2ff_tb.vhd):
--   R1: a level change on async_in appears on sync_out within 2-3 rising
--       clk edges, exactly once — no glitches, no swallowed transitions
--       (for inputs held longer than two clk periods).
--   R2: sync_out changes only at rising clk edges (it is a registered
--       output; nothing combinational touches the async input downstream).
--
-- Why two flip-flops: the first FF samples a signal that can change at any
-- moment relative to clk, so it may go metastable. The second FF gives that
-- metastability a full clock period to resolve before anyone looks. RTL
-- simulation cannot show metastability — here the pair behaves as a plain
-- 2-stage delay — which is exactly why the TB's 3-edge allowance matters:
-- real silicon may need the extra edge.
--
-- No reset on purpose: a synchronizer carries no state worth initializing,
-- and a reset mux in this path only adds delay where margin matters most.
-- (For synthesis you would also pin the pair together with ASYNC_REG-style
-- attributes / a timing exception; that is a constraints topic, not RTL.)
--
-- Radar analog: every real sensor front end is asynchronous to the DSP
-- clock. This module is the border checkpoint the antenna oscillator must
-- pass through before freq_meas may count its edges.

library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff is
  port (
    clk      : in  std_logic;
    async_in : in  std_logic;  -- from another clock domain / the outside world
    sync_out : out std_logic   -- safe to use anywhere in the clk domain
  );
end entity sync_2ff;

architecture rtl of sync_2ff is
  signal meta_ff : std_logic := '0';  -- may go metastable in real hardware
  signal sync_ff : std_logic := '0';  -- resolved, clk-domain-clean copy
begin

  synchronize : process (clk)
  begin
    if rising_edge(clk) then
      meta_ff <= async_in;
      sync_ff <= meta_ff;
    end if;
  end process;

  sync_out <= sync_ff;

end architecture rtl;
```

**File: course/work/lesson14/freq_meas.vhd**

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

**File: course/work/lesson14/pitch_map.vhd**

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

**File: course/work/lesson14/nco.vhd**

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

**File: course/work/lesson14/sine_lut.vhd**

```vhdl
-- sine_lut.vhd — quarter-wave folded sine lookup table (the NCO's waveform memory).
--
-- Requirements this module implements (verified in sine_lut_tb.vhd):
--   R1: peak output amplitude is within 1 LSB of full scale
--       (+/-(2**(DATA_BITS-1) - 1)); the asymmetric most-negative code is
--       never stored, so negating a table entry can never overflow.
--   R2: quarter-wave symmetry is exact — data for phase p equals data for
--       phase 2**(PHASE_BITS-1)-1-p (sin(x) = sin(pi - x)); only
--       2**(PHASE_BITS-2) samples are stored.
--   R3: sign symmetry is exact — data for phase p + 2**(PHASE_BITS-1) is the
--       negation of data for phase p (sin(x + pi) = -sin(x)).
--   R4: output is registered: the sample for a given phase appears exactly
--       one clk edge after that phase is presented. Pure ROM — no reset, no
--       enable, a lookup every clock.
--
-- The table is built at elaboration time by init_rom (ieee.math_real — this
-- is compile-time math, it costs zero gates). Entry i holds
-- round(AMP * sin((i + 0.5) * (pi/2) / Q)). The half-sample offset (+0.5) is
-- what makes R2/R3 *exact*: mirroring an address with "not addr" (== Q-1-addr)
-- lands on the same stored sample, so folding adds zero error. It also means
-- neither 0 nor the exact peak is stored; the largest entry is
-- round(AMP * sin((Q-0.5)/Q * pi/2)), within 1 LSB of full scale (R1).
--
-- Radar analog: this is DDS waveform memory. Table depth sets the
-- phase-truncation spur floor, and quarter-wave folding buys 4x effective
-- depth for two layers of XOR-grade logic — the same trick real DDS chips use.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sine_lut is
  generic (
    PHASE_BITS : positive := 10;  -- full circle = 2**PHASE_BITS phases (must be >= 3)
    DATA_BITS  : positive := 8    -- signed output width
  );
  port (
    clk   : in  std_logic;
    phase : in  unsigned(PHASE_BITS - 1 downto 0);  -- e.g. top bits of nco's phase port
    data  : out signed(DATA_BITS - 1 downto 0)      -- registered sine sample
  );
end entity sine_lut;

architecture rtl of sine_lut is
  constant Q   : natural := 2 ** (PHASE_BITS - 2);           -- quarter-wave depth
  constant AMP : real    := real(2 ** (DATA_BITS - 1) - 1);  -- full scale (127 for 8 bits)

  type rom_t is array (0 to Q - 1) of signed(DATA_BITS - 1 downto 0);

  function init_rom return rom_t is
    variable r : rom_t;
  begin
    for i in 0 to Q - 1 loop
      r(i) := to_signed(integer(round(
                AMP * sin((real(i) + 0.5) * MATH_PI_OVER_2 / real(Q)))), DATA_BITS);
    end loop;
    return r;
  end function init_rom;

  constant rom : rom_t := init_rom;
begin

  lookup : process (clk)
    variable quad : unsigned(1 downto 0);               -- which quarter of the circle
    variable addr : unsigned(PHASE_BITS - 3 downto 0);  -- index into the quarter table
    variable v    : signed(DATA_BITS - 1 downto 0);
  begin
    if rising_edge(clk) then
      quad := phase(PHASE_BITS - 1 downto PHASE_BITS - 2);
      addr := phase(PHASE_BITS - 3 downto 0);
      if quad(0) = '1' then
        addr := not addr;  -- mirror: Q-1-addr (2nd and 4th quarters run backwards)
      end if;
      v := rom(to_integer(addr));
      if quad(1) = '1' then
        v := -v;           -- lower half of the circle is negative
      end if;
      data <= v;
    end if;
  end process;

end architecture rtl;
```

**File: course/work/lesson14/dsm_dac.vhd**

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

Now the first of the two new files — the instrument:

**File: course/work/lesson14/theremin_top.vhd**

```vhdl
-- theremin_top.vhd — the finished instrument: every verified block from
-- lessons 04-13 wired per the curriculum signal chain.
--
--   osc_in -> sync_2ff -> freq_meas -> pitch_map -> nco -> sine_lut -> dsm_dac -> audio_out
--     (L09)      (L10)       (L13)     (L04)      (L07)     (L08)
--
-- Requirements this module implements (verified in theremin_top_tb.vhd):
--   R1: the design self-starts: a power-on-reset counter (pattern from
--       fpga/phase1/rtl/top.vhd) holds the chain in reset for the first 15
--       clocks after configuration, then releases it; audio_out shows
--       delta-sigma activity shortly after with no external reset pin.
--   R2: with the hand far away (antenna oscillator at its 200 kHz base),
--       the audio fundamental settles to C4 (fcw = FCW_BASE = 93640,
--       f = 261.6 Hz) — the calibrated reference point of the instrument.
--   R3/R4: as the hand approaches (oscillator pulled down in frequency),
--       the audio fundamental tracks it per the lesson13 mapping:
--       fcw = clamp(FCW_BASE + (P_REF - period)*2**SHIFT).
--   R5: pitch is monotonic in hand position end-to-end: more hand
--       capacitance -> longer measured period -> lower fcw -> lower note.
--
-- All pitch_map generics stay at their defaults — the curriculum pins them
-- to this exact integration scenario (12 MHz clock, 200 kHz oscillator,
-- EDGES = 64 => P_REF = 3840; FCW_BASE = C4; clamps C3..C6).
--
-- Registered boundaries: every block in the chain registers its output
-- (freq_meas's period/valid, pitch_map's fcw, nco's phase, sine_lut's data,
-- dsm_dac's bit), so no combinational path crosses more than one module.
--
-- Radar analog: this is system integration against a target model —
-- the whole chain is proven end-to-end in simulation (osc_model standing in
-- for the antenna hardware) before the bench ever sees a bitstream.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity theremin_top is
  port (
    clk12     : in  std_logic;  -- 12 MHz board oscillator
    osc_in    : in  std_logic;  -- antenna relaxation oscillator (async, ~200 kHz)
    audio_out : out std_logic;  -- delta-sigma bitstream: RC filter -> amp
    led_hb    : out std_logic   -- heartbeat, ~0.7 Hz
  );
end entity theremin_top;

architecture rtl of theremin_top is
  signal por_cnt : unsigned(3 downto 0)  := (others => '0');
  signal rst     : std_logic;
  signal hb_cnt  : unsigned(23 downto 0) := (others => '0');

  signal osc_sync : std_logic;
  signal period   : unsigned(23 downto 0);
  signal valid    : std_logic;
  signal fcw      : unsigned(31 downto 0);
  signal phase    : unsigned(31 downto 0);
  signal sample   : signed(7 downto 0);
begin

  -- Boards have no reset button: hold the chain in reset for the first 15
  -- clocks after configuration (same POR as fpga/phase1/rtl/top.vhd).
  rst <= '1' when por_cnt /= x"F" else '0';

  housekeeping : process (clk12)
  begin
    if rising_edge(clk12) then
      if por_cnt /= x"F" then
        por_cnt <= por_cnt + 1;
      end if;
      hb_cnt <= hb_cnt + 1;
    end if;
  end process;

  led_hb <= hb_cnt(23);  -- 12 MHz / 2**24 ~= 0.72 Hz

  -- The antenna oscillator is the only asynchronous input in the design;
  -- it crosses into the 12 MHz domain here and nowhere else.
  u_sync : entity work.sync_2ff
    port map (
      clk      => clk12,
      async_in => osc_in,
      sync_out => osc_sync
    );

  u_meas : entity work.freq_meas
    generic map (
      EDGES    => 64,   -- => P_REF = 64 * 12e6/200e3 = 3840 in pitch_map
      CNT_BITS => 24
    )
    port map (
      clk    => clk12,
      rst    => rst,
      sig_in => osc_sync,
      period => period,
      valid  => valid
    );

  -- Defaults only: the curriculum pins pitch_map's generics to this
  -- integration (P_REF 3840, FCW_BASE C4, clamps C3..C6, slope 2**6).
  u_map : entity work.pitch_map
    port map (
      clk    => clk12,
      rst    => rst,
      period => period,
      valid  => valid,
      fcw    => fcw
    );

  u_nco : entity work.nco
    generic map (W => 32)
    port map (
      clk    => clk12,
      rst    => rst,
      en     => '1',
      fcw    => fcw,
      phase  => phase,
      sq_out => open  -- square tap unused: the sine path is the voice
    );

  u_lut : entity work.sine_lut
    generic map (
      PHASE_BITS => 10,
      DATA_BITS  => 8
    )
    port map (
      clk   => clk12,
      phase => phase(31 downto 22),  -- top 10 bits: phase truncation, lesson07
      data  => sample
    );

  u_dac : entity work.dsm_dac
    generic map (W => 8)
    port map (
      clk     => clk12,
      rst     => rst,
      sample  => sample,
      bit_out => audio_out
    );

end architecture rtl;
```

Read the instantiations against the chain diagram; there should be no
surprises, which is the highest compliment an integration can earn. Worth
a second look:

- **Direct entity instantiation** (`entity work.sync_2ff`) throughout — no
  component declarations to drift out of sync with the entities. The port
  map *is* the wiring diagram.
- **`u_map` takes no generic map at all.** The curriculum pins
  `pitch_map`'s defaults to exactly this integration (P_REF 3840 assumes
  EDGES 64 at 200 kHz and 12 MHz); instantiating bare states "I am the
  scenario the defaults were derived for." The one generic that must
  *agree* with it — EDGES on `u_meas` — is set right beside a comment
  doing the arithmetic. Interface couplings deserve to be written where
  they bite.
- **`phase(31 downto 22)`** — the top 10 of 32 phase bits address the sine
  table: lesson 07's phase truncation, and the single most tempting place
  in the design for an off-by-one that every unit TB would forgive.
- **`sq_out => open`** — the NCO's square tap, explicitly unconnected.
  `open` documents "unused on purpose"; yosys prunes the wire for free.
- The POR and heartbeat are lesson 05's `top.vhd` pattern, verbatim in
  spirit: housekeeping in one process, `rst` decoded combinationally,
  `led_hb` a plain counter bit (12 MHz / 2^24 ≈ 0.72 Hz) that will prove
  the clock is alive on lab day before anything else works.

The simulation-only target model, reused from lesson 10:

**File: course/work/lesson14/osc_model.vhd**

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

And the system test:

**File: course/work/lesson14/theremin_top_tb.vhd**

```vhdl
-- theremin_top_tb.vhd — end-to-end integration testbench: the whole
-- instrument against the target model.
--
-- osc_model (BASE_HZ = 200 kHz, DELTA_HZ = 20 kHz — the lesson10 scenario)
-- drives theremin_top's osc_in; the "hand" moves through three positions
-- and the TB verifies the AUDIO OUTPUT tracks it — a pure black-box check
-- through the DUT's four real pins, exactly what the bench will see.
--
-- The audio fundamental is recovered from the delta-sigma BITSTREAM
-- itself: the bitstream is boxcar-filtered by an accumulate-and-dump over
-- BLK = 256 clocks (lesson12's trick: the block sum is a low-pass filter,
-- so the audio sine re-emerges from the 1-bit noise); a comparator with
-- +/-32-count hysteresis around midscale turns it into a clean square,
-- and the fundamental is timed over N whole cycles. The expected value is
-- computed independently in real math from the oscillator physics:
--   period  = EDGES * f_clk / f_osc          (freq_meas contract)
--   fcw     = FCW_BASE + (P_REF - period)*2**SHIFT   (pitch_map contract)
--   f_audio = fcw * f_clk / 2**32            (nco contract)
-- Tolerance 2%: +/-2 counts of period quantization is +/-128 fcw
-- (~0.15%), crossing quantization is one block = 21 us against audio
-- periods of ~4 ms, and smoothing dither adds a few fcw counts.
--
-- (A white-box fcw tap via a VHDL-2008 external name would be the other
-- legitimate probe; this GHDL build miscompiles external names into
-- sibling instances, so the TB stays strictly black-box.)
--
-- After each hand move the TB waits 25 ms: at ~2.9 kHz measurement rate
-- that is ~70 valid strobes, and pitch_map's 1/8-per-strobe smoothing has
-- long converged (residual < 2 fcw counts from the worst-case jump).
--
-- Requirement tags (R1..R5 from theremin_top.vhd):
--   R1: bitstream alive (both levels seen) within 2 ms of power-up — the
--       POR self-start, no external reset.
--   R2: hand = 0.0  -> audio ~= 261.6 Hz (C4: fcw = FCW_BASE = 93640)
--   R3: hand = 0.5  -> audio ~= 225.5 Hz (fcw ~= 80705)
--   R4: hand = 1.0  -> audio ~= 185.3 Hz (fcw ~= 66333)
--   R5: measured audio frequency strictly decreases as the hand
--       approaches: pitch tracks the hand end-to-end.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity theremin_top_tb is
end entity theremin_top_tb;

architecture sim of theremin_top_tb is
  constant CLK_HZ   : real     := 12_000_000.0;
  constant CLK_PER  : time     := 1 sec / 12_000_000;
  constant BASE_HZ  : real     := 200_000.0;
  constant DELTA_HZ : real     := 20_000.0;
  constant EDGES    : positive := 64;      -- must match theremin_top's freq_meas
  constant P_REF    : positive := 3840;    -- pitch_map defaults (pinned)
  constant FCW_BASE : positive := 93640;
  constant SHIFT    : natural  := 6;

  constant BLK  : positive := 256;  -- accumulate-and-dump block, 21.3 us
  constant HYST : positive := 32;   -- comparator hysteresis, counts of BLK

  signal clk   : std_logic := '0';
  signal hand  : real      := 0.0;
  signal osc   : std_logic;
  signal audio : std_logic;
  signal led   : std_logic;
  signal done  : boolean   := false;

  signal audio_hi     : boolean := false;  -- filtered + hysteresis comparator
  signal seen0, seen1 : boolean := false;  -- bitstream activity (R1)
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  u_osc : entity work.osc_model
    generic map (
      BASE_HZ  => BASE_HZ,
      DELTA_HZ => DELTA_HZ
    )
    port map (
      hand    => hand,
      osc_out => osc
    );

  dut : entity work.theremin_top
    port map (
      clk12     => clk,
      osc_in    => osc,
      audio_out => audio,
      led_hb    => led
    );

  -- R1 probe: has the delta-sigma bitstream shown both levels yet?
  activity : process (clk)
  begin
    if rising_edge(clk) then
      if audio = '1' then
        seen1 <= true;
      elsif audio = '0' then
        seen0 <= true;
      end if;
    end if;
  end process;

  -- Audio recovery: accumulate-and-dump boxcar over BLK clocks, then a
  -- midscale comparator with hysteresis. audio_hi is the sign of the
  -- filtered sine — its rising edges mark the audio fundamental.
  recover : process (clk)
    variable acc : natural range 0 to BLK := 0;
    variable n   : natural range 0 to BLK - 1 := 0;
  begin
    if rising_edge(clk) then
      if audio = '1' then
        acc := acc + 1;
      end if;
      if n = BLK - 1 then
        if acc >= BLK / 2 + HYST then
          audio_hi <= true;
        elsif acc <= BLK / 2 - HYST then
          audio_hi <= false;
        end if;
        acc := 0;
        n   := 0;
      else
        n := n + 1;
      end if;
    end if;
  end process;

  main : process
    -- Time N whole cycles of the recovered audio square, first->last
    -- rising crossing, and return the fundamental in Hz.
    procedure measure_audio(n_cyc : positive; f_meas : out real) is
      variable t0 : time;
    begin
      if audio_hi then
        wait until not audio_hi;
      end if;
      wait until audio_hi;
      t0 := now;
      for i in 1 to n_cyc loop
        wait until not audio_hi;
        wait until audio_hi;
      end loop;
      f_meas := real(n_cyc) * 1.0e9 / real((now - t0) / 1 ns);
    end procedure;

    -- Move the hand, let the measurement/smoothing chain settle, then
    -- check the audio fundamental against the physics-derived expectation.
    procedure check_hand(tag : string; hand_val : real; f_meas : out real) is
      variable p_exp   : real;  -- expected freq_meas period, clk counts
      variable fcw_exp : real;  -- expected pitch_map output
      variable f_exp   : real;  -- expected audio fundamental, Hz
      variable f       : real;
    begin
      hand  <= hand_val;
      p_exp   := real(EDGES) * CLK_HZ / (BASE_HZ - hand_val * DELTA_HZ);
      fcw_exp := real(FCW_BASE) + (real(P_REF) - p_exp) * real(2 ** SHIFT);
      f_exp   := fcw_exp * CLK_HZ / 2.0 ** 32;
      wait for 25 ms;  -- ~70 valid strobes: smoothing fully settled
      measure_audio(2, f);
      assert abs(f - f_exp) <= 0.02 * f_exp
        report tag & " FAIL: audio=" & real'image(f) &
               " Hz, expected=" & real'image(f_exp) & " Hz +/-2%"
        severity error;
      report tag & " pass: hand=" & real'image(hand_val) &
             " audio=" & real'image(f) &
             " Hz (exp~=" & real'image(f_exp) & " Hz," &
             " fcw~=" & real'image(fcw_exp) & ")";
      f_meas := f;
    end procedure;

    variable f_far, f_mid, f_near : real;
  begin
    -- R1: no external reset exists — the POR must self-start the chain.
    wait for 2 ms;
    assert seen0 and seen1
      report "R1 FAIL: audio_out not toggling within 2 ms of power-up"
      severity error;
    report "R1 pass: delta-sigma bitstream live within 2 ms of power-up (POR self-start)";

    check_hand("R2", 0.0, f_far);   -- 200 kHz -> C4, 261.6 Hz
    check_hand("R3", 0.5, f_mid);   -- 190 kHz -> ~225.5 Hz
    check_hand("R4", 1.0, f_near);  -- 180 kHz -> ~185.3 Hz

    -- R5: end-to-end tracking direction — more hand, lower note.
    assert f_far > f_mid and f_mid > f_near
      report "R5 FAIL: audio frequency not monotonic in hand position"
      severity error;
    report "R5 pass: audio tracks hand monotonically: " &
           real'image(f_far) & " > " & real'image(f_mid) &
           " > " & real'image(f_near) & " Hz";

    report "theremin_top testbench complete (any FAILs are listed above)";
    -- osc_model free-runs forever: end the simulation explicitly.
    done <= true;
    std.env.finish;
  end process;

  -- Whole run is ~110 ms of simulated time; stop instead of hanging if the
  -- recovered audio never crosses (measure_audio would wait forever).
  watchdog : process
  begin
    wait until done for 500 ms;
    assert done
      report "TB FAIL: watchdog timeout - no recovered audio crossings"
      severity failure;
    wait;
  end process;

end architecture sim;
```

The Concepts section already walked the design; map it to the code:

- `recover` is the accumulate-and-dump boxcar plus hysteresis comparator —
  fifteen lines that turn a 12 MHz bitstream back into audio.
- `measure_audio` times N whole cycles between rising crossings of the
  recovered square; `check_hand` computes the expectation from the three
  module contracts in real arithmetic, then asserts to ±2%.
- Every assert carries its requirement tag (R1–R5, declared in
  `theremin_top.vhd`'s header) and every pass line prints the *numbers*,
  because "pass" without numbers is a rumor.
- The watchdog is a second process, not a flag check inside `main` —
  `main` may be blocked in a `wait until` that never fires, which is
  exactly the failure the watchdog exists to catch.

The constraint files. `osc_in` is new since lesson 05 — the antenna
oscillator input joins the party, on the iCEstick PMOD pin physically next
to `audio_out` so lesson 99's breadboard ribbon stays short:

**File: course/work/lesson14/icestick.pcf**

```text
# Lattice iCEstick (iCE40-HX1K, TQ144) — theremin_top
# clk12/led_hb/audio_out match fpga/phase1/constraints/icestick.pcf.
set_io clk12     21   # 12 MHz FTDI-derived oscillator
set_io led_hb    99   # D1 (red)
set_io audio_out 78   # PMOD J2 pin 1 — series 1k -> RC filter -> amp
set_io osc_in    79   # PMOD J2 pin 2 — 74HC14 relaxation oscillator output
```

**File: course/work/lesson14/hx8k.pcf**

```text
# Lattice iCE40-HX8K-B-EVN breakout (iCE40-HX8K, CT256) — theremin_top
# clk12/led_hb/audio_out match fpga/phase1/constraints/hx8k.pcf.
set_io clk12     J3   # 12 MHz oscillator
set_io led_hb    B5   # D2 (LED bank: B5 B4 A2 A1 C5 C4 B3 C3)
set_io audio_out B1   # J2 header — series 1k -> RC filter -> amp
# osc_in: J2 header ball next to audio_out; as with audio_out, VERIFY the
# ball name against the HX8K-B-EVN schematic silk before wiring the bench.
set_io osc_in    B2   # 74HC14 relaxation oscillator output
```

(The HX8K file carries lesson 05's standing order forward: header-ball
names get *verified against the schematic* before a wire touches them on
lab day.)

**File: course/work/lesson14/Makefile**

```make
# Lesson 14 — theremin_top integration. Usage (after sourcing
# ~/tools/oss-cad-suite/environment):
#
#   make sim              end-to-end testbench (osc_model hand sweep)
#   make synth            VHDL -> netlist (yosys via ghdl-yosys-plugin)
#   make bit              netlist -> place/route -> bitstream
#   make time             static timing estimate (icetime)
#   make prog             flash the board (iceprog; lesson99)
#   make clean
#
#   make BOARD=hx8k bit   for the iCE40-HX8K-B-EVN (default: icestick)
#
# Mirrors fpga/phase1/Makefile. osc_model.vhd is SIMULATION-ONLY and must
# never appear in RTL (yosys would reject it).

BOARD ?= icestick
TOP    = theremin_top
TB    ?= theremin_top_tb

RTL     = sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd \
          dsm_dac.vhd theremin_top.vhd
SIM_SRC = osc_model.vhd theremin_top_tb.vhd

ifeq ($(BOARD),icestick)
  DEVICE  = hx1k
  PACKAGE = tq144
  PCF     = icestick.pcf
else ifeq ($(BOARD),hx8k)
  DEVICE  = hx8k
  PACKAGE = ct256
  PCF     = hx8k.pcf
else
  $(error unknown BOARD '$(BOARD)': use icestick or hx8k)
endif

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; on older hosts elaboration
# needs the __isoc23_* forwarding shim (see fpga/phase1/Makefile).
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim synth bit time prog clean

# ---------- simulation (GHDL) ----------

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(SIM_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

# ---------- synthesis -> bitstream ----------

synth: build/$(TOP).json
bit:   build/$(TOP)-$(BOARD).bin

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@'

build/$(TOP)-$(BOARD).asc: build/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

build/$(TOP)-$(BOARD).bin: build/$(TOP)-$(BOARD).asc
	icepack $< $@

time: build/$(TOP)-$(BOARD).asc
	icetime -d $(DEVICE) -p $(PCF) -t $<

prog: build/$(TOP)-$(BOARD).bin
	iceprog $<

build:
	mkdir -p build

clean:
	rm -rf build
```

Lesson 05's Makefile grown up. Three changes earn their keep:

- **`RTL` vs `SIM_SRC` is a firewall.** `osc_model.vhd` (real-valued
  ports, `wait for`) would be rejected by yosys on sight; it appears only
  in the simulation file list, and the synthesis command is built from
  `$(RTL)` alone. When you add a file to any project, the first question
  is which list it belongs in.
- **Analysis order is load-bearing, twice.** Modules before
  `theremin_top.vhd` (which instantiates them), `osc_model.vhd` before the
  TB (ditto) — same GHDL rule as always, now with nine files to get wrong.
- **Artifacts carry the board name** (`theremin_top-icestick.bin`,
  `theremin_top-hx8k.bin`). Lesson 05's stale-bitstream trap — switching
  boards without `make clean` and flashing an hx1k image at an hx8k — is
  designed out rather than remembered about. The yosys netlist stays
  board-neutral and shared, which is also a statement: the *design* does
  not know which board it is on; only place-and-route does.

**Stopping point.** You should now be able to explain:

- why the seven reused files must be byte-identical to their home lessons
  — what integration is allowed to add (wiring), and what it is never
  allowed to do (sneaky edits).
- why `u_map` takes no generic map while `u_meas` sets `EDGES => 64`
  explicitly, and what breaks if the two stop agreeing.
- why `osc_model.vhd` lives in `SIM_SRC` and must never appear in `RTL`,
  and what yosys would do if it leaked across that firewall.
- why the TB's watchdog is a separate process instead of a flag check
  inside `main`.

---

## Session 14.3 — Prove It: Sim, Fit, Timing (~75 min)

### Run

From `course/work/lesson14/` (toolchain sourced via the `fpga` alias).
First the system test — and note it runs for several minutes of wall
clock; it is simulating 110 ms of a 12 MHz instrument. The R1 line appears
early; the silence after it is ~36 ms of simulated settling and
measurement per hand position, not a hang (the watchdog would say so):

```bash
make sim
```

Expected output (a `mkdir -p build` line precedes this on the first run;
your home directory replaces `/home/clementsj` in the shim path):

```text
ghdl -a --std=08 --workdir=build sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd dsm_dac.vhd theremin_top.vhd osc_model.vhd theremin_top_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/theremin_top_tb theremin_top_tb
./build/theremin_top_tb --assert-level=failure
theremin_top_tb.vhd:178:5:@2ms:(report note): R1 pass: delta-sigma bitstream live within 2 ms of power-up (POR self-start)
theremin_top_tb.vhd:164:7:@38399957718934fs:(report note): R2 pass: hand=0.0 audio=2.618715198093366e2 Hz (exp~=2.616271376609802e2 Hz, fcw~=9.364e4)
theremin_top_tb.vhd:164:7:@73429290491798fs:(report note): R3 pass: hand=5.0e-1 audio=2.259036229632388e2 Hz (exp~=2.2548790040769077e2 Hz, fcw~=8.070526315789475e4)
theremin_top_tb.vhd:164:7:@110591956563862fs:(report note): R4 pass: hand=1.0 audio=1.8527669128438063e2 Hz (exp~=1.8533319234848017e2 Hz, fcw~=6.633333333333331e4)
theremin_top_tb.vhd:188:5:@110591956563862fs:(report note): R5 pass: audio tracks hand monotonically: 2.618715198093366e2 > 2.259036229632388e2 > 1.8527669128438063e2 Hz
theremin_top_tb.vhd:192:5:@110591956563862fs:(report note): theremin_top testbench complete (any FAILs are listed above)
simulation finished @110591956563862fs
```

Read it the way you'd read range data. R2's measured 261.87 Hz sits 0.09%
from the 261.63 Hz prediction; R3 lands 0.18% off; R4, 0.03% — the 2%
budget is loafing, which is what a healthy system looks like. The whole
theremin — measured, mapped, synthesized, delta-sigma'd, then *recovered
from one bit and demodulated by the testbench* — agrees with three
composed module contracts to a tenth of a percent. That number is thirteen
lessons shaking hands.

Now the physical budgets. Synthesis:

```bash
make synth
```

Expected output (yosys prints ~2300 lines; these are the ones to find):

```text
yosys -m ghdl -p 'ghdl --std=08 --workdir=build sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd dsm_dac.vhd theremin_top.vhd -e theremin_top; synth_ice40 -top theremin_top -json build/theremin_top.json'
[...]
using FF mapping for memory theremin_top.u_lut.:223
[...]
2.50. Printing statistics.

=== theremin_top ===

        +----------Local Count, excluding submodules.
        | 
      636 wires
     1513 wire bits
      636 public wires
     1513 public wire bits
        4 ports
        4 port bits
        6 cells
        6   $scopeinfo
      820 submodules
      228   SB_CARRY
       33   SB_DFF
        4   SB_DFFE
       87   SB_DFFESR
       44   SB_DFFSR
      424   SB_LUT4
[...]
```

Before moving on, do the 168-flop audit from Concepts against your own
log, and find the `FF mapping` line that explains the BRAM you don't have.

Place, route, pack for the iCEstick:

```bash
make bit
```

Expected output:

```text
nextpnr-ice40 --hx1k --package tq144 --pcf icestick.pcf \
              --json build/theremin_top.json --asc build/theremin_top-icestick.asc --freq 12
Info: constrained 'clk12' to bel 'X0/Y8/io1'
Info: constrained 'led_hb' to bel 'X13/Y12/io1'
Info: constrained 'audio_out' to bel 'X13/Y3/io1'
Info: constrained 'osc_in' to bel 'X13/Y4/io0'
[...]
Info: Device utilisation:
Info: 	         ICESTORM_LC:     495/   1280    38%
Info: 	        ICESTORM_RAM:       0/     16     0%
Info: 	               SB_IO:       4/     96     4%
Info: 	               SB_GB:       2/      8    25%
Info: 	        ICESTORM_PLL:       0/      1     0%
Info: 	         SB_WARMBOOT:       0/      1     0%
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 37.16 MHz (PASS at 12.00 MHz)
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 35.86 MHz (PASS at 12.00 MHz)
[...]
Info: Program finished normally.
icepack build/theremin_top-icestick.asc build/theremin_top-icestick.bin
```

38% of the small chip; two globals (the clock and the promoted `rst`);
both f_max graders PASS with the post-route number, as always, the honest
one. `build/theremin_top-icestick.bin` — 32,220 bytes of instrument — now
waits for lesson 99.

The independent timing verdict:

```bash
make time
```

Expected output:

```text
icetime -d hx1k -p icestick.pcf -t build/theremin_top-icestick.asc
// Reading input .pcf file..
// Reading input .asc file..
// Reading 1k chipdb file..
// Creating timing netlist..

icetime topological timing analysis report
==========================================

Report for critical path:
-------------------------

        lc40_4_8_5 (LogicCell40) [clk] -> lcout: 0.640 ns
     0.640 ns net_7075 (period[3])
[...]
    27.501 ns .. 27.761 ns u_map.fcw_r_SB_DFFESR_Q_17_D_SB_LUT4_O_I3
                  lcout -> fcw[31]

Total number of logic levels: 94
Total path delay: 27.98 ns (35.74 MHz)
```

The story the Concepts section promised, told in net names: launch from
`period[3]` — `freq_meas`'s output register — then 94 levels of nets all
named `u_map.fcw_r_...` (the mangled remains of lesson 13's subtract,
shift, clamps, and smoother, packed into LUTs and carries), landing on
`fcw_r`. One module's cloud, one registered boundary, 27.98 ns spent of an
83.3 ns budget. Nothing else in the design comes close.

Same instrument, bigger chip:

```bash
make clean
make BOARD=hx8k bit
make BOARD=hx8k time
```

Expected output (elided down to the verdicts):

```text
mkdir -p build
yosys -m ghdl -p 'ghdl --std=08 --workdir=build sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd dsm_dac.vhd theremin_top.vhd -e theremin_top; synth_ice40 -top theremin_top -json build/theremin_top.json'
[...]
nextpnr-ice40 --hx8k --package ct256 --pcf hx8k.pcf \
              --json build/theremin_top.json --asc build/theremin_top-hx8k.asc --freq 12
Info: constrained 'clk12' to bel 'X0/Y16/io1'
Info: constrained 'led_hb' to bel 'X7/Y33/io1'
Info: constrained 'audio_out' to bel 'X0/Y30/io0'
Info: constrained 'osc_in' to bel 'X0/Y31/io0'
[...]
Info: Device utilisation:
Info: 	         ICESTORM_LC:     495/   7680     6%
Info: 	        ICESTORM_RAM:       0/     32     0%
Info: 	               SB_IO:       4/    206     1%
Info: 	               SB_GB:       2/      8    25%
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 36.69 MHz (PASS at 12.00 MHz)
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 36.14 MHz (PASS at 12.00 MHz)
[...]
Info: Program finished normally.
icepack build/theremin_top-hx8k.asc build/theremin_top-hx8k.bin
icetime -d hx8k -p hx8k.pcf -t build/theremin_top-hx8k.asc
[...]
Total number of logic levels: 96
Total path delay: 27.43 ns (36.45 MHz)
```

Same 495 logic cells at 6% utilisation, same critical path give-or-take
routing luck, and a 135,100-byte bitstream — four times the iCEstick's,
because a bitstream configures the *die*, not the design (lesson 05's
observation, still true). Both boards green: the pinned deliverable of
this lesson.

**Stopping point.** You should now be able to explain:

- why R2/R3/R4 landing 0.03–0.18% from prediction — against a 2% budget —
  is what a healthy system looks like, and what it means that the number
  was recovered from the 1-bit stream itself.
- the critical path in design terms: launched from `freq_meas`'s `period`
  register, through `pitch_map`'s map-clamp-smooth cloud, into `fcw_r` —
  27.98 ns spent of an 83.3 ns budget, one registered boundary crossed.
- why the hx8k bitstream is four times the iCEstick's when both hold the
  same 495 logic cells.

---

## Session 14.4 — Explore & Checkpoint (~75 min)

### Explore

Attempt these before opening `course/solutions/lesson14/`. Each one is a
class of integration failure, on purpose.

1. **Break the interface contract.** In `theremin_top.vhd`, change
   `u_meas`'s `EDGES => 64` to `EDGES => 32` and `make sim`. Predict
   first: period halves to 1920, but `pitch_map` still believes
   P_REF = 3840, so fcw = 93640 + 1920·64 = 216520 → about 605 Hz. Run it:

   ```text
   R2 FAIL: audio=6.048388316207322e2 Hz, expected=2.616271376609802e2 Hz +/-2%
   ```

   R3 and R4 fail the same way — yet **R5 still passes**: pitch tracks the
   hand perfectly, monotonic and smooth, a fifth-and-change sharp. Every
   unit TB in the course would still be green; only the system test knows
   the instrument is mistuned. This is the integration-bug signature:
   locally correct, globally wrong, and invisible below the top. Restore
   `EDGES => 64`.

2. **Drive the truth model out of its envelope.** In `theremin_top_tb.vhd`
   set `DELTA_HZ` to `40_000.0` (a hand with twice the capacitive pull)
   and `make sim`. At hand = 1.0 the oscillator hits 160 kHz, period 4800,
   and the *mapped* fcw would be 32200 — below FCW_MIN. The DUT does
   exactly what lesson 13 verified: clamps at 46820 and plays C3. But the
   TB's expected-value formula never modeled the clamp:

   ```text
   R4 FAIL: audio=1.3075314662350593e2 Hz, expected=8.996576070785522e1 Hz +/-2%
   ```

   The DUT is *right* (130.8 Hz is C3, the designed floor) and the
   testbench is *wrong* — its truth model is only valid where the mapping
   is linear, and nobody wrote that down until now. Fix nothing; learn the
   sentence: a model-based sign-off is bounded by the model's envelope,
   and the envelope belongs in the TB's comments (add it, if you like,
   then restore 20 kHz).

3. **Measure the timing margin for real.** In the Makefile change
   `--freq 12` to `--freq 36` and `make clean && make bit`:

   ```text
   Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 37.16 MHz (PASS at 36.00 MHz)
   [...]
   ERROR: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 35.86 MHz (FAIL at 36.00 MHz)
   ```

   Post-placement optimism says yes; post-route reality says no, and the
   build *fails* — a missed constraint is an error, not a warning. The
   instrument's real ceiling sits just under 36 MHz, so at 12 MHz you hold
   3× margin, and now you know it by test rather than by the report's
   word. Restore `--freq 12`.

4. **Watch margin erode without failing.** In `theremin_top_tb.vhd` cut
   the settling `wait for 25 ms` to `wait for 3 ms` and rerun. Everything
   still passes — but read the numbers: R3's error against prediction
   grows from 0.18% to 0.9% (audio 227.5 Hz vs 225.5), R4's from 0.03% to
   0.97%, because you are now measuring a smoother that is still moving
   (and settles further *during* the two-cycle measurement — the value you
   catch is a moving target). Nothing turned red; a quarter of the
   tolerance budget silently became settling error. Green-with-eroded-
   margin is the most dangerous state a system test can be in, and the
   only instrument that detects it is the one you just used: reading the
   numbers, not the verdict. Restore 25 ms.

### Tips & Pitfalls

- **Emacs / vhdl-mode: let the editor write the port maps.** In each
  module file, put point inside the entity declaration and hit
  `C-c C-p C-w` (`vhdl-port-copy`); then in `theremin_top.vhd` hit
  `C-c C-p C-i` (`vhdl-port-paste-instance`) — a complete named-
  association instantiation appears, every port listed, nothing
  misspelled. Six instantiations, zero typo'd port maps. (`C-c C-p C-t`
  pastes a testbench skeleton the same way — remember it for your own
  projects.)
- **Toolchain gotcha: keep `osc_model.vhd` out of `RTL`.** Add it to the
  wrong Makefile variable and yosys dies at the GHDL step on the `real`
  port. The simulation/synthesis file split is a firewall you maintain by
  hand — there is no lint that knows your intent.
- **`make sim` is slow here and that's correct.** ~110 ms at 12 MHz is
  minutes of wall time. Don't reach for `--wave` casually either: a GHW of
  this run is gigabytes. If you need waves, shorten the scenario in a
  scratch copy of the TB (one hand position, a few ms) — instrument the
  *experiment*, not the regression.
- **If the TB seems hung, wait for the watchdog.** No recovered-audio
  crossings (a dead DAC path, a phase-slice typo) leaves `measure_audio`
  blocked; the watchdog converts that silence into a loud
  `severity failure` at 500 ms simulated. Silence ending in FAIL is a
  diagnosis; silence forever would be a mystery. Steal the pattern for
  every system TB you ever write.
- **Nine files, one order.** GHDL analyzes left to right: every entity
  before its instantiator — the six modules before `theremin_top.vhd`,
  `osc_model.vhd` before the TB. If synthesis or analysis errors mention
  missing units after you've edited, `make clean` first; a stale
  `work-obj08.cf` shared between sim and synth flows can hold ghosts.
- **`fcw~=` in the pass lines is the TB's prediction, not a DUT reading.**
  The TB is black-box; it cannot see fcw. It prints its own model's value
  so that when something fails you can tell at a glance whether the miss
  smells like mapping (wrong fcw regime entirely) or measurement (right
  regime, few percent off). Design your failure messages for the bad day,
  during the good one.

### Checkpoint

Before lesson 99 — the lab day — you must have:

- `make sim` in `course/work/lesson14/` printing `R1 pass` through
  `R5 pass` and the completion line with zero FAILs, R2/R3/R4 within a
  fraction of a percent of 261.6 / 225.5 / 185.3 Hz.
- `make bit` green for the iCEstick: 495/1280 LCs (38%), 4 SB_IO, 2 SB_GB,
  both `Max frequency` lines PASS at 12 MHz, `theremin_top-icestick.bin`
  (32,220 bytes) on disk. `make clean && make BOARD=hx8k bit` likewise
  green at 495/7680 (6%), `theremin_top-hx8k.bin` (135,100 bytes).
- `make time` reporting ≈27.98 ns / 94 levels (hx1k; ≈27.43 ns / 96 on
  hx8k), and you can name the path in design terms: `period` register →
  `pitch_map`'s map-clamp-smooth cloud → `fcw_r`.
- The 168-flop audit reproduced from memory, module by module.
- One-breath explanations of: why `ICESTORM_RAM` is 0 and what it costs;
  how the TB recovers audio from one bit (boxcar + hysteresis); the three
  terms inside the ±2% budget; and why 25 ms of settling is ~9 time
  constants.
- The radar mapping cold: target generator ↔ `osc_model`, test-at-the-
  ports ↔ four-pin black box, independent truth ↔ contract-composed
  expected values, budget rollup ↔ the 2%, model envelope ↔ Explore 2.

Next — lesson 99, the only lesson that needs the physical bench: flash
lesson 05's A440 to prove the toolchain-to-board path, breadboard the
74HC14 antenna oscillator, flash `theremin_top`, and meet the first live
target. The simulation sign-off you just produced is what makes that day
bring-up instead of debugging: every question the bench can ask about the
digital instrument already has a tested answer.
