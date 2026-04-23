#!/bin/bash
# ===========================================================================
# config.sh — Centralized default configuration for Telco JeOS Builder
#
# This file defines ALL tunable parameters with sane defaults.
# Values can be overridden by:
#   1. Environment variables (highest priority)
#   2. /etc/telco-nfv/config (runtime override on deployed images)
#   3. Defaults defined here (lowest priority)
#
# Prerequisites: source logger.sh before this file.
#
# Usage:
#   source lib/logger.sh
#   source lib/config.sh
# ===========================================================================

# Guard against double-sourcing
[[ -n "${_TELCO_CONFIG_LOADED:-}" ]] && return 0
readonly _TELCO_CONFIG_LOADED=1

# ---------------------------------------------------------------------------
# Project paths
# ---------------------------------------------------------------------------
TELCO_PROJECT_ROOT="${TELCO_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TELCO_BUILD_DIR="${TELCO_BUILD_DIR:-${TELCO_PROJECT_ROOT}/build}"

# ---------------------------------------------------------------------------
# Kernel configuration
# ---------------------------------------------------------------------------
KERNEL_VERSION="${KERNEL_VERSION:-6.6.70}"
KERNEL_LOCALVERSION="${KERNEL_LOCALVERSION:--telco-nfv}"
KERNEL_RELEASE="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"

# ---------------------------------------------------------------------------
# HugePages
# ---------------------------------------------------------------------------
HUGEPAGES_2M="${HUGEPAGES_2M:-1024}"           # Number of 2MB pages (= 2GB RAM)
HUGEPAGES_1G="${HUGEPAGES_1G:-0}"              # Number of 1GB pages (default: 0)
HUGEPAGE_MOUNT="${HUGEPAGE_MOUNT:-/mnt/huge}"  # hugetlbfs mount point

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
NET_MODE="${NET_MODE:-dhcp}"                   # "dhcp" or "static"
NET_IFACE="${NET_IFACE:-eth0}"                 # Primary interface
NET_IP="${NET_IP:-192.168.1.100/24}"           # Static IP (when mode=static)
NET_GATEWAY="${NET_GATEWAY:-192.168.1.1}"      # Default gateway
NET_DNS="${NET_DNS:-8.8.8.8}"                  # DNS server

# ---------------------------------------------------------------------------
# Kernel modules to load at boot
# ---------------------------------------------------------------------------
TELCO_MODULES="${TELCO_MODULES:-vfio vfio-pci vhost_net tun tap bonding 8021q bridge}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-/var/log/telco-nfv-init.log}"

# ---------------------------------------------------------------------------
# Override loader
# ---------------------------------------------------------------------------
TELCO_CONFIG_FILE="${TELCO_CONFIG_FILE:-/etc/telco-nfv/config}"

load_override_config() {
    if [[ -f "${TELCO_CONFIG_FILE}" ]]; then
        log_info "Loading config override from ${TELCO_CONFIG_FILE}"
        # shellcheck source=/dev/null
        source "${TELCO_CONFIG_FILE}"
        log_ok "Config override loaded successfully"
    else
        log_debug "No override config at ${TELCO_CONFIG_FILE}, using defaults"
    fi
}
