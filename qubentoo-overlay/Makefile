# Qubentoo Overlay — top-level Makefile
#
# All targets delegate to scripts/ and require bash.
# Run 'make help' for a full description of each target.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

OVERLAY_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS     := $(OVERLAY_DIR)/scripts

# Colour helpers (safe in both terminal and CI — CI can set NO_COLOR=1)
ifeq ($(NO_COLOR),1)
  BOLD  :=
  RESET :=
else
  BOLD  := \033[1m
  RESET := \033[0m
endif

# ---------------------------------------------------------------------------
# Default target
# ---------------------------------------------------------------------------

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Public targets
# ---------------------------------------------------------------------------

.PHONY: help
help:
	@printf '$(BOLD)Qubentoo overlay — available targets$(RESET)\n\n'
	@printf '  %-20s %s\n' 'make preflight'       'Check host hardware and kernel readiness'
	@printf '  %-20s %s\n' 'make dry-run'          'Pretend emerge — validate deps without building'
	@printf '  %-20s %s\n' 'make manifests'        'Generate Portage Manifest files (uses Docker if not on Gentoo)'
	@printf '  %-20s %s\n' 'make verify'           'Run repoman QA scan on the overlay'
	@printf '  %-20s %s\n' 'make verify-strict'    'Same as verify but fail on warnings too'
	@printf '  %-20s %s\n' 'make bootstrap'        'Run the full dom0 bootstrap (prompts for confirmation)'
	@printf '  %-20s %s\n' 'make install'          'Install Qubentoo onto a target disk from live CD'
	@printf '  %-20s %s\n' 'make kernel'           'Build and install dom0 kernel from kernel/qubentoo-dom0.config'
	@printf '  %-20s %s\n' 'make gentoo-template'  'Build the Gentoo PV domU template tarball'
	@printf '  %-20s %s\n' 'make all'              'preflight → dry-run → manifests → verify'
	@printf '\n'
	@printf '$(BOLD)Options (set via environment):$(RESET)\n'
	@printf '  %-20s %s\n' 'VERBOSE=1'             'Show full pretend/emerge output'
	@printf '  %-20s %s\n' 'DM_CHOICE=lightdm'     'Set display manager for bootstrap/install non-interactively'
	@printf '  %-20s %s\n' 'GRUB_DISK=/dev/sda'    'Target disk for grub-install (bootstrap)'
	@printf '  %-20s %s\n' 'TARGET_DISK=/dev/sda'  'Target disk for installer (make install)'
	@printf '  %-20s %s\n' 'HOSTNAME=qubentoo'     'Hostname for installed system'
	@printf '  %-20s %s\n' 'TIMEZONE=UTC'          'Timezone for installed system'
	@printf '  %-20s %s\n' 'LUKS=1'                'Enable LUKS root encryption (make install)'
	@printf '  %-20s %s\n' 'XEN_VERSION=4.17.5'    'Xen version to build'
	@printf '  %-20s %s\n' 'OVERLAY_SRC=<path>'    'Local overlay directory (default: this repo)'
	@printf '\n'
	@printf '$(BOLD)Quick start:$(RESET)\n'
	@printf '  make all        # validate everything\n'
	@printf '  make bootstrap  # run the full install (requires root)\n'
	@printf '\n'

.PHONY: preflight
preflight:
	@printf '$(BOLD)>>> Running preflight checks...$(RESET)\n'
	@bash "$(SCRIPTS)/preflight-check.sh" $(if $(filter 1,$(VERBOSE)),--verbose)

.PHONY: dry-run
dry-run:
	@printf '$(BOLD)>>> Running bootstrap dry run (emerge --pretend)...$(RESET)\n'
	@bash "$(SCRIPTS)/test-bootstrap.sh" \
		$(if $(filter 1,$(VERBOSE)),--verbose)

.PHONY: manifests
manifests:
	@printf '$(BOLD)>>> Generating Manifest files...$(RESET)\n'
	@if command -v ebuild &>/dev/null; then \
		OVERLAY_DIR="$(OVERLAY_DIR)" bash "$(SCRIPTS)/gen-manifests.sh"; \
	else \
		bash "$(SCRIPTS)/docker-gen-manifests.sh"; \
	fi

.PHONY: verify
verify:
	@printf '$(BOLD)>>> Running repoman QA scan...$(RESET)\n'
	@OVERLAY_DIR="$(OVERLAY_DIR)" bash "$(SCRIPTS)/verify-overlay.sh"

.PHONY: verify-strict
verify-strict:
	@printf '$(BOLD)>>> Running repoman QA scan (strict — warnings = failure)...$(RESET)\n'
	@OVERLAY_DIR="$(OVERLAY_DIR)" bash "$(SCRIPTS)/verify-overlay.sh" --strict

.PHONY: kernel
kernel: preflight
	@if [ ! -d /usr/src/linux ]; then \
		printf '\e[1;31mERROR:\e[0m /usr/src/linux not found. Emerge gentoo-sources first.\n'; \
		exit 1; \
	fi
	@printf '$(BOLD)>>> Building Qubentoo dom0 kernel...$(RESET)\n'
	cp "$(OVERLAY_DIR)/kernel/qubentoo-dom0.config" /tmp/qubentoo.config
	cd /usr/src/linux && \
		make defconfig && \
		scripts/kconfig/merge_config.sh .config /tmp/qubentoo.config
	@printf '$(BOLD)>>> Verifying critical config flags...$(RESET)\n'
	@grep -q 'CONFIG_XEN=y'                     /usr/src/linux/.config || \
		{ echo 'FAIL: CONFIG_XEN missing';        exit 1; }
	@grep -q 'CONFIG_XEN_DOM0=y'                /usr/src/linux/.config || \
		{ echo 'FAIL: CONFIG_XEN_DOM0 missing';   exit 1; }
	@grep -q '# CONFIG_XEN_PVCALLS_FRONTEND is not set' /usr/src/linux/.config || \
		{ echo 'FAIL: PVCALLS_FRONTEND not disabled'; exit 1; }
	@printf '$(BOLD)>>> Config verified. Building...$(RESET)\n'
	cd /usr/src/linux && \
		make -j$$(nproc) 2>&1 | tee /var/log/qubentoo-kernel-build.log && \
		make modules_install && \
		make install
	@printf '$(BOLD)>>> Kernel installed. Updating GRUB...$(RESET)\n'
	grub-mkconfig -o /boot/grub/grub.cfg
	@grep -q 'xen' /boot/grub/grub.cfg || \
		printf '\e[1;33mWARNING:\e[0m No Xen stanza in grub.cfg. See docs/troubleshooting/grub-xen-missing.md\n'

.PHONY: all
all: preflight dry-run manifests verify
	@printf '\n$(BOLD)>>> All pre-bootstrap checks complete.$(RESET)\n'
	@printf 'Review output above, then run: make bootstrap\n'

.PHONY: bootstrap
bootstrap: _bootstrap-guard
	@printf '$(BOLD)>>> Running dom0 bootstrap...$(RESET)\n'
	@OVERLAY_SRC="$(OVERLAY_DIR)" \
	 DM_CHOICE="$(DM_CHOICE)" \
	 GRUB_DISK="$(GRUB_DISK)" \
	 XEN_VERSION="$(XEN_VERSION)" \
	 bash "$(SCRIPTS)/bootstrap-dom0.sh"

.PHONY: _bootstrap-guard
_bootstrap-guard:
	@if [[ $$(id -u) -ne 0 ]]; then \
		printf '\e[1;31mERROR:\e[0m bootstrap requires root (run as root or with sudo)\n'; \
		exit 1; \
	fi
	@printf '\n'
	@printf '$(BOLD)╔═══════════════════════════════════════════════╗$(RESET)\n'
	@printf '$(BOLD)║  WARNING: This will modify your system.        ║$(RESET)\n'
	@printf '$(BOLD)║  It installs Xen, Qubes, and reconfigures GRUB.║$(RESET)\n'
	@printf '$(BOLD)║  Run '"'"'make dry-run'"'"' first if you have not yet. ║$(RESET)\n'
	@printf '$(BOLD)╚═══════════════════════════════════════════════╝$(RESET)\n'
	@printf '\n'
	@printf 'Type YES to continue, anything else to abort: '
	@read -r ARE_YOU_SURE; \
	if [[ "$${ARE_YOU_SURE}" != "YES" ]]; then \
		printf 'Aborted.\n'; \
		exit 1; \
	fi

.PHONY: install
install:
	@if [[ $$(id -u) -ne 0 ]]; then \
		printf '\e[1;31mERROR:\e[0m install requires root\n'; \
		exit 1; \
	fi
	@printf '$(BOLD)>>> Running Qubentoo installer...$(RESET)\n'
	@OVERLAY_SRC="$(OVERLAY_DIR)" \
	 DM_CHOICE="$(DM_CHOICE)" \
	 bash "$(SCRIPTS)/install-qubentoo.sh" \
	   --disk "$(TARGET_DISK)" \
	   --dm   "$(DM_CHOICE)" \
	   $(if $(HOSTNAME),--hostname "$(HOSTNAME)") \
	   $(if $(TIMEZONE),--timezone "$(TIMEZONE)") \
	   $(if $(filter 1,$(LUKS)),--luks)

.PHONY: gentoo-template
gentoo-template:
	@if [[ $$(id -u) -ne 0 ]]; then \
		printf '\e[1;31mERROR:\e[0m gentoo-template requires root\n'; \
		exit 1; \
	fi
	@printf '$(BOLD)>>> Building Gentoo template VM...$(RESET)\n'
	@OVERLAY_SRC="$(OVERLAY_DIR)" \
	 bash "$(SCRIPTS)/build-gentoo-template.sh"

# ---------------------------------------------------------------------------
# Convenience aliases
# ---------------------------------------------------------------------------

.PHONY: check
check: preflight

.PHONY: test
test: dry-run

.PHONY: clean
clean:
	@printf '$(BOLD)>>> Removing generated log files...$(RESET)\n'
	rm -fv \
		"$(OVERLAY_DIR)/manifest-gen.log" \
		"$(OVERLAY_DIR)/test-bootstrap.log" \
		"$(OVERLAY_DIR)/repoman-report.txt"
	@printf 'Clean complete.\n'
