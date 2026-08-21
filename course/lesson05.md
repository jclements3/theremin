# Lesson 05 — From RTL to Bitstream

*Where we are.* Lesson04 took the NCO apart line by line and proved with a
requirement-tagged testbench that a 32-bit phase accumulator clocked at
12 MHz really does emit any frequency you ask for, to a resolution of
0.0028 Hz. Everything so far has run inside GHDL — a program pretending to
be hardware. This lesson, the pretending stops: you will push that NCO
through synthesis, place-and-route, and bitstream packing, and end holding a
`top.bin` that would make an iCEstick sing concert A through a piezo. You
won't flash it yet — the boards live on the lab bench, and flashing is
lesson99's opening act — but the file you build today is the exact one
you'll program then. The point of the lesson is that nothing between your
VHDL and that file is magic: four tools, each with one job, each leaving an
inspectable text file behind.

## Objectives

- Name the four tools in the flow — yosys, nextpnr, icepack, icetime — and
  state what each consumes and produces.
- Read a yosys `stat` report and account for every flip-flop in it from the
  VHDL source, including the one that's missing.
- Write a PCF constraints file and explain what nextpnr does when a
  top-level port has no `set_io` line.
- Explain the power-on-reset pattern in `top.vhd` and why a board with no
  reset button needs it.
- Build the A440 bitstream for both course boards and read the two timing
  reports that decide whether it's allowed to exist.

## Concepts

### A compiler with three back ends

You know this shape from software: compiler → linker → loader, each stage
narrowing "what I meant" toward "what the machine executes". The FPGA flow
has the same shape with different nouns:

```
  nco.vhd ──┐
  top.vhd ──┴─► yosys (+ ghdl plugin) ──► build/top.json    SYNTHESIS
                                            "which primitives, wired how"

  icestick.pcf ──┐
  build/top.json ┴─► nextpnr-ice40 ─────► build/top.asc     PLACE & ROUTE
                                            "which physical cell, which wire"

  build/top.asc ───► icepack ───────────► build/top.bin     PACKING
                                            "config bits, in load order"

  build/top.asc ───► icetime ───────────► timing report     THE GATE
                                            (no file: a pass/fail verdict)
```

The deep difference from a software compiler: there is no instruction
stream at the end. A CPU binary is a *plan* for one ALU to follow, one step
at a time. `top.json` is a *parts list and wiring diagram* — when it's
loaded into the chip, every part on the list exists simultaneously and all
of them work on every clock edge. Synthesis doesn't schedule your design
onto hardware; it *becomes* the hardware.

Every intermediate is text. `top.json` is a netlist you can read with
`less`; `top.asc` is an ASCII grid of configuration bits. When the flow
does something you don't expect, you can always open the artifact and look.
No black boxes — the course rule, enforced by the toolchain's own file
formats.

### What the fabric offers: the iCE40 logic cell

Synthesis needs a target vocabulary. The iCE40's is small enough to learn
completely. The atom is the **logic cell (LC)**:

- a **LUT4**: a 16×1-bit lookup table — *any* boolean function of 4 inputs,
  the function being 16 configuration bits;
- a **D flip-flop** after it, optionally used, with optional clock-enable
  and optional set/reset;
- **carry logic** beside it: a dedicated fast path that chains LC-to-LC so
  adders don't burn a whole LUT per carry.

The iCEstick's HX1K has 1280 LCs; the HX8K breakout has 7680. Both also
have block RAMs (16 and 32 — lesson07's territory), a PLL, and I/O cells.
In yosys output these appear as `SB_`-prefixed primitives (SiliconBlue, the
startup Lattice bought): `SB_LUT4`, `SB_CARRY`, `SB_DFF` and its variants,
`SB_IO`, `SB_GB` (a global buffer — the dedicated low-skew network your
clock rides on). Your entire design is about to be re-expressed in that
vocabulary and nothing else.

### Stage 1: yosys, with GHDL as its front end

Yosys is a Verilog synthesizer; our VHDL enters through the
`ghdl-yosys-plugin`, which embeds the same GHDL you've been simulating with
as a yosys front end. One command runs the whole stage:

```
yosys -m ghdl -p 'ghdl --std=08 --workdir=build nco.vhd top.vhd -e top; synth_ice40 -top top -json build/top.json'
```

Read it inside-out: `-m ghdl` loads the plugin; the `-p` script first runs
`ghdl` (same `--std=08 --workdir=build` flags as simulation — analyze the
two RTL files, elaborate `top`) to produce yosys's internal representation,
then `synth_ice40` lowers it to iCE40 primitives and writes the JSON
netlist. `synth_ice40` is itself no black box: it's a published recipe of
~30 passes (type `yosys> help synth_ice40` to see it) — infer memories,
map arithmetic onto carry chains, map logic onto LUT4s via ABC, map
registers onto the `SB_DFF` family.

Note what is *not* in the command: the testbench. `nco_tb.vhd` is full of
`wait for`, `report`, file I/O of waveforms — meaningful to a simulator,
meaningless as hardware. The RTL/TB split you've kept since lesson02 is
exactly the synthesizable/unsynthesizable split.

### Reading the stat report

Near the end of the log, `synth_ice40` prints statistics — the parts list.
For this design:

```
     53   SB_CARRY
     24   SB_DFF
      4   SB_DFFE
     31   SB_DFFSR
     60   SB_LUT4
```

House rule: never let a resource report go by unexplained. Account for
every flip-flop. The source declares three registers: `acc` (32 bits,
inside the NCO), `hb_cnt` (24 bits), `por_cnt` (4 bits) — 60 flops. The
report shows 24 + 4 + 31 = 59. Map them:

| cells | source register | why that flavor |
|---|---|---|
| 24 × `SB_DFF` | `hb_cnt` | plain `if rising_edge` — no reset, no enable |
| 4 × `SB_DFFE` | `por_cnt` | the `if por_cnt /= x"F"` guard became a clock **e**nable |
| 31 × `SB_DFFSR` | `acc` | our synchronous reset became the **s**ynchronous-**r**eset flop |

The house style you've been following since lesson01 — synchronous
active-high resets, clock enables instead of gated clocks — is precisely
the style that maps 1:1 onto this cell family. That's not a coincidence;
the style exists because this is what fabrics provide.

And the missing flop? `acc` is 32 bits but only 31 made it. The frequency
control word is a *constant*, 157482 — an even number, so its bit 0 is `0`.
`acc(0) <= acc(0) + 0` can never leave zero, and yosys's constant
propagation deleted the flip-flop, the carry cell under it, and the wire.
The synthesizer read your arithmetic more carefully than you did. (Explore
exercise 2 turns this into an experiment.)

The rest: 53 `SB_CARRY` cells carry the three adders (the 31 live bits of
`acc + fcw`, the 24-bit `hb_cnt` increment, the 4-bit `por_cnt`); 60
`SB_LUT4`s hold the add logic, the mux-with-reset in front of each DFFSR,
and the `por_cnt /= x"F"` comparison. Zero block RAMs — remember that line;
in lesson07 it's the line you'll be watching.

### Stage 2: the PCF — names to pins

The netlist says `top` has ports `clk12`, `audio_out`, `led_hb`. The board
says the 12 MHz can arrives at package pin 21. Nothing connects those two
facts except you, and the PCF (physical constraints file) is where you
write it down:

```
set_io clk12     21
set_io led_hb    99
set_io audio_out 78
```

Names must match the top-level port names exactly. The iCEstick's TQ144
package uses pin numbers; the HX8K's CT256 is a ball-grid array, so its PCF
uses ball names like `J3`. Where do the numbers come from? The board
schematic, and only the board schematic — a PCF is a claim about copper,
and a wrong claim can connect an output driver to a supply rail. That's why
nextpnr treats a port with *no* `set_io` line as a hard error rather than
picking a pin for you (Explore exercise 1 shows you the message), and why
`hx8k.pcf` ships with a comment ordering you to verify the audio ball
against the schematic before trusting it.

### Stage 3: nextpnr — the netlist meets geometry

```
nextpnr-ice40 --hx1k --package tq144 --pcf icestick.pcf \
              --json build/top.json --asc build/top.asc --freq 12
```

nextpnr does the two NP-hard halves: **place** (assign each of the ~65
packed LCs to one of 1280 physical sites — near each other where they
connect, since distance is delay) and **route** (claim actual wire segments
and switch-box crossings for every net). `--freq 12` declares the timing
contract: every register-to-register path must settle inside one 12 MHz
period, 83.3 ns. The placer and router optimize against that number, the
final report grades it — `PASS` or the build errors out. You'll see the
`Max frequency` line twice: once after placement (an estimate) and once
after routing (real wire delays). Watch the utilisation block too: this
design uses 5% of an HX1K. By lesson14 that number is a budget.

### Stages 4 and 5: icepack, and icetime as the gate

`icepack` is the boring one, deliberately: `top.asc` (ASCII bits) in,
`top.bin` (binary bits in configuration-load order) out, no decisions
made. Two facts worth noticing: the `.asc` is readable text — `head` it —
and the `.bin` is ~32 KB for the HX1K and ~135 KB for the HX8K *regardless
of your design*, because a bitstream configures every cell on the die,
including the unused ones.

`icetime` is the opposite of boring. It rebuilds a timing graph from the
*routed* `.asc` using the icestorm project's independently measured device
timing model, and reports the critical path — the slowest
register-to-register route in the design. Two tools now grade the same
question; they will disagree slightly (different models — trust the lower
number) and **both must pass at 12 MHz** before a bitstream is considered
buildable. That's the course rule, and it has teeth: a design that
simulates perfectly but misses timing will run on the bench — usually —
until temperature or voltage shifts the margins, and then it fails in ways
simulation can never show you. Timing closure is a *proof obligation*, like
the testbench, not a benchmark.

For this design the critical path is exactly where lesson04 said the cost
of a wide accumulator lives: a carry chain. Look at the report you'll
generate: it enters at `u_nco.acc[1]`, ripples carry-to-carry up all ~30
live accumulator bits (0.126 ns per bit — the dedicated carry path earning
its keep), and lands on the `audio_out` flop's setup: 31 logic levels,
6.19 ns, fmax 161 MHz. At 12 MHz we have a 13× margin. Enjoy it; the
integration lesson will spend some of it.

### top.vhd: the power-on-reset

`top.vhd` is small, but it answers a question the testbench never had to
face: who drives `rst`? In simulation, the TB did. The boards have no reset
button. The iCE40 has a property that fills the gap: at configuration, every
flip-flop powers up holding its declared initial value — that's what
`:= (others => '0')` on `por_cnt` means *to the synthesizer*, not just to
GHDL. So `top.vhd` builds a reset out of that guarantee: `por_cnt` wakes at
0, counts to 15, and sticks (its enable — the `SB_DFFE`s you counted —
turns off at `x"F"`); `rst` is asserted while it counts. Fifteen clean
clock cycles of synchronous reset after configuration, then the design runs
forever. This exact pattern reappears in `theremin_top` in lesson14.

The other thing `top.vhd` shows is lesson03's discipline paying off:
`FCW_A440` is 157482 because round(440 × 2³² / 12 MHz) = 157482, giving
439.9996 Hz — an error of 0.4 millihertz, three orders of magnitude below
the ~1 Hz a trained ear can resolve at A4. The header comment shows the derivation,
so the next reader doesn't have to take the magic number on faith. `led_hb`
is the classic hello-world of FPGA bring-up: bit 23 of a free-running
counter blinks at 12 MHz/2²⁴ ≈ 0.72 Hz, proving clock, configuration, and
at least one flop are alive even if audio is silent.

## Radar Connection

**Why sensor front ends are FPGAs and not CPUs or GPUs.** The stat report
you just read is the whole argument, if you read it the right way. Those 59
flip-flops and 60 LUTs all exist at once and all switch on every one of the
12 million clock edges per second. A CPU running "the same" NCO time-slices
one ALU: fetch, add, store, loop — maybe 20 ns per update on a good day,
*if* the caches cooperate. The FPGA version updates in one clock, every
clock, because the accumulator isn't a variable, it's a place.

Now scale the input. A radar digitizer runs at hundreds of MS/s to several
GS/s — one sample every nanosecond or faster. The front-end work
(digital downconversion, decimating filters, beamforming sums) must happen
*at that rate, forever, without a hiccup*. A single CPU cache miss costs
~100 ns: a hundred samples on the floor. A GPU can crunch the aggregate
throughput easily, but only by batching — and its milliseconds of batch
latency are fine for SAR image formation and fatal for anything closed-loop:
a seeker steering toward its echo, a jammer that must respond inside a pulse
width. So real systems layer: FPGA/ASIC at the antenna end doing the
sample-synchronous arithmetic, CPUs and GPUs downstream where data rates
have collapsed and latency has stopped mattering.

The deciding property is not speed but *determinism*, and you have now held
its paperwork in your hands: `icetime` PASS at 12 MHz is a worst-case
guarantee — every path, every cycle, over temperature and voltage, no
scheduler, no interrupts, no cache. The CPU-world equivalent (worst-case
execution time analysis) is so hard that hard-real-time engineers routinely
pad estimates by an order of magnitude. When lesson10 builds the frequency
counter, its measurement dwell will be exact to the clock cycle for the
same reason — and when a radar signal processor promises a Doppler filter
output every CPI, this is the machinery keeping the promise.

The price of determinism is also on your screen: place-and-route took
longer than every GHDL run so far combined, for 65 LCs — big designs take
hours per iteration. And the fabric is a fixed budget: 1280 LCs is 1280
LCs, budgeted like mass and power on an airframe. That's why the
utilisation block is in every build log, and why lesson14 tracks it.

## Build

Create `course/work/lesson05/`. Six files this time: two you already have
(`nco.vhd` and `nco_tb.vhd` are byte-identical to lesson04's — copy them
in), one new design file, two PCFs, and a Makefile that grows synthesis
targets. The NCO first, unchanged — the point of module reuse is that a
verified file travels whole:

**File: course/work/lesson05/nco.vhd**

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

**File: course/work/lesson05/nco_tb.vhd**

```vhdl
-- nco_tb.vhd — self-checking testbench for the NCO.
--
-- Verification approach (DO-254 flavor): every assert is tagged with the
-- requirement it verifies (R1..R3 from rtl/nco.vhd). The frequency check is
-- a *property*, not a golden trace: for any fcw, the number of output rising
-- edges observed over K clocks must satisfy |edges - K*fcw/2**W| <= 1,
-- which follows from the accumulator being exact (error is pure phase
-- truncation, bounded by one wrap). Run with a small W so corner cases are
-- reachable in simulation.
--
-- Sampling note: the TB samples sq_out immediately after rising_edge(clk),
-- i.e. one delta before the DUT's new value propagates — the observed edge
-- sequence is shifted one clock, which the +/-1 tolerance absorbs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco_tb is
end entity nco_tb;

architecture sim of nco_tb is
  constant W       : positive := 16;
  constant CLK_PER : time     := 83.333 ns;  -- 12 MHz

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal fcw   : unsigned(W - 1 downto 0) := (others => '0');
  signal phase : unsigned(W - 1 downto 0);
  signal sq    : std_logic;
  signal done  : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.nco
    generic map (W => W)
    port map (
      clk    => clk,
      rst    => rst,
      en     => en,
      fcw    => fcw,
      phase  => phase,
      sq_out => sq
    );

  main : process
    -- R1: count output rising edges over n_clks clocks and compare against
    -- the exact expected count n_clks * fcw / 2**W.
    procedure check_freq(fcw_val : natural; n_clks : positive) is
      variable edges    : natural := 0;
      variable expected : real;
      variable last     : std_logic;
    begin
      rst <= '1'; en <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      fcw <= to_unsigned(fcw_val, W);
      en  <= '1';
      wait until rising_edge(clk);
      last := sq;
      for i in 1 to n_clks loop
        wait until rising_edge(clk);
        if sq = '1' and last = '0' then
          edges := edges + 1;
        end if;
        last := sq;
      end loop;
      expected := real(n_clks) * real(fcw_val) / 2.0 ** W;
      assert abs(real(edges) - expected) <= 1.0
        report "R1 FAIL: fcw=" & integer'image(fcw_val) &
               " edges=" & integer'image(edges) &
               " expected=" & real'image(expected)
        severity error;
      report "R1 pass: fcw=" & integer'image(fcw_val) &
             " edges=" & integer'image(edges) &
             " expected~=" & real'image(expected);
    end procedure;

    variable phase_hold : unsigned(W - 1 downto 0);
  begin
    -- R2: synchronous reset clears the phase.
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;  -- let post-edge value settle
    assert phase = 0
      report "R2 FAIL: phase not cleared by synchronous reset"
      severity error;
    report "R2 pass: reset clears phase";

    -- R1 across the operating range, including corners:
    check_freq(700,          20000);       -- arbitrary non-power-of-two
    check_freq(1024,         20000);       -- exact divisor: period = 64 clocks
    check_freq(2 ** (W - 1), 64);          -- Nyquist corner: toggles every clock
    check_freq(1,            3 * 2 ** W);  -- slowest: 3 full wraps -> 3 edges

    -- R3: en='0' freezes the phase.
    en <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    phase_hold := phase;
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    assert phase = phase_hold
      report "R3 FAIL: phase advanced while en='0'"
      severity error;
    report "R3 pass: clock-enable holds phase";

    report "NCO testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

The new top level. Read the header's FCW derivation, then find the three
pieces in the body: the POR counter with its stick-at-15 enable, the
heartbeat divider, and the NCO instance with `fcw` tied to a constant and
`en` tied high.

**File: course/work/lesson05/top.vhd**

```vhdl
-- top.vhd — Phase 1 board top: 440 Hz square wave on a header pin, plus a
-- heartbeat LED proving the bitstream is alive.
--
-- FCW derivation for A440 from a 12 MHz clock, W = 32:
--   fcw = round(440 * 2**32 / 12e6) = 157482  ->  f_out = 439.9996 Hz
--
-- Boards have no reset button, so a small power-on-reset counter holds the
-- NCO in reset for the first 15 clocks after configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port (
    clk12     : in  std_logic;  -- 12 MHz board oscillator
    audio_out : out std_logic;  -- square wave: series 1k resistor -> piezo -> GND
    led_hb    : out std_logic   -- heartbeat, ~0.7 Hz
  );
end entity top;

architecture rtl of top is
  constant FCW_A440 : unsigned(31 downto 0) := to_unsigned(157482, 32);

  signal por_cnt : unsigned(3 downto 0)  := (others => '0');
  signal rst     : std_logic;
  signal hb_cnt  : unsigned(23 downto 0) := (others => '0');
  signal phase   : unsigned(31 downto 0);
begin

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

  u_nco : entity work.nco
    generic map (W => 32)
    port map (
      clk    => clk12,
      rst    => rst,
      en     => '1',
      fcw    => FCW_A440,
      phase  => phase,
      sq_out => audio_out
    );

end architecture rtl;
```

The constraints, one file per board. Pin 21/99/78 for the iCEstick come
from its schematic; note the standing order in the HX8K file.

**File: course/work/lesson05/icestick.pcf**

```
# Lattice iCEstick (iCE40-HX1K, TQ144)
set_io clk12     21   # 12 MHz FTDI-derived oscillator
set_io led_hb    99   # D1 (red)
set_io audio_out 78   # PMOD J2 pin 1 — series 1k -> piezo -> GND
```

**File: course/work/lesson05/hx8k.pcf**

```
# Lattice iCE40-HX8K-B-EVN breakout (iCE40-HX8K, CT256)
set_io clk12  J3   # 12 MHz oscillator
set_io led_hb B5   # D2 (LED bank: B5 B4 A2 A1 C5 C4 B3 C3)
# audio_out: pick any pin on the J2 header and VERIFY the ball name against
# the HX8K-B-EVN schematic silk before building — then delete this comment.
set_io audio_out B1
```

The Makefile is lesson03's sim pattern plus the four synthesis rules from
the Concepts diagram, written as real `make` dependencies: `bit` needs
`.bin`, which needs `.asc`, which needs `.json` and the PCF, which needs
the RTL. Change one VHDL file and `make bit` reruns exactly the stages
downstream of it. The `BOARD` variable selects device/package/PCF as a
triple, and an unknown board is a loud error, not a default.

**File: course/work/lesson05/Makefile**

```makefile
# Lesson 05 — RTL to bitstream. GHDL + Yosys + nextpnr + icestorm flow.
#
#   make sim          run the self-checking NCO testbench (do this FIRST)
#   make wave         sim + open the waveform in GTKWave
#   make synth        VHDL -> netlist (yosys via ghdl-yosys-plugin)
#   make bit          netlist -> place/route -> bitstream
#   make time         static timing estimate (icetime)
#   make prog         flash the board (iceprog) — lesson99 only
#   make clean
#
#   make BOARD=hx8k bit    for the iCE40-HX8K-B-EVN (default: icestick)

BOARD ?= icestick
TOP    = top
TB     = nco_tb

RTL    = nco.vhd top.vhd
TB_SRC = nco_tb.vhd

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
# needs the __isoc23_* forwarding shim (harmless if glibc is new enough).
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave synth bit time prog clean

# ---------- simulation (GHDL) ----------

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure

# Opens the waveform even when the sim fails an assert — that's when you
# most need it. The '-' keeps make going past sim's nonzero exit.
wave:
	-$(MAKE) sim
	gtkwave build/$(TB).ghw &

# ---------- synthesis -> bitstream ----------

synth: build/$(TOP).json
bit:   build/$(TOP).bin

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@'

build/$(TOP).asc: build/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

build/$(TOP).bin: build/$(TOP).asc
	icepack $< $@

time: build/$(TOP).asc
	icetime -d $(DEVICE) -p $(PCF) -t $<

prog: build/$(TOP).bin
	iceprog $<

build:
	mkdir -p build

clean:
	rm -rf build
```

## Run

From `course/work/lesson05/` (with the `fpga` alias already sourced in this
shell). Simulation first — always. Nothing gets synthesized in this course
before its testbench is green:

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build nco.vhd top.vhd nco_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/nco_tb nco_tb
./build/nco_tb --wave=build/nco_tb.ghw --assert-level=failure
nco_tb.vhd:92:5:@125999500fs:(report note): R2 pass: reset clears phase
nco_tb.vhd:77:7:@1667034998500fs:(report note): R1 pass: fcw=700 edges=214 expected~=2.13623046875e2
nco_tb.vhd:77:7:@3333944997500fs:(report note): R1 pass: fcw=1024 edges=313 expected~=3.125e2
nco_tb.vhd:77:7:@3339528308500fs:(report note): R1 pass: fcw=32768 edges=32 expected~=3.2e1
nco_tb.vhd:77:7:@19723712771500fs:(report note): R1 pass: fcw=1 edges=3 expected~=3.0
nco_tb.vhd:112:5:@19724630434500fs:(report note): R3 pass: clock-enable holds phase
nco_tb.vhd:114:5:@19724630434500fs:(report note): NCO testbench complete (any FAILs are listed above)
```

(Same conventions as before: `mkdir -p build` appears only on the first
run, and your home directory replaces `/home/clementsj` in the shim path.
This is lesson04's exact output — same NCO, same TB.)

Now synthesis. Yosys prints a few hundred lines; the excerpt below is the
part you must learn to find and read — the statistics:

```bash
make synth
```

Expected output:

```text
yosys -m ghdl -p 'ghdl --std=08 --workdir=build nco.vhd top.vhd -e top; synth_ice40 -top top -json build/top.json'
[...]
2.50. Printing statistics.

=== top ===

        +----------Local Count, excluding submodules.
        | 
      125 wires
      244 wire bits
      125 public wires
      244 public wire bits
        3 ports
        3 port bits
        1 cells
        1   $scopeinfo
      172 submodules
       53   SB_CARRY
       24   SB_DFF
        4   SB_DFFE
       31   SB_DFFSR
       60   SB_LUT4
[...]
```

Before scrolling on, do the flip-flop accounting from Concepts against your
own log: 24 + 4 + 31, and say where each group lives in the source and why
`acc` contributed 31, not 32.

Place, route, pack:

```bash
make bit
```

Expected output:

```text
nextpnr-ice40 --hx1k --package tq144 --pcf icestick.pcf \
              --json build/top.json --asc build/top.asc --freq 12
Info: constrained 'clk12' to bel 'X0/Y8/io1'
Info: constrained 'led_hb' to bel 'X13/Y12/io1'
Info: constrained 'audio_out' to bel 'X13/Y3/io1'
[...]
Info: Device utilisation:
Info: 	         ICESTORM_LC:      65/   1280     5%
Info: 	        ICESTORM_RAM:       0/     16     0%
Info: 	               SB_IO:       3/     96     3%
Info: 	               SB_GB:       1/      8    12%
Info: 	        ICESTORM_PLL:       0/      1     0%
Info: 	         SB_WARMBOOT:       0/      1     0%
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 159.72 MHz (PASS at 12.00 MHz)
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 160.69 MHz (PASS at 12.00 MHz)
[...]
Info: Program finished normally.
icepack build/top.asc build/top.bin
```

(The first `Max frequency` line is the post-placement estimate, the second
is post-routing truth; exact MHz values wobble slightly across nextpnr
versions but both must say `PASS at 12.00 MHz`. The 65 LCs are yosys's
LUTs, flops, and carries packed together into whole logic cells.)
`build/top.bin` now exists: 32,220 bytes of would-be A440. It stays on disk
until lesson99 — `make prog` is in the Makefile, but there's no board on
this machine to program.

The independent timing verdict:

```bash
make time
```

Expected output:

```text
icetime -d hx1k -p icestick.pcf -t build/top.asc
// Reading input .pcf file..
// Reading input .asc file..
// Reading 1k chipdb file..
// Creating timing netlist..

icetime topological timing analysis report
==========================================

Report for critical path:
-------------------------

        lc40_11_1_5 (LogicCell40) [clk] -> lcout: 0.640 ns
     0.640 ns net_20775 (u_nco.acc[1])
        t57 (LocalMux) I -> O: 0.330 ns
        inmux_12_1_24698_24720 (InMux) I -> O: 0.260 ns
        t26 (CascadeMux) I -> O: 0.000 ns
        lc40_12_1_0 (LogicCell40) in2 -> carryout: 0.231 ns
     1.461 ns t10
        lc40_12_1_1 (LogicCell40) carryin -> carryout: 0.126 ns
     1.587 ns net_24723 (u_nco.acc_SB_DFFSR_Q_27_D_SB_LUT4_O_I3)
        lc40_12_1_2 (LogicCell40) carryin -> carryout: 0.126 ns
     1.713 ns net_24729 (u_nco.acc_SB_DFFSR_Q_26_D_SB_LUT4_O_I3)
[...]
        lc40_12_4_5 (LogicCell40) carryin -> carryout: 0.126 ns
     5.711 ns net_25224 (audio_out_SB_LUT4_I2_I3)
        inmux_12_4_25224_25234 (InMux) I -> O: 0.260 ns
     5.970 ns net_25234 (audio_out_SB_LUT4_I2_I3)
        lc40_12_4_6 (LogicCell40) in3 [setup]: 0.217 ns
     6.188 ns net_22958 (audio_out$SB_IO_OUT)
[...]
Total number of logic levels: 31
Total path delay: 6.19 ns (161.61 MHz)
```

Read the path like a story: launch from the flop holding `u_nco.acc[1]`
(0.640 ns clock-to-out), enter the carry chain, then a metronomic
`carryin -> carryout: 0.126 ns` per accumulator bit — count the `[...]`-
elided middle and you'll find the ~30 live bits — arriving at a setup check
at `audio_out`. 6.19 ns against an 83.3 ns budget. Note icetime says
161.61 MHz where nextpnr said 160.69: two independent models, one question.
Trust the lower; require both to pass.

Same design, bigger chip:

```bash
make clean
make BOARD=hx8k bit
```

Expected output:

```text
mkdir -p build
yosys -m ghdl -p 'ghdl --std=08 --workdir=build nco.vhd top.vhd -e top; synth_ice40 -top top -json build/top.json'
[...]
nextpnr-ice40 --hx8k --package ct256 --pcf hx8k.pcf \
              --json build/top.json --asc build/top.asc --freq 12
Info: constrained 'clk12' to bel 'X0/Y16/io1'
Info: constrained 'led_hb' to bel 'X7/Y33/io1'
Info: constrained 'audio_out' to bel 'X0/Y30/io0'
[...]
Info: Device utilisation:
Info: 	         ICESTORM_LC:      65/   7680     0%
Info: 	        ICESTORM_RAM:       0/     32     0%
Info: 	               SB_IO:       3/    206     1%
Info: 	               SB_GB:       1/      8    12%
Info: 	        ICESTORM_PLL:       0/      2     0%
Info: 	         SB_WARMBOOT:       0/      1     0%
[...]
Info: Program finished normally.
icepack build/top.asc build/top.bin
```

Same 65 LCs, now 0% of a 7680-LC fabric — the netlist didn't change, only
the floor plan under it. Compare `wc -c build/top.bin` between the two
builds (~32 KB vs ~135 KB): a bitstream's size tracks the *device*, not the
design, because it configures every cell on the die including the idle
ones.

## Explore

Attempt these before opening `course/solutions/lesson05/`.

1. **Break it on purpose — lose a pin.** Comment out the `audio_out` line
   in `icestick.pcf` (prefix it with `#`) and run `make clean && make bit`.
   nextpnr stops with:
   `ERROR: IO 'audio_out' is unconstrained in PCF (override this error with --pcf-allow-unconstrained)`.
   Think about why *error* is the right default when a tool could trivially
   pick a pin for you — then think about what that pin might be wired to on
   a board nextpnr has never heard of. Restore the line, rebuild to green.

2. **The synthesizer reads your constants.** Predict, then measure, the
   `SB_DFFSR` count for two variants of `FCW_A440`: (a) 157483 — one off,
   audibly identical, but odd; (b) 314964 — exactly double, A880, one
   octave up (lesson04's frequency equation is linear in fcw). Hint: write
   both numbers in binary and count trailing zeros. Run
   `make clean && make synth` for each and check the stat block. You should
   find 32 flops for (a) and 30 for (b), against the shipped 31 — constant
   propagation trimming exactly the accumulator bits that can never change.
   Restore 157482 afterward.

3. **Spend the timing margin.** In the Makefile, change `--freq 12` to
   `--freq 150` and `make clean && make bit`: nextpnr works harder but
   passes — the carry chain fits under 6.67 ns. Now try `--freq 170`:
   place-and-route ends with
   `ERROR: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': ... (FAIL at 170.00 MHz)`
   and refuses to emit an `.asc`. A missed timing contract is a build
   *failure*, not a warning — the toolchain enforcing the course rule for
   you. Restore `--freq 12`.

4. **Open the artifacts.** `less build/top.json` and find `"top"` and the
   cells section — locate an `SB_DFFSR` and read its connections. Then
   `head -25 build/top.asc`. You are looking at the actual configuration
   memory of the chip, as text, produced by a fully documented open flow —
   ten years ago this file format was a trade secret. This inspectability
   is what "no black boxes" buys you at the hardware level.

## Tips & Pitfalls

- **Switching boards? `make clean` first.** The build artifacts don't
  encode `BOARD` in their names, so after an iCEstick build,
  `make BOARD=hx8k bit` says `make: Nothing to be done for 'bit'` — the
  `.bin` looks up to date and you'd flash an HX1K bitstream at an HX8K.
  Clean when changing boards. (You'll meet this exact trap on lab day;
  meet it here first.)
- **Emacs: drive the whole flow from `M-x compile`.** Run `M-x compile`
  once with `make bit`; from then on `<f6>` reruns it. GHDL's messages keep
  their `file:line:col:` format even when GHDL runs *inside* yosys, so
  `M-g n` still jumps you to the offending VHDL line when synthesis fails.
- **Yosys dying at the GHDL step** (an error naming a missing entity or
  unit) usually means analysis order or a stale `build/`: the plugin's
  `ghdl` command analyzes `$(RTL)` left to right into `build/`, so
  `nco.vhd` must precede `top.vhd` in the Makefile's `RTL` list — same
  rule as lesson03's `SRC`. When in doubt, `make clean`: the `.cf` library
  file in `build/` is shared between simulation and synthesis and can hold
  stale units.
- **Two fmax numbers is normal; three graders is the point.** nextpnr's
  post-place estimate, nextpnr's post-route number, and icetime's
  independent model will all differ by a few MHz. Only rule: every one of
  them says PASS at your clock. Trust the lowest.
- **The stat report prints twice** (once "Local Count", once "design
  hierarchy" totals). For our single flattened top they're identical;
  from lesson07 onward, read the hierarchy section.
- **Don't run `make prog` today.** It's wired up and it will happily wait
  forever for an iCEstick that isn't there. Flashing — and the udev/usbipd
  plumbing it needs — is lesson99's material.

## Checkpoint

Before lesson06, you must have:

- `make sim` in `course/work/lesson05/` printing the lesson04 outputs
  unchanged: `R2 pass`, four `R1 pass` lines, `R3 pass`, zero FAILs.
- `make bit` completing with `Info: Program finished normally.`, a
  utilisation block showing 65/1280 LCs, and both nextpnr `Max frequency`
  lines reading `PASS at 12.00 MHz`; `build/top.bin` on disk (~32 KB).
- `make time` reporting the critical path at ~6.2 ns / 31 logic levels —
  and you can say in one sentence which piece of VHDL that path is.
- `make clean && make BOARD=hx8k bit` also finishing green (65/7680 LCs).
- The flip-flop accounting done from memory: 24 + 4 + 31, which register
  each group is, why the flavors differ, and why `acc` is one short.
- Explore 1 attempted: you've seen the unconstrained-IO error and can
  explain why it's an error and not a convenience.
