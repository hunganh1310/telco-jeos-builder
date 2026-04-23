#!/bin/bash
# ===========================================================================
# utils.sh — Common utility functions for Telco JeOS Builder
#
# Prerequisites: source logger.sh before this file.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# ===========================================================================

# Guard against double-sourcing
[[ -n "${_TELCO_UTILS_LOADED:-}" ]] && return 0
readonly _TELCO_UTILS_LOADED=1

# ---------------------------------------------------------------------------
# Privilege checks
# ---------------------------------------------------------------------------

# Ensure the script is running as root.
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        die "This script must be run as root (use sudo)"
    fi
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

# Ensure a command is available on PATH.
# Usage: require_command make "make (GNU Make)"
require_command() {
    local cmd="$1"
    local hint="${2:-$1}"
    if ! command -v "${cmd}" &>/dev/null; then
        die "Required command '${cmd}' is missing. Install it: zypper install ${hint}"
    fi
}

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

# Resolve the absolute directory of the calling script.
# Usage: SCRIPT_DIR=$(get_script_dir)
get_script_dir() {
    local dir
    dir=$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
    echo "${dir}"
}

# Resolve the project root (parent of lib/).
# Usage: PROJECT_ROOT=$(get_project_root)
get_project_root() {
    local lib_dir
    lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    echo "$(cd "${lib_dir}/.." && pwd)"
}

# ---------------------------------------------------------------------------
# Idempotency helpers
# ---------------------------------------------------------------------------

# Check whether an operation has already been performed.
# Creates a marker file on first call; returns 0 (already done) on subsequent calls.
# Usage:
#   if is_already_done "/var/lib/telco-nfv/.hugepages-configured"; then
#       log_info "HugePages already configured, skipping"
#   else
#       configure_hugepages
#       mark_done "/var/lib/telco-nfv/.hugepages-configured"
#   fi
is_already_done() {
    local marker="$1"
    [[ -f "${marker}" ]]
}

mark_done() {
    local marker="$1"
    local marker_dir
    marker_dir=$(dirname "${marker}")
    mkdir -p "${marker_dir}"
    date '+%Y-%m-%d %H:%M:%S' > "${marker}"
}

# ---------------------------------------------------------------------------
# File safety
# ---------------------------------------------------------------------------

# Create a timestamped backup of a file before modifying it.
# Usage: backup_file /etc/fstab
backup_file() {
    local path="$1"
    if [[ -f "${path}" ]]; then
        local backup="${path}.bak.$(date '+%Y%m%d-%H%M%S')"
        cp -a "${path}" "${backup}"
        log_debug "Backed up ${path} → ${backup}"
    fi
}

# Append a block of text to a file only if it is not already present.
# The sentinel string is used to detect whether the block was already added.
# Usage: append_once /etc/fstab "hugetlbfs" "hugetlbfs /mnt/huge hugetlbfs defaults 0 0"
append_once() {
    local file="$1"
    local sentinel="$2"
    local content="$3"

    if [[ -f "${file}" ]] && grep -qF "${sentinel}" "${file}" 2>/dev/null; then
        log_debug "Already present in ${file}: ${sentinel}"
        return 0
    fi

    backup_file "${file}"
    echo "${content}" >> "${file}"
    log_ok "Appended to ${file}"
}

# ---------------------------------------------------------------------------
# Network validation
# ---------------------------------------------------------------------------

# Validate an IPv4 CIDR address (e.g., 192.168.1.100/24).
# Returns 0 if valid, 1 otherwise.
validate_ip_cidr() {
    local addr="$1"
    if [[ "${addr}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Kernel helpers
# ---------------------------------------------------------------------------

# Check if the currently running kernel matches a given version string.
is_booted_kernel() {
    local expected="$1"
    [[ "$(uname -r)" == "${expected}" ]]
}

# ---------------------------------------------------------------------------
# Cleanup / trap helpers
# ---------------------------------------------------------------------------

# Register a cleanup function to run on EXIT.
# Multiple calls append handlers (they execute in LIFO order).
# Usage: on_exit "rm -f /tmp/lockfile"
_TELCO_EXIT_HANDLERS=()

_run_exit_handlers() {
    local i
    for (( i=${#_TELCO_EXIT_HANDLERS[@]}-1; i>=0; i-- )); do
        eval "${_TELCO_EXIT_HANDLERS[$i]}" || true
    done
}
trap _run_exit_handlers EXIT

on_exit() {
    _TELCO_EXIT_HANDLERS+=("$1")
}
