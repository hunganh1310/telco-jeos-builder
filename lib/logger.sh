#!/bin/bash
# ===========================================================================
# logger.sh — Structured logging library for Telco JeOS Builder
#
# Features:
#   - Colored console output (auto-disabled when not a TTY)
#   - File logging (no ANSI codes)
#   - Systemd journal integration (when running under systemd)
#   - Configurable log level (DEBUG / INFO / WARN / ERROR)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
#   log_info "Starting build..."
#   log_ok   "Build complete"
#   die      "Fatal error" 2
#
# Environment:
#   LOG_FILE   — Path to log file (default: /var/log/telco-builder.log)
#   LOG_LEVEL  — Minimum level to emit (default: INFO)
# ===========================================================================

# Guard against double-sourcing
[[ -n "${_TELCO_LOGGER_LOADED:-}" ]] && return 0
readonly _TELCO_LOGGER_LOADED=1

# ---------------------------------------------------------------------------
# Color palette (disabled when stdout is not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly _CLR_RESET='\033[0m'
    readonly _CLR_DEBUG='\033[90m'    # Grey
    readonly _CLR_INFO='\033[36m'     # Cyan
    readonly _CLR_OK='\033[32m'       # Green
    readonly _CLR_WARN='\033[33m'     # Yellow
    readonly _CLR_ERROR='\033[31m'    # Red
    readonly _CLR_BOLD='\033[1m'
else
    readonly _CLR_RESET=''
    readonly _CLR_DEBUG=''
    readonly _CLR_INFO=''
    readonly _CLR_OK=''
    readonly _CLR_WARN=''
    readonly _CLR_ERROR=''
    readonly _CLR_BOLD=''
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-/var/log/telco-builder.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Numeric log levels for comparison
declare -A _LOG_LEVELS=( [DEBUG]=0 [INFO]=1 [OK]=1 [WARN]=2 [ERROR]=3 )

# ---------------------------------------------------------------------------
# Internal: core logging function
# ---------------------------------------------------------------------------
_log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Check log level threshold
    local level_num="${_LOG_LEVELS[${level}]:-1}"
    local threshold="${_LOG_LEVELS[${LOG_LEVEL}]:-1}"
    if (( level_num < threshold )); then
        return 0
    fi

    # Console output (with color)
    printf '%b[%s] [%-5s] %s%b\n' "${color}" "${timestamp}" "${level}" "${msg}" "${_CLR_RESET}" >&2

    # File output (without color)
    if [[ -n "${LOG_FILE}" ]]; then
        local log_dir
        log_dir=$(dirname "${LOG_FILE}")
        if [[ -w "${log_dir}" ]] || mkdir -p "${log_dir}" 2>/dev/null; then
            printf '[%s] [%-5s] %s\n' "${timestamp}" "${level}" "${msg}" >> "${LOG_FILE}" 2>/dev/null
        fi
    fi

    # Systemd journal integration (when running as a service)
    if [[ -n "${INVOCATION_ID:-}" ]] && command -v logger &>/dev/null; then
        local priority="info"
        case "${level}" in
            DEBUG) priority="debug" ;;
            WARN)  priority="warning" ;;
            ERROR) priority="err" ;;
        esac
        logger -t "telco-nfv" -p "local0.${priority}" "${msg}" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
log_debug() { _log "DEBUG" "${_CLR_DEBUG}" "$@"; }
log_info()  { _log "INFO"  "${_CLR_INFO}"  "$@"; }
log_ok()    { _log "OK"    "${_CLR_OK}"    "$@"; }
log_warn()  { _log "WARN"  "${_CLR_WARN}"  "$@"; }
log_error() { _log "ERROR" "${_CLR_ERROR}" "$@"; }

# Print a visual section header
log_section() {
    local title="$1"
    _log "INFO" "${_CLR_BOLD}" "============================================================"
    _log "INFO" "${_CLR_BOLD}" "  ${title}"
    _log "INFO" "${_CLR_BOLD}" "============================================================"
}

# Log an error and exit with the given code (default: 1)
die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "${msg}"
    exit "${code}"
}
