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
