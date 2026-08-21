# Lesson 01 — Entities, Architectures, Signals

*Where we are.* Lesson00 proved the pipeline: you can analyze, elaborate, and
run a VHDL file, and Emacs jumps you to errors. But `hello_tb` had no ports,
no logic, and no clock — it was a program wearing a VHDL costume. This lesson
is where you stop writing programs. You will build the smallest circuit that
exhibits the two ideas everything else in this course stands on: the
entity/architecture split, and *signal update semantics* — the scheduling
model that makes `<=` mean something fundamentally different from `=` in
every language you already know. The vehicle is a 2:1 multiplexer with a
registered output; the same "wrap it in a clock edge" move reappears in every
module through `theremin_top`. Lesson02 then turns the testbench itself into
a first-class subject.

---

## Session 01.1 — Signal Semantics & Delta Cycles (~60 min)

### Objectives

- Write an entity (the pinout) and an architecture (the contents) and say
  precisely which information lives in which.
- Explain what a signal assignment (`<=`) actually does — schedule a future
  value — and predict the behavior of two processes touching the same signal.
- Explain delta cycles: how the simulator models "everything at once" on a
  machine that can only do one thing at a time.
- Turn a combinational mux into a registered mux by wrapping it in
  `if rising_edge(clk)`, and state what hardware each version becomes.
- Read a testbench's `wait until rising_edge(clk); wait for 1 ns;` idiom and
  explain the delta-cycle race it avoids.

### Concepts

#### The entity/architecture split

A VHDL design unit comes in two parts:

```
entity reg_mux is           <-- the pinout: names, directions, types.
  port ( ... );                 Nothing about behavior. This is the part
end entity;                     other modules see when they instantiate you.

architecture rtl of reg_mux is  <-- the contents: what is inside the box.
  ...                           One entity can have several architectures
end architecture;               (rtl, behavioral model, gate-level netlist).
```

The software analogy — header vs. implementation — is fine as far as it
goes, but note what it implies here: the entity is a *component outline on a
schematic*. When `reg_mux_tb` writes `entity work.reg_mux`, it is dropping
that component onto its own schematic and wiring nets to its pins. Nobody
"calls" anything. Instantiation is placement, not invocation: the hardware
exists and runs for the entire life of the design, whether or not anyone is
"using" it this cycle.

`work` is simply the library your analyzed units land in — that is what
`ghdl -a --workdir=build` maintains, and why analysis order matters (more in
Tips & Pitfalls).

#### Signals are not variables — `<=` posts to the future

This is the conceptual hurdle of the whole course, so we take it slowly.

In software, `x = y` is an action that completes before the next line runs.
In VHDL, a signal assignment

```vhdl
q <= a;
```

does **not** change `q`. It *schedules* a transaction: "at the end of the
current simulation step, `q`'s driver takes the value `a` has right now."
Until that step ends, every reader of `q` — including the very next line of
the same process — still sees the old value.

Why would a language do that? Because it is modeling parallel hardware. In a
real circuit, every flip-flop that shares a clock edge samples its input
*simultaneously*, and each one samples the value its input had *before* the
edge. The simulator reproduces that on a sequential CPU by splitting each
instant into two phases: first every triggered process runs and *reads* a
consistent snapshot of all signals while only *posting* its writes; then all
posted writes are applied at once. Read-phase, then commit-phase. No process
can ever see another process's write from the same instant.

The canonical demonstration — inside one clocked process:

```vhdl
if rising_edge(clk) then
  x <= y;
  y <= x;   -- reads the OLD x: this SWAPS x and y every clock
end if;
```

In C those two lines destroy `x`. In VHDL they swap, because both right-hand
sides are read from the pre-edge snapshot and both writes commit together.
That is exactly what two back-to-back flip-flops cross-wired to each other
would do, which is the point: the semantics are strange for a programmer and
obvious for a circuit.

(Processes also have `variable`s, assigned with `:=`, which *do* update
immediately — software semantics, scoped to one process. The testbench below
uses one for `expected`. Rule of thumb: signals are wires between hardware;
variables are scratch arithmetic inside one process.)

#### Delta cycles: "at the same time" on a sequential machine

The commit phase can wake other processes: if the commit changes `q`, any
process sensitive to `q` must now run — but no simulated time has passed.
The simulator handles this with **delta cycles**: zero-duration sub-steps
within one instant of simulation time.

```
simulation time T  (say, a rising clock edge)
 |
 |  delta 0: clk changes 0->1. Every process waiting on clk wakes.
 |           They read the pre-edge world and post their writes.
 |  commit:  posted writes applied. Suppose q changed...
 |  delta 1: ...processes sensitive to q wake, read, post.
 |  commit:  apply. Anything change? If yes, delta 2...
 |
 v  no more activity: NOW advance simulation time toward T + something.
```

Time `T` is over only when a delta produces no new events. A combinational
chain of five processes settles in five deltas — all at the same simulation
time, exactly like gate outputs rippling through a real circuit within one
clock period. If your deltas *never* settle (`a <= not a;` outside a clocked
process), the simulator hangs at time `T` forever: a zero-delay oscillation,
the simulation analog of a combinational feedback loop.

Keep this model in your head; the testbench section below is where it stops
being philosophy and starts biting.

#### One expression, two circuits

Here is a mux as pure combinational logic:

```vhdl
mux : process (sel, a, b)        -- runs whenever any input changes
begin
  if sel = '0' then
    q <= a;
  else
    q <= b;
  end if;
end process;
```

Sensitivity list `(sel, a, b)`: any input event re-evaluates the output,
continuously, like the gates it describes. Synthesis gives you a 4-input
LUT and nothing else; `q` follows the inputs after mere gate delay.

Now the same if/else wrapped differently:

```vhdl
reg : process (clk)              -- runs only on clk events
begin
  if rising_edge(clk) then
    if sel = '0' then
      q <= a;
    else
      q <= b;
    end if;
  end if;
end process;
```

The *only* structural change is the wrapper, but the hardware is different:
`q` is now assigned only at rising clock edges, so synthesis must put a
**D flip-flop** on `q`, fed by the mux LUT. Between edges the inputs can do
anything; `q` holds. After an edge, `q` shows what the inputs were *at* the
edge — a one-cycle latency from cause to visible effect.

That wrapper is the single most consequential idiom in RTL design. It is how
you create state, how you break long logic chains into pipeline stages, and
how you make timing analyzable ("does the mux settle within one clock
period?" is a question a tool can answer; "does this settle eventually?" is
not). Compare `fpga/phase1/rtl/nco.vhd`: same shape, with an accumulator
inside the wrapper instead of a mux.

#### The testbench races the DUT — and must lose politely

Now the payoff. The testbench's checking process does this:

```vhdl
sel <= vecs(i).sel;  a <= vecs(i).a;  b <= vecs(i).b;
wait until rising_edge(clk);   -- DUT samples the inputs at this edge
wait for 1 ns;                 -- let the post-edge value settle
assert q = expected ...
```

Walk it in delta cycles. The stimulus assignments are signal writes: they
commit one delta after they are posted — long before the next clock edge,
which is tens of ns away, so the DUT cleanly sees them at the edge. Fine.

The subtle part is the edge itself. At the rising edge, *two* processes wake
in delta 0: the DUT's `reg` process and the testbench's `main` process (its
`wait until` just came true). The DUT reads the inputs and *posts* the new
`q`. If the testbench read `q` right now — same delta — it would see the
**old** value, because the DUT's write has not committed. The testbench
samples one delta behind the clock edge. Always. Regardless of process
ordering — that snapshot consistency is the whole design of the language.

Both outcomes are useful, and this course uses both:

- `nco_tb.vhd` (which you will dissect in lesson 04) checks `sq_out`
  immediately after the edge, deliberately sampling one delta behind — it
  counts edges over thousands of cycles and a one-cycle shift is absorbed by
  its ±1 tolerance. Its header says so.
- `reg_mux_tb` checks exact per-cycle values, so it must get *past* the
  commit: `wait for 1 ns` advances real simulation time, which forces every
  pending delta to settle first. 1 ns is nothing against an 83 ns clock
  period, so it lands "just after the edge," where the post-edge world is
  fully consistent.

If you ever see a testbench that is mysteriously off by exactly one clock
cycle, this is almost always why. You will prove it to yourself in Explore
exercise 2 by deleting the `wait for 1 ns` and watching R1 fail on the
first vector.

### Radar Connection

Why is hardware description not programming? Because a radar signal chain is
not a sequence of steps — it is a *plumbing diagram running everywhere at
once*. In the receive path of a CW radar (and of our theremin: mixer →
filter → measurement → output), every stage processes this sample while the
stage before it processes the next and the stage after it processes the
previous. A CPU fakes concurrency by time-slicing; an FPGA *is* concurrent,
and VHDL's odd semantics — processes as always-running machines, signals
that commit simultaneously, delta cycles standing in for gate delay — exist
precisely to describe that honestly.

The registered mux is your first **pipeline stage**, and its "one-cycle
latency" is not a bug to optimize away — it is a designed, countable
property. In radar this bookkeeping is deadly serious: every register
between the ADC and the detector adds a known number of clocks, and for a
pulsed or FMCW system, uncounted latency literally becomes a range error
(at our 12 MHz, one cycle is 83 ns — a 12.5 m range bias, since radar range
is two-way: c·t/2).
When lesson 14 wires `theremin_top`, each block boundary is registered and
the total latency is knowable by adding integers. That habit — every stage's
delay pinned to a clock edge, tallied through the chain — starts here.

Even the humble mux has a radar day job: synchronously selecting between an
antenna input and a built-in calibration/test source. It is registered so
the switch lands exactly on a sample boundary instead of mid-sample — the
same reason ours is registered, in miniature.

**Stopping point.** You should now be able to explain:

- why `q <= a;` schedules a future value instead of changing `q`, and why
  `x <= y; y <= x;` inside a clocked process swaps the two signals instead of
  destroying one.
- how delta cycles let a sequential simulator model "everything at once" —
  read-phase then commit-phase, repeated until no new events — and why
  simulation time only advances once a delta produces no activity.
- what hardware the same if/else describes with and without the
  `if rising_edge(clk)` wrapper, and where the one-cycle latency comes from.
- why a registered stage's latency is a countable, designed property — and
  what an uncounted clock cycle of latency does to a radar's range estimate.

---

## Session 01.2 — Build & Run the Registered Mux (~60 min)

### Build

Create `course/work/lesson01/` and the three files below with Emacs. Type
them or paste them, but read every line — the header comments carry the
requirement tags (R1, R2) that the testbench asserts trace back to; that
tag discipline is course law from here on.

**File: course/work/lesson01/reg_mux.vhd**

```vhdl
-- reg_mux.vhd — 2:1 multiplexer with a registered output.
--
-- Requirements this module implements (verified in reg_mux_tb.vhd):
--   R1: q takes the value of a when sel = '0' and b when sel = '1'
--       (the 2:1 mux truth table).
--   R2: the output is registered — q changes only on a rising clock edge,
--       exactly one cycle after the inputs are sampled (1-cycle latency).
--
-- Teaching point: the mux itself is the combinational if/else inside the
-- process; the register is what you get by wrapping that logic in
-- "if rising_edge(clk)". Same expression, different hardware.

library ieee;
use ieee.std_logic_1164.all;

entity reg_mux is
  port (
    clk : in  std_logic;
    sel : in  std_logic;
    a   : in  std_logic;
    b   : in  std_logic;
    q   : out std_logic
  );
end entity reg_mux;

architecture rtl of reg_mux is
begin

  reg : process (clk)
  begin
    if rising_edge(clk) then
      if sel = '0' then
        q <= a;  -- R1
      else
        q <= b;  -- R1
      end if;
    end if;
  end process;

end architecture rtl;
```

Notes on the DUT:

- House style throughout: lowercase keywords, 2-space indent, one entity per
  file, header comment listing the requirements the module implements.
- The process is sensitive to `clk` **only**. `sel`, `a`, `b` are read
  inside, but changes to them must not wake the process — the register cares
  about nothing between edges. Listing them would still simulate correctly
  (the body does nothing without an edge) but misstate your intent.
- No reset: a mux output needs no defined power-on value, and iCE40 flops
  power up to '0' anyway. The counter in lesson 02 *will* need its synchronous
  reset, and you'll see the `if rst = '1' ... elsif` shape from `nco.vhd`.

**File: course/work/lesson01/reg_mux_tb.vhd**

```vhdl
-- reg_mux_tb.vhd — self-checking testbench for reg_mux.
--
-- Verifies (tags match the header of reg_mux.vhd):
--   R1: the full truth table — all 8 combinations of (sel, a, b) produce
--       q = the selected input one clock later.
--   R2: 1-cycle latency — after an input change, q holds its old value
--       until the next rising edge. A combinational mux fails this check;
--       that is the whole point of the lesson.
--
-- Sampling note: checks wait 1 ns after the clock edge so the DUT's
-- post-edge value has settled (same pattern as fpga/phase1/tb/nco_tb.vhd).

library ieee;
use ieee.std_logic_1164.all;

entity reg_mux_tb is
end entity reg_mux_tb;

architecture sim of reg_mux_tb is
  constant CLK_PER : time := 83.333 ns;  -- 12 MHz, as on the target board

  -- one row of the truth table
  type vec_t is record
    sel, a, b : std_logic;
  end record;
  type vec_arr_t is array (natural range <>) of vec_t;
  constant vecs : vec_arr_t := (
    ('0', '0', '0'), ('0', '0', '1'), ('0', '1', '0'), ('0', '1', '1'),
    ('1', '0', '0'), ('1', '0', '1'), ('1', '1', '0'), ('1', '1', '1'));

  signal clk  : std_logic := '0';
  signal sel  : std_logic := '0';
  signal a    : std_logic := '0';
  signal b    : std_logic := '0';
  signal q    : std_logic;
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.reg_mux
    port map (
      clk => clk,
      sel => sel,
      a   => a,
      b   => b,
      q   => q
    );

  main : process
    variable expected : std_logic;
  begin
    -- R1: walk the full truth table.
    for i in vecs'range loop
      sel <= vecs(i).sel;
      a   <= vecs(i).a;
      b   <= vecs(i).b;
      wait until rising_edge(clk);  -- DUT samples the inputs here
      wait for 1 ns;                -- let the post-edge value settle
      if vecs(i).sel = '0' then
        expected := vecs(i).a;
      else
        expected := vecs(i).b;
      end if;
      assert q = expected
        report "R1 FAIL: sel=" & std_logic'image(vecs(i).sel) &
               " a=" & std_logic'image(vecs(i).a) &
               " b=" & std_logic'image(vecs(i).b) &
               " gave q=" & std_logic'image(q)
        severity error;
    end loop;
    report "R1 pass: all 8 (sel,a,b) combinations select the right input";

    -- R2: prove there is a register. Park q at '0', then present inputs
    -- that select '1' and look at q *before* the next clock edge — a
    -- combinational mux would already show '1'.
    sel <= '0'; a <= '0'; b <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert q = '0'
      report "R2 setup FAIL: q should be '0' before the latency check"
      severity error;
    sel <= '1';            -- now selecting b = '1'
    wait for CLK_PER / 4;  -- well inside the cycle, no edge yet
    assert q = '0'
      report "R2 FAIL: q changed without a clock edge (output not registered)"
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert q = '1'
      report "R2 FAIL: q did not update on the clock edge"
      severity error;
    report "R2 pass: q changes only on the rising edge (1-cycle latency)";

    report "reg_mux testbench complete: R1-R2 checked (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Notes on the testbench — every line explainable, per course rules:

- `clk <= not clk after CLK_PER / 2 when not done else '0';` is a
  *concurrent* signal assignment: a one-line process making a 12 MHz clock.
  Each transition schedules the next, half a period out, until `done` stops
  it — and with no events left to serve, the simulator exits. That is the
  standard way a testbench ends without `std.env.stop`.
- The record array `vecs` is the full truth table as data. Walking a
  constant table beats eight copy-pasted stanzas: one loop, one assert, and
  the failure report prints exactly which row lied.
- `expected` is a `variable` (`:=`, updates immediately) — scratch
  arithmetic inside the process, not a wire to anything. This is the
  signal/variable division of labor from Concepts.
- The R1 loop is the `drive → wait for edge → wait 1 ns → check` idiom you
  now understand at the delta-cycle level.
- R2 is the check a combinational mux cannot pass: park `q` at '0', then
  make the inputs select '1' and look at `q` in the *middle* of the cycle
  (`wait for CLK_PER / 4` — real time passes, all deltas settle, but no
  edge occurs). Registered mux: still '0'. Combinational mux: already '1'.
  Then confirm the edge delivers the '1'. Latency proven, both halves.
- Asserts use `severity error`, which reports and *continues* — you get the
  full damage report in one run. The Makefile's `--assert-level=failure`
  means only `severity failure` (none here) would abort the simulation.

**File: course/work/lesson01/Makefile**

```make
# Lesson 01 — GHDL sim flow. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors tutorial/Makefile — same
# flags, same shim, no synthesis targets.

TB         = reg_mux_tb
SRC        = reg_mux.vhd reg_mux_tb.vhd
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

Same skeleton as `tutorial/Makefile`, with two sources: analyze both, elab
the testbench, run it. `reg_mux.vhd` must precede `reg_mux_tb.vhd` in `SRC`
— the testbench instantiates `entity work.reg_mux`, so the mux must already
be in the `work` library when the testbench is analyzed.

### Run

From `course/work/lesson01/`:

```bash
fpga        # the lesson00 alias: put the oss-cad-suite tools on PATH
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build reg_mux.vhd reg_mux_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/reg_mux_tb reg_mux_tb
./build/reg_mux_tb --assert-level=failure
reg_mux_tb.vhd:72:5:@625997500fs:(report note): R1 pass: all 8 (sel,a,b) combinations select the right input
reg_mux_tb.vhd:93:5:@792663500fs:(report note): R2 pass: q changes only on the rising edge (1-cycle latency)
reg_mux_tb.vhd:95:5:@792663500fs:(report note): reg_mux testbench complete: R1-R2 checked (any FAILs are listed above)
```

(The `mkdir` line appears only on the first run; your shim path shows your
own `$HOME`.) The timestamps are femtosecond-exact receipts of the edge
story from Concepts, and auditing one once is worth doing: the R1 report at
`@625997500fs` is 625.9975 ns. Predict it: the clock starts at '0', so the
first rising edge lands at half a period, 41.6665 ns; the 8 truth-table rows
consume one edge each, so the 8th edge is at 41.6665 + 7 × 83.333 =
624.9975 ns; add the final `wait for 1 ns` settle and the report fires at
625.9975 ns. Exactly what the log says. (The odd digits exist because
83.333 ns is our stand-in for 1/12 MHz, not the real irrational thing.)

**Stopping point.** You should now be able to explain:

- why `reg_mux.vhd` must precede `reg_mux_tb.vhd` in the Makefile's `SRC`
  line — what the `work` library is and why analysis order matters.
- why the DUT's process is sensitive to `clk` only, and what listing `sel`,
  `a`, `b` there would misstate about the hardware.
- why the R1 loop's `drive → wait for edge → wait 1 ns → check` sequence
  samples a fully consistent post-edge world, in terms of delta 0 versus the
  commit.
- how the `@625997500fs` timestamp on the R1 report is predicted from the
  first rising edge at half a period plus seven more periods plus the 1 ns
  settle.

---

## Session 01.3 — Explore & Checkpoint (~75 min)

### Explore

Solutions live in `course/solutions/lesson01/` — attempt these before
peeking.

1. **Break it: de-register the mux.** In `reg_mux.vhd`, remove the
   `if rising_edge(clk) then` / matching `end if;` and change the
   sensitivity list to `(sel, a, b)` — the combinational mux from Concepts.
   `make sim`. Predict first, then observe: R1 still *passes* (after the
   edge + 1 ns, a combinational `q` is also correct — R1 cannot tell the
   two circuits apart), but R2 prints
   `R2 FAIL: q changed without a clock edge (output not registered)`.
   Note the run still ends with the "testbench complete" line and `make`
   reports success — `severity error` does not abort. Moral: a green exit
   code is not a pass; the *absence of FAIL lines* is. Lesson02 formalizes
   this. Restore the register afterward.
2. **Break it: sample in the race window.** In the R1 loop of the
   testbench, delete only the `wait for 1 ns;` line. Now the check reads
   `q` in delta 0 of the edge — one delta behind the DUT's commit. First
   vector: `R1 FAIL: sel='0' a='0' b='0' gave q='U'` — `q` still holds its
   *uninitialized* pre-edge value; later rows report the previous row's
   answer. You have now seen the off-by-one-delta bug from both sides of
   the assert. Put the line back.
3. **Two-stage pipeline.** Inside the clocked process, route the mux
   through an intermediate signal: declare `signal p : std_logic;` in the
   architecture, assign `p <= a;`/`p <= b;` in the if/else, and add
   `q <= p;` after the inner `end if;` (still inside the edge wrapper).
   Predict from the commit rules why this creates *two* flip-flops and a
   2-cycle latency — then run and match each TB failure message to that
   prediction. This is the classic "extra register by accident" bug, and
   also exactly how you pipeline on purpose.
4. **Widen it.** Make `a`, `b`, `q` 4-bit: `std_logic_vector(3 downto 0)`.
   The TB needs its record, truth table, and reports updated (for vectors,
   VHDL-2008's `to_string(q)` replaces `std_logic'image(q)`), but the DUT's
   process body does not change at all — the same if/else now describes four
   LUT+flop bit-slices. That "describe one bit, get N" scaling is why the
   NCO's 32-bit accumulator in lesson 04 is still three lines.

### Tips & Pitfalls

- **Emacs, ports for free:** with point inside the `reg_mux` entity, `C-c
  C-p C-w` (`vhdl-port-copy`) captures the port list; in the testbench,
  `C-c C-p C-i` (`vhdl-port-paste-instance`) drops a complete named-map
  instantiation, and `C-c C-p C-s` pastes matching signal declarations.
  Hand-typing port maps is how `sel` gets wired to `a` at 5 pm.
- **Emacs, keep style automatic:** `C-c C-b` (`vhdl-beautify-buffer`)
  re-indents to vhdl-mode's settings; run it before comparing against a
  lesson listing so diffs show substance, not whitespace.
- **Toolchain: analysis order.** GHDL analyzes strictly in the order given.
  Swap `SRC` to put the testbench first and you get
  `unit "reg_mux" not found in library "work"` — dependency before
  dependent, always. (Lesson05's multi-file builds keep this discipline.)
- **Toolchain: stale units.** GHDL cross-checks each unit against what
  `build/` remembers; if you rename an entity but not its file (or vice
  versa) and things get confusing, `make clean && make sim` re-analyzes
  from scratch. Cheap at this size — reach for it early.
- **Pitfall: `<=` vs `:=`.** Writing `:=` to a signal or `<=` to a variable
  is a hard error, which is kind of GHDL; the *silent* version of this trap
  is expecting a signal you just assigned to hold the new value two lines
  later. When a process "ignores" an assignment, reread the commit rules —
  it is delta scheduling, working as specified, every time.
- **Pitfall: partial sensitivity lists.** A combinational process missing
  an input (e.g. `process (sel, a)` reading `b`) simulates as a subtly
  wrong latch-ish thing but synthesizes as the full mux — a sim/hardware
  mismatch, the worst bug class in HDL. VHDL-2008's `process (all)` sidesteps
  it for combinational processes; clocked processes stay `process (clk)`.

### Checkpoint

Before lesson 02, all of the following are true:

- `course/work/lesson01/` contains `reg_mux.vhd`, `reg_mux_tb.vhd`, and
  `Makefile`, and `make sim` prints the `R1 pass:`, `R2 pass:`, and
  `reg_mux testbench complete` lines with no `FAIL` anywhere.
- You can state, without notes, what `q <= a;` does *not* do, and why
  `x <= y; y <= x;` swaps inside a clocked process.
- You can explain why the testbench's `wait for 1 ns` exists, in terms of
  delta 0 versus the commit — and you have watched its removal fail R1
  (Explore 2).
- You have de-registered the mux (Explore 1), predicted correctly which
  requirement would fail, and restored it.
- You can say what hardware `if rising_edge(clk)` around an if/else infers,
  and what the same if/else infers without it.
