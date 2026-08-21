# Lesson 04 — NCO simulation. Usage: make sim  (after sourcing
# ~/tools/oss-cad-suite/environment). Mirrors fpga/phase1/Makefile in
# miniature — same flags, same shim, sim only.

TB         = nco_tb
SRC        = nco.vhd nco_tb.vhd
GHDL_FLAGS = --std=08 --workdir=build
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave clean

sim: | build
	ghdl -a $(GHDL_FLAGS) $(SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure

# Opens the waveform even when the sim fails an assert — that's when you
# most need it. The '-' keeps make going past sim's nonzero exit.
wave:
	-$(MAKE) sim
	gtkwave build/$(TB).ghw &

build:
	mkdir -p build

clean:
	rm -rf build
