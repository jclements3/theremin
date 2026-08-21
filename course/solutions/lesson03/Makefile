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
