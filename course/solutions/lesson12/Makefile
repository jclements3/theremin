# Lesson 12 solutions — het_mixer (the heterodyne heart). Usage: make sim
# (after sourcing ~/tools/oss-cad-suite/environment). Mirrors
# tutorial/Makefile — same flags, same shim. No synthesis targets:
# het_mixer is the standalone physics-authentic path; theremin_top
# (lesson14) uses the measurement path instead.

TB         = het_mixer_tb
SRC        = nco.vhd het_mixer.vhd het_mixer_tb.vhd
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
