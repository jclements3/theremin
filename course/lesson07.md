# Lesson 07 — Sine Tables and Block RAM

*Where we are.* Lesson04's NCO gives you a phase that sweeps the circle at
exactly the frequency you command — but so far you've only listened to its
top bit, a square wave. That was fine for the A440 bitstream (lesson 05) and
for `scale_seq` (lesson 06), because a speaker driven by a square wave still
plays the right pitch, just wrapped in odd harmonics. A theremin should sound
like a theremin, not an alarm clock, so this lesson converts phase into
*sine samples*: a lookup table that exploits the sine wave's symmetries to
store a quarter of itself, filled at elaboration time by real-valued math
that costs zero gates. Along the way you'll meet the iCE40's block RAMs,
learn the rule that decides whether your table lands in one, and read a
yosys `stat` report closely enough to know the difference. Next lesson the
delta-sigma DAC turns these samples into a 1-bit stream your RC filter can
smooth into an actual voltage.

---

## Session 07.1 — Folding the Sine (~75 min)

### Objectives

- Size a sine table from first principles: what phase bits cost, what data
  bits cost, and why 2**10 × 8 bits is enough for this instrument.
- Derive quarter-wave folding from `sin(pi - x) = sin(x)` and
  `sin(x + pi) = -sin(x)`, and explain why the half-sample offset makes the
  folding *exact* rather than approximate.
- Write an elaboration-time function that fills a ROM using
  `ieee.math_real`, and say precisely when that code runs and why it never
  becomes hardware.
- State the synchronous-read rule behind BRAM inference, and read a yosys
  `stat` block to determine whether a memory landed in `SB_RAM40_4K` or in
  logic cells.
- Explain the module's 1-cycle latency and why the testbench checks it
  explicitly.

### Concepts

#### From phase to voltage, and what the top bit was costing you

A square wave at frequency f contains f plus every odd harmonic — 3f at a
third of the amplitude, 5f at a fifth, forever; your ear hears buzzy and
hollow. A sine wave is one spectral line, and everything downstream (the
delta-sigma DAC, the RC filter, the amplifier) is easier to reason about
when the signal going in is one line.

The NCO already knows the whole waveform, not just its sign: its phase
accumulator *is* the angle, scaled so 0 to 2**32 - 1 spans 0 to 360°. To
get amplitude, evaluate sine at that angle. Hardware can't call `sin()` at
12 MHz, but it can look the answer up: precompute sine at N evenly spaced
angles and use the phase as the address.

Not all 32 phase bits, though — that table would need 4 billion entries.
We take the top `PHASE_BITS = 10`, i.e. `nco_phase(31 downto 22)`,
quantizing the circle into 1024 slices. Discarding the low 22 bits is
**phase truncation**, and it isn't free — the error is periodic, so it
shows up as discrete spurious tones, not benign noise. The Radar Connection
quantifies that; the punchline is that 10 bits puts the spurs around 60 dB
below the fundamental, under this chain's other noise floors. The second
size decision is `DATA_BITS = 8`: amplitude quantization, worth roughly
6.02×8 + 1.76 ≈ 50 dB of signal-to-quantization-noise — more than enough
for this instrument, though don't credit the 1-bit DAC for the limit:
lesson 08 shows the delta-sigma stage actually preserves about 13 effective
bits (≈78 dB) in the audio band, so this LUT, not the DAC, is the chain's
amplitude bottleneck — and it's the cheap block to widen if you ever need
to. So the naive table is:

```
2**10 phases  ×  8 bits  =  8192 bits of ROM
```

Hold that number; we're about to shrink it by 4.

#### Quarter-wave folding: pay for 90°, get 360°

A sine wave carries the same quarter-cycle of information four times:

```
 +FS |      _......_
     |    ,'        `.        quad 00: table read forward
     |   /            \       quad 01: table read BACKWARD   sin(pi-x)=sin(x)
   0 +--+--------------+--------------+--  phase
     |  0°            180°             \             360°
     |                  \              /
     |                   `.        _.'    quad 10: forward, NEGATED
 -FS |                     `-....-'       quad 11: backward, NEGATED
```

Split the 10-bit phase into fields:

```
  phase(9) phase(8) | phase(7) ............ phase(0)
  \______quad______/ \_________addr__________________/
     |        |          8 bits: index into a 256-entry
     |        |          quarter table (Q = 2**(PHASE_BITS-2))
     |        +-- mirror bit: 2nd/4th quarter run backward
     +----------- sign bit:   lower half of the circle is negative
```

Two identities do all the work. `sin(pi - x) = sin(x)` says the second
quarter is the first quarter read backward: when `quad(0) = '1'`, replace
`addr` with `Q - 1 - addr`. And `sin(x + pi) = -sin(x)` says the bottom half
is the top half negated: when `quad(1) = '1'`, negate the table output. Cost
of admission: `Q - 1 - addr` for an 8-bit addr is just the ones' complement,
`not addr` — one layer of inverters steered by `quad(0)` — and the negation
is a conditional two's complement. Two thin layers of logic, and the ROM
drops from 1024 entries to 256:

```
2**8 entries  ×  8 bits  =  2048 bits — a quarter of the naive table
```

#### The half-sample offset, or: how folding becomes exact

Here's the trap everyone falls into the first time. Suppose entry i stores
`sin(i * 90°/Q)` — samples *at* the grid points, starting at exactly 0°.
Then the first quarter's samples are sin(0°), sin(0.35°), …, sin(89.65°) —
note the peak, sin(90°), is *not in the table* (it belongs to index Q, one
past the end). Now mirror for the second quarter: phase Q + a needs
`sin(90° + a·(90°/Q))` = `sin(90° - a·(90°/Q))`, which lives at fractional
index Q - a — for a = 0 that's index Q. Off the end of the table. You can
fudge it with `Q - 1 - a` and eat a one-sample phase error at every fold
seam, or you can fix the sampling grid instead.

The fix: store samples at the *midpoints* of the phase slices. Entry i
holds

```
sin( (i + 0.5) * 90°/Q )
```

Midpoints are symmetric about 90°: the mirror of midpoint i + 0.5 is
midpoint Q - 1 - i + 0.5, exactly. Check it — the folded value the second
quarter needs at offset a is

```
sin(90° + (a+0.5)·90°/Q) = cos((a+0.5)·90°/Q) = sin((Q-1-a + 0.5)·90°/Q)
```

which is *precisely* entry Q - 1 - a, i.e. entry `not a`. The fold adds
zero error; the ones' complement isn't an approximation of the mirror, it
*is* the mirror. (The whole output is a half-slice phase-shifted sine,
`sin(2*pi*(p+0.5)/1024)` — a constant phase offset nobody can hear or
measure without a reference.) Consequences worth noticing: neither exact 0
nor the exact peak is stored — entry 0 is `round(127*sin(0.18°)) = 0` and
entry 255 is `round(127*sin(89.82°)) = 127`, within 1 LSB of full scale.
That's requirement R1, and it dovetails with the next paragraph.

**Why full scale is 127, not 128.** Two's complement is asymmetric: 8 bits
hold -128 to +127. If the table ever stored 128 it wouldn't fit; worse, if
it stored -128 anywhere, the sign-fold's negation would compute +128 and
wrap to -128 — a full-scale glitch four times per cycle. So the amplitude
constant is `2**(DATA_BITS-1) - 1 = 127`: every stored value is in 0..127,
every negated value is in -127..0, and negation can *never* overflow. This
is the same asymmetry you met in lesson 03's signed saturation — here we
design it out of reach instead of clamping.

#### The init function: math_real at elaboration time

Lesson03 computed single constants with `math_real`. This module computes
256 of them:

```vhdl
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
```

Read the last line first: `rom` is a **constant**, so its initializer must
be computable at **elaboration time** — the phase after analysis when the
design hierarchy is built, generics get their values, and every constant is
evaluated. Both GHDL (for simulation) and yosys+GHDL (for synthesis) run
`init_rom` exactly once, on your workstation, before any simulation cycle
runs or any gate exists. The loop, the `real` arithmetic, the `sin` — none
of it is "synthesized"; only the 256 resulting integers survive into the
netlist, as ROM contents. That's why calling `sin()` here is legal in a
flow where `sin()` in a clocked process would be rejected instantly:
synthesizable VHDL is about *what must become hardware*, and a constant
never does. `MATH_PI_OVER_2` is just pi/2 from `math_real`, and note the
function can size itself off the generics (`Q`, `AMP`, `DATA_BITS`) —
change `PHASE_BITS` to 12 at instantiation and a 1024-entry table is
computed instead, no other edits.

When you run `make synth` you'll see GHDL announce the result:

```
sine_lut.vhd:61:12:note: found ROM "n15", width: 8 bits, depth: 256
```

Your table survived the trip into the synthesizer as a recognized memory.
Where it lands in the fabric is the next question.

#### Block RAM, and the rule that decides who gets it

An iCE40 logic cell is a 4-input LUT plus a flip-flop; storing data in
fabric means burning LUTs as tiny ROMs. But the die also has dedicated
memory tiles: **SB_RAM40_4K**, 4096 bits each, configurable as 256×16,
512×8, 1024×4, or 2048×2. The icestick's hx1k has 16 of them; the hx8k has
32. Our 2048-bit quarter table fits in half of one.

There's a catch, and it's physical: BRAM reads are **synchronous only**.
The address is captured on a clock edge and data appears after it; there is
no combinational path from address to data through the tile. So yosys can
only put your array in BRAM if your HDL *reads it synchronously* — and
yosys establishes that by pattern-matching: during the `memory_dff` pass it
looks for a flip-flop it can merge into the memory read port, either on the
read data (output register) or on the address. The canonical inferable
shape is:

```vhdl
if rising_edge(clk) then
  data <= rom(to_integer(addr));   -- FF sits directly on the read data
end if;
```

Now look at our process. Between the ROM read and the output register sits
the sign fold: `v := rom(...); if quad(1) = '1' then v := -v; end if;
data <= v;`. The flip-flop's input is the *negate mux*, not the raw ROM
output — so `memory_dff` finds no FF to merge, the read stays
combinational, and combinational reads cannot go to iCE40 BRAM. Yosys tells
you all of this, in order, if you know which lines to read:

```
2.23.5. Executing MEMORY_DFF pass (merging $dff cells to $memrd).
Checking read port `\:26'[0] in module `\sine_lut': no output FF found.
Checking read port address `\:26'[0] in module `\sine_lut': no address FF found.
...
2.25. Executing MEMORY_LIBMAP pass (mapping memories to cells).
using FF mapping for memory sine_lut.:26
```

"FF mapping" would mean a flip-flop per bit for a RAM — but a ROM has no
writes, so after `memory_map` it collapses to pure constant logic and ABC
optimizes it hard. Two things make it shockingly small. First, every stored
value is non-negative, so bit 7 of every entry is 0 — yosys deletes the
whole lane (`removing const-0 lane 7` in the log; our R1 design choice just
saved an eighth of the table). Second, sine is smooth, so neighboring
entries share high bits and the mux trees collapse. The 2048-bit table plus
both folds lands in **132 SB_LUT4** — about 10% of an hx1k, for the
complete waveform memory of the instrument. That's a price we'll happily
pay to keep the latency at one cycle; Explore 3 rebuilds the module the
BRAM way and shows exactly what changes, in the stat block and in the
testbench.

The takeaway discipline: **never assert where a memory went — read the
`stat` block.** The one printed after `3. Printing statistics` is the
final netlist. `SB_RAM40_4K` count tells you BRAMs; a suspiciously large
`SB_LUT4` count tells you a memory fell into fabric; and the `memory_dff`
lines tell you *why*.

#### Latency is part of the interface

The output register means `data` answers for the phase presented one clock
*earlier*. One cycle is nothing for audio, but it is a contract: when
lesson 14 wires `nco -> sine_lut -> dsm_dac`, every stage's delay adds, and
a testbench that doesn't know the pipeline depth reads garbage. So the
testbench pins it down as requirement R4: after a phase step, `data` must
*not* change before the next edge (registered, not combinational) and
*must* have changed just after it (one cycle, not two). When Explore 3 adds
a pipeline stage, R4 is the assert that catches it.

Note also what's absent: no reset (a ROM has no state worth clearing — the
register holds *some* table value one edge in, and which one doesn't
matter) and no enable (a lookup every clock is free; downstream samples
when it cares). House style mandates resets and enables on *stateful*
logic; a ROM lookup is arithmetic that happens to take a cycle.

### Radar Connection

**Waveform memory and the DDS spur floor.** Swap the RC filter for a power
amplifier and the sine table for "arbitrary waveform," and this lesson's
module is the waveform memory of a direct digital synthesizer — the way
modern radars generate transmit waveforms, chirps, and stable local
oscillators. The design pressures are identical, just with more zeros on
the requirements.

Phase truncation is the one that bites. The 22 discarded phase bits mean
the address presented to the table lags the true phase by up to one
1024th of a cycle, and that error is not random: it's a periodic sawtooth
locked to the ratio of FCW and phase, so it appears as discrete **spurs** —
phantom spectral lines at predictable offsets from the carrier. The
rule of thumb: worst-case truncation spurs sit near **-6.02 dB per phase
bit** used to address the table. Our 10 bits → spurs around -60 dBc, fine
under an 8-bit amplitude floor (≈ -50 dB SQNR, 6.02 dB/bit + 1.76). A
radar exciter chasing -100 dBc spurs (a Doppler radar's clutter rejection
lives or dies on spectral purity — a -60 dBc spur *is* a slow-moving false
target) needs 16-plus phase bits, which naively means a 65536-entry table.
This is why quarter-wave folding isn't a hobbyist trick: it's in the real
DDS chips (AD9910-class parts do folding plus coarse/fine table
factorizations and angle-rotation tricks on top) because every doubling of
effective table depth is 6 dB of spur floor, and folding buys two doublings
for two layers of XOR-grade logic. Same table, same fold, same `stat`
discipline — the radar version just has a spur budget taped above the
bench.

**Stopping point.** You should now be able to explain:

- why the half-sample offset makes `not addr` the *exact* mirror of the
  quarter table rather than an off-by-one approximation — and why entry 0
  is not 0 and entry Q-1 is not quite full scale.
- why the amplitude constant is 127 and not 128: what a stored -128 would
  do to the sign fold, and how the design puts that overflow out of reach.
- when `init_rom` runs, and why calling `sin()` there is legal in a
  synthesis flow that would reject the same call in a clocked process.
- why a memory whose read data passes through the sign fold before the
  flip-flop cannot land in iCE40 BRAM, and which yosys log lines tell you
  where a memory actually went.

---

## Session 07.2 — Build & Run (~75 min)

### Build

Create `course/work/lesson07/` and enter the three files below. Read the
module's header comment first — it declares requirements R1–R4, and every
testbench assert carries one of those tags, same discipline as lessons
02–06.

While you type the module, watch for: the `rom` constant initialized by a
function call (elaboration-time math), the `not addr` mirror and the
guarded negation (the two folds), and `quad`/`addr`/`v` being process
**variables**, not signals — each is computed and consumed within a single
rising edge, which is exactly what variables are for (lesson 01: signals
update at the delta, variables update immediately).

**File: course/work/lesson07/sine_lut.vhd**

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

The testbench takes a different shape from lesson 03's paired
stimulus/check calls: it sweeps all 1024 phases once, capturing every
registered output into an array, then checks **properties of the whole
array**. There is deliberately no golden table of 1024 expected values —
the table contents come from your host's `sin()`, and a byte-exact golden
trace would be hostage to libm rounding on somebody else's machine. The
symmetry properties (R2, R3) are exact by construction on *any* correct
build, which makes them the honest thing to assert. Note the sampling
pattern in the sweep loop: phase i is applied just after an edge, the next
edge registers it, and the read happens 1 ns after that edge — R4's
one-cycle contract, exercised 1024 times before it's tested explicitly.

**File: course/work/lesson07/sine_lut_tb.vhd**

```vhdl
-- sine_lut_tb.vhd — self-checking testbench for sine_lut.
--
-- Verification approach: sweep the full phase circle once, capturing the
-- registered output for every phase into an array, then check *properties*
-- of that array — no golden trace. Every assert is tagged with the
-- requirement it verifies (R1..R4 from sine_lut.vhd):
--   R1: peak amplitude within 1 LSB of full scale, both polarities.
--   R2: quarter symmetry — samples(p) = samples(HALF-1-p) exactly.
--   R3: sign symmetry — samples(p+HALF) = -samples(p) exactly.
--   R4: exactly one clock of latency: output holds mid-cycle after a phase
--       change (not combinational) and updates on the next edge (not slower).
--
-- Sampling note: phase is applied just after an edge, so the *next* rising
-- edge registers it; the TB waits 1 ns past that edge before reading data.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sine_lut_tb is
end entity sine_lut_tb;

architecture sim of sine_lut_tb is
  constant PB      : positive := 10;             -- PHASE_BITS under test
  constant DB      : positive := 8;              -- DATA_BITS under test
  constant N       : natural  := 2 ** PB;        -- phases in a full circle
  constant HALF    : natural  := N / 2;
  constant FS      : integer  := 2 ** (DB - 1) - 1;  -- full scale = 127
  constant CLK_PER : time     := 83.333 ns;      -- 12 MHz

  signal clk   : std_logic := '0';
  signal phase : unsigned(PB - 1 downto 0) := (others => '0');
  signal data  : signed(DB - 1 downto 0);
  signal done  : boolean := false;

  type sample_arr is array (0 to N - 1) of integer;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.sine_lut
    generic map (PHASE_BITS => PB, DATA_BITS => DB)
    port map (clk => clk, phase => phase, data => data);

  main : process
    variable samples    : sample_arr;
    variable vmax, vmin : integer;
    variable errs       : natural;
  begin
    -- one full circle: apply phase i, let the next edge register it, read.
    for i in 0 to N - 1 loop
      phase <= to_unsigned(i, PB);
      wait until rising_edge(clk);  -- DUT registers the sample for phase i
      wait for 1 ns;                -- let data settle past the edge
      samples(i) := to_integer(data);
    end loop;

    -- R1: peak amplitude within 1 LSB of full scale, both polarities.
    vmax := integer'low;
    vmin := integer'high;
    for i in 0 to N - 1 loop
      if samples(i) > vmax then vmax := samples(i); end if;
      if samples(i) < vmin then vmin := samples(i); end if;
    end loop;
    assert vmax <= FS and vmax >= FS - 1
      report "R1 FAIL: positive peak " & integer'image(vmax) &
             " not within 1 LSB of full scale " & integer'image(FS)
      severity error;
    assert vmin >= -FS and vmin <= -(FS - 1)
      report "R1 FAIL: negative peak " & integer'image(vmin) &
             " not within 1 LSB of full scale " & integer'image(-FS)
      severity error;
    report "R1 pass: peaks " & integer'image(vmax) & " / " &
           integer'image(vmin) & " within 1 LSB of full scale " &
           integer'image(FS);

    -- R2: quarter symmetry, sin(x) = sin(pi - x), exact.
    errs := 0;
    for i in 0 to HALF - 1 loop
      if samples(i) /= samples(HALF - 1 - i) then
        errs := errs + 1;
      end if;
    end loop;
    assert errs = 0
      report "R2 FAIL: " & integer'image(errs) &
             " phases break sin(x) = sin(pi - x)"
      severity error;
    report "R2 pass: quarter symmetry exact over " &
           integer'image(HALF) & " phases";

    -- R3: sign symmetry, sin(x + pi) = -sin(x), exact.
    errs := 0;
    for i in 0 to HALF - 1 loop
      if samples(i + HALF) /= -samples(i) then
        errs := errs + 1;
      end if;
    end loop;
    assert errs = 0
      report "R3 FAIL: " & integer'image(errs) &
             " phases break sin(x + pi) = -sin(x)"
      severity error;
    report "R3 pass: sign symmetry exact over " &
           integer'image(HALF) & " phases";

    -- R4: exactly one clock of latency. Settle at phase 0, then step to the
    -- positive peak (N/4): the output must NOT change before the next edge
    -- and MUST have changed just after it.
    phase <= to_unsigned(0, PB);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    assert to_integer(data) = samples(0)
      report "R4 FAIL: output for phase 0 not stable before the step"
      severity error;
    phase <= to_unsigned(N / 4, PB);
    wait for CLK_PER / 4;  -- mid-cycle, before the registering edge
    assert to_integer(data) = samples(0)
      report "R4 FAIL: output changed before the clock edge (combinational?)"
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert to_integer(data) = samples(N / 4)
      report "R4 FAIL: output did not update one edge after the phase change"
      severity error;
    report "R4 pass: registered output, exactly one clock of latency";

    report "sine_lut testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

The Makefile is the lesson 05 shape in miniature: the `sim` target you know,
plus a standalone `synth` target that runs yosys through the GHDL plugin
and prints `stat` — no PCF, no place-and-route, just "what did my RTL
become". A `wave` target is included because a sine table is the first
module in this course genuinely worth *looking* at.

**File: course/work/lesson07/Makefile**

```makefile
# Lesson 07 — sine_lut simulation. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile in
# miniature — same flags, same shim. 'make synth' prints the yosys stat
# report so you can see how the table maps onto the iCE40 fabric.

TB         = sine_lut_tb
SRC        = sine_lut.vhd sine_lut_tb.vhd
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave synth clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure

# Opens the waveform even when the sim fails an assert — that's when you
# most need it. The '-' keeps make going past sim's nonzero exit.
wave:
	-$(MAKE) sim
	gtkwave build/$(TB).ghw &

# Standalone resource report (no pcf, no pnr): read the 'stat' block to see
# whether the ROM landed in BRAM or logic cells — discussed in the lesson.
synth: | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) sine_lut.vhd -e sine_lut; synth_ice40 -top sine_lut; stat'

build:
	mkdir -p build

clean:
	rm -rf build
```

### Run

From `course/work/lesson07/` (with the `fpga` alias already sourced in your
shell):

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build sine_lut.vhd sine_lut_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/sine_lut_tb sine_lut_tb
./build/sine_lut_tb --wave=build/sine_lut_tb.ghw --assert-level=failure
sine_lut_tb.vhd:73:5:@85292325500fs:(report note): R1 pass: peaks 127 / -127 within 1 LSB of full scale 127
sine_lut_tb.vhd:88:5:@85292325500fs:(report note): R2 pass: quarter symmetry exact over 512 phases
sine_lut_tb.vhd:102:5:@85292325500fs:(report note): R3 pass: sign symmetry exact over 512 phases
sine_lut_tb.vhd:125:5:@85542324500fs:(report note): R4 pass: registered output, exactly one clock of latency
sine_lut_tb.vhd:127:5:@85542324500fs:(report note): sine_lut testbench complete (any FAILs are listed above)
```

(The `mkdir -p build` line appears only on the first run, and your home
directory will appear in the shim path instead of `/home/clementsj`.) Read
the timestamp on the R1–R3 lines: ~85.29 µs is 1024 phases swept at one per
12 MHz clock (1024 × 83.33 ns ≈ 85.3 µs) — the whole-circle capture the
testbench header promised. The sim also wrote `build/sine_lut_tb.ghw`; run
`make wave` and plot `data` in GTKWave (Data Format → Signed Decimal, then
Analog → Step) to see the staircase sine you just synthesized from
symmetry.

Now ask the synthesizer what this becomes on the iCE40:

```bash
make synth
```

Expected output (yosys prints ~2000 lines; everything but the lines worth
reading is elided — pass numbers like `2.23.5` may differ with your yosys
version):

```text
yosys -m ghdl -p 'ghdl --std=08 --workdir=build sine_lut.vhd -e sine_lut; synth_ice40 -top sine_lut; stat'
[...]
1. Executing GHDL.
sine_lut.vhd:61:12:note: found ROM "n15", width: 8 bits, depth: 256
  constant rom : rom_t := init_rom;
           ^
[...]
2.23.1. Executing OPT_MEM pass (optimize memories).
sine_lut.:26: removing const-0 lane 7
[...]
2.23.5. Executing MEMORY_DFF pass (merging $dff cells to $memrd).
Checking read port `\:26'[0] in module `\sine_lut': no output FF found.
Checking read port address `\:26'[0] in module `\sine_lut': no address FF found.
[...]
2.25. Executing MEMORY_LIBMAP pass (mapping memories to cells).
using FF mapping for memory sine_lut.:26
[...]
3. Printing statistics.

=== sine_lut ===

        +----------Local Count, excluding submodules.
        | 
       90 wires
      286 wire bits
       90 public wires
      286 public wire bits
        3 ports
       19 port bits
      146 cells
        6   SB_CARRY
        7   SB_DFF
        1   SB_DFFSR
      132   SB_LUT4

End of script. [...]
```

Walk the story in order: GHDL recognized a 256×8 ROM; `opt_mem` deleted the
constant-zero sign lane (the R1 design choice, visible in the log);
`memory_dff` found no register to merge (our sign fold sits between the
read and the FF); `memory_libmap` therefore fell back from BRAM; and the
final stat shows the result — **zero `SB_RAM40_4K`, 132 `SB_LUT4`**, plus
the eight output flip-flops. Note that `stat`-style cell counts appear
earlier in the log too (the hierarchy pass prints one); the block after
`3. Printing statistics` is the final netlist and the only one that counts.

**Stopping point.** You should now be able to explain:

- why the testbench asserts symmetry *properties* of the captured array
  instead of comparing against a 1024-entry golden trace — and why the
  golden trace would be the less honest check.
- how the ~85.29 µs timestamp on the R1–R3 report lines confirms the
  whole-circle sweep: 1024 phases at one per 12 MHz clock.
- the `make synth` log as a story, in order: `found ROM` → `removing
  const-0 lane 7` → `no output FF found` → `using FF mapping` → a final
  stat with zero `SB_RAM40_4K` and 132 `SB_LUT4`.
- why only the stat block after `3. Printing statistics` describes the
  final netlist, and what `-m ghdl` is doing on the yosys command line.

---

## Session 07.3 — Explore & Checkpoint (~75 min)

### Explore

Solutions live in `course/solutions/lesson07/` — attempt these before
peeking.

1. **Break it on purpose — delete the mirror.** Comment out the
   `addr := not addr;` line (keep the `if`), so the 2nd and 4th quarters
   read the table forward instead of backward. Predict which requirement
   tags fail before you run: the waveform becomes four repeats of the
   rising quarter (two positive, two negated) — is that still
   quarter-symmetric? Sign-symmetric? Run `make sim`: R2 reports hundreds
   of broken phases while R3 still passes (negation doesn't care what it
   negates). Look at the wreckage with `make wave` — it's a shark-fin
   wave, and this is exactly what a folded-table address bug looks like on
   a bench scope. Restore and re-run to green.

2. **Store full scale, meet the asymmetry.** Change `AMP` to
   `real(2 ** (DATA_BITS - 1))` — 128, "real" full scale. Elaboration now
   computes entries that don't fit in 8 bits; watch GHDL emit
   `to_signed: vector truncated` warnings as +128 wraps to -128, then
   watch R1 and R3 fail (a stored -128 negates to... -128, breaking sign
   symmetry — lesson 03's asymmetric code, striking exactly as the module
   header warned). One LSB of amplitude is what that headroom costs.
   Restore `- 1`.

3. **Earn the BRAM.** Restructure the architecture into the inferable
   shape: compute `addr` (with the mirror) as a combinational signal
   *outside* the process; inside the process do a raw registered read
   `raw <= rom(to_integer(addr));`, register the sign bit alongside it
   (`neg_d <= phase(PHASE_BITS - 1);`), and in the same process apply the
   negation to the *previous* cycle's `raw` to produce `data`. Run
   `make synth`: `memory_dff` now merges the read register, and stat shows
   `1 SB_RAM40_4K` with the LUT count collapsing to ~28. Then run
   `make sim`: R4 fails — the negate-after-read is a second pipeline
   stage, so latency is now two cycles — and so does R2, more subtly: the
   sweep loop assumed one cycle, so every captured sample is really the
   *previous* phase's, the whole array is rotated by one, and rotation
   breaks the mirror pairing (while leaving R3's fixed +HALF offset
   intact — check you can explain why). You'll also see a
   `TO_INTEGER: metavalue detected` warning: the very first capture reads
   a register nothing has filled yet. That's the trade stated by the
   tools themselves: one BRAM and ~100 LUTs back, for a cycle of latency
   and a testbench contract change. Our chain keeps the 1-cycle version;
   at 132 LUTs the fabric price is noise.

4. **Generic sweep — the table that resizes itself.** Set `PB := 12` and
   `DB := 12` in the testbench constants only and re-run `make sim`: the
   init function builds a 1024-entry, 12-bit table (peaks 2047/-2047, R2/R3
   over 2048 phases) with zero edits to `sine_lut.vhd`. The `synth` target
   elaborates `sine_lut` with its *defaults*, so to see the fabric cost,
   temporarily set the defaults in `sine_lut.vhd` to 12/12 too and
   `make synth`: the LUT bill roughly quadruples. This is the knob the
   Radar Connection prices at 6 dB of spur floor per phase bit. Restore
   both files.

### Tips & Pitfalls

- **`sin` won't synthesize — until it will.** The dividing line is not the
  function, it's the context: `math_real` in constants, generics, and
  functions reached only from constant initializers is elaboration-time
  and free; the same call inside clocked logic is an error. If yosys/GHDL
  ever complains about a `real` in your design, you've let one leak out of
  a constant.
- **Read the *last* stat block.** A yosys log contains cell counts in at
  least three places; only the one after `3. Printing statistics` is the
  final netlist. Grep discipline: `make synth 2>&1 | sed -n '/^3\./,$p'`
  when the scrollback gets long. And `-m ghdl` on the yosys command is the
  oss-cad-suite plugin that lets yosys read VHDL at all — forget it and
  you get `ERROR: Unknown command: ghdl`.
- **Variables for intra-edge math.** `quad`, `addr`, `v` update
  immediately, in order, within the edge — a signal there would hand you
  last delta's value (lesson 01) and the folds would lag the phase by a
  cycle each. Rule of thumb: variables for scratch math inside a process,
  signals for anything that leaves it.
- **Emacs/vhdl-mode: sensitivity lists for free.** With everything under
  `rising_edge(clk)`, the sensitivity list is just `(clk)` — but when you
  write combinational processes (Explore 3's mirror mux, if you do it as a
  process), `M-x vhdl-update-sensitivity-list-process` rewrites the list
  from what the body actually reads. Stale sensitivity lists simulate
  wrong and synthesize right — the worst kind of bug — and GHDL won't
  always warn you.
- **`downto 0` off-by-two.** `addr` is `PHASE_BITS - 3 downto 0` — the
  *two* quad bits come off the top, so the quarter table index is
  PHASE_BITS-2 bits wide, ending at index PHASE_BITS-3. Writing
  `PHASE_BITS - 2 downto 0` gives a width mismatch GHDL catches; writing
  the slice as `phase(7 downto 0)` hard-codes the generic away and GHDL
  *won't* catch it until someone changes PHASE_BITS. Keep slice bounds in
  terms of the generic, always.

### Checkpoint

Before lesson 08, you must have:

- `make sim` in `course/work/lesson07/` printing `R1 pass` through
  `R4 pass` and the `testbench complete` line, zero FAILs.
- `make synth` run, and the answer to "did my ROM land in BRAM?" read from
  the log itself: `using FF mapping`, no `SB_RAM40_4K` in the final stat,
  132 `SB_LUT4` — plus one sentence on *why* (the sign fold sits between
  the ROM read and the output register, so the read isn't synchronous).
- Explore 1 or 2 done: you've watched a symmetry requirement fail and can
  name which fold each of R2/R3 checks.
- One-sentence answers to: why is the stored amplitude 127 and not 128?
  Why does the half-sample offset make `not addr` an exact mirror?
- The latency contract internalized: `data` answers for last cycle's
  `phase`, and the R4 assert is what will catch any future edit that
  changes that.
