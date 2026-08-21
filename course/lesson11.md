# Lesson 11 — Telemetry: UART

*Where we are.* Lessons 09 and 10 built the input side of the chain: the
antenna oscillator crosses into the 12 MHz domain through `sync_2ff`, and
`freq_meas` turns it into a 24-bit period number with a `valid` strobe.
Those numbers now exist — inside the chip, where you cannot see them. This
lesson builds the hardware equivalent of `printf`: `uart_tx`, an 8N1 serial
transmitter that streams bytes to a laptop over one wire. It is a sideband,
not part of the audio path — `theremin_top` (lesson 14) does not include
it, and no later lesson wires it in for you; it stays available as a
sideband you can wire in yourself (Explore 4's stretch shows how), and on
the bench that wiring is the difference between "the pitch is wrong" and
"the measured period is 4 011 when it should be 3 840." Along the way: a
serial frame designed from nothing, a clock-division error budget, the
busy/strobe handshake you will meet again in every streaming interface,
and — the lesson's deepest point — why a testbench must *not* verify a
transmitter by reusing the transmitter's own logic.

---

## Session 11.1 — Designing 8N1 from Nothing (~75 min)

### Objectives

- Derive the 8N1 frame from first principles: why idle-high, why a start
  bit, why lsb-first, what the stop bit actually guarantees.
- Compute the baud divider for 12 MHz / 115 200, quantify the 0.16%
  frequency error it leaves, and show from the receiver's sampling geometry
  why it is harmless — and where the budget runs out.
- Implement a transmitter whose entire state is one 10-bit shift register
  and two counters — no FSM enum, no special cases for start or stop.
- State the busy/strobe handshake contract, including what happens to a
  strobe that arrives mid-frame — and why "ignored, by design, and tested"
  beats "undefined."
- Explain why the testbench decodes `txd` by mid-bit sampling at the *ideal*
  baud period instead of counting the DUT's divider — verification
  independence, made concrete.

### Concepts

#### The printf problem

Every debugging tool you own assumes a screen; the FPGA has pins. The
cheapest bridge is one pin wiggled slowly enough that a USB-serial adapter
(every lab bench has one) can decode it: a UART link. UART — universal
asynchronous receiver/transmitter — is two independent simplex channels;
we build only the transmit half, because the laptop end is somebody else's
silicon. "Asynchronous" is the load-bearing word: there is no clock wire.
Both ends agree on a bit rate ahead of time, and everything else — where a
byte starts, which bit is which — must be recoverable from the data wire
alone. So let's design that from nothing.

#### Designing a serial frame from nothing

One wire, two agreed constants (bit rate, byte width), no shared clock.
Three problems to solve.

**Problem 1: when does a byte start?** The line needs a distinguishable
"nothing happening" level — idle, high by convention (a survivor from
current-loop teletypes, where a broken wire reads permanently low and can
be flagged; UARTs still report it, as "break"). A byte then begins with one
bit-time of the opposite level: the **start bit**. Its falling edge is the
*only* timing reference the receiver gets; every later sample instant is
dead reckoning from that edge at the agreed rate.

**Problem 2: which data bit is which?** Eight data bits follow,
**lsb first** — shift-register economics, as you are about to build: the
transmitter shifts right and emits bit 0 first; the receiver shifts right
and bit 0 lands in place. Both ends are the same cheap structure. (It also
means a byte on an oscilloscope reads "backwards" — remember that on lab
day.)

**Problem 3: how does the receiver know it stayed in sync?** After d7, the
line returns high for at least one bit time: the **stop bit**. Two jobs.
It is a checkable prediction — if the ninth-and-a-half dead-reckoned
sample is not high, the frame was garbage and the receiver flags a
*framing error* instead of handing you a wrong byte. And it guarantees the
line is high before the next frame, so the next start bit has a falling
edge to detect. The scheme re-synchronizes on every start edge, which is
why clock error never accumulates beyond one frame — hold that thought.

The result, 8N1 (8 data bits, No parity, 1 stop bit), ten bit-times per
byte:

```
 idle      start  d0  d1  d2  d3  d4  d5  d6  d7  stop   idle
 ────────┐      ┌───────── lsb first ──────────┐ ┌─────────────
         └──────┘  (each slot = one bit time)  └─┘
         ^ falling edge: the receiver's only timing reference
```

At 115 200 baud that is 11 520 bytes per second, ceiling. (Parity is one
optional bit of error *detection* — it catches single flipped bits and
nothing more; over ten centimeters of bench wire it buys little, so "N".)

#### The baud divider and its error budget

The transmitter needs a tick every bit time: `DIV = CLK_HZ / BAUD` clocks.

```
12 000 000 / 115 200 = 104.1666...  =  104 + 1/6  → DIV = 104
```

Integer division truncates, so our bit lasts 104 clocks instead of 104⅙ —
the line actually runs at 12 MHz/104 = 115 384.6 baud, **0.16% fast**. Is
that a bug? Do the receiver's geometry honestly. The receiver detects the
start edge, waits 1.5 bit times, then samples every bit time after that —
aiming for the *middle* of each bit, the point farthest from both edges.
Sampling instants are multiples of the *ideal* bit time; our bits are 1/6
clock short each. The drift is cumulative across the frame:

```
 sample of d7 (worst data bit): 8.5 x 104.167 = 885.4 clocks after the edge
 center of the DUT's d7:        8.5 x 104     = 884.0 clocks
 drift: 1.4 clocks = 1.4% of a bit          (stop-bit sample: ~1.6%)
```

The sample point has to stay *inside* the intended bit, i.e. drift under
half a bit — 50%. We are at 1.4%. The frame then ends, the next start edge
re-zeros the dead reckoning, and the error never compounds. That is the
deep reason async serial works at all: framing converts a frequency error
into a bounded per-frame phase error.

Where does the budget run out? Solve the geometry for the worst sample
(d7): the transmitter can run fast until 8.5 ideal bit times overruns the
end of its ninth slot — DIV ≥ 99 against an ideal receiver, about 5% fast
(and DIV ≤ 110 slow). Real budgets are tighter — the receiver's clock errs
too, possibly the opposite way; its start-edge detection is quantized
(classic UARTs oversample at 16× baud, which is why the 1.8432 MHz crystal
exists: 16 × 115 200 exactly); rise times eat margin — so the folklore
figure is "keep each end within 1–2%." Our 0.16% clears it by an order of
magnitude. Explore 1 finds the cliff experimentally, exactly where this
arithmetic says.

And if 0.16% were too much, the fix is not a new crystal: accumulate the
remainder — every sixth bit 105 clocks instead of 104 — and the *average*
rate is exact. A fractional divider is a phase accumulator is an NCO is a
delta-sigma loop: lesson 04's machine, wearing its fourth hat. Explore 2
builds it.

#### busy/stb: the smallest flow-control contract

A frame takes 1 040 clocks to send; the rest of the design produces bytes
in one. Something must mediate, and the smallest honest contract is two
wires:

- **stb** (producer → uart): "here is a byte, send it" — held for one clock.
- **busy** (uart → producer): "a frame is on the wire; I am not listening."

The rules: `stb` is honored only when `busy` is low; the accepted byte is
latched at that clock edge (the producer may change `data` immediately
after); `busy` rises on the accept edge and falls when the stop bit
completes. The sharp edge: a strobe that arrives while busy is
**ignored** — not queued, dropped. That is a design decision, not a shrug:
a queue is more hardware that merely moves the overflow question one FIFO
deeper, while "dropped" is a behavior the producer can design against
(poll busy — or accept the loss; telemetry that drops a stale measurement
to send a fresh one is often *better*). What would be unacceptable is
*undefined*: a mid-frame strobe that corrupts the in-flight byte. So the
requirement list says ignored (R3), and the testbench attacks it —
hammering `stb` with a different byte mid-frame and demanding the frame
land intact with nothing queued behind it. This
producer-offers/consumer-throttles pattern is the seed of AXI-Stream's
valid/ready handshake; `busy` is just `not ready`.

#### One shift register is the whole transmitter

Here is the design insight that keeps `uart_tx` at three signals: **the
frame is data**. Don't build an FSM with IDLE/START/DATA/STOP states that
treats each field specially — build the whole 10-bit frame in a register
and shift it out:

```
 load on accept:   shreg = '1'  &  data(7..0)  &  '0'
                    bit9=stop     bits 8..1      bit0=start

 txd = shreg(0), always.  every DIV clocks: shift right, backfill '1'.

 emitted, in order: '0', d0, d1, ... d7, '1'   — an 8N1 frame, lsb first.
```

The start and stop bits are not states; they are payload. And the backfill
value is `'1'` — the idle level — so after ten shifts the register is all
ones and `txd` sits high *by falling through the same shift path*, no idle
special case anywhere. `bits_left` (10 down to 0) is the only notion of
state: zero means idle, and `busy` is just `bits_left /= 0`. Add the
down-counter that produces the every-DIV-clocks enable and that is the
entire module: a 10-bit shift register, a 4-bit counter, a 7-bit counter.
This "control as a datum" move — encode the sequence in a register's
contents rather than a state machine's cases — recurs constantly in good
RTL; you saw its cousin in lesson 06's sequencer.

#### Verifying without a mirror

Now the verification question, and it has teeth. The lazy testbench checks
`txd` by counting 104 clocks per bit — maybe even reusing the DUT's `DIV`
constant. That testbench is a mirror: it verifies that the design agrees
with itself. Build the transmitter msb-first by mistake and mirror it in
the checker — pass. Botch `DIV` and reuse the constant — pass. Every
shared assumption between DUT and checker is a bug class the testbench is
*structurally blind to*.

The rule: **verify at the interface, against an independent model of the
contract**. The contract is not "104 clocks per bit"; it is "8N1 at
115 200 baud, decodable by a standard receiver." So the testbench *is* a
standard receiver, built from the spec and nothing else:

- It measures in **time** — `BIT_TIME := 1 sec / BAUD`, the ideal
  8 680.6 ns — never in DUT clocks, and it never mentions `DIV`.
- It **hunts** for the falling start edge rather than knowing when to
  expect it, waits half a bit, checks the start is genuinely low, then
  samples mid-bit at ideal intervals, lsb first, and checks the stop.
- Expected values are the bytes the test *sent*, compared at the far end
  of the wire.

Notice what this buys beyond hygiene: the DUT's 0.16% truncation error is
now *inside the test loop*. The TB's ideal-time sampling drifts across the
DUT's slightly-fast bits exactly as a real receiver's would — the 1.4%
figure is exercised on every frame, not assumed away. If the divider error
ever grew past the budget, this testbench fails; a clock-counting one
never would. One severity note: "no start bit within 20 bit times" asserts
`failure` (nothing after it could mean anything), while decode mismatches
assert `error` and continue — one run, all verdicts, the lesson 02 ladder.

### Radar Connection

- **The instrumentation link is the first thing a radar grows.** Before a
  testbed detects anything, it streams housekeeping — AGC state, STALO
  lock flags, temperatures, per-dwell diagnostics — over exactly this kind
  of low-rate serial sideband (UART behind an RS-422 driver, more often
  than anyone admits). It is deliberately the dumbest link in the system,
  because it must work *before* anything else does and keep working while
  everything else fails. Lab day's `uart_tx` streaming raw `freq_meas`
  periods is precisely this: debugging the sensor through a channel
  simpler than the sensor.
- **Backpressure policy is a system requirement, not plumbing.** Our
  drop-when-busy rule is one point in a space every radar data path picks
  from explicitly: raw IQ capture stalls or drops by documented policy
  when the recorder falls behind; detection reports queue, because losing
  one matters. The busy/stb contract — and the habit of *testing* the
  overload case, as R3 does — scales up to AXI-Stream valid/ready between
  your FFT and your CFAR with the semantics unchanged.
- **The 0.16% analysis is a ppm budget in miniature.** Radar engineering
  runs on frequency-tolerance ledgers: oscillators specified in parts per
  million, error allocated across a chain, margin demonstrated — not
  vibes. We just did one: computed the error (1 600 ppm), derived the
  tolerance from the receiver's sampling geometry, showed margin. And the
  structural fix — re-synchronize on every frame so error cannot
  accumulate — is the same trick as re-referencing phase every CPI instead
  of demanding an oscillator that holds forever.
- **Independent verification is how test equipment earns trust.** You do
  not verify a transmitter with a receiver built from the transmitter's
  RTL — the both-ends-wrong trap. A radar's waveform is checked by a
  *separately calibrated* analyzer tracing to a different reference;
  DO-254 makes design/verification independence a formal requirement. Our
  TB decoding from the spec in ideal time units, blind to `DIV`, is that
  principle at benchtop scale — and the transferable habit: whenever your
  checker imports a constant from the DUT, ask who is checking the
  constant.

**Stopping point.** You should now be able to explain:

- why the start bit's falling edge is the receiver's *only* timing
  reference, and how re-synchronizing on every frame converts a frequency
  error into a bounded per-frame phase error instead of an accumulating one.
- where the divider's 0.16% error sits against the geometric budget — the
  d7 mid-bit sample drifting ~1.4% of a bit against a 50% limit — and why
  the arithmetic puts the cliff at DIV = 99 for an ideal receiver.
- why a strobe that arrives mid-frame is dropped rather than queued, and
  why "ignored, by design, and tested" is a contract while "undefined"
  is a bug factory.
- what class of bug a testbench that counts the DUT's `DIV` clocks per bit
  is structurally blind to, and why the checker must decode from the spec
  in ideal time units instead.

---

## Session 11.2 — Build & Run (~90 min)

### Build

Three files, byte-for-byte the reference implementation in
`course/solutions/lesson11/` — which exists, and which you should resist
opening until you have attempted the Explore exercises. Type them in; the
dissections below account for every line.

**File: course/work/lesson11/uart_tx.vhd**

```vhdl
-- uart_tx.vhd — 8N1 UART transmitter (telemetry link, lesson 11).
--
-- Requirements this module implements (verified in uart_tx_tb.vhd):
--   R1: 8N1 framing — each frame on txd is one low start bit, 8 data bits
--       lsb-first, one high stop bit, every bit lasting DIV = CLK_HZ/BAUD
--       clock cycles.
--   R2: the 8 data bits of the frame equal the byte on 'data' at the clock
--       edge where 'stb' was accepted.
--   R3: busy/strobe handshake — busy rises the cycle stb is accepted, stays
--       high through the stop bit, and stb is IGNORED while busy (no queue:
--       the in-flight payload is untouched and no second frame follows).
--   R4: txd idles high — out of reset and between frames.
--
-- Baud division: DIV = CLK_HZ / BAUD, integer truncation. At the defaults
-- 12_000_000 / 115_200 = 104 (exact quotient 104.17), so the line runs
-- 0.16 % fast — far inside the ~2 % per-frame budget an 8N1 receiver
-- tolerates, since the receiver re-synchronizes on every start edge.
--
-- Structure: a single 10-bit shift register holds the whole frame
-- ('1' stop & data & '0' start). txd is just shreg(0), so the line is
-- driven by a register at all times; idle is maintained by shifting in '1's.
-- bits_left doubles as the state: 0 = idle, nonzero = sending.
--
-- Radar analog: the instrumentation link. Every radar testbed streams
-- housekeeping (AGC state, detections, temperatures) over exactly this
-- kind of low-rate serial sideband; the busy/stb handshake is the same
-- backpressure contract you meet again in AXI-Stream's valid/ready.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLK_HZ : positive := 12_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;                     -- synchronous, active-high
    data : in  std_logic_vector(7 downto 0);  -- byte to send, latched on accept
    stb  : in  std_logic;                     -- request: send 'data' (1 clk)
    busy : out std_logic;                     -- '1' while a frame is on the wire
    txd  : out std_logic                      -- serial line, idles '1'
  );
end entity uart_tx;

architecture rtl of uart_tx is
  constant DIV : positive := CLK_HZ / BAUD;  -- clocks per bit

  -- frame shift register: (9)=stop, (8:1)=data msb..lsb, (0)=start.
  -- txd = shreg(0); shifting right emits start, d0..d7, stop in order.
  signal shreg     : std_logic_vector(9 downto 0) := (others => '1');
  signal bits_left : natural range 0 to 10 := 0;
  signal baud_cnt  : natural range 0 to DIV - 1 := 0;
begin

  txd  <= shreg(0);
  busy <= '1' when bits_left /= 0 else '0';

  shift : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        shreg     <= (others => '1');  -- line high: idle (R4)
        bits_left <= 0;
        baud_cnt  <= 0;
      elsif bits_left = 0 then
        -- idle: only here is stb honored (R3)
        if stb = '1' then
          shreg     <= '1' & data & '0';  -- stop & payload & start (R1, R2)
          bits_left <= 10;
          baud_cnt  <= DIV - 1;
        end if;
      elsif baud_cnt = 0 then
        -- one bit period elapsed: emit the next bit
        shreg     <= '1' & shreg(9 downto 1);  -- backfill '1' -> idle after stop
        bits_left <= bits_left - 1;
        baud_cnt  <= DIV - 1;
      else
        baud_cnt <= baud_cnt - 1;
      end if;
    end if;
  end process;

end architecture rtl;
```

Dissection:

- **`constant DIV`** is computed at elaboration from the generics — change
  `BAUD` at instantiation and everything re-derives. The truncation
  analyzed in Concepts happens on this line, silently: VHDL integer `/`
  rounds toward zero, and the header comment is where that decision is
  owned in writing.
- **The two concurrent assignments are the module's whole face.**
  `txd <= shreg(0)` means the line is a register output at every instant —
  no combinational path can glitch it (lesson 08's `bit_out` discipline).
  `busy` is a comparison against registered state, so it rises one delta
  after the accept edge and needs no register of its own.
- **`'1' & data & '0'`** — read it against the frame diagram: bit 0 (start)
  goes to the line immediately, `data` sits in bits 8..1 so the lsb is next
  in line, the stop bit waits at bit 9. One concatenation implements R1's
  field order and R2's latch at once; `data` is copied, so the producer may
  change it the very next cycle.
- **The priority ladder in the process** is the state machine, written as
  guards instead of an enum: reset beats everything; `bits_left = 0` is
  idle, and the strobe check lives *only* inside it — that placement is
  the entire implementation of "stb ignored while busy" (R3). Nothing
  elsewhere ever looks at `stb`, so there is nothing to get wrong
  mid-frame.
- **`baud_cnt = 0` is a clock enable, not a clock** — the shift branch runs
  once per DIV cycles while everything stays on the 12 MHz edge (the
  lesson 02 rule: one clock, many enables). Loading `DIV - 1` and firing
  on zero gives exactly DIV cycles per bit; loading `DIV` would be the
  fencepost error, every bit 0.96% long — which, satisfyingly, the
  testbench would still pass, and Explore 1 explains why.
- **The shift line** `'1' & shreg(9 downto 1)` retires the emitted bit and
  backfills idle level. Trace the endgame: after nine shifts the stop bit
  occupies `shreg(0)`; the tenth shift drops `bits_left` to 0 — busy falls
  exactly as the stop bit's DIV cycles complete — and `shreg(0)` is now a
  backfilled `'1'`, indistinguishable from the stop bit it replaces. Idle,
  stop, and the gap between frames are one value arriving by one path; R4
  costs zero gates.
- **The `natural range` subtypes** on `bits_left` and `baud_cnt` are free
  assertions: any bug that drives a counter out of range dies loudly at
  the assignment in simulation instead of wrapping quietly. Synthesis uses
  the range to size the registers — 4 and 7 bits.

**File: course/work/lesson11/uart_tx_tb.vhd**

```vhdl
-- uart_tx_tb.vhd — self-checking testbench for the 8N1 UART transmitter.
--
-- Verification approach: the TB is an INDEPENDENT serial decoder. It never
-- looks inside the DUT — it watches txd like a receiver would: find the
-- falling start edge, wait half a bit, then sample mid-bit at the IDEAL
-- baud period (1 sec / BAUD), not at the DUT's integer divider. The DUT's
-- divider truncation (104 vs 104.17 clocks/bit, 0.16 % fast) drifts the
-- sample points by ~1.4 % of a bit over the whole frame — mid-bit sampling
-- absorbs it, exactly as a real receiver's does.
--
-- Requirements verified (R1..R4 from uart_tx.vhd):
--   R1 framing: start bit low and stop bit high at their mid-bit samples.
--   R2 payload: 8 mid-bit samples, lsb first, equal the byte sent
--      (checked for 0x55, 0x00, 0xFF, 0xA5).
--   R3 handshake: busy rises on accept, is still high mid-frame while stb
--      is hammered with a different byte, falls after the stop bit; the
--      hammered byte neither corrupts the frame nor queues a second one.
--   R4 idle: txd stays high out of reset, between frames, and after the
--      ignored-stb test (watched over multi-bit windows, not spot-checked).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx_tb is
end entity uart_tx_tb;

architecture sim of uart_tx_tb is
  constant CLK_HZ   : positive := 12_000_000;
  constant BAUD     : positive := 115_200;
  constant CLK_PER  : time     := 83.333 ns;      -- 12 MHz
  constant BIT_TIME : time     := 1 sec / BAUD;   -- ideal baud period (8680.6 ns),
                                                  -- independent of the DUT divider
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal data : std_logic_vector(7 downto 0) := (others => '0');
  signal stb  : std_logic := '0';
  signal busy : std_logic;
  signal txd  : std_logic;
  signal done : boolean := false;
begin

  clk <= not clk after CLK_PER / 2 when not done else '0';

  dut : entity work.uart_tx
    generic map (
      CLK_HZ => CLK_HZ,
      BAUD   => BAUD
    )
    port map (
      clk  => clk,
      rst  => rst,
      data => data,
      stb  => stb,
      busy => busy,
      txd  => txd
    );

  main : process
    -- Watch txd for 'dur': any falling edge fails (line must idle high).
    procedure check_idle_high(dur : time; tag : string) is
    begin
      wait until txd = '0' for dur;  -- resumes early only if txd falls
      assert txd = '1'
        report tag & " FAIL: txd went low during an idle window"
        severity error;
    end procedure;

    -- Offer one byte for exactly one clock; busy must rise (R3).
    procedure send_byte(b : std_logic_vector(7 downto 0)) is
    begin
      data <= b;
      stb  <= '1';
      wait until rising_edge(clk);
      stb  <= '0';
      wait for 1 ns;  -- let post-edge values settle
      assert busy = '1'
        report "R3 FAIL: busy not asserted on the accept edge"
        severity error;
    end procedure;

    -- Decode one frame off txd by mid-bit sampling (R1, R2). With
    -- poke=true, hammer stb with the complement byte during data bits
    -- 2..5 — the DUT must ignore it (R3).
    procedure decode_frame(expected : std_logic_vector(7 downto 0);
                           poke     : boolean := false) is
      variable rx : std_logic_vector(7 downto 0);
    begin
      if txd = '1' then
        wait until txd = '0' for 20 * BIT_TIME;  -- hunt for the start edge
      end if;
      assert txd = '0'
        report "R1 FAIL: no start bit within 20 bit times"
        severity failure;
      wait for BIT_TIME / 2;
      assert txd = '0'
        report "R1 FAIL: start bit not low at mid-bit"
        severity error;
      for i in 0 to 7 loop
        wait for BIT_TIME;
        rx(i) := txd;  -- 8N1 sends the lsb first
        if poke and i = 1 then      -- R3: offer a different byte mid-frame
          data <= not expected;
          stb  <= '1';
        end if;
        if poke and i = 5 then
          assert busy = '1'
            report "R3 FAIL: busy dropped mid-frame"
            severity error;
          stb <= '0';
        end if;
      end loop;
      wait for BIT_TIME;  -- mid-stop
      assert txd = '1'
        report "R1 FAIL: stop bit not high at mid-bit"
        severity error;
      report "R1 pass: start/stop framing ok (byte 0x" & to_hstring(expected) & ")";
      assert rx = expected
        report "R2 FAIL: sent 0x" & to_hstring(expected) &
               " but decoded 0x" & to_hstring(rx)
        severity error;
      report "R2 pass: decoded payload 0x" & to_hstring(rx) & " matches";
    end procedure;

    -- After mid-stop, busy must fall when the stop bit completes (R3).
    procedure end_frame is
    begin
      wait until busy = '0' for 2 * BIT_TIME;
      assert busy = '0'
        report "R3 FAIL: busy not released after the stop bit"
        severity error;
      wait until rising_edge(clk);
    end procedure;
  begin
    -- synchronous reset, then release
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert busy = '0'
      report "R3 FAIL: busy asserted out of reset"
      severity error;

    -- R4: line idles high before anything is sent
    check_idle_high(4 * BIT_TIME, "R4");
    report "R4 pass: txd idles high out of reset";

    -- R1/R2: alternating, all-zeros and all-ones payloads
    send_byte(x"55");  decode_frame(x"55");  end_frame;
    report "R3 pass: busy rose on accept and fell after the stop bit";
    send_byte(x"00");  decode_frame(x"00");  end_frame;
    send_byte(x"FF");  decode_frame(x"FF");  end_frame;

    -- R4: line returns to idle between frames
    check_idle_high(3 * BIT_TIME, "R4");
    report "R4 pass: txd idles high between frames";

    -- R3: hammer stb with 0x5A while 0xA5 is in flight — must be ignored
    send_byte(x"A5");  decode_frame(x"A5", poke => true);  end_frame;
    check_idle_high(3 * BIT_TIME, "R3");
    report "R3 pass: stb while busy ignored (payload intact, nothing queued)";

    report "uart_tx testbench complete (any FAILs are listed above)";
    done <= true;
    wait;
  end process;

end architecture sim;
```

Dissection:

- **The header leads with the verification approach**, and its first
  sentence is this lesson's thesis: the TB is an independent decoder.
  Audit the claim by grepping the file for `DIV` — nothing.
- **Four procedures, four verbs** — watch, offer, decode, close — declared
  inside the process (the lesson 04 pattern) so they can drive signals and
  consume time. The test sequence at the bottom then reads like the
  contract itself: send, decode, end; the plumbing is out of the way.
- **`check_idle_high` verifies a *negative* over a window.**
  `wait until txd = '0' for dur` resumes early only if a falling *event*
  occurs; otherwise it sleeps out the full window. One line watches four
  bit-times continuously — a spot check ("is it high now?") would sleep
  through a glitch. This is how you assert "nothing happens," which is as
  much a requirement as anything that does.
- **`decode_frame` is the spec, executable.** The `if txd = '1'` guard
  exists because `wait until` needs an event — if the start edge already
  fired, waiting for another would hang; severity `failure` on a missing
  start bit stops the run, because every later check would be noise. Then
  half a bit, verify the start is real, and eight `rx(i) := txd` samples —
  the index *is* the lsb-first rule, bit 0 filled first. All in ideal
  `BIT_TIME` units: the drift analysis is being exercised, not assumed.
- **The poke is surgical.** During the hammered frame, `stb` is held with
  the *complement* byte from the mid-bit sample of d1 to the mid-bit
  sample of d5 — four bit-times, hundreds of clocks — and the frame must
  still decode as the original (R2 catches corruption), busy must still
  be high at mid-d5, and the post-frame `check_idle_high` catches
  the other failure mode: a queued second frame would put a start edge in
  the idle window. Three independent asserts triangulate "ignored."
- **`end_frame` waits for busy's fall with a bound** — 2 bit-times, not
  forever — so a busy-stuck-high bug fails the assert instead of hanging
  the simulation. Bounded waits are what make a failing run *diagnosable*:
  it always terminates, with the ledger printed.
- **The byte choices are an attack set, not a sample.** 0x55 on the wire is
  alternating — maximum edges, the timing torture test; 0x00 holds the
  line low for nine straight bit-times, so only correct dead reckoning
  finds the stop bit; 0xFF is the opposite degenerate (only the start bit
  is low); 0xA5 is asymmetric, so any bit-order or off-by-one scramble
  decodes to a visibly different value instead of accidentally matching.

**File: course/work/lesson11/Makefile**

```make
# Lesson 11 — uart_tx + decoding testbench. Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# uart_tx joins a top-level build only if you wire it in yourself
# (Explore exercise); the course's theremin_top does not use it.

TB         = uart_tx_tb
SRC        = uart_tx.vhd uart_tx_tb.vhd
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

The familiar minimal flow: analyze DUT before TB (analysis order is
load-bearing, lesson 04), elaborate with the glibc shim, run with
`--assert-level=failure` so `error` asserts report and continue. Sim-only:
`uart_tx` reaches hardware only if you wire it into a top level yourself —
see Explore 4's stretch goal.

### Run

From `course/work/lesson11/` (toolchain environment sourced — the `fpga`
alias from lesson 00):

```bash
make sim
```

Expected output:

```text
ghdl -a --std=08 --workdir=build uart_tx.vhd uart_tx_tb.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/uart_tx_tb uart_tx_tb
./build/uart_tx_tb --assert-level=failure
uart_tx_tb.vhd:148:5:@34931554720fs:(report note): R4 pass: txd idles high out of reset
uart_tx_tb.vhd:117:7:@117424471272fs:(report note): R1 pass: start/stop framing ok (byte 0x55)
uart_tx_tb.vhd:122:7:@117424471272fs:(report note): R2 pass: decoded payload 0x55 matches
uart_tx_tb.vhd:152:5:@121707846500fs:(report note): R3 pass: busy rose on accept and fell after the stop bit
uart_tx_tb.vhd:117:7:@204257457272fs:(report note): R1 pass: start/stop framing ok (byte 0x00)
uart_tx_tb.vhd:122:7:@204257457272fs:(report note): R2 pass: decoded payload 0x00 matches
uart_tx_tb.vhd:117:7:@291090443272fs:(report note): R1 pass: start/stop framing ok (byte 0xFF)
uart_tx_tb.vhd:122:7:@291090443272fs:(report note): R2 pass: decoded payload 0xFF matches
uart_tx_tb.vhd:158:5:@321415485165fs:(report note): R4 pass: txd idles high between frames
uart_tx_tb.vhd:117:7:@403923325272fs:(report note): R1 pass: start/stop framing ok (byte 0xA5)
uart_tx_tb.vhd:122:7:@403923325272fs:(report note): R2 pass: decoded payload 0xA5 matches
uart_tx_tb.vhd:163:5:@434248367165fs:(report note): R3 pass: stb while busy ignored (payload intact, nothing queued)
uart_tx_tb.vhd:165:5:@434248367165fs:(report note): uart_tx testbench complete (any FAILs are listed above)
```

(A first run also prints `mkdir -p build` at the top.) Read the timestamps
— they are the frame timing, audited. The first R4 pass lands at 34.9 µs:
reset plus the 4-bit-time idle window (4 × 8.68 µs). Each decode completes
about 87 µs after its send — ten bits at ~8.7 µs — and each "R2 pass"
shares its timestamp with its "R1 pass": both fire at the mid-stop sample,
where the frame's verdict is complete. Total: 434 µs of simulated time for
four bytes. Serial is slow; that is Explore 4's subject.

**Stopping point.** You should now be able to explain:

- why the whole 8N1 frame lives in one 10-bit shift register — start and
  stop bits as payload, not states — and how backfilling `'1'` on every
  shift makes the idle line fall out of the same path with no special case.
- why the `stb` check living *only* inside the `bits_left = 0` branch is
  the entire implementation of "strobe ignored while busy," with nothing
  elsewhere to get wrong mid-frame.
- why loading `DIV - 1` and shifting on zero yields exactly DIV clocks per
  bit, and why loading `DIV` instead would be a fencepost error the
  testbench would still pass.
- why each "R2 pass" line in the log shares its timestamp with its "R1
  pass" — both verdicts complete at the mid-stop sample — and why four
  bytes cost 434 µs of simulated time.

---

## Session 11.3 — Explore & Checkpoint (~75 min)

### Explore

Attempt these before opening `course/solutions/lesson11/`.

1. **Break it: find the baud-error cliff.** Concepts claims an ideal
   receiver tolerates the transmitter fast until the d7 sample overruns its
   bit: 8.5 × 104.167 < 9 × DIV, i.e. DIV ≥ 99. Test the claim. Change the
   constant to `CLK_HZ / BAUD - 5` (DIV = 99, 5% fast): everything still
   passes. Now `- 6` (DIV = 98): exactly two decodes fail —
   `R2 FAIL: sent 0x55 but decoded 0xD5` and `sent 0x00 but decoded 0x80`
   — while 0xFF and 0xA5 still pass. Work out why before reading on: at
   DIV = 98 only the *last* sample (d7, the most drifted) has slipped into
   the stop bit, so it reads '1'; bytes whose d7 is already 1 decode
   "correctly" by luck. A marginal link doesn't fail — it fails
   *pattern-dependently*, the nastiest way. Note each FAIL is followed by
   the unconditional progress line with the decoded value (the lesson 04
   assert/report pairing), and that `make sim` still exits 0 — see Tips.
   Restore and re-run to green.
2. **Build the fractional divider.** Make the average bit exactly 104⅙
   clocks: widen the counter (`baud_cnt : natural range 0 to DIV`), add
   `signal sextile : natural range 0 to 5 := 0;`, and make every sixth bit
   one clock longer — in the accept branch load `baud_cnt <= DIV;` (105
   clocks: DIV..0) and `sextile <= 1;`; in the shift branch replace the
   reload with: if `sextile = 0` load `DIV` and set sextile to 1, else
   load `DIV - 1` and advance `sextile <= (sextile + 1) mod 6;`. Run: all
   thirteen passes, timestamps a hair later (each frame ~2 clocks longer).
   The TB can't applaud — 0.16% was already inside tolerance — but you
   have built a first-order fractional-N divider: the same
   accumulate-and-overflow idea as the NCO and the delta-sigma DAC, and
   the standard move when a clock doesn't divide your baud. Restore the
   original (the solution doesn't carry it).
3. **See a frame.** Add `--wave=build/$(TB).ghw` to the run line, re-run,
   open in GTKWave, and zoom into the 0x55 frame: the line alternates
   every bit (start 0, then 1,0,1,0... — lsb-first does *not* read "55"
   left to right), `busy` is a clean 10-bit-wide envelope, and cursors
   across one bit measure 8.667 µs — 104 clocks, not the ideal 8.681. You
   are looking at the 0.16% with your own eyes. Then find the poke on the
   0xA5 frame: `stb` high for four bit-times (mid-d1 to mid-d5), `txd`
   serenely ignoring it. Remove the flag afterwards.
4. **Paper: can telemetry keep up with the sensor?** At lesson 10's
   defaults the measurement rate is one `valid` per 3 840 clocks — 3 125
   measurements/s. Streaming each 24-bit period raw is 3 bytes: 9 375 B/s,
   fits under 11 520 with 19% headroom — but add a single sync/header byte
   per measurement (and you must, or the stream has no framing above the
   byte level: which of three bytes is the msb?) and you need 12 500 B/s.
   The link saturates. Design your way out on paper — decimate to every
   second measurement, or send the 16-bit offset from P_REF = 3840 plus a
   header — and state what each costs. Budgeting the link is the whole job
   of telemetry engineering. *Stretch, for lab day:* wire `uart_tx` to
   `freq_meas` (valid → stb, plus a byte-serializing FSM) in a copy of
   lesson 05's top — the iCEstick routes two FPGA pins to its FTDI's
   second channel, so `txd` can reach your laptop's `/dev/ttyUSB*` — and
   watch periods stream as you wave your hand.

### Tips & Pitfalls

- **Emacs / vhdl-mode: never type a port map again.** Put point in the
  `uart_tx` entity and hit `C-c C-p C-w` (`vhdl-port-copy`); then in the
  testbench, `C-c C-p C-i` (`vhdl-port-paste-instance`) drops a complete,
  correctly-associated instantiation, and `C-c C-p C-t` goes further and
  generates a whole testbench skeleton. Port-map typos — swapped
  associations, a forgotten signal — are among the most tedious bugs in
  hand-written TBs, and this feature deletes the category.
- **Toolchain gotcha: `make sim` exits 0 even when R-FAIL lines print.**
  `--assert-level=failure` makes only severity `failure` fatal to the exit
  code; `error` asserts report and continue by design (one run, every
  verdict). You saw it in Explore 1: two R2 FAILs, exit status 0. The log
  is the verdict, not `$?` — read it, or `make sim 2>&1 | grep FAIL`. If
  you ever script this flow into CI, that grep is load-bearing.
- **`wait until <cond> for <time>` resumes early only on an *event*.** If
  `txd` is already '0', `wait until txd = '0'` still blocks until the next
  transition to '0' — a condition that is true but eventless does not
  release the wait. That is why `decode_frame` guards the hunt with
  `if txd = '1'`, and why `check_idle_high` works as a window watcher.
  Forget this semantics and a testbench hangs, silently.
- **Hold `stb` for one clock — or know exactly why you didn't.** `stb` is
  *level*-sampled whenever the transmitter is idle: hold it high across a
  frame boundary and the moment busy falls, a second frame starts with
  whatever `data` then holds. The poke test passes only because the TB
  drops `stb` at mid-d5, before the frame ends. In your own producers, pulse
  stb for one cycle (lesson 10's `valid` is already shaped like this) or
  gate it with `not busy`.
- **On the bench, "UART garbage" means rate mismatch until proven
  otherwise:** wrong `BAUD` generic, wrong terminal setting, or a `CLK_HZ`
  that doesn't match the crystal — byte salad that changes character with
  the rate error, exactly like Explore 1's pattern-dependent failures. Two
  scope cursors across the start bit settle it: measure the bit, divide
  into 1 second, and argue with no one.

### Checkpoint

Before lesson 12 you must have:

- `course/work/lesson11/` containing `uart_tx.vhd`, `uart_tx_tb.vhd`, and
  the `Makefile`, with `make sim` printing all thirteen `pass`/complete
  report lines and no `FAIL` lines.
- An 8N1 frame drawn from memory — idle high, start low, eight data bits
  *lsb first*, stop high — with the falling start edge marked as the
  receiver's only timing reference.
- The divider ledger, cold: DIV = 104 from 12 MHz / 115 200 (exact quotient
  104⅙), line 0.16% fast, worst mid-bit sample drift ~1.4% of a bit against
  a 50% geometric limit, error re-zeroed by every start edge.
- A one-sentence answer to "why doesn't the testbench count 104 clocks per
  bit?" that uses the word *independent* — and names what class of bug a
  mirroring testbench can never see.

Next: lesson 12, the heterodyne heart — two oscillators, an XOR, and the
discovery that the theremin has been a CW radar all along.
