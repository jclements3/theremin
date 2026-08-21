# Lesson 00 — Setup & Hello, World

*Where we are.* This is the ground floor of a fifteen-lesson climb from "never
written HDL" to a digital theremin singing out of a Lattice iCE40 — and,
running quietly underneath the whole course, a working intuition for CW radar,
because a theremin *is* one. Before any of that, you need a toolchain that
works, an editor that talks to it, and proof — captured output, not vibes —
that a simulation runs on your machine. That proof takes the form of the
smallest possible VHDL testbench: no ports, no logic, one passing assert.
Everything you build in lessons 01–14 will run through exactly the pipeline
you stand up today.

## Objectives

- Activate the pinned OSS CAD Suite toolchain with the `fpga` alias and
  confirm `ghdl` resolves to `~/tools/oss-cad-suite/bin/ghdl`.
- Create your working directory `course/work/lesson00/` and build `hello_tb`
  from this lesson's code blocks.
- Run `make sim` and match the expected output line for line.
- Drive the whole loop from Emacs: dir-locals trust prompt, `M-x compile`,
  `<f6>` to recompile, `M-g n` to jump to an error.
- Deliberately break the build two ways (syntax error, failing assert) and
  read both failure shapes fluently.

## Concepts

### The toolchain, and why it is pinned

This course uses the open FPGA flow: **GHDL** simulates VHDL, **Yosys**
synthesizes it to a netlist, **nextpnr** places and routes for the iCE40, and
**icestorm** packs and flashes bitstreams. All four ship together in the
YosysHQ **OSS CAD Suite**, installed as one dated tarball at
`~/tools/oss-cad-suite/`. This repo pins release **2026-08-20** (GHDL
7.0.0-dev, Yosys 0.68, nextpnr 0.11.1).

Installation is already done on the course machine, and the full procedure —
tarball, machine split, USB rules for lab day — lives in `fpga/ROADMAP.md`
Phase 0. Read it once now; this lesson assumes it. Two details from it that
you will trip over if you skip them:

1. **Activation is per-shell, on purpose.** The suite bundles its own
   `python3` and libraries and activates by prepending itself to `PATH`. Put
   that in `.bashrc` and you've shadowed your system Python for every shell
   forever. Instead there's an alias in `~/.bashrc`:

   ```
   alias fpga='source ~/tools/oss-cad-suite/environment'
   ```

   Type `fpga` once per terminal before any `ghdl`/`yosys`/`make sim`. Your
   prompt grows a magenta `⦗OSS CAD Suite⦘` badge so you can see at a glance
   whether a shell is activated.

2. **The glibc shim.** The suite's GHDL runtime library was built against
   glibc ≥ 2.38, which renamed a few C library functions (`strtol` and
   friends grew `__isoc23_` prefixes). On hosts with older glibc — Ubuntu
   22.04 ships 2.35 — the *elaboration* (link) step fails with undefined
   `__isoc23_*` symbols. The fix is a tiny forwarding shim, prebuilt at
   `~/tools/glibc-isoc23-shim.o` and passed to the linker via
   `GHDL_ELAB_FLAGS` in every Makefile in this course. On hosts with glibc ≥
   2.38 the shim is unnecessary but harmless, so the Makefiles include it
   unconditionally. This is the one and only time the course explains it;
   from here on it's just a line in the Makefile.

### What GHDL actually does: analyze, elaborate, run

GHDL is not an interpreter. It compiles your VHDL to native code in three
distinct steps, and each step catches a different class of mistake:

```
  hello.vhd --(ghdl -a)--> work library --(ghdl -e)--> ./build/hello_tb --(run)--> output
              "analyze"    (build/*.cf,    "elaborate"   a real Linux       report/assert
               parse +      *.o files)      link an       executable        lines on stdout
               typecheck                    executable
```

- **Analyze** (`ghdl -a`) parses each file, checks syntax and types, and
  deposits compiled units into a *work library* (the `work-obj08.cf` file
  plus object files in `build/`). Syntax errors die here, with `file:line:col`
  locations.
- **Elaborate** (`ghdl -e`) picks a top-level unit — for us, always a
  testbench entity — resolves its instantiations, and links an ordinary
  executable. Missing entities and the glibc symbol problem die here.
- **Run** — the elaborated result is just a program. `./build/hello_tb`
  executes the simulation and prints every `report` and failed `assert` to
  stdout, tagged with source location and simulation time.

Keep this pipeline in your head: "which step failed?" is always the first
debugging question, and the Makefile echoes each command so you can see.

### The two files you'll build

**`hello.vhd`** holds an *entity* named `hello_tb` with no ports and an
*architecture* containing one *process*. Lesson 01 develops entities and
architectures properly; for today, the reading is:

- `entity hello_tb is end entity;` — a design unit with no connections to
  the outside world. That's the defining shape of a testbench: it is a closed
  universe that instantiates the design under test and stimulates it
  internally. (Here there is no DUT at all — the universe is empty except
  for one process.)
- `main : process ... end process;` — a labeled sequential block. Its
  statements execute in order, like a thread.
- `report "...";` — print a message, tagged `note` by default.
- `assert <condition> report "..." severity failure;` — evaluate the
  condition; if it is **false**, print the message at the given severity.
  Severities form a ladder (`note`, `warning`, `error`, `failure`) and the
  simulator can be told which rung is fatal — that's the
  `--assert-level=failure` flag in the Makefile, which means "stop the
  simulation only on `failure`-severity asserts." Lesson 02 builds the whole
  self-checking-testbench discipline on this ladder.
- `wait;` — suspend this process forever. A process with no wait statement
  restarts from the top endlessly at simulation time zero; you will watch
  that happen, on purpose, in Explore.

**`Makefile`** is the phase1 Makefile in miniature — same flags, same shim,
no synthesis targets (nothing to synthesize until lesson 05). Line by line:

- `GHDL_FLAGS = --std=08 --workdir=build` — VHDL-2008 everywhere, and the
  work library lives in `build/` so compiled artifacts never pollute the
  source directory. `make clean` is just `rm -rf build`.
- `GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o` — hands the shim
  object to the linker (`-Wl,x` means "pass `x` through to `ld`").
- `sim: | build` — the `|` makes `build` an *order-only* prerequisite:
  the directory must exist before the recipe runs, but its timestamp (which
  changes every time GHDL writes into it) never triggers a rebuild.
- The three recipe lines are exactly the analyze → elaborate → run pipeline
  above, with `--assert-level=failure` on the run.

### The Emacs loop

You will spend the course in one loop: edit VHDL, compile, jump to the first
error, fix, recompile. Emacs runs the whole loop without leaving the editor.

**First visit: the dir-locals trust prompt.** The repo root has a
`.dir-locals.el` that configures `vhdl-mode` to house style — 2-space
indentation, lowercase keywords, VHDL-2008 — and wires up a default compile
command. The first time you open a `.vhd` file under the repo, Emacs asks
whether to apply these local variables (they can run code, so it asks).
Answer **`!`** — apply and trust permanently. If you answered `n` in a hurry,
reopen the file with `C-x C-v RET` and answer `!` this time.

**`M-x compile`.** Prompts for a shell command, runs it in a `*compilation*`
buffer. The dir-locals default points at the phase1 exercise, so for course
work you edit the minibuffer to:

```
source ~/tools/oss-cad-suite/environment && make -C ~/projects/theremin/course/work/lesson00 sim
```

Why `source ...` again — didn't the `fpga` alias handle that? No: aliases
live in your interactive shell. `M-x compile` spawns a fresh non-interactive
shell that has never heard of `fpga`, so the compile command must activate
the toolchain itself. And `make -C <dir>` runs make *in* that directory, so
the command works no matter which file you're visiting.

**`<f6>`** is bound globally (in `~/.emacs`:
`(global-set-key (kbd "<f6>") #'recompile)`) to `recompile`: re-run the last
compile command, no prompting. After the first
`M-x compile`, the loop is just edit → `<f6>`.

**`M-g n`** (`next-error`) jumps point to the file and line of the next error
in the `*compilation*` buffer. GHDL's `file:line:col:` message format is
exactly what Emacs expects, so this Just Works. `M-g p` goes back; `M-g M-n`
/ `M-g M-p` are the same keys for the shift-averse.

That's the whole loop: `<f6>`, read the first error, `M-g n`, fix, `<f6>`.
You'll drill it below until it's reflex.

## Radar Connection

This lesson's radar content is not a signal-processing concept — it's a
discipline, and it's the one the others stand on: **qualified, pinned tools
and simulation evidence before hardware.**

Certification-grade FPGA work (DO-254, the airborne-hardware standard you'll
meet in radar programs) does not permit "whatever version of the tools was on
the machine that day." Tool versions are pinned, tool outputs are
independently verified, and every requirement is traced to a test whose
*captured output* is the evidence it passed. When a radar altimeter's FPGA
misbehaves at 30,000 feet, "it worked on my laptop" is not an artifact anyone
can review.

This course runs the hobbyist version of that regime from day one, because
the habits are free now and expensive to retrofit: one dated OSS CAD Suite
release for every machine that touches the project (`2026-08-20`, recorded in
`fpga/ROADMAP.md`); every lesson's expected output captured from a real run
and re-verified mechanically (`course/verify.sh` extracts the code blocks
from these lessons and re-runs them); simulation always before synthesis,
synthesis always before hardware. Even today's toy assert prints a
requirement-shaped line of evidence. By lesson 02 those lines will carry
requirement tags (`R1 pass: ...`), which is DO-254 traceability with the
paperwork sanded off.

The theremin connection proper starts in lesson 01. Today you're doing what a
radar shop calls tool qualification — and what everyone else calls making
sure the build isn't lying to you.

## Build

You are creating two files in your own working directory. `course/work/` is
git-ignored scratch space — it's yours. Verified reference copies of every
lesson's files live in `course/solutions/lesson00/`; resist peeking until
you've done the Explore exercises.

Create the directory, then enter each file below in Emacs, verbatim
(`C-x C-f ~/projects/theremin/course/work/lesson00/hello.vhd` and answer `!`
at the trust prompt).

**File: course/work/lesson00/hello.vhd**

```vhdl
-- hello.vhd — smallest possible GHDL sanity check.
-- A testbench needs no ports and no logic; this one just proves the
-- analyze -> elaborate -> run pipeline (including the glibc shim link)
-- works, and shows what a passing assert looks like.

entity hello_tb is
end entity hello_tb;

architecture sim of hello_tb is
begin

  main : process
  begin
    report "Hello, world - GHDL simulation is alive.";
    assert 2 + 2 = 4
      report "arithmetic is broken; seek shelter"
      severity failure;
    report "hello_tb complete: 1 check passed.";
    wait;  -- a testbench process must end in a wait or it loops forever
  end process;

end architecture sim;
```

**File: course/work/lesson00/Makefile**

```make
# Lesson 00 — minimal GHDL sim flow. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors tutorial/Makefile — same
# flags, same shim, no synthesis targets.

TB         = hello_tb
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim clean

sim: | build
	ghdl -a $(GHDL_FLAGS) hello.vhd
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --assert-level=failure

build:
	mkdir -p build

clean:
	rm -rf build
```

Makefile gotcha before you save: recipe lines (the indented commands under
`sim:`, `build:`, `clean:`) must start with a **tab**, not spaces. Emacs
`makefile-mode` inserts tabs for you and highlights suspicious lines; if make
greets you with `*** missing separator.  Stop.`, a recipe line has spaces.

## Run

All commands assume cwd = `course/work/lesson00/`. First, a terminal-side
green run; then the same thing from Emacs; then two deliberate failures.

Activate the toolchain in this shell (once per terminal):

```bash
fpga
```

Expected output: nothing — but the prompt gains the `⦗OSS CAD Suite⦘` badge,
and `which ghdl` now answers `~/tools/oss-cad-suite/bin/ghdl`.

### Green

```bash
make sim
```

Expected output:

```text
mkdir -p build
ghdl -a --std=08 --workdir=build hello.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/hello_tb hello_tb
./build/hello_tb --assert-level=failure
hello.vhd:14:5:@0ms:(report note): Hello, world - GHDL simulation is alive.
hello.vhd:18:5:@0ms:(report note): hello_tb complete: 1 check passed.
```

(`$(HOME)` expands to *your* home directory; `mkdir -p build` appears only on
the first run, when `build/` doesn't exist yet.) Read the two report lines
closely — that format follows you through the whole course:
`file:line:col`, then `@0ms` (simulation time — zero, since nothing here
waits), then the severity class, then your message. The passing assert on
line 15 printed nothing: asserts are silent when true.

Now the same run from Emacs: visit `hello.vhd`, `M-x compile`, and edit the
command to

```
source ~/tools/oss-cad-suite/environment && make -C ~/projects/theremin/course/work/lesson00 sim
```

The `*compilation*` buffer shows the identical output and finishes
`Compilation finished`. From now on, `<f6>` reruns it.

### Red drill 1 — syntax error, caught by analyze

In `hello.vhd`, delete the semicolon at the end of line 14 (the
`report "Hello, world...` line), save, and press `<f6>`.

Expected output (the interesting part of the `*compilation*` buffer, or of
`make sim` in the terminal):

```text
ghdl -a --std=08 --workdir=build hello.vhd
hello.vhd:14:54:error: missing ";" at end of statement
    report "Hello, world - GHDL simulation is alive."
                                                     ^
/home/clementsj/tools/oss-cad-suite/libexec/ghdl:error: compilation error
make: *** [Makefile:12: sim] Error 1
```

The pipeline died at analyze — nothing was elaborated, nothing ran. Now
press `M-g n`: point jumps into `hello.vhd`, line 14, column 54, exactly
where the semicolon belongs. Type it back, save, `<f6>`: green again.
That `<f6>` → `M-g n` → fix → `<f6>` cycle is the muscle memory this drill
exists to build.

### Red drill 2 — failing assert, caught at runtime

Now break the *logic* instead of the syntax: on line 15, change
`assert 2 + 2 = 4` to `assert 2 + 2 = 5`, save, `<f6>`.

Expected output:

```text
ghdl -a --std=08 --workdir=build hello.vhd
ghdl -e --std=08 --workdir=build -Wl,/home/clementsj/tools/glibc-isoc23-shim.o -o build/hello_tb hello_tb
./build/hello_tb --assert-level=failure
hello.vhd:14:5:@0ms:(report note): Hello, world - GHDL simulation is alive.
hello.vhd:15:5:@0ms:(assertion failure): arithmetic is broken; seek shelter
./build/hello_tb:error: assertion failed
  instance: .hello_tb(sim).main
./build/hello_tb:error: simulation failed
make: *** [Makefile:14: sim] Error 1
```

Compare the two failure shapes. Drill 1 never got past `ghdl -a`; here all
three pipeline steps ran and the *simulation itself* reported the failure,
with the assert's message, its source line, and the instance path of the
process that tripped it (`.hello_tb(sim).main` — entity, architecture,
process label). The severity was `failure` and the run flag is
`--assert-level=failure`, so the simulation stopped and make saw a nonzero
exit. This distinction — build failure vs. simulation evidence of a design
failure — is the difference between a typo and a bug, and every lesson after
this one is about manufacturing the second kind of failure on purpose until
the design stops producing it.

Restore `= 4`, save, `<f6>`, and confirm you're green before moving on.

## Explore

Solutions for this lesson are in `course/solutions/lesson00/` — attempt these
first.

1. **Run the pipeline by hand.** `make clean`, then run the three commands
   from the Makefile yourself, one at a time (`ghdl -a ...`, `ghdl -e ...`,
   `./build/hello_tb --assert-level=failure`), and `ls build` after each.
   Observe what each step deposits: analyze creates `work-obj08.cf` and
   `hello.o`; elaborate creates the `hello_tb` executable; run creates
   nothing — it's just a program printing to stdout.
2. **Break it on purpose: delete the `wait;`.** Remove line 19, `<f6>`, and
   watch the `*compilation*` buffer scroll `Hello, world` forever at `@0ms`.
   A process is not a function that returns — it's concurrent hardware
   behavior, and with no `wait` it re-executes endlessly without simulation
   time ever advancing. Kill it with `C-c C-k` in the `*compilation*` buffer
   (or `Ctrl-C` in a terminal), restore the `wait;`, and remember the
   symptom: *infinite output at @0ms means a process with no wait.*
3. **Walk the severity ladder.** With the assert re-broken to `2 + 2 = 5`,
   change `severity failure` to `severity note` and `<f6>`. The failed
   assert prints as `(assertion note)` — and the simulation carries on,
   prints the "1 check passed." line (now a lie), and exits **0**: make
   reports success. Only `failure`-severity asserts stop a run under
   `--assert-level=failure`. Sit with how dangerous that quiet green is;
   lesson 02's testbench conventions exist to make sure a failing check can
   never whisper. Restore the file (both the `= 4` and the
   `severity failure`) and finish green.

## Tips & Pitfalls

- **Emacs:** if `M-g n` says `No compilation errors` right after an
  obviously red build, your `*compilation*` buffer probably scrolled past a
  *second* compile you ran; `M-g n` walks the most recent one. Also learn
  `C-x `` ` (backtick) — the ancient synonym for `next-error` — because
  every Emacs tutorial you'll ever read uses it.
- **Emacs/vhdl-mode:** with the dir-locals trusted, `TAB` re-indents any
  line to house style (2 spaces) and `M-x vhdl-beautify-buffer` fixes a
  whole file. If indentation comes out at 3 spaces or keywords upcase
  themselves, you skipped the `!` at the trust prompt — dir-locals never
  applied.
- **Toolchain:** `ghdl: command not found` means this shell never ran
  `fpga`. The activation is per-shell; every new terminal, every tmux pane,
  starts cold. The `⦗OSS CAD Suite⦘` prompt badge is your indicator.
- **Toolchain:** an elaboration failure mentioning `__isoc23_strtol` (or any
  `__isoc23_*` symbol) means the glibc shim didn't get linked — check that
  `~/tools/glibc-isoc23-shim.o` exists and that your Makefile's
  `GHDL_ELAB_FLAGS` line matches this lesson's byte for byte. Full
  background: `fpga/ROADMAP.md` Phase 0.
- **Make:** recipe lines start with a tab. Spaces give you
  `*** missing separator.  Stop.` with no other clue.
- **GHDL:** stale build state after renaming entities can produce confusing
  elaboration errors; `make clean` costs half a second and is always the
  first thing to try when an error makes no sense.

## Checkpoint

Before lesson 01, all of the following are true:

- `fpga` in a fresh terminal changes the prompt, and `which ghdl` prints
  `/home/<you>/tools/oss-cad-suite/bin/ghdl`.
- `course/work/lesson00/` contains your `hello.vhd` and `Makefile`, and
  `make sim` there prints the two `(report note)` lines ending in
  `hello_tb complete: 1 check passed.` with exit status 0.
- Opening `hello.vhd` in Emacs shows no dir-locals prompt (you answered `!`
  once) and `TAB` indents to 2 spaces.
- `<f6>` reruns your compile command, and after re-breaking the line-14
  semicolon, `M-g n` lands point on `hello.vhd` line 14. (Fix it back;
  finish green.)
- You can say, without looking, which pipeline step (analyze / elaborate /
  run) catches: a missing semicolon; a `__isoc23_*` link error; a failing
  assert.
