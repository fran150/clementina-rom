# ============================================================================
# Clementina ROM - top-level build
# ----------------------------------------------------------------------------
# Builds the kernel+BASIC image (kernel.bin) that MIA loads into base RAM.
# The kernel owns reset/video/console; MS BASIC owns the foreground after
# cold start.
#
# Bottom-anchored (2026-09 rework, reversing the earlier top-anchored/
# descending-loader design): the image starts at a fixed low address, $04B7
# (right after working RAM), kernel+WozMon first, then BASIC growing upward -
# reclaimable up through $BFFF by a loaded program that no longer needs
# BASIC. Anchoring at a fixed START lets ld65 place everything in one pass
# natively (no measure-then-relink dance needed - that was only required by
# the old design's fixed END anchor, where the start had to be computed
# backward from the total size first). See src/kernel/clementina.cfg and
# docs/memory-map.md.
# ============================================================================

CA65    ?= ca65
LD65    ?= ld65
CPU     ?= 65C02

KERNEL_DIR  := src/kernel
BASIC_DIR   := src/basic
MONITOR_DIR := src/monitor
BUILD_DIR   := build

KERNEL_SRC  := $(KERNEL_DIR)/kernel.s
KERNEL_CFG  := $(KERNEL_DIR)/clementina.cfg
KERNEL_BIN  := $(BUILD_DIR)/kernel.bin
BASIC_SRC   := $(BASIC_DIR)/msbasic.s
# WOZ monitor, linked into the image and reachable via KERN_WOZMON.
MONITOR_SRC := $(MONITOR_DIR)/wozmon-clementina.s

# Destinations for the kernel image. Override on the command line if your
# checkouts live elsewhere, e.g.  make install MIA_DIR=... EMU_DIR=...
MIA_DIR ?= /Users/fran150/development/pico/clementina-mia
EMU_DIR ?= /Users/fran150/development/go/clementina-6502
EMU_KERNEL := $(EMU_DIR)/assets/computer/mia/kernel.bin
MIA_KERNEL := $(MIA_DIR)/kernel.bin

.PHONY: all kernel clean install install-emulator install-firmware help

all: kernel

kernel: $(KERNEL_BIN)

$(KERNEL_BIN): $(KERNEL_DIR)/*.s $(KERNEL_DIR)/kernel.inc $(KERNEL_CFG) $(BASIC_DIR)/*.s $(MONITOR_SRC) | $(BUILD_DIR)
	$(CA65) --cpu $(CPU) -g -l $(BUILD_DIR)/kernel.lst -o $(BUILD_DIR)/kernel.o $(KERNEL_SRC)
	$(CA65) --cpu $(CPU) -D clementina -g -l $(BUILD_DIR)/basic.lst -o $(BUILD_DIR)/basic.o $(BASIC_SRC)
	$(CA65) --cpu $(CPU) -g -l $(BUILD_DIR)/wozmon.lst -o $(BUILD_DIR)/wozmon.o $(MONITOR_SRC)
	$(LD65) -C $(KERNEL_CFG) \
		-m $(BUILD_DIR)/kernel.map -Ln $(BUILD_DIR)/kernel.lbl -o $(KERNEL_BIN) \
		$(BUILD_DIR)/kernel.o $(BUILD_DIR)/wozmon.o $(BUILD_DIR)/basic.o
	@SIZE=$$(wc -c < $(KERNEL_BIN) | tr -d ' '); \
	sym() { awk -v n="$$1" '{ for (i=1;i<=NF;i++) if ($$i==n) { print $$(i+1); exit } }' $(BUILD_DIR)/kernel.map; }; \
	KLAST=0x$$(sym __KERNEL_LAST__); BLAST=0x$$(sym __BASICMEM_LAST__); \
	echo "Built $(KERNEL_BIN) ($$SIZE bytes): kernel+wozmon \$$04B7-$$(printf '0x%04X' $$((KLAST-1)))," \
		"basic $$(printf '0x%04X' $$KLAST)-$$(printf '0x%04X' $$((BLAST-1)))," \
		"heap $$(printf '0x%04X' $$BLAST)-\$$BFFF"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Copy the freshly built image into the emulator's embedded asset so the next
# `go build`/`go run` of the emulator picks it up.
install-emulator: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(EMU_KERNEL)
	@echo "Copied kernel.bin -> $(EMU_KERNEL)"
	@echo "NOTE: emulator must have kernelTargetAddress/kernelLoadBottomAddress=0x04B7 (registers.go)"

# Copy the image into the firmware tree (CMake turns it into kernel_data.c).
install-firmware: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(MIA_KERNEL)
	@echo "Copied kernel.bin -> $(MIA_KERNEL)"
	@echo "NOTE: firmware must have kernel_target_address/kernel_load_bottom_address=0x04B7 (mia.c)"

install: install-emulator

clean:
	rm -rf $(BUILD_DIR)

help:
	@echo "Clementina ROM"
	@echo
	@echo "  make            Build the kernel+BASIC image (build/kernel.bin)"
	@echo "  make install    Copy kernel.bin into the emulator asset"
	@echo "  make install-firmware  Copy kernel.bin into the MIA firmware tree"
	@echo "  make clean      Remove build artifacts"
	@echo
	@echo "The image is bottom-anchored: it always starts at \$$04B7 (kernel,"
	@echo "then WozMon, then BASIC growing upward, reclaimable through \$$BFFF),"
	@echo "loaded by an ascending MIA bootstrap. Needs kernel_target_address/"
	@echo "kernel_load_bottom_address=0x04B7 in both the MIA firmware (mia.c)"
	@echo "and the emulator (registers.go). See docs/memory-map.md."
