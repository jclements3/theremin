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
