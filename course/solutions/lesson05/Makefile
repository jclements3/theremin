# Lesson 05 — RTL to bitstream. GHDL + Yosys + nextpnr + icestorm flow.
#
#   make sim          run the self-checking NCO testbench (do this FIRST)
#   make wave         sim + open the waveform in GTKWave
#   make synth        VHDL -> netlist (yosys via ghdl-yosys-plugin)
#   make bit          netlist -> place/route -> bitstream
#   make time         static timing estimate (icetime)
#   make prog         flash the board (iceprog) — lesson99 only
#   make clean
#
#   make BOARD=hx8k bit    for the iCE40-HX8K-B-EVN (default: icestick)

BOARD ?= icestick
TOP    = top
TB     = nco_tb

RTL    = nco.vhd top.vhd
TB_SRC = nco_tb.vhd

ifeq ($(BOARD),icestick)
  DEVICE  = hx1k
  PACKAGE = tq144
  PCF     = icestick.pcf
else ifeq ($(BOARD),hx8k)
  DEVICE  = hx8k
  PACKAGE = ct256
  PCF     = hx8k.pcf
else
  $(error unknown BOARD '$(BOARD)': use icestick or hx8k)
endif

GHDL_FLAGS = --std=08 --workdir=build

# OSS CAD Suite's libgrt.a targets glibc >= 2.38; on older hosts elaboration
# needs the __isoc23_* forwarding shim (harmless if glibc is new enough).
GHDL_ELAB_FLAGS = -Wl,$(HOME)/tools/glibc-isoc23-shim.o

.PHONY: sim wave synth bit time prog clean

# ---------- simulation (GHDL) ----------

sim: | build
	ghdl -a $(GHDL_FLAGS) $(RTL) $(TB_SRC)
	ghdl -e $(GHDL_FLAGS) $(GHDL_ELAB_FLAGS) -o build/$(TB) $(TB)
	./build/$(TB) --wave=build/$(TB).ghw --assert-level=failure

# Opens the waveform even when the sim fails an assert — that's when you
# most need it. The '-' keeps make going past sim's nonzero exit.
wave:
	-$(MAKE) sim
	gtkwave build/$(TB).ghw &

# ---------- synthesis -> bitstream ----------

synth: build/$(TOP).json
bit:   build/$(TOP).bin

build/$(TOP).json: $(RTL) | build
	yosys -m ghdl -p 'ghdl $(GHDL_FLAGS) $(RTL) -e $(TOP); synth_ice40 -top $(TOP) -json $@'

build/$(TOP).asc: build/$(TOP).json $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --pcf $(PCF) \
	              --json $< --asc $@ --freq 12

build/$(TOP).bin: build/$(TOP).asc
	icepack $< $@

time: build/$(TOP).asc
	icetime -d $(DEVICE) -p $(PCF) -t $<

prog: build/$(TOP).bin
	iceprog $<

build:
	mkdir -p build

clean:
	rm -rf build
