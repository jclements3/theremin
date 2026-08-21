# Lesson 03 — numeric_std and Fixed-Point Thinking

*Where we are.* You can structure a design (lesson01) and prove it works with
a self-checking, requirement-tagged testbench (lesson02). But so far the data
flowing through your designs has been bags of bits. This lesson gives those
bits arithmetic meaning: `unsigned` and `signed` from `ieee.numeric_std`,
what happens at the edges of a fixed word (wrap or saturate — you must
choose, the hardware won't choose well for you), and how to compute design
constants with real-number math that costs zero gates. The vehicle is a
saturating adder — small enough to see every bit, and the exact behavior the
theremin's audio path will need when two signals sum past full scale. Next
lesson, the NCO makes the opposite choice — deliberate wraparound — and
you'll know exactly why both are right.

## Objectives

- Explain what `unsigned`/`signed` are (vectors with a declared numeric
  interpretation) and why `std_logic_vector` has no `+`.
- Use `resize()` to grow operands before adding so the carry bit survives,
  and predict its behavior for both unsigned and signed values.
- State precisely what a W-bit add does on overflow (wraps mod 2**W) and
  implement saturation on top of it, with a flag that reports clipping.
- Say why `std_logic_arith` is banned in this repo and what to do when you
  meet it in legacy code.
- Compute a hardware constant at elaboration time with `math_real` and
  explain why that's free in silicon.

## Concepts

### Bits don't have a value until you say so

A `std_logic_vector(7 downto 0)` holding `"11111111"` is not 255. It is not
-1. It is eight wires. The number it represents depends on an interpretation
you haven't given yet — and VHDL, unlike C, refuses to guess. There is no
`+` defined for `std_logic_vector` in the standard libraries, on purpose.

`ieee.numeric_std` defines two array types that are physically identical to
`std_logic_vector` — same wires, same simulation values — but carry the
interpretation in the type:

- `unsigned(7 downto 0)`: pure binary, `"11111111"` = 255.
- `signed(7 downto 0)`: two's complement, `"11111111"` = -1.

Declaring a port as `unsigned` is documentation the compiler enforces. You
saw this in lesson02's counter; from here on every arithmetic signal in the
course is `unsigned` or `signed`, and conversions to/from `std_logic_vector`
happen only at boundaries that genuinely are just bits (a UART byte, a LED
bus).

The conversion functions you'll use constantly:

```
to_unsigned(30, 8)      -- integer -> unsigned(7 downto 0)
to_signed(-3, 8)        -- integer -> signed(7 downto 0)
to_integer(u)           -- unsigned or signed -> integer
unsigned(slv), std_logic_vector(u)   -- free type casts, zero hardware
```

The casts on the last line are legal because the types have the same shape —
they rename the wires, nothing more.

### What a fixed-width add actually builds

In software, `a + b` on 64-bit integers overflows so rarely you forget it
can. In hardware you pick the word width, so overflow is a design decision
you make on every adder. The rule for `numeric_std`:

> `unsigned(W-1 downto 0) + unsigned(W-1 downto 0)` yields
> `unsigned(W-1 downto 0)`. The result width equals the wider operand.
> The carry out of the top bit **does not exist**. Arithmetic is mod 2**W.

So with W = 8: `200 + 56 = 0`, `255 + 255 = 254`. No error, no warning, at
simulation or synthesis. The adder is a ring:

```
        255   0   1
      254  \  |  /  2
         \  \ | /  /
    ...    (mod 256)     200 + 56 walks 56 steps
         /  / | \  \     clockwise from 200 and
      130  /  |  \ 126   lands back on 0.
        129  128  127
```

Sometimes the ring is exactly what you want. The NCO's phase accumulator
(lesson04) *is* this ring: phase is inherently modular — 360° = 0° — so
wrapping is the correct physics and costs nothing. That's why `nco.vhd`'s
accumulate line is a bare `acc <= acc + fcw` with a comment celebrating the
wrap.

Audio is not modular. If two half-scale sine waves sum past full scale and
wrap, the top of the waveform teleports to the bottom: a rail-to-rail
discontinuity every cycle, which your ear receives as a harsh buzz far worse
than clipping. Analog gear clips — the peak flattens, distortion appears
gradually. Digital audio must be *made* to clip, and that's called
**saturation**: if the true sum exceeds full scale, hold full scale.

Wrap vs saturate, when each is right:

| situation | correct behavior | why |
|---|---|---|
| phase, angles, ring buffer indices | wrap | the quantity is modular |
| audio samples, gains, control signals | saturate | off-scale should clip, not teleport |
| counters you compare against a limit | either, if the limit is checked first | overflow never reached |

### Saturation from first principles: keep the carry

The W-bit add threw the carry away, and the carry is exactly the information
"did this overflow?". So don't do a W-bit add. Do a (W+1)-bit add:

```
resize(a, W+1) + resize(b, W+1)
```

Two W-bit numbers sum to at most 2**W - 1 + 2**W - 1 = 2**(W+1) - 2, which
always fits in W+1 bits — the wide add is *exact*. Now bit W of the result
is the old carry, reborn as an ordinary signal you can inspect:

```
   a = 200 :   1 1 0 0 1 0 0 0
   b =  56 :   0 0 1 1 1 0 0 0
             -------------------
 wide = 256: 1 0 0 0 0 0 0 0 0     <- 9 bits, exact
             ^
             wide(8) = '1' : the sum did not fit in 8 bits
```

The saturating adder is then a one-line multiplexer: if `wide(W)` is set,
output all-ones (2**W - 1); otherwise output the low W bits. And `wide(W)`
itself is a useful output — a `sat` flag telling downstream logic (or a
telemetry UART, lesson11) that clipping happened. In hardware terms you've
built a W+1-bit adder plus a W-wide 2:1 mux: about one extra LUT per bit
over the plain adder. Saturation is cheap. Debugging a wrap that only
happens when the input peaks is not.

### resize(), precisely

`resize(x, N)` is the standard way to change a word's width, and its
behavior is type-aware — this is where `unsigned` vs `signed` earns its
keep:

- **unsigned, growing**: zero-extend on the left. `resize("1100", 6)` =
  `"001100"`. Value preserved.
- **signed, growing**: *sign*-extend on the left. `resize("1100", 6)` =
  `"111100"` (-4 stays -4). Same wires in, different bits out, because the
  type declared what the top bit means.
- **shrinking**: high bits are dropped (unsigned), or the sign bit is kept
  and high magnitude bits dropped (signed). Either way, shrinking can change
  the value silently — shrink only when you've established the value fits,
  or follow it with a saturation check like the one you're building.

Idiom to internalize: **resize before you add, then decide what to do with
the top bit.** Grow to the exact width that makes the operation lossless
(one extra bit per add; N+M bits for an N×M multiply), do the math exactly,
then wrap, saturate, or round *once*, deliberately, at the output.

### Why std_logic_arith is banned

You will meet `use ieee.std_logic_arith.all` in legacy code and old
tutorials. It is not an IEEE standard — it's a Synopsys package that squatted
in the `ieee` namespace — and it comes with two companion packages,
`std_logic_unsigned` and `std_logic_signed`, that define arithmetic directly
on `std_logic_vector`. Which companion you import decides whether
`"11111111" + 1` means 255+1 or -1+1 — the *interpretation lives in the
import list*, not in the type. Import both (it happens, via nested use
clauses) and you get ambiguous-operator errors; mix files that chose
differently and you get a design that simulates one way and reads another.
Vendors ship it for backward compatibility only. `numeric_std` puts the
interpretation in the type, where the compiler can check it at every
assignment. House rule, no exceptions: `numeric_std` only.

### Constants and elaboration-time math

Question you'll face next lesson: what frequency control word makes a 32-bit
NCO clocked at 12 MHz produce concert A? The answer is
round(440.0 / 12e6 × 2**32) = 157,482. You could compute that on a
calculator and paste in a magic number — or you can make the *tools* do it:

```vhdl
use ieee.math_real.all;

constant CLK_HZ : real := 12.0e6;
constant FCW_A4 : natural := natural(round(440.0 / CLK_HZ * 2.0**32));
```

`math_real` gives you `round`, `floor`, `log2`, `sin`, `**` on reals — none
of which is synthesizable as *hardware*. But a `constant` is evaluated at
**elaboration time**, when the design is being built, before any gate
exists. The synthesizer runs the math once on your workstation, and only the
resulting integer reaches silicon. Zero gates, and the source now documents
*where the number came from* — change `CLK_HZ` and every derived constant
follows.

The rule that keeps you safe: `math_real` in constants, generics, and
functions called only from constant declarations — never in a process or a
signal assignment that must become logic. Lesson07's sine LUT pushes this to
its limit: an elaboration-time function calls `sin()` 256 times to fill a
ROM. This lesson's testbench uses the humbler integer form of the same idea:
`2 ** W - 1` as a named constant, computed by the compiler, not by you.

## Radar Connection

**Word growth through a signal chain.** Every DSP block in a radar grows its
data, and somebody has to budget the bits — usually you.

- An N-bit + N-bit add needs N+1 bits to be exact.
- An N-bit × M-bit multiply needs N+M bits.
- Summing K samples (a coherent integrator) grows log2(K) bits.

Chain them and it compounds. Take a plausible radar front end: a 12-bit ADC,
a complex mixer (multiply by a 16-bit local oscillator: 12+16 = 28 bits),
then coherent integration over 1024 pulses (+10 bits): you're at 38 bits —
and the classic decimating filter that follows, the **CIC (cascaded
integrator-comb)**, is famous precisely for this problem. A CIC of order N
decimating by R grows N·log2(R) bits internally: a modest 4th-order,
decimate-by-256 CIC adds 32 bits on top of its input width. Its integrator
stages *rely on modular wraparound being exact* (the comb subtractions
cancel the wraps — the NCO's ring, exploited on purpose), and its output
stage *truncates or rounds deliberately* back down to the bus width. Wrap
where the math is modular, size exactly where it must be lossless, clip or
round once at the boundary you choose: the entire discipline of this lesson,
industrialized.

Where does saturation show up in radar? At the seams you don't fully
control: AGC settling, a strong jammer or clutter spike hitting a fixed-point
IF chain, the final resize onto a 16-bit output bus. A wrapped spike looks
like a *different, valid* signal — it aliases into your data and can paint
phantom targets. A saturated spike is visibly clipped, flagged (your `sat`
output is exactly this flag; real receivers count these events and report
them in telemetry), and recoverable. Radar engineers carry a "bit-growth
budget" spreadsheet for the whole chain the way structural engineers carry
load tables. You'll do the miniature version in lesson10, when the frequency
counter's width sets how fine a hand movement you can resolve.

## Build

Create `course/work/lesson03/` and enter the two design files and the
Makefile below. The module first — read the header comment: it declares the
requirements R1–R3, and the testbench checks them by tag, same discipline as
lesson02.

Two things to notice while you type. First, `wide` has range `W downto 0` —
that's W+1 bits, the guard bit at index W. Second, the output is a
conditional signal assignment (a mux, not a process): this module is purely
combinational, which is requirement R3 and the reason the testbench needs no
clock.

**File: course/work/lesson03/sat_add.vhd**

```vhdl
-- sat_add.vhd — W-bit unsigned adder that saturates instead of wrapping.
--
-- Requirements this module implements (verified in sat_add_tb.vhd):
--   R1: when a + b fits in W bits, sum = a + b and sat = '0'.
--   R2: when a + b overflows W bits, sum clamps to 2**W - 1 (all ones)
--       and sat = '1'.
--   R3: purely combinational — sum and sat follow a and b with no clock.
--
-- Teaching point: resize() both operands to W+1 bits *before* adding, so
-- the carry survives; that carry bit, wide(W), is exactly the saturation
-- flag. A plain W-bit numeric_std add would wrap silently mod 2**W —
-- the testbench demonstrates both behaviors side by side.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sat_add is
  generic (
    W : positive := 8  -- operand width
  );
  port (
    a   : in  unsigned(W - 1 downto 0);
    b   : in  unsigned(W - 1 downto 0);
    sum : out unsigned(W - 1 downto 0);
    sat : out std_logic  -- '1' when the true sum did not fit
  );
end entity sat_add;

architecture rtl of sat_add is
  -- one guard bit: W+1 bits hold any sum of two W-bit numbers exactly
  signal wide : unsigned(W downto 0);
begin

  wide <= resize(a, W + 1) + resize(b, W + 1);

  sum <= (others => '1') when wide(W) = '1' else wide(W - 1 downto 0);  -- R2 / R1
  sat <= wide(W);

end architecture rtl;
```

The testbench introduces one new tool: a **procedure** declared inside the
stimulus process. `check(av, bv)` drives one input pair, waits 1 ns for the
combinational logic to settle, and compares against expectations computed in
plain integer math — `av + bv` as unbounded integers, clamped against
`MAXV`. The expected values never touch the DUT's formula; if `sat_add` and
the integer model disagree, somebody's wrong and the assert says so. Note
also the `wrapped` variable: on every saturating case the log prints what a
plain 8-bit add *would* have produced, so wrap and saturate sit side by side
in the output.

**File: course/work/lesson03/sat_add_tb.vhd**

```vhdl
-- sat_add_tb.vhd — self-checking testbench for sat_add (W = 8).
--
-- Verifies (tags match the header of sat_add.vhd):
--   R1: in-range sums pass through untouched with sat = '0', including the
--       fencepost case that lands exactly on 255.
--   R2: overflowing sums clamp to 255 with sat = '1'; each report line
--       also shows what a plain wrapping W-bit add would have produced,
--       so wrap vs saturate sit side by side in the log.
--   R3: there is no clock anywhere in this testbench — outputs settle
--       within the 1 ns wait after every input change, proving the DUT
--       is combinational.
--
-- The expected values are computed independently in plain integer math
-- (av + bv against 2**W - 1), never by re-running the DUT's own formula.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sat_add_tb is
end entity sat_add_tb;

architecture sim of sat_add_tb is
  constant W : positive := 8;

  signal a   : unsigned(W - 1 downto 0) := (others => '0');
  signal b   : unsigned(W - 1 downto 0) := (others => '0');
  signal sum : unsigned(W - 1 downto 0);
  signal sat : std_logic;
begin

  dut : entity work.sat_add
    generic map (W => W)
    port map (
      a   => a,
      b   => b,
      sum => sum,
      sat => sat
    );

  main : process
    constant MAXV : natural := 2 ** W - 1;

    -- Drive one (a, b) pair, wait for the combinational settle, check
    -- sum and sat against integer-math expectations, and report the
    -- wrapped alternative whenever saturation fired.
    procedure check(av, bv : natural) is
      variable exp_sum : natural;
      variable exp_sat : std_logic;
      variable wrapped : natural;
    begin
      a <= to_unsigned(av, W);
      b <= to_unsigned(bv, W);
      wait for 1 ns;  -- R3: no clock — this settle is all it takes
      wrapped := (av + bv) mod 2 ** W;
      if av + bv > MAXV then
        exp_sum := MAXV;
        exp_sat := '1';
      else
        exp_sum := av + bv;
        exp_sat := '0';
      end if;
      assert to_integer(sum) = exp_sum and sat = exp_sat
        report "R1/R2 FAIL: " & integer'image(av) & "+" & integer'image(bv) &
               " gave sum=" & integer'image(to_integer(sum)) &
               " sat=" & std_logic'image(sat) &
               ", expected sum=" & integer'image(exp_sum) &
               " sat=" & std_logic'image(exp_sat)
        severity error;
      if exp_sat = '1' then
        report "R2 pass: " & integer'image(av) & "+" & integer'image(bv) &
               " -> sum=" & integer'image(to_integer(sum)) & " sat=1" &
               " (a plain 8-bit add would wrap to " &
               integer'image(wrapped) & ")";
      else
        report "R1 pass: " & integer'image(av) & "+" & integer'image(bv) &
               " -> sum=" & integer'image(to_integer(sum)) & " sat=0";
      end if;
    end procedure;
  begin
    -- R1: ordinary in-range sums.
    check(10, 20);    -- nothing special: 30
    check(0, 0);      -- both zero
    check(255, 0);    -- one operand already at max, still no overflow

    -- R1 fencepost: lands exactly on 255 — sat must stay '0'.
    check(200, 55);

    -- R2: one past the fencepost, then the classic MSB and worst cases.
    check(200, 56);   -- 256: wrap would give 0
    check(128, 128);  -- MSB + MSB: wrap would give 0
    check(255, 255);  -- worst case: wrap would give 254

    report "R3 pass: all checks settled with no clock (combinational DUT)";
    report "sat_add testbench complete: R1-R3 checked (any FAILs are listed above)";
    wait;
  end process;

end architecture sim;
```

Look at the chosen test vectors before running: 200+55 and 200+56 straddle
the fencepost at 255 — the single most likely off-by-one in any saturation
implementation (a `>=` where `>` belongs, or clamping at 254). 128+128 is
the MSB-meets-MSB case, and 255+255 is the worst case, whose wrap (254, not
0) surprises most people the first time.

The Makefile is the lesson02 pattern with two source files — analysis order
matters: `sat_add.vhd` before `sat_add_tb.vhd`, because the testbench
instantiates `entity work.sat_add` and GHDL must have analyzed it first.

**File: course/work/lesson03/Makefile**

```makefile
# Lesson 03 solution — GHDL sim flow. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors tutorial/Makefile — same
# flags, same shim, no synthesis targets.

TB         = sat_add_tb
SRC        = sat_add.vhd sat_add_tb.vhd
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

## Run

From `course/work/lesson03/` (with the `fpga` alias already sourced in your
shell):

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build sat_add.vhd sat_add_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/sat_add_tb sat_add_tb
./build/sat_add_tb --assert-level=failure
sat_add_tb.vhd:76:9:@1ns:(report note): R1 pass: 10+20 -> sum=30 sat=0
sat_add_tb.vhd:76:9:@2ns:(report note): R1 pass: 0+0 -> sum=0 sat=0
sat_add_tb.vhd:76:9:@3ns:(report note): R1 pass: 255+0 -> sum=255 sat=0
sat_add_tb.vhd:76:9:@4ns:(report note): R1 pass: 200+55 -> sum=255 sat=0
sat_add_tb.vhd:71:9:@5ns:(report note): R2 pass: 200+56 -> sum=255 sat=1 (a plain 8-bit add would wrap to 0)
sat_add_tb.vhd:71:9:@6ns:(report note): R2 pass: 128+128 -> sum=255 sat=1 (a plain 8-bit add would wrap to 0)
sat_add_tb.vhd:71:9:@7ns:(report note): R2 pass: 255+255 -> sum=255 sat=1 (a plain 8-bit add would wrap to 254)
sat_add_tb.vhd:94:5:@7ns:(report note): R3 pass: all checks settled with no clock (combinational DUT)
sat_add_tb.vhd:95:5:@7ns:(report note): sat_add testbench complete: R1-R3 checked (any FAILs are listed above)
```

(The `mkdir -p build` line appears only on the first run; on later runs the
directory already exists and make skips it. Your home directory will appear
in the shim path instead of `/home/clementsj`.)

Read the timestamps: `@1ns`, `@2ns`, … — each `check` call advances
simulated time by exactly its one `wait for 1 ns`. No clock ever ticks. And
read the three R2 lines against their parenthesized wrap values: 256 wraps
to 0, 256 wraps to 0, 510 wraps to 254. That's the buzz your speaker is
being spared.

## Explore

Do these before peeking at `course/solutions/lesson03/`.

1. **Break it on purpose — build the wrapping adder.** In `sat_add.vhd`,
   replace the three lines of the architecture body with the naive version:
   `sum <= a + b;` and `sat <= '0';` (delete or ignore `wide`). Run
   `make sim`. You should get exactly three `R1/R2 FAIL` lines — the three
   R2 vectors — each reporting the wrapped value the log had predicted
   (`sum=0`, `sum=0`, `sum=254`). The four R1 cases still pass: wrap and
   saturate agree everywhere except past the fencepost, which is why
   overflow bugs hide so well. Restore the file and re-run to green.

2. **Move the fencepost.** Change the comparison logic by making `sum`
   clamp when `wide(W) = '1'` **or** `wide(W-1 downto 0) = 255` — a
   plausible-looking `>=`-style bug. Which single test vector catches it?
   (Predict first, then run: it's the one that lands exactly *on* 255.)

3. **Generic sweep.** Change `constant W : positive := 8` to `4` in the
   testbench only, and update the seven `check` calls to interesting 4-bit
   vectors (max value is now 15; keep a fencepost pair like 9+6 and 9+7).
   Nothing in `sat_add.vhd` changes — that's the point of the generic. Then
   try `W := 31` and watch the testbench itself die of integer overflow
   (see Tips below for why), which is its own lesson in word growth.

4. **Signed variant.** Copy `sat_add.vhd` to `sat_add_s.vhd`, entity
   `sat_add_s`, ports `signed(W-1 downto 0)`. Signed saturation is
   two-sided: clamp to +2**(W-1)-1 and -2**(W-1). Overflow detection
   changes too — the carry-bit trick doesn't transfer. Hint: after
   `resize`-ing to W+1 bits and adding (now sign-extension does the work),
   the sum overflows W bits exactly when the top two bits of `wide`
   differ. Write four checks: big+big, -big+-big, and one in-range case of
   each sign. This is the version the audio mixer in lesson14's chain
   would need if we summed voices.

## Tips & Pitfalls

- **GHDL: "no declaration of operator +".** The #1 beginner error in this
  chapter. It means you're adding types that have no `+` defined — usually
  `std_logic_vector`s, or an `unsigned` and an `integer` in a context GHDL
  can't resolve. Check your `use` clauses first (`ieee.numeric_std.all`
  present? `std_logic_arith` absent?), then your types. `M-g n` jumps you
  to the offending line.
- **Width mismatch errors are your friend.** `numeric_std` refuses
  `unsigned(8 downto 0) <= unsigned(7 downto 0) + ...` — the wide add in
  this lesson *requires* the explicit `resize` on both operands. Annoying
  for five minutes, then it catches your first real truncation bug and you
  stop complaining. (VHDL's strictness is the point: lesson01's delta-cycle
  rules told you *when* things happen; the type system tells you *what* the
  bits mean.)
- **Testbench math has word growth too.** `2 ** W - 1` with `W = 31`
  overflows VHDL's `integer` (guaranteed only up to 2**31 - 1), which is
  why Explore 3's last step dies at elaboration. Simulation-side integer
  math is 32-bit — when the counters in lesson10 get wide, the testbench
  will compare `unsigned` values directly instead of round-tripping through
  `to_integer`.
- **Emacs/vhdl-mode: stop indenting by hand.** After editing, `M-x
  vhdl-beautify-buffer` re-indents and re-aligns the whole file to the
  mode's settings (this repo's dir-locals set 2-space `vhdl-basic-offset`,
  matching house style). Select a region and `M-x vhdl-beautify-region` to
  fix just your paste. If your diffs against the solutions show only
  whitespace, this is the cure.
- **Toolchain gotcha: analysis order.** `ghdl -a` processes files left to
  right; a file must be analyzed after every design unit it references.
  Feed GHDL `sat_add_tb.vhd sat_add.vhd` (swapped) and you get an error
  naming the missing unit. In these small
  Makefiles, order `SRC` dependency-first; larger projects let
  `ghdl -i`/`-m` compute the order.
- **Keep `sat` even if nothing consumes it yet.** An unused output costs
  nothing after synthesis trims it, but during bring-up a clip flag wired
  to an LED or a UART counter is the difference between "audio sounds
  wrong sometimes" and "input stage clipped 14 times during that sweep".
  Radar telemetry does exactly this at every fixed-point boundary.

## Checkpoint

Before lesson04, you must have:

- `make sim` in `course/work/lesson03/` printing four `R1 pass`, three
  `R2 pass`, the `R3 pass` line, and the `testbench complete` line, with
  zero `FAIL` lines.
- Explore 1 done: you've seen the wrapping adder fail exactly the three R2
  vectors, and can state from memory what 255+255 wraps to in 8 bits.
- A one-sentence answer to: why does `nco.vhd` (lesson04) *want* its
  accumulator to wrap, while this adder must not?
- The rule internalized: resize to exact width, do the math losslessly,
  then wrap/saturate/round once, deliberately, at the output.
