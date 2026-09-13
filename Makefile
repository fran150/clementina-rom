# ============================================================================
# Clementina ROM - top-level build
# ----------------------------------------------------------------------------
# Builds the kernel+BASIC image (kernel.bin) that MIA loads into base RAM.
# The kernel owns reset/video/console; MS BASIC owns the foreground after
# cold start.
#
# 2026-09 RAM/ROM reorg: the image is top-anchored, ending exactly at $BFFF
# (immediately below I/O), instead of starting at a fixed low load base.
# Since the image's own size determines where it *starts*, and the linker
# needs concrete addresses at link time, this is a two-pass build: pass 1
# links with a throwaway placement just to measure the image's total size,
# then pass 2 relinks with the region's start computed as $C000 - <that
# size>, so the image's last byte always lands on $BFFF with no wasted
# address space. See src/kernel/clementina.cfg and docs/memory-map.md.
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
# WOZ monitor, linked into the image and reachable via KERN_WOZMON ($BFFA).
MONITOR_SRC := $(MONITOR_DIR)/wozmon-clementina.s

# BASIC's heap floor (RAMSTART2, src/basic/defines_clementina.s) - a small,
# stable constant now that the image no longer sits between working RAM and
# the heap. The two-pass link below fails loudly if a future image ever grows
# large enough to reach down into it.
RAMSTART2 := 0x04B7

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
	@# Pass 1: link with a throwaway placement, just to measure the image's
	@# total size (kernel + WozMon + BASIC + jump table).
	$(LD65) -C $(KERNEL_CFG) -D __CODE_START__=0x0400 -D __CODE_SIZE__=0x7C00 \
		-o $(BUILD_DIR)/kernel_measure.bin \
		$(BUILD_DIR)/kernel.o $(BUILD_DIR)/wozmon.o $(BUILD_DIR)/basic.o
	@SIZE=$$(wc -c < $(BUILD_DIR)/kernel_measure.bin | tr -d ' '); \
	START=$$(( 0xC000 - SIZE )); \
	if [ $$START -le $$(( $(RAMSTART2) )) ]; then \
		echo "ERROR: image ($$SIZE bytes) would start at $$(printf '0x%04X' $$START)," \
			"at or below RAMSTART2 ($(RAMSTART2)) - it would overlap BASIC's heap floor"; \
		exit 1; \
	fi; \
	START_HEX=$$(printf '0x%04X' $$START); \
	$(LD65) -C $(KERNEL_CFG) -D __CODE_START__=$$START_HEX -D __CODE_SIZE__=$$SIZE \
		-m $(BUILD_DIR)/kernel.map -Ln $(BUILD_DIR)/kernel.lbl -o $(KERNEL_BIN) \
		$(BUILD_DIR)/kernel.o $(BUILD_DIR)/wozmon.o $(BUILD_DIR)/basic.o; \
	echo "Built $(KERNEL_BIN) ($$SIZE bytes): image $$START_HEX-\$$BFFF," \
		"heap $(shell printf '0x%04X' $$(( $(RAMSTART2) )))-$$(printf '0x%04X' $$(( START - 1 )))"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Copy the freshly built image into the emulator's embedded asset so the next
# `go build`/`go run` of the emulator picks it up.
install-emulator: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(EMU_KERNEL)
	@echo "Copied kernel.bin -> $(EMU_KERNEL)"
	@echo "NOTE: emulator must have miaKernelTargetAddress=0xBFD0, miaKernelLoadTopAddress=0xBFFF (registers.go)"

# Copy the image into the firmware tree (CMake turns it into kernel_data.c).
install-firmware: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(MIA_KERNEL)
	@echo "Copied kernel.bin -> $(MIA_KERNEL)"
	@echo "NOTE: firmware must have kernel_target_address=0xBFD0, kernel_load_top_address=0xBFFF (mia.c)"

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
	@echo "The image is top-anchored: it always ends at \$$BFFF, loaded by a"
	@echo "descending MIA bootstrap. Needs kernel_target_address=0xBFD0 and"
	@echo "kernel_load_top_address=0xBFFF in both the MIA firmware (mia.c) and"
	@echo "the emulator (registers.go). See docs/memory-map.md."
