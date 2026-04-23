#!/bin/bash
# ===========================================================================
# telco-nfv-init.sh — Telco/NFV Boot-Time Initialization Script
#
# Runs at boot via systemd (telco-nfv-init.service) to configure the
# system for NFV workloads.
#
# Modules:
#   1. HugePages allocation & verification
#   2. Network IP configuration (DHCP / Static)
#   3. Kernel module loading (VFIO, vhost_net, etc.)
#   4. CPU isolation verification
#   5. Sysctl performance tuning
#   6. IOMMU / VT-d verification
#   7. System summary
#
# Configuration:
#   Override defaults via /etc/telco-nfv/config
#
# Options:
#   --dry-run   Show what would be done without making changes
#
# Author: Hung Anh
# Project: Telco JeOS Builder (Ericsson Ascent Cloud Engineer)
# ===========================================================================

set -euo pipefail

# ===========================================================================
# Configuration defaults (overridable via /etc/telco-nfv/config or env vars)
# ===========================================================================

# HugePages
HUGEPAGES_2M="${HUGEPAGES_2M:-1024}"           # Number of 2MB pages (= 2GB RAM)
HUGEPAGES_1G="${HUGEPAGES_1G:-0}"              # Number of 1GB pages (default: 0)
HUGEPAGE_MOUNT="${HUGEPAGE_MOUNT:-/mnt/huge}"  # hugetlbfs mount point

# Network
NET_MODE="${NET_MODE:-dhcp}"                   # "dhcp" or "static"
NET_IFACE="${NET_IFACE:-eth0}"                 # Primary interface
NET_IP="${NET_IP:-192.168.1.100/24}"           # Static IP (when mode=static)
NET_GATEWAY="${NET_GATEWAY:-192.168.1.1}"      # Default gateway
NET_DNS="${NET_DNS:-8.8.8.8}"                  # DNS server

# Kernel modules to load
TELCO_MODULES="${TELCO_MODULES:-vfio vfio-pci vhost_net tun bonding 8021q bridge}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/telco-nfv-init.log}"

# ===========================================================================
# Parse arguments
# ===========================================================================
DRY_RUN=false
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=true ;;
    esac
done

# ===========================================================================
# Logging functions
# ===========================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

log_info()  { log "INFO " "$@"; }
log_ok()    { log " OK  " "$@"; }
log_warn()  { log "WARN " "$@"; }
log_error() { log "ERROR" "$@"; }

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo "============================================================" | tee -a "${LOG_FILE}"
    echo "  $1" | tee -a "${LOG_FILE}"
    echo "============================================================" | tee -a "${LOG_FILE}"
}

# ===========================================================================
# Load override config
# ===========================================================================
load_config() {
    local config_file="/etc/telco-nfv/config"
    if [[ -f "${config_file}" ]]; then
        log_info "Loading config from ${config_file}"
        # shellcheck source=/dev/null
        source "${config_file}"
        log_ok "Config loaded successfully"
    else
        log_info "No override config found, using defaults"
    fi
}

# ===========================================================================
# 1. HUGEPAGES CONFIGURATION
# ===========================================================================
configure_hugepages() {
    log_section "1. HUGEPAGES CONFIGURATION"

    # --- 2MB HugePages ---
    log_info "Configuring 2MB HugePages: requesting ${HUGEPAGES_2M} pages"

    local hp_path="/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"

    if [[ -f "${hp_path}" ]]; then
        local current
        current=$(cat "${hp_path}")
        log_info "Current 2MB HugePages: ${current}"

        if [[ "${current}" -lt "${HUGEPAGES_2M}" ]]; then
            log_info "Allocating more hugepages: ${current} → ${HUGEPAGES_2M}"
            if ! "${DRY_RUN}"; then
                echo "${HUGEPAGES_2M}" > "${hp_path}"
            else
                log_info "[DRY-RUN] Would write ${HUGEPAGES_2M} to ${hp_path}"
            fi
        fi

        # Verify
        local actual
        actual=$(cat "${hp_path}")
        local free
        free=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages)
        local total_mb=$(( actual * 2 ))

        if [[ "${actual}" -ge "${HUGEPAGES_2M}" ]]; then
            log_ok "2MB HugePages: ${actual} pages allocated (${total_mb} MB total, ${free} free)"
        else
            log_warn "2MB HugePages: only ${actual}/${HUGEPAGES_2M} allocated (not enough contiguous memory?)"
        fi
    else
        log_error "HugePages sysfs not found: ${hp_path}"
        log_error "Kernel may not support HugePages!"
    fi

    # --- 1GB HugePages (optional) ---
    if [[ "${HUGEPAGES_1G}" -gt 0 ]]; then
        local hp1g_path="/sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
        if [[ -f "${hp1g_path}" ]]; then
            log_info "Configuring 1GB HugePages: requesting ${HUGEPAGES_1G} pages"
            if ! "${DRY_RUN}"; then
                echo "${HUGEPAGES_1G}" > "${hp1g_path}"
            fi
            local actual1g
            actual1g=$(cat "${hp1g_path}")
            log_ok "1GB HugePages: ${actual1g} pages allocated"
        else
            log_warn "1GB HugePages sysfs not found (not supported or not enabled in kernel)"
        fi
    fi

    # --- Mount hugetlbfs ---
    log_info "Mounting hugetlbfs at ${HUGEPAGE_MOUNT}"
    mkdir -p "${HUGEPAGE_MOUNT}"

    if mountpoint -q "${HUGEPAGE_MOUNT}" 2>/dev/null; then
        log_ok "hugetlbfs already mounted at ${HUGEPAGE_MOUNT}"
    else
        if ! "${DRY_RUN}"; then
            mount -t hugetlbfs nodev "${HUGEPAGE_MOUNT}" -o pagesize=2M 2>/dev/null && \
                log_ok "hugetlbfs mounted at ${HUGEPAGE_MOUNT}" || \
                log_warn "Failed to mount hugetlbfs (may need kernel support)"
        else
            log_info "[DRY-RUN] Would mount hugetlbfs at ${HUGEPAGE_MOUNT}"
        fi
    fi

    # --- Summary ---
    log_info "HugePages memory summary:"
    if [[ -f /proc/meminfo ]]; then
        grep -i huge /proc/meminfo | while read -r line; do
            log_info "  ${line}"
        done
    fi
}

# ===========================================================================
# 2. NETWORK CONFIGURATION
# ===========================================================================
configure_network() {
    log_section "2. NETWORK CONFIGURATION"

    log_info "Mode: ${NET_MODE} | Interface: ${NET_IFACE}"

    # Check interface exists
    if ! ip link show "${NET_IFACE}" &>/dev/null; then
        log_warn "Interface ${NET_IFACE} not found. Available interfaces:"
        ip -br link show | while read -r line; do
            log_warn "  ${line}"
        done

        # Auto-select the first non-loopback interface
        local auto_iface
        auto_iface=$(ip -br link show | grep -v "^lo " | head -1 | awk '{print $1}')
        if [[ -n "${auto_iface}" ]]; then
            log_info "Auto-selecting interface: ${auto_iface}"
            NET_IFACE="${auto_iface}"
        else
            log_error "No network interface available!"
            return 1
        fi
    fi

    # Bring interface up
    if ! "${DRY_RUN}"; then
        ip link set "${NET_IFACE}" up 2>/dev/null || true
    fi

    case "${NET_MODE}" in
        dhcp)
            log_info "Starting DHCP client on ${NET_IFACE}..."

            if "${DRY_RUN}"; then
                log_info "[DRY-RUN] Would configure DHCP on ${NET_IFACE}"
            elif command -v wicked &>/dev/null; then
                # Use wicked (SUSE default)
                mkdir -p /etc/sysconfig/network
                cat > "/etc/sysconfig/network/ifcfg-${NET_IFACE}" << WICKED
BOOTPROTO='dhcp'
STARTMODE='auto'
DHCLIENT_SET_DEFAULT_ROUTE='yes'
WICKED
                wicked ifup "${NET_IFACE}" 2>/dev/null && \
                    log_ok "DHCP via wicked: success" || \
                    log_warn "wicked ifup failed, trying dhclient..."
            fi

            # Fallback: dhclient
            if ! "${DRY_RUN}" && ! ip addr show "${NET_IFACE}" | grep -q "inet "; then
                if command -v dhclient &>/dev/null; then
                    dhclient "${NET_IFACE}" 2>/dev/null && \
                        log_ok "DHCP via dhclient: success" || \
                        log_warn "dhclient failed"
                fi
            fi
            ;;

        static)
            log_info "Configuring static IP: ${NET_IP} on ${NET_IFACE}"

            if "${DRY_RUN}"; then
                log_info "[DRY-RUN] Would assign ${NET_IP} to ${NET_IFACE}"
            else
                # Flush existing addresses
                ip addr flush dev "${NET_IFACE}" 2>/dev/null || true

                # Assign IP
                ip addr add "${NET_IP}" dev "${NET_IFACE}" 2>/dev/null && \
                    log_ok "IP ${NET_IP} assigned to ${NET_IFACE}" || \
                    log_error "Failed to assign IP"

                # Set gateway
                if [[ -n "${NET_GATEWAY}" ]]; then
                    ip route add default via "${NET_GATEWAY}" dev "${NET_IFACE}" 2>/dev/null && \
                        log_ok "Default gateway: ${NET_GATEWAY}" || \
                        log_warn "Failed to set gateway (may already exist)"
                fi

                # Set DNS
                if [[ -n "${NET_DNS}" ]]; then
                    echo "nameserver ${NET_DNS}" > /etc/resolv.conf
                    log_ok "DNS: ${NET_DNS}"
                fi
            fi
            ;;

        *)
            log_warn "Unknown NET_MODE: ${NET_MODE}. Skipping network config."
            ;;
    esac

    # Verify
    log_info "Network status:"
    ip -br addr show "${NET_IFACE}" 2>/dev/null | while read -r line; do
        log_info "  ${line}"
    done

    # Connectivity test
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        log_ok "Internet connectivity: OK"
    else
        log_warn "Internet connectivity: FAILED (may be normal in isolated env)"
    fi
}

# ===========================================================================
# 3. KERNEL MODULES
# ===========================================================================
load_kernel_modules() {
    log_section "3. KERNEL MODULES"

    for mod in ${TELCO_MODULES}; do
        if lsmod | grep -q "^${mod//-/_}"; then
            log_ok "Module already loaded: ${mod}"
        else
            log_info "Loading module: ${mod}"
            if "${DRY_RUN}"; then
                log_info "[DRY-RUN] Would load module: ${mod}"
            elif modprobe "${mod}" 2>/dev/null; then
                log_ok "Module loaded: ${mod}"
            else
                log_warn "Failed to load module: ${mod} (may not be available)"
            fi
        fi
    done

    log_info "Loaded Telco/NFV modules:"
    lsmod | grep -E "vfio|vhost|tun|bond|8021q|bridge" 2>/dev/null | while read -r line; do
        log_info "  ${line}"
    done
}

# ===========================================================================
# 4. CPU ISOLATION VERIFICATION
# ===========================================================================
verify_cpu_isolation() {
    log_section "4. CPU ISOLATION"

    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")

    # Check isolcpus
    if [[ "${cmdline}" =~ isolcpus=([^ ]+) ]]; then
        log_ok "Isolated CPUs (from cmdline): ${BASH_REMATCH[1]}"
    else
        log_info "No CPU isolation configured (isolcpus not in cmdline)"
    fi

    # Check nohz_full
    if [[ "${cmdline}" =~ nohz_full=([^ ]+) ]]; then
        log_ok "Tickless CPUs (nohz_full): ${BASH_REMATCH[1]}"
    fi

    # Check rcu_nocbs
    if [[ "${cmdline}" =~ rcu_nocbs=([^ ]+) ]]; then
        log_ok "RCU offload CPUs (rcu_nocbs): ${BASH_REMATCH[1]}"
    fi

    # CPU topology
    local total_cpus
    total_cpus=$(nproc)
    log_info "Total CPUs: ${total_cpus}"

    if command -v numactl &>/dev/null; then
        log_info "NUMA topology:"
        numactl --hardware 2>/dev/null | while read -r line; do
            log_info "  ${line}"
        done
    fi

    log_info "Full kernel cmdline:"
    log_info "  ${cmdline}"
}

# ===========================================================================
# 5. SYSCTL PERFORMANCE TUNING
# ===========================================================================
apply_sysctl_tuning() {
    log_section "5. SYSCTL PERFORMANCE TUNING"

    # The sysctl config file is delivered via the root overlay at
    # /etc/sysctl.d/90-telco-nfv.conf — only write it if missing
    local sysctl_conf="/etc/sysctl.d/90-telco-nfv.conf"
    if [[ ! -f "${sysctl_conf}" ]]; then
        log_info "Sysctl config not found, creating ${sysctl_conf}"
        if ! "${DRY_RUN}"; then
            cat > "${sysctl_conf}" << 'SYSCTL'
# ===========================================================================
# Telco/NFV Network & Memory Tuning
# Applied by telco-nfv-init.sh
# ===========================================================================

# Network buffer tuning (line-rate 10G/25G burst handling)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535

# TCP tuning
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# Memory — disable swap (Telco = low-latency, swap = unacceptable)
vm.swappiness = 0

# HugePages
vm.nr_hugepages = 1024
vm.hugetlb_shm_group = 0

# Panic on OOM instead of random kill (predictable failure mode)
vm.panic_on_oom = 0
vm.overcommit_memory = 0

# NUMA balancing (let kernel optimize memory placement)
kernel.numa_balancing = 1
SYSCTL
        fi
    else
        log_ok "Sysctl config already exists at ${sysctl_conf}"
    fi

    # Apply sysctl settings
    if ! "${DRY_RUN}"; then
        sysctl --system 2>/dev/null | tail -1 | while read -r line; do
            log_ok "Sysctl: ${line}"
        done
    fi

    # Disable Transparent HugePages (THP) — conflicts with DPDK explicit hugepages
    local thp_path="/sys/kernel/mm/transparent_hugepage/enabled"
    if [[ -f "${thp_path}" ]]; then
        if ! "${DRY_RUN}"; then
            echo never > "${thp_path}" 2>/dev/null && \
                log_ok "Transparent HugePages: disabled (never)" || \
                log_warn "Failed to disable THP"
        else
            log_info "[DRY-RUN] Would disable THP"
        fi
    fi

    # Verify key settings
    log_info "Key sysctl values:"
    for key in vm.nr_hugepages vm.swappiness net.core.rmem_max kernel.numa_balancing; do
        local val
        val=$(sysctl -n "${key}" 2>/dev/null || echo "N/A")
        log_info "  ${key} = ${val}"
    done
}

# ===========================================================================
# 6. IOMMU VERIFICATION
# ===========================================================================
verify_iommu() {
    log_section "6. IOMMU / VT-d VERIFICATION"

    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")

    # Check cmdline params
    if echo "${cmdline}" | grep -q "intel_iommu=on"; then
        log_ok "Intel IOMMU: enabled in cmdline"
    elif echo "${cmdline}" | grep -q "amd_iommu=on"; then
        log_ok "AMD IOMMU: enabled in cmdline"
    else
        log_warn "IOMMU not enabled in kernel cmdline"
    fi

    if echo "${cmdline}" | grep -q "iommu=pt"; then
        log_ok "IOMMU passthrough mode: enabled"
    fi

    # Check IOMMU groups
    local iommu_groups="/sys/kernel/iommu_groups"
    if [[ -d "${iommu_groups}" ]]; then
        local group_count
        group_count=$(find "${iommu_groups}" -maxdepth 1 -mindepth 1 -type d | wc -l)
        log_ok "IOMMU groups found: ${group_count}"
    else
        log_warn "IOMMU groups directory not found (IOMMU may not be active)"
    fi

    # Check VFIO device
    if [[ -c /dev/vfio/vfio ]]; then
        log_ok "VFIO device: /dev/vfio/vfio exists"
    else
        log_info "VFIO device not present (normal if no devices bound to vfio-pci)"
    fi
}

# ===========================================================================
# 7. SYSTEM SUMMARY
# ===========================================================================
print_summary() {
    log_section "7. SYSTEM SUMMARY"

    log_info "Hostname:    $(hostname)"
    log_info "Kernel:      $(uname -r)"
    log_info "Uptime:      $(uptime -p 2>/dev/null || uptime)"
    log_info "CPUs:        $(nproc)"
    log_info "Total RAM:   $(awk '/MemTotal/ {printf "%.0f MB", $2/1024}' /proc/meminfo)"
    log_info "Free RAM:    $(awk '/MemAvailable/ {printf "%.0f MB", $2/1024}' /proc/meminfo)"

    # HugePages summary
    local hp_total hp_free hp_size_kb
    hp_total=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo 0)
    hp_free=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo 0)
    hp_size_kb=$((hp_total * 2048))
    log_info "HugePages:   ${hp_total} x 2MB = $((hp_size_kb / 1024)) MB (${hp_free} free)"

    # Network
    log_info "Network:"
    ip -br addr show 2>/dev/null | grep -v "^lo " | while read -r line; do
        log_info "  ${line}"
    done

    echo "" | tee -a "${LOG_FILE}"
    log_ok "========== Telco NFV Init COMPLETE =========="
    echo "" | tee -a "${LOG_FILE}"
}

# ===========================================================================
# MAIN
# ===========================================================================
main() {
    # Create log directory
    mkdir -p "$(dirname "${LOG_FILE}")"

    echo "" | tee -a "${LOG_FILE}"
    log_info "========== Telco NFV Init START =========="
    log_info "Script: $0"
    log_info "Date: $(date)"
    log_info "Kernel: $(uname -r)"

    if "${DRY_RUN}"; then
        log_warn "*** DRY-RUN MODE — no changes will be made ***"
    fi

    # Load override config
    load_config

    # Execute each module
    configure_hugepages
    configure_network
    load_kernel_modules
    verify_cpu_isolation
    apply_sysctl_tuning
    verify_iommu
    print_summary

    return 0
}

main "$@"
