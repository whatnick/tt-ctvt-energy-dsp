YOSYS ?= yowasp-yosys
NEXTPNR ?= yowasp-nextpnr-ice40
ICEPACK ?= yowasp-icepack

TOP := tt_fpga_top
BUILD := build
SOURCES := tt_fpga_top.v $(wildcard ../src/*.v)
PCF := tt_fpga_fabricfox.pcf
FREQ_MHZ ?= 25

.PHONY: all bitstream report clean

all: bitstream

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/design.json: $(SOURCES) | $(BUILD)
	$(YOSYS) -q -p "synth_ice40 -dsp -top $(TOP) -json $@" $(SOURCES)

$(BUILD)/design.asc: $(BUILD)/design.json $(PCF)
	$(NEXTPNR) --up5k --package sg48 --pcf $(PCF) \
		--pcf-allow-unconstrained --seed 10 --freq $(FREQ_MHZ) \
		--json $< --asc $@ 2>&1 | tee $(BUILD)/nextpnr.log

$(BUILD)/tt_um_whatnick_ctvt_energy_dsp.bin: $(BUILD)/design.asc
	$(ICEPACK) $< $@

bitstream: $(BUILD)/tt_um_whatnick_ctvt_energy_dsp.bin

report: bitstream
	grep -E "ICESTORM_(LC|DSP|RAM|SPRAM):|Max frequency" $(BUILD)/nextpnr.log

clean:
	rm -rf $(BUILD)
