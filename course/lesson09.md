# Lesson 09 — Crossing Clock Domains Safely

*Where we are.* Lessons 04–08 built the voice of the instrument — NCO,
sine table, delta-sigma DAC — all inside a single 12 MHz clock domain.
Lesson 10 breaks that comfort: the antenna oscillator is a 74HC14
relaxation oscillator free-running near 200 kHz, with *no timing
relationship whatsoever* to our clock, and before `freq_meas` may count
its edges the signal must pass through this lesson's module. `sync_2ff`
is the smallest entity in the course — two flip-flops, zero arithmetic —
and the one with the highest stakes per line. Clock-domain crossing is
certification-grade material: in a DO-254 flow, CDC analysis is a named
signoff item with its own tools and review, because a CDC bug is the
classic defect that passes every simulation and every bench test, then
corrupts data once a week in the field, unreproducibly. This lesson is
where you learn to never write one.

## Objectives

- Explain metastability from the physics: what the setup/hold window
  really is, why sampling a moving signal can leave a flop balanced
  between states, and why the balance decays exponentially.
- Compute a synchronizer's MTBF from τ, the aperture window, and the two
  frequencies involved — and use the numbers to justify the 2-FF pattern.
- State the CDC rules of the road: single-bit level signals only, one
  synchronizer per signal, never a bus bit-wise, Gray codes for values
  that must cross whole.
- Explain what RTL simulation of a synchronizer can verify and what it
  fundamentally cannot; build `sync_2ff` and its self-checking testbench
  and pass all checks.

## Concepts

### What a flip-flop actually is

Every clocked process you have written so far had its inputs produced by
other clocked processes on the *same* clock — the timing tools (icetime,
lesson 05) verify every register-to-register path settles before the next
edge, so every flip-flop samples a signal *guaranteed stable* during its
critical window, and flip-flops behave ideally. An asynchronous input
voids that contract: the 74HC14 doesn't know our clock exists, and its
edges land at any moment — including the exact moment a flip-flop is
sampling. No constraint file can fix that, because there is no timing
relationship to constrain. What happens then is physics.

Strip a D flip-flop to its storage element and you find two inverters in
a loop — a bistable. Its two stable states are the rails, '0' and '1';
between them lies an unstable equilibrium, a ball balanced on the crest
of a hill:

```
        energy
          |         ball here = metastable
          |              o
          |          _.-' '-._
          |      _.-'         '-._
          |  _.-'                 '-._
          |-'                         '-
          +------------------------------
             '0'      V_meta       '1'
```

Clocking the flop briefly connects D to the loop, nudging the ball
toward one side, then latches the loop closed. If D is solidly '0' or
'1' during the aperture — the real physical quantity behind the
datasheet's *setup and hold window* — the ball rolls cleanly to a rail.
But if D is *in transition* during the aperture, the loop can latch with
the ball near the crest: an internal voltage near the switching
threshold, neither '0' nor '1'. That is **metastability**. The output
may hover at an invalid level, or oscillate, for an unbounded time
before falling to *some* rail — and which rail is genuinely random;
thermal noise decides. Unbounded, but not unquantified: the loop's own
gain pulls the ball off balance exponentially, with a regeneration time
constant τ (tens to ~100 ps for an iCE40-class flip-flop), so the
probability the flop is *still* undecided after a wait t_r is:

```
P(still metastable after t_r) = e^(-t_r / τ)
```

### MTBF: putting numbers on the failure

Two questions: how often does a flop get hit, and how long does it need
to recover? A data edge causes trouble only if it lands inside the
aperture window T_W around a clock edge; for an async input the landing
position is uniformly random over the clock period, so each transition
hits with probability T_W · f_clk, and with f_data transitions per
second:

```
hit rate = T_W * f_clk * f_data     [events / second]
```

If downstream logic samples the flop's output t_r after the clock edge, a
hit becomes an actual failure only if the flop is still undecided at
t_r — probability e^(-t_r/τ). Mean time between failures:

```
              e^(t_r / τ)
MTBF = ---------------------------
        T_W * f_clk * f_data
```

Now our numbers. Take T_W = 100 ps and τ = 100 ps (deliberately
pessimistic; vendors publish characterized values per family, and the
certifiable engineering method is to *look them up and do this budget*,
not to trust folklore). f_clk = 12 MHz; the antenna oscillator at 200 kHz
gives f_data = 400 k transitions/s (two edges per cycle).

- Hit rate = 1e-10 × 12e6 × 4e5 ≈ **480 events per second**. A flop
  sampling the raw antenna signal goes metastable about every 2 ms. Not
  rare: your instrument would inhale one during every note.
- Use the raw flop output combinationally — t_r ≈ 0 — and every one of
  those 480 events/s is a potential failure: different fan-out branches
  of the undecided signal can read *different values*, and a state
  machine seeing half-old, half-new inputs jumps to states you never
  drew.
- Give the flop one full clock period to decide — t_r ≈ 83 ns minus
  routing and setup, call it 80 ns — and e^(t_r/τ) = e^800 ≈ 10^347, so

```
MTBF ≈ 10^347 / 480  ≈  10^344 seconds
```

The age of the universe is about 4×10^17 seconds. Metastability cannot
be *prevented* — any flop sampling an async signal goes metastable,
regularly — only made irrelevant, and irrelevance is exponential in
resolve time. One clock period of patience buys more margin than the
lifetime of the cosmos: that is the entire theoretical content of the
two-flip-flop synchronizer.

### The 2-FF synchronizer

The pattern writes itself: let the first flop take the metastability hit,
and let no one look at it for one full period. The only "anyone" allowed
is a second flop:

```
async_in ----> D   Q ----------> D   Q ----------> sync_out
             (meta_ff)         (sync_ff)          safe in clk
clk -----------^-----------------^                domain
```

`meta_ff` may spend time undecided; that's its job. By the next rising
edge it has resolved (with the 10^344-second confidence computed above)
and `sync_ff` captures a clean, rail-settled value. Everything downstream
sees only `sync_ff`, which changes exactly on clock edges like any other
registered signal. What does the crossing *cost*? Latency, and a specific
uncertainty:

```
clk       _/‾\_/‾\_/‾\_/‾\_/‾\_
                e1  e2  e3
async_in  ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾     rises between clock edges
meta_ff   _______/????‾‾‾‾‾‾‾‾‾     e1 samples it; may waver, then resolves
sync_out  ___________/‾‾‾‾‾‾‾‾‾     e2 — if meta_ff resolved high
sync_out  _______________/‾‾‾‾‾     e3 — if meta_ff resolved low and
                                    recaptured the level at e2
```

The transition reaches `sync_out` after 2 or 3 clock edges, and *which*
is decided by a coin flip inside the silicon. A synchronizer does not
remove uncertainty about when an edge is captured — it converts "invalid
voltage anywhere in my logic" into "clean value, ±1 cycle of timestamp
ambiguity". That residual ±1 cycle is permanent: never build anything
downstream that assumes the latency is fixed. (In lesson 10 it becomes ±1
count of period-measurement noise — quantifiable, budgetable, harmless.
That's the trade you want.)

### The CDC rules of the road

The 2-FF pattern is safe *only* inside a discipline. These rules are what
a CDC signoff tool mechanically checks and what a DO-254 reviewer will
ask you to demonstrate. Learn them as law:

1. **Synchronize single-bit level signals only** — one bit whose *level*
   carries the information, held well over two clock periods. Our antenna
   square wave (200 kHz into 12 MHz — a level every 30 clocks) is the
   perfect customer.
2. **Never synchronize a bus bit-wise.** Tempting, fatal. Put a 2-FF on
   each bit of a counter and let it step 0x0FF → 0x100: nine bits change,
   each synchronizer resolves its own coin flip, some bits arrive a cycle
   before others, and the receiver can read 0x1FF, 0x000 — any *tear* of
   old and new bits. A synchronizer preserves each bit, not the *word*.
   Buses cross via a handshake (a synchronized single-bit "valid" whose
   acknowledgment gates the next update), or —
3. **Gray-code counters that must cross whole.** Consecutive Gray-code
   values differ in exactly one bit, so however the coin flips land, the
   receiver reads either the old value or the new — both legitimate.
   That's the trick inside every async FIFO's read/write pointers. The
   theremin doesn't need one, but know the name; you will meet async
   FIFOs at every ADC interface of your career.
4. **One synchronizer per signal, at the border, immediately.** If the
   raw input fans out to two synchronizers, the copies can disagree by a
   cycle and reconverging logic sees contradictions. Synchronize once, at
   the pin; only the synchronized copy travels. `theremin_top` follows
   this to the letter: `osc_in` touches one `sync_2ff`, nothing else.
5. **Respect the minimum pulse width.** A level shorter than two clock
   periods can fall entirely between sampling edges and vanish (you'll
   watch it happen in Explore). Fast or single-cycle events need
   pulse-stretchers or handshakes, not a bare 2-FF.
6. **Tell the tools.** In flows with timing pressure you mark the pair
   with vendor attributes (ASYNC_REG and friends) so the placer keeps the
   flops adjacent — routing delay between them eats directly into t_r,
   the exponent of your MTBF — and declare the crossing so the timing
   analyzer doesn't demand the impossible. A constraints topic, not RTL;
   at 12 MHz on an iCE40 our flow needs none of it.

### What simulation can and cannot verify

The uncomfortable fact this lesson must not hide: **RTL simulation
cannot exhibit metastability.** GHDL's flip-flop is ideal — no aperture,
no undecided state — so in simulation `sync_2ff` behaves as a plain
2-stage delay line, and a *missing* synchronizer usually simulates
perfectly too. The bug class this lesson prevents is invisible to the
very tool this course runs on; that is why certification flows treat CDC
as its own discipline, with structural analysis rather than simulation.
The testbench below is honest about its role: it verifies the
*synchronous contract* — latency window, no glitches, no lost levels,
output changes only on clock edges — while the metastability protection
is established by the MTBF arithmetic, by construction. The TB accepts a
transition in 2 *or 3* edges even though simulation always delivers
exactly 2: the allowance encodes the hardware coin flip simulation
cannot show. Write the check the *silicon* must pass, not the check the
simulator happens to pass.

## Radar Connection

**Every ADC and sensor interface you will ever touch is a clock-domain
crossing.** This is the least optional lesson in the course for a radar
engineer.

- A radar receiver's ADC runs on the *sampling clock* — low-jitter,
  carefully distributed, its purity setting the achievable SNR — while
  the DSP fabric runs on a *processing clock* sized to the computation.
  Nobody gets to make those the same clock, so every sample word ever
  digitized crosses a domain boundary, invariably through an async FIFO
  with Gray-coded pointers — rule 3, industrialized. When a
  deserializer/JESD datasheet says "elastic buffer", you're looking at
  this lesson.
- The rest of the sensor suite is a catalog of rule 1: GPS PPS pulses,
  encoder edges, blanking and interlock discretes, the neighboring
  transmitter's trigger — every one asynchronous, every one owed exactly
  one 2-FF at the pin.
- The theremin is the miniature: the 74HC14 antenna oscillator *is* the
  sensor front end, `sync_2ff` the border checkpoint, and everything
  downstream one clean synchronous domain. One async signal, one
  synchronizer, rule 4 by construction.
- The failure mode is why this is signoff material. An unsynchronized
  input usually survives the bench — until a metastable event lands in a
  state machine's decision logic on a real mission. The symptom: a radar
  that corrupts one CPI a week, differently each time, never under the
  debugger, worse when the chassis is hot — the worst bug profile there
  is, and the reason DO-254 asks you to *prove* crossings are structured
  rather than test them. The proof here is two paragraphs of arithmetic
  in Concepts. Cheap insurance.

## Build

Three files. Solutions live in `course/solutions/lesson09/` — type the
code in rather than copying, and resist peeking until you've attempted
the Explore exercises.

**File: course/work/lesson09/sync_2ff.vhd**

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

Dissection — short file, but every absence is a decision:

- **No `numeric_std`, no generics, no reset, no enable.** Two bits of
  state, one wire out; the header argues the no-reset deviation, and the
  port list is the pinned curriculum interface, exactly.
- **`meta_ff <= async_in; sync_ff <= meta_ff;`** — signal assignment
  semantics (lesson 01) mean `sync_ff` gets meta_ff's *pre-edge* value,
  so this is two flops in series, never one flop with renamed wires.
  Variables here would have built a single wire — delta-cycle semantics
  are load-bearing in this file.
- **`sync_out <= sync_ff;`** — only the *second* flop is exported, and
  nothing combinational touches `async_in` or `meta_ff`; that structural
  property *is* requirement R2. Synthesis maps this to exactly two iCE40
  flip-flops back to back.

**File: course/work/lesson09/sync_2ff_tb.vhd**

```vhdl
-- sync_2ff_tb.vhd — self-checking testbench for the 2-FF synchronizer.
--
-- Verification approach (requirement tags R1..R2 from sync_2ff.vhd):
-- async_in toggles every 599 ns while clk runs at 12 MHz (period
-- 83.333 ns). The half-periods are coprime (83,333 = 167 x 499; 599 is
-- prime) and the stimulus starts at a 100 ns offset, so no async edge ever
-- lands on a clk edge and the async/clk phase alignment sweeps the whole
-- clock period over the run — a deliberate model of two unrelated clocks.
--
--   R1: every async_in transition reaches sync_out within 2-3 rising clk
--       edges, and exactly once — total sync_out transitions must equal
--       total async_in transitions (any glitch or swallowed level breaks
--       the equality).
--   R2: sync_out changes only at rising clk edges (checked at every
--       sync_out event via clk'last_event = 0 ns).
--
-- RTL simulation has no metastability, so the observed R1 latency is
-- always exactly 2 edges; the 3-edge allowance is the hardware truth (the
-- first FF may resolve to the old value and catch up one clock later).

library ieee;
use ieee.std_logic_1164.all;

entity sync_2ff_tb is
end entity sync_2ff_tb;

architecture sim of sync_2ff_tb is
  constant CLK_PER    : time     := 83.333 ns;  -- 12 MHz
  constant ASYNC_HALF : time     := 599 ns;     -- prime-ratio toggle interval
  constant N_TOGGLES  : positive := 120;

  signal clk      : std_logic := '0';
  signal async_in : std_logic := '0';
  signal sync_out : std_logic;
  signal done     : boolean := false;

  signal n_r1_ok : natural := 0;  -- async transitions seen on sync_out in 2-3 edges
  signal n_sync  : natural := 0;  -- total sync_out transitions (glitch detector)
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.sync_2ff
    port map (
      clk      => clk,
      async_in => async_in,
      sync_out => sync_out
    );

  -- R1: after each async_in change, count rising clk edges until sync_out
  -- matches. Must happen within 3 edges and no sooner than 2 (the level
  -- has to traverse both flops). The 599 ns level time (> 7 clk periods)
  -- guarantees this process is back waiting before the next change.
  check_r1 : process
    variable target  : std_logic;
    variable settled : boolean;
  begin
    wait on async_in;
    target  := async_in;
    settled := false;
    for e in 1 to 3 loop
      wait until rising_edge(clk);
      wait for 1 ns;  -- let the post-edge value settle before sampling
      if sync_out = target then
        assert e >= 2
          report "R1 FAIL: sync_out changed after only " &
                 integer'image(e) & " clk edge(s) - bypassing a flop?"
          severity error;
        settled := true;
        exit;
      end if;
    end loop;
    assert settled
      report "R1 FAIL: async_in change at " & time'image(async_in'last_event) &
             " before now not on sync_out within 3 clk edges"
      severity error;
    if settled then
      n_r1_ok <= n_r1_ok + 1;
    end if;
  end process;

  -- R2: every sync_out event must coincide with a rising clk edge (the
  -- time-0 'U' -> '0' initialization event is not a transition; skip it).
  check_r2 : process
  begin
    wait on sync_out;
    if now > 0 ns then
      assert clk = '1' and clk'last_event = 0 ns
        report "R2 FAIL: sync_out changed at " & time'image(now) &
               ", not aligned with a rising clk edge"
        severity error;
      n_sync <= n_sync + 1;
    end if;
  end process;

  main : process
  begin
    wait for 100 ns;  -- offset so async edges never coincide with clk edges
    for i in 1 to N_TOGGLES loop
      async_in <= not async_in;
      wait for ASYNC_HALF;
    end loop;
    wait for 4 * CLK_PER;  -- flush the last transition through both flops

    assert n_r1_ok = N_TOGGLES
      report "R1 FAIL: only " & integer'image(n_r1_ok) & " of " &
             integer'image(N_TOGGLES) & " transitions arrived in 2-3 edges"
      severity error;
    report "R1 pass: " & integer'image(n_r1_ok) & "/" &
           integer'image(N_TOGGLES) &
           " async transitions reached sync_out in 2-3 clk edges";

    assert n_sync = N_TOGGLES
      report "R1 FAIL: " & integer'image(n_sync) &
             " sync_out transitions for " & integer'image(N_TOGGLES) &
             " async transitions - glitch or swallowed level"
      severity error;
    report "R1 pass: no glitches - sync_out transition count matches async_in (" &
           integer'image(n_sync) & ")";

    report "R2 pass: all " & integer'image(n_sync) &
           " sync_out transitions occurred on rising clk edges";

    report "sync_2ff testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **The stimulus models asynchrony with number theory.** A simulator's
  edges can't be "random", but they can be *unrelated*: in simulator
  units the clock period is 83,333 ps = 167 × 499 and the toggle interval
  599,000 ps with 599 prime, so the async edges' phase precesses through
  the whole clock period over 120 toggles; the 100 ns offset keeps any
  edge from landing exactly *on* a clock edge, where the simulator would
  resolve the tie deterministically by delta ordering — precisely the
  fiction we refuse to test against.
- **Three processes instead of lesson 04's one.** `main` drives stimulus
  and delivers the verdict; `check_r1` and `check_r2` are *monitors* —
  infinite processes that sleep on `wait on <signal>`, check the event,
  and go back to sleep. Monitors watch every transition without the
  stimulus code having to remember to look.
- **`check_r1` is a latency window check.** Wake on an `async_in` event,
  count rising clock edges until `sync_out` shows the new level. The
  loop bound enforces the ceiling (within 3 edges); `assert e >= 2`
  enforces the floor — arrival after 1 edge means the level bypassed a
  flop, the classic broken-synchronizer refactor. Here we *do* burn
  `wait for 1 ns` after each edge, the opposite call from lesson 04's
  counting loop: this check is *about* edge alignment, so it must sample
  cleanly past the delta cycle. Choose per check, and know why.
- **"599 ns > 7 clk periods" is the monitor's own contract.** `check_r1`
  takes up to 3 edges to finish one check; each level lasts over 7
  periods, so the monitor is always back at `wait on async_in` before the
  next transition. A monitor that can miss events while busy is a
  verification bug — do this arithmetic every time you write one.
- **`check_r2` uses `clk'last_event = 0 ns`** — "clk changed in this very
  simulation cycle" — so the assert reads *this sync_out event is
  simultaneous with a rising clock edge*; any combinational path from
  `async_in` to `sync_out` would break it. The `now > 0 ns` guard skips
  the time-zero 'U' → '0' initialization event: wiring, not a transition.
- **The counters are signals, not variables**, because they're shared:
  monitors increment, `main` reads the verdict — and the verdict
  cross-checks the monitors against each other. `n_r1_ok = 120` says
  every transition arrived on time; `n_sync = 120` says *nothing else*
  happened (121 output transitions would be a glitch, 119 a swallowed
  level). The final `wait for 4 * CLK_PER` drains the last transition
  through the flops before judgment.

**File: course/work/lesson09/Makefile**

```make
# Lesson 09 solution: 2-FF synchronizer. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile in
# miniature — same flags, same shim, no synthesis targets.

TB         = sync_2ff_tb
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) sync_2ff.vhd sync_2ff_tb.vhd
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
```

The lesson 04 Makefile minus the wave targets — for a 2-flop module the
asserts tell the whole story (add `--wave=build/$(TB).ghw` to the run
line to see the shift in GTKWave). Analysis order still matters:
`sync_2ff.vhd` before the TB that instantiates it.

## Run

From `course/work/lesson09/` (with the toolchain environment sourced —
the `fpga` alias from lesson 00 does this):

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build sync_2ff.vhd sync_2ff_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/sync_2ff_tb sync_2ff_tb
./build/sync_2ff_tb --assert-level=failure
sync_2ff_tb.vhd:109:5:@72313332ps:(report note): R1 pass: 120/120 async transitions reached sync_out in 2-3 clk edges
sync_2ff_tb.vhd:118:5:@72313332ps:(report note): R1 pass: no glitches - sync_out transition count matches async_in (120)
sync_2ff_tb.vhd:121:5:@72313332ps:(report note): R2 pass: all 120 sync_out transitions occurred on rising clk edges
sync_2ff_tb.vhd:124:5:@72313332ps:(report note): sync_2ff testbench complete (any FAILs are listed above)
```

(The `mkdir -p build` line appears only on the first run; the home path
in the `-Wl` line will match your machine.) Sanity-check the timestamp:
100 ns offset + 120 × 599 ns of toggling + 4 clock periods of flush =
72,313,332 ps ≈ 72.3 µs.

## Explore

Attempt these before peeking at anything in `course/solutions/`.

1. **Break it: bypass the second flop.** In `sync_2ff.vhd`, change
   `sync_out <= sync_ff;` to `sync_out <= meta_ff;` — the refactor a
   well-meaning teammate makes because "it works and saves a cycle".
   Predict, then `make sim`. You get 120 assertion errors — `R1 FAIL:
   sync_out changed after only 1 clk edge(s) - bypassing a flop?` — yet
   the summary still reports `120/120` and no glitches (work out why from
   `check_r1`: the floor assert fires but the transition still counts as
   settled — the per-event FAIL lines carry the verdict). The one-flop
   version passes every *functional* check; only the structural latency
   floor catches it, because metastability doesn't exist in RTL. Restore
   and re-run to green.
2. **Swallow some levels.** In the TB, set `ASYNC_HALF` to `60 ns` —
   shorter than one clock period, violating rule 5. Predict first.
   Observed: `R1 FAIL: only 34 of 120 transitions arrived in 2-3 edges`
   and `54 sync_out transitions for 120 async transitions`, plus a stream
   of per-transition timeouts. Levels that fit between two sampling edges
   never existed as far as the clk domain knows — a synchronizer is not a
   pulse catcher. (Yet R2 still passes: safe and lossy are different
   axes.) Restore 599 ns.
3. **Add a third flop.** Extend the shift register (`extra_ff` after
   `sync_ff`, export that) and re-run. The TB stays green — latency is
   now exactly 3 edges, inside the allowance that exists for the hardware
   coin flip. One tolerance doing two jobs (hardware margin *and*
   pipeline headroom): decide whether that's a feature or a hole, and
   what a stricter TB would assert (e.g. constant latency across
   transitions in simulation). Real 3-FF chains are what you specify when
   the MTBF budget comes up short — at 500 MHz, t_r is 2 ns, not 80 ns,
   and e^(t_r/τ) stops being astronomical. Restore two flops (solutions
   and OUTPUT.log are the 2-FF version). On paper afterwards: find
   roughly the clock frequency at which 2-FF MTBF drops below 10 years —
   the cliff is sharp once t_r shrinks to tens of τ, and that cliff is
   why vendors publish characterized τ instead of letting you guess.

## Tips & Pitfalls

- **Emacs / vhdl-mode:** `M-x vhdl-beautify-buffer` re-indents and
  re-aligns the whole file in one stroke — run it after hand-editing
  declarations and watch the `:` and `<=` columns snap into line (this
  lesson's files are the target look). On a region,
  `M-x vhdl-beautify-region`. Beautify *before* your first commit, not
  after reviews start.
- **Toolchain gotcha — GHDL's shape-shifting timestamps.** Lesson 04
  printed `@...fs`; this lesson prints `@...ps`. Nothing changed: GHDL
  simulates in femtoseconds but prints each timestamp in the coarsest
  unit that represents it exactly (lesson 04's reports fired on …500 fs
  half-period boundaries; this TB's summary lands on whole picoseconds).
  Don't let scripts assume the unit — and remember `83.333 ns` is only
  *near* 12 MHz; exact edge arithmetic must use the literal, not the
  nominal frequency.
- **Guard the pattern against helpful tools and teammates.** Synthesis
  can replicate a synchronizer's flops to reduce fan-out — quietly
  creating rule 4's disagreeing-copies hazard — and retiming can move
  logic between the pair, eating t_r. Keeping the synchronizer as its
  own entity makes the structure visible; production flows add
  ASYNC_REG-style attributes to make it enforceable. At 12 MHz none of
  this bites, but write it as if it will, because next time it will.
- **Don't reset what shouldn't be reset.** Reflexively add the
  house-style `rst` port here and a reviewer should make you defend it.
  You can't — the header explains why — and "I applied the pattern
  without thinking" is exactly what CDC reviews exist to catch.

## Checkpoint

Before lesson 10 you must have:

- `course/work/lesson09/` containing `sync_2ff.vhd`, `sync_2ff_tb.vhd`,
  and the `Makefile`, with `make sim` printing the two `R1 pass` lines
  (120/120 and no-glitches), the `R2 pass` line, and the completion
  message — no `FAIL` lines.
- The MTBF formula from memory — e^(t_r/τ) / (T_W·f_clk·f_data) — with
  the worked 12 MHz / 200 kHz numbers: ~480 metastable events per second
  at the first flop, MTBF beyond the age of the universe after one clock
  period of resolution.
- The rules of the road recited cold: single bits only, one synchronizer
  per signal at the border, never a bus bit-wise, Gray code or handshake
  for anything wider, levels longer than two clock periods.
- A one-sentence answer to: why does the TB allow 3 edges when simulation
  always shows 2? (The first flop of real silicon may resolve to the
  *old* value and recapture next edge — the allowance encodes physics the
  simulator doesn't model.)

Next: lesson 10 stands a simulated antenna oscillator on the far side of
this synchronizer and measures its frequency — where the gate-time
arithmetic meets radar's dwell-vs-Doppler-resolution trade head on.
