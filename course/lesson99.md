# Lesson 99 — Lab Day: Hardware Bring-Up

*Where we are.* Fourteen lessons of simulation are behind you: every module
has a green, requirement-tagged testbench, and `theremin_top` passed an
end-to-end simulation against a behavioural antenna model, fits in 38% of
an HX1K, and makes timing at 12 MHz with 3× margin. You have never touched
hardware — by design: nothing gets flashed that hasn't been simulated, and
now everything has been. Today, at the lab machine, you replace
`osc_model.vhd` with physics: a 74HC14, a handful of passives, and a rod of
aluminium. Four acts: set up the lab machine, flash lesson05's A440 as a
smoke test, bring up the analog oscillator, then flash `theremin_top` and
tune it until it plays. From here on the outputs that matter appear on a
scope screen and in the air, not in a terminal — this lesson describes
them and marks them **observe on bench** instead of pretending to quote
them.

## Objectives

- Set up a fresh lab machine — pinned toolchain, udev rule, and (on WSL2)
  the usbipd USB bridge — and prove it with a flashed A440 bitstream.
- Explain the 74HC14 relaxation oscillator from RC first principles and
  derive starting component values for ~200 kHz from f ≈ 1/(0.8·R·C).
- Breadboard the oscillator, verify its frequency and levels on a scope,
  and state why the antenna node must never be probed directly.
- Flash `theremin_top`, tune the free-running oscillator to 200 kHz so the
  open-hand pitch sits at C4, and play the instrument.
- Diagnose the four classic bring-up failures — no tone, wrong pitch,
  jittery pitch, no USB device — using the signal chain as a fault tree.

## Concepts

### What changes today

Simulation answered "is the design right?" The bench asks "is *this
assembly* of design, board, breadboard, cabling, and room right?" — and
the room is not a flourish; your body is about to be a circuit element.
Two habits carry the day:

1. **Smallest known-good thing first.** The A440 bitstream goes on before
   `theremin_top` because it needs no breadboard, no antenna, no tuning —
   just clock, configuration, one pin. If A440 sings, the whole
   toolchain-to-board path is proven, and every later failure is analog.
2. **One variable at a time.** When the theremin misbehaves, don't touch
   the breadboard and the PCF and the Makefile in one pass. The
   troubleshooting table in Run is ordered so each check isolates one
   link of the chain.

### Who may touch the USB port

The boards talk to the PC through an FTDI FT2232H: channel A wired to the
iCE40's SPI configuration interface, channel B to spare pins (lesson11's
UART, if you extend the design). `iceprog` speaks raw USB to that chip —
no serial-port driver — which is why two pieces of plumbing live in
`fpga/setup/`:

- **`53-lattice-ftdi.rules`** — a udev rule making FTDI devices
  (0403:6010/6014) world-accessible so `iceprog` runs without sudo.
  Needed on native Linux *and* inside WSL2.
- **`attach-fpga.sh`** — WSL2 only. WSL2 is a VM and sees no USB devices;
  `usbipd-win` (installed once from an elevated PowerShell) forwards one
  from Windows over USB/IP. The script finds the FTDI device in
  `usbipd list`, prints the one-time elevated `bind` step if needed, then
  attaches it. Attachment does not survive a replug — rerun the script
  every time the cable moves.

The dev machine (no Windows admin rights, so no usbipd-win) could never do
this — the machine split from `fpga/ROADMAP.md`, and the reason today
happens at the lab bench.

### The 74HC14 relaxation oscillator

The last black box in the project is the one `osc_model.vhd` has been
impersonating since lesson10. A 74HC14 is six inverters with
**Schmitt-trigger** inputs: the switching threshold depends on direction —
rising inputs must pass V_T+ before the output falls; falling inputs must
pass the lower V_T− before it rises. That hysteresis gap is what makes a
one-gate oscillator possible. Feed the output back to the input through a
resistor, hang a capacitor from the input to ground:

- Output high → R charges C toward V_CC; the input ramps up (an RC
  exponential, not a line) until it crosses V_T+ — output snaps low.
- Output low → R discharges C toward 0 V; the input ramps down to V_T− —
  output snaps high. Repeat forever.

The capacitor shuttles between the two thresholds, each half-period one RC
exponential segment, so from the charging law the period is

```
T = R·C · [ ln( (Vcc − V_T−) / (Vcc − V_T+) )  +  ln( V_T+ / V_T− ) ]
      \_________ charge half ________________/   \___ discharge half __/
```

Both logs are pure threshold ratios, so T = k·R·C with k set by where this
particular die's thresholds sit; typical 74HC14 datasheet thresholds give
k ≈ 0.8, hence the rule of thumb:

```
f  ≈  1 / (0.8 · R · C)
```

Treat 0.8 as *typical*, not a spec: thresholds vary part to part, with
supply and temperature, and the breadboard adds strays the formula never
heard of. Every value derived from it is a **starting value to tune on
the bench** — fine, since the instrument needs a tuning control anyway.

And this oscillator is the perfect capacitance sensor, because C is simply
*everything hanging on the input node*. Put the antenna there: its ~10 pF
to the room joins C, a hand approaching the rod adds ~0.1–1 pF more (a few
pF nearly touching), and f drops in proportion. The hand is one plate of a
capacitor, the rod the other — the physics claim the course opened with.

### Choosing the values

Work backwards from what the digital side was pinned to in lesson13:
nominal oscillator 200 kHz, so `freq_meas` (EDGES = 64) reports
P_REF = 64 · 12 MHz / 200 kHz = 3840 counts and `pitch_map` outputs
FCW_BASE — C4. Budget the node capacitance first:

```
C_node ≈ C_base 47 pF + antenna ~10 pF + gate input & strays ~5 pF ≈ 62 pF
```

The deliberate 47 pF base capacitor swamps the strays so the math stays
predictable, at the cost of some sensitivity (more on that below). Then:

```
R = 1 / (0.8 · f · C_node) = 1 / (0.8 · 200e3 · 62e-12) ≈ 101 kΩ
```

So: **R ≈ 100 kΩ, C_base = 47 pF** — R implemented as 82 kΩ fixed in
series with a 50 kΩ trimmer: 82–132 kΩ, roughly 152–245 kHz of tuning
range around the target. All starting values; the trimmer exists because
0.8 was a lie of convenience.

Two more parts matter. A **second inverter** on the same chip buffers the
oscillator — otherwise the FPGA pin, its jumper wire, and any scope probe
hang directly on the timing node and detune it. And the chip runs from the
board's **3.3 V** pin: the iCE40's I/O bank is 3.3 V and not 5 V-tolerant.

### Tuning: what mistuning sounds like

The mapping is linear: fcw = FCW_BASE + (P_REF − period)·2⁶. Feel out its
sensitivity with two numbers you can now derive yourself:

- **Mistuned oscillator.** Free-running at 195 kHz instead of 200 kHz
  (2.5% low — within part tolerance): period = 3938, so
  fcw = 93640 − 98·64 = 87368 → 244 Hz. A 2.5% oscillator error is about
  a semitone flat. That's the trimmer's job: hand away, trim until the
  open-hand pitch is C4 (261.6 Hz) — identically, until the oscillator
  free-runs at 200.0 kHz.
- **The hand.** 1 pF on 62 pF pulls f by 200 kHz/62 ≈ 3.2 kHz, the period
  by ~62 counts, fcw by ~3970 — about 0.7 semitone per pF. Arm's length
  couples a fraction of a pF; a hand 2 cm from the rod is several pF
  (parallel-plate: ε₀·0.01 m²/0.02 m ≈ 4.4 pF), so most of the playable
  range lives close to the rod, bunching like the iso-pitch shells in the
  original theremin explainer. Expect a few comfortable semitones with
  these values — Explore 1 trades stability for more.

The measurement side updates at 200 kHz/64 ≈ 3 kHz with a ~2.7 ms
smoothing constant, so tuning feels instantaneous; nothing digital changes
today.

## Radar Connection

Today is integration and test, and every radar program has this day —
usually several months of it, on an outdoor range, with more paperwork.
The moves you're making map one-to-one:

- **Known-good stimulus first.** Flashing A440 before the theremin is
  injecting a built-in test signal before trusting the antenna: it splits
  the world into "signal path works" and "sensor works" so the two can't
  alibi each other. Radars do the same with beacon transponders and
  injected test tones before the first live-target run.
- **Calibration against a physical reference.** Trimming the free-running
  oscillator to 200 kHz is zeroing the sensor — making the no-target
  reading match the design's assumed operating point (P_REF = 3840 is
  your boresight). Every fielded radar has the ritual: STALO alignment,
  range zero against a corner reflector at surveyed distance.
- **The environment is part of the system.** Your body detunes the
  antenna; the breadboard's strays live inside C_node; grounding changes
  the note. Radar's versions are multipath, radome losses, clutter — none
  of which appeared in the target model, all of which appear on the range.
  That is why `osc_model.vhd` was labelled a *model*: it earned you the
  right to debug only analog problems today, but it never claimed to be
  the room.
- **Fault isolation along the chain.** The troubleshooting table works
  because lesson14 registered every module boundary: each interface is an
  observable, so a failure bisects to one block — the same test-point-by-
  test-point discipline that debugs a radar chain from antenna to display.

And the instrument itself is the radar: a CW oscillator coupled into
space, a target modulating the return, a frequency measurement turning
that modulation into an output. The Epilogue makes this literal.

## Build

**No new files.** Lesson99 adds zero VHDL — the whole point. You flash
the bitstreams you already verified in `course/work/lesson05/` (A440) and
`course/work/lesson14/` (`theremin_top`); what you build today is the lab
machine environment and one analog circuit. (The course verification
harness skips this lesson's extraction step explicitly — there is no
`course/solutions/lesson99/`.)

**Bring to the bench** (from the ROADMAP shopping list):

- The board (iCEstick, or HX8K-B-EVN — see Tips for its jumper caveat),
  USB cable, breadboard, jumpers.
- 74HC14 (HC, not HCT); 82 kΩ, 50 kΩ trimmer, 100 Ω, 1 kΩ; 47 pF
  (C0G/NP0), 100 nF decoupling, 33 nF for the audio RC (lesson08's
  filter: 1 kΩ series + 33 nF to ground ≈ 4.8 kHz corner) and ~1 µF to
  AC-couple into the amplified speaker, and the smoke-test piezo.
  Lesson08's optional second stage (10 kΩ + 3.3 nF) if hiss bothers you.
- Antenna: 30–50 cm of stiff aluminium rod or a telescopic whip, on a
  screw terminal or banana jack mounted *at* the breadboard.
- Oscilloscope (≥ 10 MHz bandwidth is plenty for a 200 kHz square wave).

**The circuit** (starting values from Concepts — tune on bench):

```
              R: 82k fixed + 50k trimmer (start near mid: ~100k total)
          +------[ 82k ]----[ trim ]------+
          |                               |
          |       |\  U1A                 |       |\  U1B
   node N +-------|  >o-------------------+-------|  >o----[100R]---> FPGA osc_in
          |       |/ (in:1, out:2)                |/ (in:3, out:4)    (icestick pin 79 /
          |                                                            hx8k ball B2)
          +---||--- GND     C_base = 47 pF, C0G/NP0
          |
          +---o antenna rod (~10 pF to the room; the hand adds 0.1-1 pF,
                              a few pF when nearly touching)

   74HC14 power: pin 14 -> board 3.3 V pin (NOT 5 V), pin 7 -> GND,
   100 nF decoupling directly across pins 14/7.
   Unused inputs (pins 5, 9, 11, 13) tied to GND; their outputs float.

   audio_out (icestick pin 78 / hx8k ball B1) --[1k]--+--||--> amp -> speaker
                                                      | ~1 µF (AC couple)
                                                   33 nF
                                                      |
                                                     GND
```

Wiring notes, each one a lesson learned the annoying way:

- Everything on node N is timing capacitance: keep R, C_base, the antenna
  jack, and U1A's input within a couple of breadboard rows. Extra wire on
  node N is just extra C — fine; wire that *moves* is C that changes —
  pitch drift.
- The 100 Ω at the buffer output damps ringing on the jumper and limits
  current if the pin is ever misconfigured.
- Share grounds: 74HC14, board, and audio must be one net — a floating
  ground is the classic jittery, hum-modulated pitch.
- FPGA-side pins come from the lesson14 PCFs (`osc_in` pin 79 sits next to
  `audio_out` 78 on the iCEstick's J2 PMOD, which also provides 3.3 V and
  GND rails). On the HX8K, verify B1/B2 against the board schematic before
  wiring — the PCF comment says so.

## Run

Act 0 runs anywhere on the lab machine; acts 1–3 assume the `fpga` alias
has been run in this shell and `cwd` is the named work directory. Hardware
results are prose marked **observe on bench** — quoting a fake success
would defeat the point of the day.

### Act 0 — lab machine setup

Bring the repo over (git remote, rsync, or a USB stick — you need
`course/` and `fpga/` intact, your `course/work/` dirs, and
`~/tools/glibc-isoc23-shim.c` from the dev machine). Install the pinned
toolchain release, same as the dev machine (`fpga/ROADMAP.md` Phase 0):

```bash
mkdir -p ~/tools && cd ~/tools
tar xzf ~/Downloads/oss-cad-suite-linux-x64-20260820.tgz
echo "alias fpga='source ~/tools/oss-cad-suite/environment'" >> ~/.bashrc
```

(The tarball is the dated 2026-08-20 release from YosysHQ's
oss-cad-suite-build releases page; `tar` prints nothing on success.
Pinned tools mean a bitstream built here is the one you simulated there.)
Check whether the lab machine needs the glibc shim:

```bash
ldd --version | head -1
```

Expected output:

```text
ldd (Ubuntu GLIBC 2.35-0ubuntu3.14) 2.35
```

(That's the dev machine's line; yours names its own version. If it reports
≥ 2.38 you can skip the shim — the Makefiles pass it unconditionally and a
prebuilt `.o` is harmless either way.) If < 2.38, compile the shim you
copied over — silent on success:

```bash
gcc -c -O2 -fPIC -o ~/tools/glibc-isoc23-shim.o ~/tools/glibc-isoc23-shim.c
```

USB permissions, both machine types (silent on success; replug the board
afterwards so the rule applies):

```bash
sudo cp fpga/setup/53-lattice-ftdi.rules /etc/udev/rules.d/
sudo udevadm control --reload
```

**Native-Ubuntu lab machine:** that's it — plug the board in and go to
Act 1. **WSL2 lab machine:** Windows must hand the USB device to the VM.
One-time, from an elevated PowerShell:
`winget install --exact --id dorssel.usbipd-win`. Then, per plug-in, from
WSL:

```bash
cd fpga/setup && ./attach-fpga.sh
```

The script is self-diagnosing. Before usbipd-win is installed it says
(real output, captured on the dev machine):

```text
usbipd-win not found. Install from elevated PowerShell:
  winget install --exact --id dorssel.usbipd-win
```

On first use with the board plugged in, it prints the FTDI busid and the
one-time elevated `usbipd bind --busid <id>` command to run in PowerShell;
on later runs it attaches and proves WSL sees the chip — **observe on
bench**: `lsusb` showing an `0403:` device, then
`OK — 'make prog' should work now.`

### Act 1 — smoke test: flash lesson05's A440

Sim before hardware, even today — thirty seconds of ritual that rules out
a damaged toolchain install. From `course/work/lesson05/`:

```bash
make sim
```

Expected output:

```text
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

(Usual conventions, today and in Act 3: `mkdir -p build` precedes this on a
fresh checkout, and the lab machine's home directory replaces
`/home/clementsj` in the shim path.) Rebuild the bitstream:

```bash
make bit
```

Expected output:

```text
yosys -m ghdl -p 'ghdl --std=08 --workdir=build nco.vhd top.vhd -e top; synth_ice40 -top top -json build/top.json'
[...]
nextpnr-ice40 --hx1k --package tq144 --pcf icestick.pcf \
              --json build/top.json --asc build/top.asc --freq 12
[...]
Info: 	         ICESTORM_LC:      65/   1280     5%
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 160.69 MHz (PASS at 12.00 MHz)
[...]
Info: Program finished normally.
icepack build/top.asc build/top.bin
```

(Lesson05's numbers, reproduced on a different day — that's what pinned
tools buy. `make BOARD=hx8k bit` after a `make clean` if you're on the
HX8K.) Now the first hardware moment of the course:

```bash
make prog
```

If the USB plumbing *isn't* right, you'll get this (real output, captured
with no board attached — it's also troubleshooting row 4):

```text
iceprog build/top.bin
init..
Can't find iCE FTDI USB device (vendor_id 0x0403, device_id 0x6010 or 0x6014).
ABORT.
make: *** [Makefile:72: prog] Error 2
```

With the board attached and permissions in place — **observe on bench**:
`iceprog` reports the flash ID, erase/program/verify progress ending in
`VERIFY OK` and `cdone: high`; the board reconfigures, the red LED starts
its 0.72 Hz heartbeat, and pin 78 (series 1 kΩ straight to the piezo — no
RC needed for a square smoke test) sounds concert A. Check with a tuner
app: 440 Hz ± a few tenths. A440 plus heartbeat proves the entire digital
path; put the piezo aside.

### Act 2 — bring up the oscillator

Wire the Build schematic, but **don't connect the FPGA jumper yet** — the
oscillator gets verified alone first (one variable at a time). Power it
from the board's 3.3 V pin. **Observe on bench**, scope on the *buffer*
output (U1B pin 4 — never node N; the probe's own ~10 pF on a 62 pF node
pulls the frequency ~14%, so you'd be tuning to the probe):

- A square wave, rails 0–3.3 V, somewhere in 150–250 kHz across the
  trimmer's travel; set it near 200 kHz (5.0 µs period). Duty needn't be
  50% — `freq_meas` counts rising edges only.
- Hand toward the rod: frequency drops a few kHz, smoothly and
  monotonically; touching the rod drops it hard. That's the instrument,
  pre-digitization.
- If the frequency wanders when *you* move without approaching the
  antenna, fix grounding before proceeding (see the table).

Only then connect the buffered output through the 100 Ω to `osc_in`, and
move the audio path from piezo to 1 kΩ → RC → amplifier.

### Act 3 — flash theremin_top and tune

From `course/work/lesson14/`, the full ritual — sim, build, timing, flash:

```bash
make sim
```

Expected output:

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

```bash
make bit
make time
```

Expected output:

```text
yosys -m ghdl -p 'ghdl --std=08 --workdir=build sync_2ff.vhd freq_meas.vhd pitch_map.vhd nco.vhd sine_lut.vhd dsm_dac.vhd theremin_top.vhd -e theremin_top; synth_ice40 -top theremin_top -json build/theremin_top.json'
[...]
nextpnr-ice40 --hx1k --package tq144 --pcf icestick.pcf \
              --json build/theremin_top.json --asc build/theremin_top-icestick.asc --freq 12
[...]
Info: 	         ICESTORM_LC:     495/   1280    38%
[...]
Info: Max frequency for clock 'clk12$SB_IO_IN_$glb_clk': 35.86 MHz (PASS at 12.00 MHz)
[...]
Info: Program finished normally.
icepack build/theremin_top-icestick.asc build/theremin_top-icestick.bin
icetime -d hx1k -p icestick.pcf -t build/theremin_top-icestick.asc
[...]
Total number of logic levels: 94
Total path delay: 27.98 ns (35.74 MHz)
```

(`make BOARD=hx8k bit` for the big board — lesson14's Makefile keeps
per-board `.bin` names, so no clean is needed between boards.) Then:

```bash
make prog
```

**Observe on bench**: the same `iceprog` progress as Act 1, then the
heartbeat — and a tone. Now tune:

1. **Coarse, by scope**: body clear of the antenna, trim the oscillator
   to 200 kHz at the buffer output; the tone lands within a semitone or
   two of C4.
2. **Fine, by ear or tuner app**: trim until the open-hand tone reads
   261.6 Hz (C4) — you are steering `period` to exactly P_REF = 3840.
3. **Play.** Hand toward the rod: pitch falls, fastest near the rod (the
   1/C nonlinearity — iso-pitch shells bunching at the antenna). A few
   graceful semitones in the outer range, most of the action in the last
   few centimetres.
4. Re-trim after a few minutes in place — your body's *resting* position
   near the bench is part of the calibration, as is temperature.

Listen for the smoothing: pitch glides rather than steps, because fcw
closes 1/8 of the remaining error per measurement at ~3 kHz — lesson13's
2.7 ms alpha filter, audible as portamento.

**Troubleshooting.** Work the rows in order; each isolates one link.

| Symptom | First suspect | Check (observe on bench) | Fix |
|---|---|---|---|
| No tone at all | Audio path, not the theremin | Heartbeat LED blinking? Scope `audio_out` pin: dense ~12 MHz delta-sigma bitstream present? After the RC: a small sine? | No heartbeat → reflash (Act 1 again). Bitstream but no sound → RC/amp/speaker wiring, shared ground. HX8K + power-cycled → SRAM image lost, reflash (see Tips). |
| Tone stuck / wrong pitch, hand does nothing | Oscillator not reaching the FPGA | Scope U1B output: ~200 kHz square, 0–3.3 V? Same signal on the FPGA pin side of the 100 Ω? | Dead oscillator → power/decoupling/pin-count on the 74HC14. Signal fine but pitch frozen at C4-ish → `osc_in` on the wrong pin: `freq_meas` sees no edges, `valid` never strobes, `pitch_map` holds reset fcw. Check the PCF pin against the physical header. |
| Pitch present but wrong note with hand away | Free-running frequency ≠ 200 kHz | Scope: measure actual f. Each 2.5% of error ≈ 1 semitone (Concepts) | Trim to 200 kHz. Out of trimmer range → your C_node isn't 62 pF; recompute R from measured f and swap the fixed resistor. |
| Pitch jittery / warbles / hums | Ground and coupling | Does the jitter track mains hum (100/120 Hz flutter)? Does the pitch shift when you touch ground? | Common ground for board, 74HC14, and amp; shorten node-N wiring; move the antenna away from mains cables and the scope's own supply; decoupling cap actually across pins 14/7. Last resort: increase C_base (less sensitivity, less jitter — the alpha-filter trade in analog form). |
| `Can't find iCE FTDI USB device` | USB plumbing | `lsusb` show `0403:6010`? | Native: udev rule installed? replugged since? WSL2: rerun `setup/attach-fpga.sh` — attachment is lost on every replug. |

## Explore

No solutions directory to peek at today — the bench is the answer key.

1. **Trade stability for range.** Swap C_base 47 pF → 22 pF and retune (R
   must roughly double — check the formula, then the trimmer). C_node is
   now ~37 pF, so the same hand ΔC moves pitch nearly twice as far — and
   so does every stray. Observe on bench: wider playable range, more
   drift and jitter. This one capacitor is the instrument's
   sensitivity/stability knob.
2. **Break it on purpose — starve the measurement.** While it plays, pull
   the `osc_in` jumper. Predict from the chain, then observe: the tone
   *freezes* at its last pitch instead of going silent — no edges means
   `freq_meas` never completes a window, `valid` never strobes,
   `pitch_map` holds. Reconnect: pitch snaps back within milliseconds. A
   dropout produces a *stale* output, not an absent one — remember this
   the first time a radar track coasts through a fade.
3. **See the note being made.** Scope `audio_out` before the RC (a blur
   of 1-bit switching) and after it (a stepped sine); if your scope has
   FFT, watch the fundamental slide as you play with the delta-sigma
   noise pushed up and away — lesson08's noise shaping, live.
4. **Calibrate the model.** Measure free-run f, then f with your hand at
   10 cm, 2 cm, touching. Convert each to an equivalent `hand` value of
   `osc_model` (BASE_HZ 200 kHz, DELTA_HZ 20 kHz) and judge whether the
   lesson14 testbench swept a realistic range. That is target-model
   validation with range data.

## Tips & Pitfalls

- **3.3 V, always.** The 74HC14 runs happily at 3.3 V (thresholds scale
  with V_CC). Powering it at 5 V makes a healthier-looking square wave and
  overstresses a non-5V-tolerant FPGA input; the board's 3.3 V pin is
  right there.
- **HX8K-B-EVN ships jumpered for SRAM programming**: `iceprog` needs `-S`
  (`iceprog -S build/theremin_top-hx8k.bin`), the image loads into
  configuration RAM, and a power cycle erases it. Re-jumper per the board
  guide to program SPI flash like the iCEstick. "Worked yesterday, dead
  today, heartbeat gone" on the HX8K is almost always this.
- **Probe the buffer, not the node.** A ×10 scope probe adds ~10 pF; on
  node N that's a ~14% frequency pull, which the ×2⁶ pitch map amplifies
  to most of an octave — all of it vanishing when you lift the probe.
  Every oscillator measurement happens at U1B's output. (A bench
  universal: attaching the instrument changes the circuit; arrange to
  attach it where it doesn't.)
- **C0G/NP0 for C_base.** Class-2 dielectrics (X7R and friends) drift
  with temperature and voltage and are microphonic — in a circuit whose
  job is turning tiny capacitance changes into pitch, a capacitor that
  sings along is a failure mode.
- **lesson05's build artifacts don't encode BOARD** (lesson14's do): on
  the HX8K, `make clean` before `make BOARD=hx8k bit` in `lesson05/`, or
  you'll flash an HX1K bitstream at it — the lesson05 trap, now with
  hardware attached.
- **usbipd attachment is per-plug**: every cable event on a WSL2 machine
  means rerunning `fpga/setup/attach-fpga.sh` before `make prog`. The
  udev rule is one-time (but needs a replug to take effect).
- **Emacs, at the bench too:** `M-x compile` with `make sim && make bit
  && make prog` makes the whole verify-build-flash cycle one `<f6>`, with
  `iceprog`'s output landing in the compile buffer — a one-key
  edit-to-hardware loop for the Explore experiments.

## Checkpoint

The course's exit criteria — all bench facts, all yours now:

- The lab machine builds and flashes: `make sim` in `course/work/lesson05/`
  prints the lesson04/05 output verbatim, `make bit` reaches
  `Info: Program finished normally.`, `make prog` ends in `VERIFY OK`,
  and the heartbeat LED blinks afterwards.
- The A440 smoke test sounded, and a tuner app agreed with lesson05's
  FCW arithmetic to within a hertz.
- The 74HC14 oscillator free-runs within trimmer reach of 200 kHz and
  slides smoothly down as a hand approaches the rod — both facts measured
  at the buffer output, not node N.
- `theremin_top` is flashed and tuned: open-hand pitch at C4, pitch
  falling monotonically with hand approach, portamento audible and
  explainable (1/8 per step at ~3 kHz).
- You've run the troubleshooting table's chain logic on at least one real
  fault (Explore 2 counts) and can say which module boundary each row
  tests.

## Epilogue — the same chain, real radar

One evening's perspective before the breadboard goes back in the drawer:
on the shopping list sits an **HB100**, a $6 X-band Doppler module — a
10.525 GHz oscillator, patch antennas, and a mixer that beats the echo
against the transmitted carrier. It is a theremin with the wavelength
turned down: where your antenna's near field is perturbed by a hand's
capacitance, the HB100 illuminates the room and mixes the reflection with
its own carrier — lesson12's heterodyne, in hardware, against a moving
target. Its IF output is the Doppler difference: about 70 Hz per m/s of
target speed — *audio*, a signal your chain already handles. Comparator
into `osc_in`, and `sync_2ff → freq_meas` measures speed instead of hand
position; add `uart_tx` (lesson11) and plot walking speeds at your desk.
Same pipeline. Real radar. That demo, per `fpga/ROADMAP.md` Phase 7, is
the artifact this course was quietly building toward.

The limits you'll hit with it are the next course's syllabus — roadmap
Phases 5 and 6. A single mixer can't tell approaching from receding
(lesson12's image problem): fixing that takes a quadrature NCO and I/Q
downconversion — the **DDC** at the front of every modern receiver. One
tone at a time won't separate two targets: that takes a **serial radix-2
FFT**, where lesson10's dwell-versus-resolution tradeoff returns as CPI
design. And a fixed detection threshold fails when the room changes:
that's **CA-CFAR**, P_fa from first principles. Those designs want the
ECP5 on a ULX3S — same open toolchain, same Makefiles, three letters
different. The theremin was a CW radar that sings. Next, one that sees.
