# ============================================================================
# Clementina ROM - top-level build
# ----------------------------------------------------------------------------
# Builds the kernel+BASIC image (kernel.bin) that MIA loads into base RAM at the
# load base ($0400). The kernel owns reset/video/console; MS BASIC owns the
# foreground after cold start.
# ============================================================================

CA65    ?= ca65
LD65    ?= ld65
CPU     ?= 65C02

KERNEL_DIR := src/kernel
BASIC_DIR  := src/basic
BUILD_DIR  := build

KERNEL_SRC := $(KERNEL_DIR)/kernel.s
KERNEL_CFG := $(KERNEL_DIR)/clementina.cfg
KERNEL_BIN := $(BUILD_DIR)/kernel.bin
BASIC_SRC  := $(BASIC_DIR)/msbasic.s

# Destinations for the kernel image. Override on the command line if your
# checkouts live elsewhere, e.g.  make install MIA_DIR=... EMU_DIR=...
MIA_DIR ?= /Users/fran150/development/pico/clementina-mia
EMU_DIR ?= /Users/fran150/development/go/clementina-6502
EMU_KERNEL := $(EMU_DIR)/assets/computer/mia/kernel.bin
MIA_KERNEL := $(MIA_DIR)/kernel.bin

.PHONY: all kernel clean install install-emulator install-firmware help

all: kernel

kernel: $(KERNEL_BIN)

$(KERNEL_BIN): $(KERNEL_DIR)/*.s $(KERNEL_DIR)/kernel.inc $(KERNEL_CFG) $(BASIC_DIR)/*.s | $(BUILD_DIR)
	$(CA65) --cpu $(CPU) -g -l $(BUILD_DIR)/kernel.lst -o $(BUILD_DIR)/kernel.o $(KERNEL_SRC)
	$(CA65) --cpu $(CPU) -D clementina -g -l $(BUILD_DIR)/basic.lst -o $(BUILD_DIR)/basic.o $(BASIC_SRC)
	$(LD65) -C $(KERNEL_CFG) -m $(BUILD_DIR)/kernel.map -Ln $(BUILD_DIR)/kernel.lbl -o $@ $(BUILD_DIR)/kernel.o $(BUILD_DIR)/basic.o
	@echo "Built $@ ($$(wc -c < $@) bytes), loads at \$$0400"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Copy the freshly built image into the emulator's embedded asset so the next
# `go build`/`go run` of the emulator picks it up.
install-emulator: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(EMU_KERNEL)
	@echo "Copied kernel.bin -> $(EMU_KERNEL)"
	@echo "NOTE: emulator must have miaKernelTargetAddress = 0x0400 (registers.go)"

# Copy the image into the firmware tree (CMake turns it into kernel_data.c).
install-firmware: $(KERNEL_BIN)
	cp $(KERNEL_BIN) $(MIA_KERNEL)
	@echo "Copied kernel.bin -> $(MIA_KERNEL)"
	@echo "NOTE: firmware must have kernel_target_address = 0x0400 (mia.c)"

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
	@echo "Booting at \$$0400 needs kernel_target_address = 0x0400 in both the"
	@echo "MIA firmware (mia.c) and the emulator (registers.go). See docs/memory-map.md."
