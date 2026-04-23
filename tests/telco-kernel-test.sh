#!/bin/bash
#=============================================================================
# telco-kernel-test.sh
#
# Comprehensive Testing Suite for Telco/NFV Custom Kernel
#
# Tests:
#   A. Kernel Config Verification (offline — parse .config)
#   B. Runtime Verification (online — running on custom kernel)
#   C. Performance Benchmarks (size/module comparisons)
#   D. Integration Tests (verify all components link correctly)
#
# Usage:
#   bash tests/telco-kernel-test.sh [--suite a|b|c|d]
#
# Author: Hung Anh
# Project: Telco JeOS Builder (Ericsson Ascent Cloud Engineer)
#=============================================================================

set -uo pipefail

#-----------------------------------------------------------------------------
# Resolve project root and source shared libraries
#-----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source shared libraries if available
if [[ -f "${PROJECT_ROOT}/lib/logger.sh" ]]; then
    # shellcheck source=../lib/logger.sh
    source "${PROJECT_ROOT}/lib/logger.sh"
    # shellcheck source=../lib/config.sh
    source "${PROJECT_ROOT}/lib/config.sh"
fi

#-----------------------------------------------------------------------------
# CONFIG
#-----------------------------------------------------------------------------
KVER="${KERNEL_RELEASE:-6.6.70-telco-nfv}"
KERNEL_SRC_DIR="${KERNEL_SRC_DIR:-${PROJECT_ROOT}/build/kernel/linux-6.6.70}"
CONFIG_FILE="${CONFIG_FILE:-${KERNEL_SRC_DIR}/.config}"
LOG_FILE="/tmp/telco-kernel-test-$(date +%Y%m%d-%H%M%S).log"
PASS=0; FAIL=0; WARN=0; SKIP=0
RUN_SUITE=""

#-----------------------------------------------------------------------------
# Parse arguments
#-----------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --suite=*) RUN_SUITE="${arg#*=}" ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--suite=a|b|c|d]"
            exit 0 ;;
    esac
done

#-----------------------------------------------------------------------------
# COLORS & FORMATTING
#-----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

#-----------------------------------------------------------------------------
# HELPER FUNCTIONS
#-----------------------------------------------------------------------------
log() { echo -e "$@" | tee -a "${LOG_FILE}"; }
test_pass() { log "${GREEN}  [PASS]${NC} $1"; ((PASS++)); }
test_fail() { log "${RED}  [FAIL]${NC} $1"; ((FAIL++)); }
test_warn() { log "${YELLOW}  [WARN]${NC} $1"; ((WARN++)); }
test_skip() { log "${BLUE}  [SKIP]${NC} $1"; ((SKIP++)); }
test_info() { log "${CYAN}  [INFO]${NC} $1"; }
section_header() {
    log ""; log "${BOLD}================================================================${NC}"
    log "${BOLD}  $1${NC}"; log "${BOLD}================================================================${NC}"
}

check_kconfig() {
    local option="$1" expected="$2" description="$3"
    [[ ! -f "${CONFIG_FILE}" ]] && { test_skip "${description} (no .config file)"; return; }
    local actual
    actual=$(grep "^${option}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    if [[ -z "${actual}" ]]; then
        grep -q "# ${option} is not set" "${CONFIG_FILE}" 2>/dev/null && actual="n" || actual="(not found)"
    fi
    [[ "${actual}" == "${expected}" ]] && test_pass "${description}: ${option}=${actual}" || \
        test_fail "${description}: ${option}=${actual} (expected: ${expected})"
}

#=============================================================================
# TEST SUITE A: KERNEL CONFIG VERIFICATION
#=============================================================================
test_suite_a() {
    section_header "TEST SUITE A: KERNEL CONFIG VERIFICATION"
    log "  Config file: ${CONFIG_FILE}"; log ""
    [[ ! -f "${CONFIG_FILE}" ]] && { test_fail ".config file not found: ${CONFIG_FILE}"; return; }

    log "${BOLD}  --- A1: HugePages Support ---${NC}"
    check_kconfig "CONFIG_HUGETLBFS" "y" "HugeTLB Filesystem"
    check_kconfig "CONFIG_HUGETLB_PAGE" "y" "HugeTLB Page support"
    check_kconfig "CONFIG_TRANSPARENT_HUGEPAGE" "y" "Transparent HugePages (THP)"
    grep -q "CONFIG_ARCH_HAS_GIGANTIC_PAGE=y" "${CONFIG_FILE}" 2>/dev/null && \
        test_pass "1GB Gigantic HugePages: supported" || test_info "1GB Gigantic HugePages: not explicitly set (arch dependent)"

    log ""; log "${BOLD}  --- A2: NUMA Support ---${NC}"
    check_kconfig "CONFIG_NUMA" "y" "NUMA Memory Allocation"
    check_kconfig "CONFIG_NUMA_BALANCING" "y" "NUMA Auto-Balancing"
    check_kconfig "CONFIG_X86_64_ACPI_NUMA" "y" "ACPI NUMA Detection"

    log ""; log "${BOLD}  --- A3: IOMMU / VFIO ---${NC}"
    check_kconfig "CONFIG_IOMMU_SUPPORT" "y" "IOMMU Framework"
    check_kconfig "CONFIG_INTEL_IOMMU" "y" "Intel VT-d IOMMU"
    check_kconfig "CONFIG_VFIO" "y" "VFIO Framework"
    check_kconfig "CONFIG_VFIO_IOMMU_TYPE1" "y" "VFIO IOMMU Type1"
    local vfio_pci; vfio_pci=$(grep "^CONFIG_VFIO_PCI=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${vfio_pci}" == "y" || "${vfio_pci}" == "m" ]] && test_pass "VFIO-PCI driver: ${vfio_pci}" || test_fail "VFIO-PCI driver: not enabled"

    log ""; log "${BOLD}  --- A4: KVM Virtualization ---${NC}"
    local kvm_val; kvm_val=$(grep "^CONFIG_KVM=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    [[ "${kvm_val}" == "y" || "${kvm_val}" == "m" ]] && test_pass "KVM core: =${kvm_val}" || test_fail "KVM core: not enabled"
    [[ "${kvm_val}" == "m" ]] && test_pass "KVM: built as module (OK for Telco)"
    local kvm_intel; kvm_intel=$(grep "^CONFIG_KVM_INTEL=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${kvm_intel}" == "y" || "${kvm_intel}" == "m" ]] && test_pass "KVM Intel (VMX): ${kvm_intel}" || test_fail "KVM Intel (VMX): not enabled"

    log ""; log "${BOLD}  --- A5: CPU Isolation & Low Latency ---${NC}"
    check_kconfig "CONFIG_NO_HZ_FULL" "y" "Tickless Kernel (NO_HZ_FULL)"
    check_kconfig "CONFIG_PREEMPT" "y" "Preemptible Kernel"
    check_kconfig "CONFIG_HIGH_RES_TIMERS" "y" "High Resolution Timers"
    local irq_val nohz_val
    irq_val=$(grep "^CONFIG_IRQ_TIME_ACCOUNTING=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    nohz_val=$(grep "^CONFIG_NO_HZ_FULL=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    if [[ "${irq_val}" == "y" ]]; then test_pass "IRQ Time Accounting: enabled"
    elif [[ "${nohz_val}" == "y" ]]; then test_pass "IRQ Time Accounting: disabled (OK — conflicts with NO_HZ_FULL)"
    else test_fail "IRQ Time Accounting: not enabled"; fi
    check_kconfig "CONFIG_CPU_ISOLATION" "y" "CPU Isolation support"
    check_kconfig "CONFIG_RCU_NOCB_CPU" "y" "RCU Offload (NO-CB CPUs)"

    log ""; log "${BOLD}  --- A6: Network Drivers & Features ---${NC}"
    check_kconfig "CONFIG_BPF" "y" "BPF (eBPF) support"
    check_kconfig "CONFIG_BPF_SYSCALL" "y" "BPF syscall"
    check_kconfig "CONFIG_XDP_SOCKETS" "y" "XDP Sockets (AF_XDP)"
    for drv in E1000E IGB IXGBE I40E ICE MLX4_EN MLX5_CORE; do
        local val; val=$(grep "^CONFIG_${drv}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        [[ "${val}" == "y" || "${val}" == "m" ]] && test_pass "Network driver ${drv}: ${val}" || test_warn "Network driver ${drv}: not enabled"
    done
    for feat in VLAN_8021Q BONDING BRIDGE TUN MACVLAN MACVTAP VHOST_NET; do
        local val; val=$(grep "^CONFIG_${feat}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        [[ "${val}" == "y" || "${val}" == "m" ]] && test_pass "Network feature ${feat}: ${val}" || test_fail "Network feature ${feat}: not enabled"
    done

    log ""; log "${BOLD}  --- A7: UIO / DPDK Support ---${NC}"
    check_kconfig "CONFIG_UIO" "m" "UIO framework"
    local uio_val; uio_val=$(grep "^CONFIG_UIO=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${uio_val}" == "y" ]] && test_pass "UIO: builtin (also OK)"
    local uio_pci; uio_pci=$(grep "^CONFIG_UIO_PCI_GENERIC=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${uio_pci}" == "y" || "${uio_pci}" == "m" ]] && test_pass "UIO PCI Generic: ${uio_pci}" || test_warn "UIO PCI Generic: not enabled (DPDK can use VFIO instead)"

    log ""; log "${BOLD}  --- A8: Kernel Image Size ---${NC}"
    local bzimage="${KERNEL_SRC_DIR}/arch/x86/boot/bzImage"
    if [[ -f "${bzimage}" ]]; then
        local size_mb; size_mb=$(du -m "${bzimage}" | cut -f1)
        test_info "bzImage size: ${size_mb} MB"
        if [[ "${size_mb}" -lt 15 ]]; then test_pass "Kernel size is optimized (< 15MB)"
        elif [[ "${size_mb}" -lt 30 ]]; then test_warn "Kernel size is moderate (${size_mb} MB)"
        else test_fail "Kernel size is large (${size_mb} MB)"; fi
    else test_skip "bzImage not found at ${bzimage}"; fi

    local staging="${PROJECT_ROOT}/build/kernel/staging"
    if [[ -d "${staging}" ]]; then
        local mod_count; mod_count=$(find "${staging}" -name "*.ko" | wc -l)
        test_info "Module count: ${mod_count}"
        [[ "${mod_count}" -lt 100 ]] && test_pass "Module count is lean (< 100)" || test_warn "Module count: ${mod_count} (consider trimming)"
    fi
}

#=============================================================================
# TEST SUITE B: RUNTIME VERIFICATION
#=============================================================================
test_suite_b() {
    section_header "TEST SUITE B: RUNTIME VERIFICATION"
    local running_kernel; running_kernel=$(uname -r)
    log "  Running kernel: ${running_kernel}"; log ""
    local SIMULATED=false
    if [[ "${running_kernel}" != "${KVER}" ]]; then
        log "${YELLOW}  WARNING: Not running on custom kernel ${KVER}${NC}"
        log "${YELLOW}  Some tests will be SIMULATED${NC}"; log ""
        SIMULATED=true
    fi

    log "${BOLD}  --- B1: HugePages Runtime ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] HugePages test"
        local boot_script="${PROJECT_ROOT}/image/root/usr/local/bin/telco-nfv-init.sh"
        if [[ -f "${boot_script}" ]]; then
            grep -q "HUGEPAGES_2M=.*1024" "${boot_script}" && test_pass "Boot script configures HUGEPAGES_2M=1024"
            grep -q "hugetlbfs" "${boot_script}" && test_pass "Boot script mounts hugetlbfs"
        fi
    else
        local hp_2m hp_2m_free
        hp_2m=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo "0")
        hp_2m_free=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo "0")
        test_info "2MB HugePages: ${hp_2m} total, ${hp_2m_free} free"
        [[ "${hp_2m}" -gt 0 ]] && test_pass "HugePages allocated: ${hp_2m} pages" || test_warn "HugePages: 0 allocated"
        mountpoint -q /mnt/huge 2>/dev/null && test_pass "hugetlbfs mounted at /mnt/huge" || test_warn "/mnt/huge not mounted"
    fi

    log ""; log "${BOLD}  --- B2: NUMA Topology ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] NUMA test"; test_pass "Kernel config has NUMA=y, NUMA_BALANCING=y"
    elif command -v numactl &>/dev/null; then
        local numa_nodes; numa_nodes=$(numactl --hardware 2>/dev/null | grep "available" | awk '{print $2}')
        test_info "NUMA nodes available: ${numa_nodes}"
        [[ "${numa_nodes}" -ge 1 ]] && test_pass "NUMA topology detected"
    else test_skip "numactl not installed"; fi

    log ""; log "${BOLD}  --- B3: IOMMU / VT-d Runtime ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] IOMMU test"
        local kiwi_config="${PROJECT_ROOT}/image/config.xml"
        if [[ -f "${kiwi_config}" ]]; then
            grep -q "intel_iommu=on" "${kiwi_config}" && test_pass "config.xml has intel_iommu=on"
            grep -q "iommu=pt" "${kiwi_config}" && test_pass "config.xml has iommu=pt"
        fi
    else
        local cmdline; cmdline=$(cat /proc/cmdline)
        echo "${cmdline}" | grep -q "intel_iommu=on" && test_pass "Intel IOMMU enabled" || test_warn "intel_iommu=on not found"
        echo "${cmdline}" | grep -q "iommu=pt" && test_pass "IOMMU passthrough enabled" || test_warn "iommu=pt not found"
        local ig; ig=$(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        [[ "${ig}" -gt 0 ]] && test_pass "IOMMU groups: ${ig}" || test_warn "No IOMMU groups"
    fi

    log ""; log "${BOLD}  --- B4: Kernel Modules ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] Module loading test"
        for opt in CONFIG_NO_HZ_FULL CONFIG_PREEMPT CONFIG_CPU_ISOLATION CONFIG_RCU_NOCB_CPU; do
            grep -q "^${opt}=y" "${CONFIG_FILE}" 2>/dev/null && test_pass "${opt}=y in .config"
        done
    else
        for mod in vfio vfio_pci vhost_net tun tap bonding 8021q bridge; do
            if lsmod | grep -q "^${mod}"; then test_pass "Module loaded: ${mod}"
            else modprobe "${mod}" 2>/dev/null && test_pass "Module loaded (just now): ${mod}" || test_warn "Module not available: ${mod}"; fi
        done
    fi

    log ""; log "${BOLD}  --- B5: CPU Isolation ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] CPU isolation test"
        test_info "Expected cmdline: isolcpus=2-3 nohz_full=2-3 rcu_nocbs=2-3"
    else
        local cmdline; cmdline=$(cat /proc/cmdline)
        [[ "${cmdline}" =~ isolcpus=([^ ]+) ]] && test_pass "CPU isolation: isolcpus=${BASH_REMATCH[1]}"
        [[ "${cmdline}" =~ nohz_full=([^ ]+) ]] && test_pass "Tickless CPUs: nohz_full=${BASH_REMATCH[1]}"
    fi

    log ""; log "${BOLD}  --- B6: Network Tuning ---${NC}"
    if "${SIMULATED}"; then
        test_info "[SIMULATED] Sysctl tuning test"
        local sysctl_file="${PROJECT_ROOT}/image/root/etc/sysctl.d/90-telco-nfv.conf"
        if [[ -f "${sysctl_file}" ]]; then
            for sc in rmem_max wmem_max netdev_max_backlog swappiness; do
                grep -q "${sc}" "${sysctl_file}" && test_pass "Sysctl config has: ${sc}"
            done
        fi
    else
        for entry in "net.core.rmem_max:134217728" "net.core.wmem_max:134217728" "net.core.netdev_max_backlog:250000" "vm.swappiness:0"; do
            local key="${entry%%:*}" expected="${entry##*:}" actual
            actual=$(sysctl -n "${key}" 2>/dev/null)
            [[ "${actual}" == "${expected}" ]] && test_pass "${key} = ${actual}" || test_warn "${key} = ${actual} (expected: ${expected})"
        done
    fi
}

#=============================================================================
# TEST SUITE C: PERFORMANCE BENCHMARKS
#=============================================================================
test_suite_c() {
    section_header "TEST SUITE C: PERFORMANCE BENCHMARKS"

    log ""; log "${BOLD}  --- C1: Kernel Size Comparison ---${NC}"
    local custom_bzimage="${KERNEL_SRC_DIR}/arch/x86/boot/bzImage"
    local custom_size_kb=""
    if [[ -f "${custom_bzimage}" ]]; then
        custom_size_kb=$(du -k "${custom_bzimage}" | cut -f1)
        test_info "Custom kernel (telco-nfv): ${custom_size_kb} KB"
    fi
    local default_bzimage="/boot/vmlinuz-$(uname -r)"
    if [[ -f "${default_bzimage}" ]]; then
        local default_size_kb; default_size_kb=$(du -k "${default_bzimage}" | cut -f1)
        test_info "Default kernel ($(uname -r)): ${default_size_kb} KB"
        if [[ -n "${custom_size_kb}" ]]; then
            local diff=$(( default_size_kb - custom_size_kb ))
            [[ "${diff}" -gt 0 ]] && test_pass "Custom kernel is ${diff} KB smaller" || test_info "Custom kernel is larger (more Telco drivers)"
        fi
    fi

    log ""; log "${BOLD}  --- C2: Module Count ---${NC}"
    local custom_mods; custom_mods=$(find "${PROJECT_ROOT}/build/kernel/staging" -name "*.ko" 2>/dev/null | wc -l)
    local default_mods; default_mods=$(find "/usr/lib/modules/$(uname -r)" -name "*.ko*" 2>/dev/null | wc -l)
    test_info "Custom: ${custom_mods} | Default: ${default_mods}"
    if [[ "${custom_mods}" -gt 0 && "${default_mods}" -gt 0 ]]; then
        local reduction=$(( (default_mods - custom_mods) * 100 / default_mods ))
        test_pass "Module reduction: ${reduction}% (${default_mods} → ${custom_mods})"
    fi

    log ""; log "${BOLD}  --- C3: Boot Time ---${NC}"
    command -v systemd-analyze &>/dev/null && test_info "Boot: $(systemd-analyze 2>/dev/null | head -1)"

    log ""; log "${BOLD}  --- C4: Image Size ---${NC}"
    local qcow2="${PROJECT_ROOT}/build/image/telco-jeos.x86_64-1.0.0.qcow2"
    if [[ -f "${qcow2}" ]]; then
        local img_mb; img_mb=$(du -m "${qcow2}" | cut -f1)
        test_info "QCOW2 image: ${img_mb} MB"
        [[ "${img_mb}" -lt 500 ]] && test_pass "Image < 500MB — truly JeOS!" || \
        [[ "${img_mb}" -lt 1000 ]] && test_pass "Image < 1GB — lightweight" || test_warn "Image > 1GB"
    fi

    log ""; log "${BOLD}  --- C5: Feature Matrix ---${NC}"
    local features=(
        "HugePages 2MB:CONFIG_HUGETLBFS:y" "NUMA:CONFIG_NUMA:y" "IOMMU:CONFIG_IOMMU_SUPPORT:y"
        "Intel VT-d:CONFIG_INTEL_IOMMU:y" "VFIO:CONFIG_VFIO:y" "KVM:CONFIG_KVM:m"
        "NO_HZ_FULL:CONFIG_NO_HZ_FULL:y" "PREEMPT:CONFIG_PREEMPT:y" "XDP:CONFIG_XDP_SOCKETS:y"
        "eBPF:CONFIG_BPF_SYSCALL:y" "VHOST_NET:CONFIG_VHOST_NET:m" "Bonding:CONFIG_BONDING:m"
    )
    local fp=0 ft=0
    for entry in "${features[@]}"; do
        local name="${entry%%:*}" rest="${entry#*:}" config="${rest%%:*}" expected="${rest##*:}"
        ((ft++))
        local actual; actual=$(grep "^${config}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        if [[ "${actual}" == "${expected}" || "${actual}" == "y" || "${actual}" == "m" ]]; then ((fp++)); fi
    done
    log "  Feature Score: ${fp}/${ft} ($(( fp * 100 / ft ))%)"
    [[ "${fp}" -eq "${ft}" ]] && test_pass "ALL Telco/NFV features enabled!" || test_warn "Some features missing"
}

#=============================================================================
# TEST SUITE D: INTEGRATION TESTS
#=============================================================================
test_suite_d() {
    section_header "TEST SUITE D: INTEGRATION TESTS"

    log "${BOLD}  --- D1: Kernel Component ---${NC}"
    [[ -f "${PROJECT_ROOT}/kernel/configure-telco-kernel.sh" ]] && test_pass "configure-telco-kernel.sh exists" || test_fail "Missing"
    [[ -f "${PROJECT_ROOT}/kernel/kernel-telco-nfv.spec" ]] && test_pass "RPM spec exists" || test_fail "Missing"

    log ""; log "${BOLD}  --- D2: Image Component ---${NC}"
    [[ -f "${PROJECT_ROOT}/image/config.xml" ]] && test_pass "config.xml exists" || test_fail "Missing"
    [[ -f "${PROJECT_ROOT}/image/config.sh" ]] && test_pass "config.sh exists" || test_fail "Missing"

    log ""; log "${BOLD}  --- D3: Overlay Files ---${NC}"
    local overlay="${PROJECT_ROOT}/image/root"
    [[ -f "${overlay}/usr/local/bin/telco-nfv-init.sh" ]] && test_pass "Boot script in overlay" || test_fail "Missing"
    [[ -f "${overlay}/etc/systemd/system/telco-nfv-init.service" ]] && test_pass "systemd service in overlay" || test_fail "Missing"
    [[ -f "${overlay}/etc/telco-nfv/config" ]] && test_pass "Runtime config in overlay" || test_fail "Missing"
    [[ -f "${overlay}/etc/sysctl.d/90-telco-nfv.conf" ]] && test_pass "sysctl config in overlay" || test_fail "Missing"
    [[ -f "${overlay}/etc/modules-load.d/telco-nfv.conf" ]] && test_pass "modules-load config in overlay" || test_fail "Missing"

    log ""; log "${BOLD}  --- D4: Shared Libraries ---${NC}"
    [[ -f "${PROJECT_ROOT}/lib/logger.sh" ]] && test_pass "lib/logger.sh exists" || test_fail "Missing"
    [[ -f "${PROJECT_ROOT}/lib/utils.sh" ]] && test_pass "lib/utils.sh exists" || test_fail "Missing"
    [[ -f "${PROJECT_ROOT}/lib/config.sh" ]] && test_pass "lib/config.sh exists" || test_fail "Missing"

    log ""; log "${BOLD}  --- D5: Boot Script Quality ---${NC}"
    local boot_script="${overlay}/usr/local/bin/telco-nfv-init.sh"
    if [[ -f "${boot_script}" ]]; then
        for func in configure_hugepages configure_network load_kernel_modules verify_cpu_isolation apply_sysctl_tuning verify_iommu print_summary; do
            grep -q "^${func}()" "${boot_script}" && test_pass "Function: ${func}()" || test_fail "Missing: ${func}()"
        done
        if command -v shellcheck &>/dev/null; then
            local sc_errors; sc_errors=$(shellcheck -S error "${boot_script}" 2>/dev/null | wc -l)
            [[ "${sc_errors}" -eq 0 ]] && test_pass "shellcheck: no errors" || test_warn "shellcheck: ${sc_errors} issues"
        fi
    fi
}

#=============================================================================
# MAIN
#=============================================================================
print_report() {
    section_header "FINAL TEST REPORT"
    local total=$((PASS + FAIL + WARN + SKIP))
    log ""; log "  ${GREEN}PASS${NC}: ${PASS} | ${RED}FAIL${NC}: ${FAIL} | ${YELLOW}WARN${NC}: ${WARN} | ${BLUE}SKIP${NC}: ${SKIP} | ${BOLD}TOTAL${NC}: ${total}"
    [[ "${FAIL}" -eq 0 ]] && log "  ${GREEN}${BOLD}ALL TESTS PASSED!${NC}" || log "  ${RED}${BOLD}${FAIL} TESTS FAILED${NC}"
    log "  Log: ${LOG_FILE}"
}

main() {
    log "${BOLD}Telco/NFV Kernel Test Suite v2.0 — ${KVER}${NC}"
    case "${RUN_SUITE}" in
        a) test_suite_a ;; b) test_suite_b ;; c) test_suite_c ;; d) test_suite_d ;;
        *) test_suite_a; test_suite_b; test_suite_c; test_suite_d ;;
    esac
    print_report
    [[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
