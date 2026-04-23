# ===========================================================================
# Makefile — Telco JeOS Builder Build Orchestration
#
# Targets:
#   make kernel-config  — Configure kernel for Telco/NFV
#   make kernel-build   — Build kernel and create RPM
#   make image          — Build QCOW2 image with kiwi-ng
#   make test           — Run validation test suite
#   make lint           — Run shellcheck on all scripts
#   make clean          — Remove build artifacts
#
# Configuration (override via environment):
#   KERNEL_VERSION  — Kernel version (default: 6.6.70)
#   KERNEL_SRC      — Path to kernel source tree
#   BUILD_DIR       — Build output directory (default: ./build)
# ===========================================================================

.PHONY: help kernel-config kernel-build image test lint clean

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
KERNEL_VERSION ?= 6.6.70
KERNEL_LOCALVERSION ?= -telco-nfv
KERNEL_RELEASE := $(KERNEL_VERSION)$(KERNEL_LOCALVERSION)
BUILD_DIR ?= $(CURDIR)/build
KERNEL_SRC ?= $(BUILD_DIR)/kernel/linux-$(KERNEL_VERSION)
RPMBUILD_DIR ?= $(BUILD_DIR)/kernel/rpmbuild

# ---------------------------------------------------------------------------
# Default target
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "  Telco JeOS Builder"
	@echo "  ===================="
	@echo ""
	@echo "  make kernel-config   Configure kernel $(KERNEL_RELEASE)"
	@echo "  make kernel-build    Build kernel + RPM package"
	@echo "  make image           Build QCOW2 image (requires sudo)"
	@echo "  make test            Run test suite"
	@echo "  make lint            Shellcheck all scripts"
	@echo "  make clean           Remove build artifacts"
	@echo ""
	@echo "  Configuration:"
	@echo "    KERNEL_VERSION=$(KERNEL_VERSION)"
	@echo "    KERNEL_SRC=$(KERNEL_SRC)"
	@echo "    BUILD_DIR=$(BUILD_DIR)"
	@echo ""

# ---------------------------------------------------------------------------
# Kernel configuration
# ---------------------------------------------------------------------------
kernel-config:
	@if [ ! -d "$(KERNEL_SRC)" ]; then \
		echo "ERROR: Kernel source not found at $(KERNEL_SRC)"; \
		echo "  Download and extract linux-$(KERNEL_VERSION).tar.xz into $(BUILD_DIR)/kernel/"; \
		exit 1; \
	fi
	cd "$(KERNEL_SRC)" && bash "$(CURDIR)/kernel/configure-telco-kernel.sh"

# ---------------------------------------------------------------------------
# Kernel build + RPM
# ---------------------------------------------------------------------------
kernel-build: kernel-config
	cd "$(KERNEL_SRC)" && make -j$$(nproc)
	cd "$(KERNEL_SRC)" && make modules_install INSTALL_MOD_PATH="$(BUILD_DIR)/kernel/staging"
	@mkdir -p "$(RPMBUILD_DIR)"/{BUILDROOT,RPMS,SPECS}
	rpmbuild -bb \
		--define "_topdir $(RPMBUILD_DIR)" \
		"$(CURDIR)/kernel/kernel-telco-nfv.spec"
	@echo "RPM built in $(RPMBUILD_DIR)/RPMS/"

# ---------------------------------------------------------------------------
# QCOW2 image build (requires kiwi-ng + sudo)
# ---------------------------------------------------------------------------
image:
	@if ! command -v kiwi-ng >/dev/null 2>&1; then \
		echo "ERROR: kiwi-ng not found. Install: pip install kiwi"; \
		exit 1; \
	fi
	sudo kiwi-ng system build \
		--description "$(CURDIR)/image" \
		--target-dir "$(BUILD_DIR)/image"

# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------
test:
	bash tests/telco-kernel-test.sh

# ---------------------------------------------------------------------------
# Lint all Bash scripts
# ---------------------------------------------------------------------------
lint:
	bash tests/shellcheck.sh

# ---------------------------------------------------------------------------
# Clean build artifacts
# ---------------------------------------------------------------------------
clean:
	rm -rf "$(BUILD_DIR)"
	@echo "Cleaned $(BUILD_DIR)"
