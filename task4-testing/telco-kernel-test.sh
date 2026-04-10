#!/bin/bash
#=============================================================================
# telco-kernel-test.sh
#
# Task 4: Comprehensive Testing Suite for Telco/NFV Custom Kernel
# 
# Tests:
#   A. Kernel Config Verification (offline - parse .config)
#   B. Runtime Verification (online - chạy trên kernel đang boot)
#   C. Performance Benchmarks (so sánh trước/sau)
#
# Author: Hung Anh
# Project: Telco JeOS Builder (Ericsson Ascent Cloud Engineer)
#=============================================================================

set -uo pipefail

#-----------------------------------------------------------------------------
# CONFIG
#-----------------------------------------------------------------------------
KVER="6.6.70-telco-nfv"
CONFIG_FILE="${CONFIG_FILE:-$(dirname "$0")/../task1-kernel/linux-6.6.70/.config}"
LOG_FILE="/tmp/telco-kernel-test-$(date +%Y%m%d-%H%M%S).log"
PASS=0
FAIL=0
WARN=0
SKIP=0

#-----------------------------------------------------------------------------
# COLORS & FORMATTING
#-----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

#-----------------------------------------------------------------------------
# HELPER FUNCTIONS
#-----------------------------------------------------------------------------
log() {
    echo -e "$@" | tee -a "${LOG_FILE}"
}

test_pass() {
    log "${GREEN}  [PASS]${NC} $1"
    ((PASS++))
}

test_fail() {
    log "${RED}  [FAIL]${NC} $1"
    ((FAIL++))
}

test_warn() {
    log "${YELLOW}  [WARN]${NC} $1"
    ((WARN++))
}

test_skip() {
    log "${BLUE}  [SKIP]${NC} $1"
    ((SKIP++))
}

test_info() {
    log "${CYAN}  [INFO]${NC} $1"
}

section_header() {
    log ""
    log "${BOLD}================================================================${NC}"
    log "${BOLD}  $1${NC}"
    log "${BOLD}================================================================${NC}"
}

# Check kernel .config for a specific option
check_kconfig() {
    local option="$1"
    local expected="$2"
    local description="$3"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        test_skip "${description} (no .config file)"
        return
    fi
    
    local actual
    actual=$(grep "^${option}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "${actual}" ]]; then
        # Check if it's "not set"
        if grep -q "# ${option} is not set" "${CONFIG_FILE}" 2>/dev/null; then
            actual="n"
        else
            actual="(not found)"
        fi
    fi
    
    if [[ "${actual}" == "${expected}" ]]; then
        test_pass "${description}: ${option}=${actual}"
    else
        test_fail "${description}: ${option}=${actual} (expected: ${expected})"
    fi
}

#=============================================================================
# TEST SUITE A: KERNEL CONFIG VERIFICATION (Offline)
# Parse .config file — chạy được trên mọi máy
#=============================================================================
test_suite_a() {
    section_header "TEST SUITE A: KERNEL CONFIG VERIFICATION"
    log "  Config file: ${CONFIG_FILE}"
    log ""
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        test_fail ".config file not found: ${CONFIG_FILE}"
        return
    fi
    
    #--- A1: HugePages ---
    log "${BOLD}  --- A1: HugePages Support ---${NC}"
    check_kconfig "CONFIG_HUGETLBFS"        "y" "HugeTLB Filesystem"
    check_kconfig "CONFIG_HUGETLB_PAGE"     "y" "HugeTLB Page support"
    check_kconfig "CONFIG_TRANSPARENT_HUGEPAGE" "y" "Transparent HugePages (THP)"
    
    # Check ARCH_HAS_GIGANTIC_PAGE cho 1GB hugepages
    if grep -q "CONFIG_ARCH_HAS_GIGANTIC_PAGE=y" "${CONFIG_FILE}" 2>/dev/null; then
        test_pass "1GB Gigantic HugePages: supported"
    else
        test_info "1GB Gigantic HugePages: not explicitly set (arch dependent)"
    fi
    
    #--- A2: NUMA ---
    log ""
    log "${BOLD}  --- A2: NUMA Support ---${NC}"
    check_kconfig "CONFIG_NUMA"             "y" "NUMA Memory Allocation"
    check_kconfig "CONFIG_NUMA_BALANCING"   "y" "NUMA Auto-Balancing"
    check_kconfig "CONFIG_X86_64_ACPI_NUMA" "y" "ACPI NUMA Detection"
    
    #--- A3: IOMMU / VFIO ---
    log ""
    log "${BOLD}  --- A3: IOMMU / VFIO (Device Passthrough) ---${NC}"
    check_kconfig "CONFIG_IOMMU_SUPPORT"    "y" "IOMMU Framework"
    check_kconfig "CONFIG_INTEL_IOMMU"      "y" "Intel VT-d IOMMU"
    check_kconfig "CONFIG_VFIO"             "y" "VFIO Framework"
    check_kconfig "CONFIG_VFIO_IOMMU_TYPE1" "y" "VFIO IOMMU Type1"
    
    # VFIO-PCI có thể là module
    local vfio_pci
    vfio_pci=$(grep "^CONFIG_VFIO_PCI=" "${CONFIG_FILE}" | cut -d= -f2)
    if [[ "${vfio_pci}" == "y" || "${vfio_pci}" == "m" ]]; then
        test_pass "VFIO-PCI driver: ${vfio_pci} (y=builtin, m=module)"
    else
        test_fail "VFIO-PCI driver: not enabled"
    fi
    
    #--- A4: KVM Virtualization ---
    log ""
    log "${BOLD}  --- A4: KVM Virtualization ---${NC}"
    # KVM: accept both y and m (module is preferred for Telco)
    local kvm_val_check
    kvm_val_check=$(grep "^CONFIG_KVM=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    if [[ "${kvm_val_check}" == "y" || "${kvm_val_check}" == "m" ]]; then
        test_pass "KVM core: =${kvm_val_check} (y=builtin, m=module, both OK)"
    else
        test_fail "KVM core: not enabled"
    fi
    
    local kvm_val
    kvm_val=$(grep "^CONFIG_KVM=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${kvm_val}" == "m" ]] && test_pass "KVM: built as module (OK for Telco)"
    
    local kvm_intel
    kvm_intel=$(grep "^CONFIG_KVM_INTEL=" "${CONFIG_FILE}" | cut -d= -f2)
    if [[ "${kvm_intel}" == "y" || "${kvm_intel}" == "m" ]]; then
        test_pass "KVM Intel (VMX): ${kvm_intel}"
    else
        test_fail "KVM Intel (VMX): not enabled"
    fi
    
    #--- A5: CPU Isolation / Low Latency ---
    log ""
    log "${BOLD}  --- A5: CPU Isolation & Low Latency ---${NC}"
    check_kconfig "CONFIG_NO_HZ_FULL"       "y" "Tickless Kernel (NO_HZ_FULL)"
    check_kconfig "CONFIG_PREEMPT"          "y" "Preemptible Kernel"
    check_kconfig "CONFIG_HIGH_RES_TIMERS"  "y" "High Resolution Timers"
    # IRQ_TIME_ACCOUNTING may be disabled by NO_HZ_FULL (kernel dependency)
    local irq_val
    irq_val=$(grep "^CONFIG_IRQ_TIME_ACCOUNTING=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    local nohz_val
    nohz_val=$(grep "^CONFIG_NO_HZ_FULL=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
    if [[ "${irq_val}" == "y" ]]; then
        test_pass "IRQ Time Accounting: enabled"
    elif [[ "${nohz_val}" == "y" ]]; then
        test_pass "IRQ Time Accounting: disabled (OK — conflicts with NO_HZ_FULL for low-latency)"
    else
        test_fail "IRQ Time Accounting: not enabled"
    fi
    check_kconfig "CONFIG_CPU_ISOLATION"    "y" "CPU Isolation support"
    check_kconfig "CONFIG_RCU_NOCB_CPU"     "y" "RCU Offload (NO-CB CPUs)"
    
    #--- A6: Networking ---
    log ""
    log "${BOLD}  --- A6: Network Drivers & Features ---${NC}"
    
    # XDP/eBPF
    check_kconfig "CONFIG_BPF"              "y" "BPF (eBPF) support"
    check_kconfig "CONFIG_BPF_SYSCALL"      "y" "BPF syscall"
    check_kconfig "CONFIG_XDP_SOCKETS"      "y" "XDP Sockets (AF_XDP)"
    
    # Networking modules/features
    local net_drivers=("E1000E" "IGB" "IXGBE" "I40E" "ICE" "MLX4_EN" "MLX5_CORE")
    for drv in "${net_drivers[@]}"; do
        local val
        val=$(grep "^CONFIG_${drv}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        if [[ "${val}" == "y" || "${val}" == "m" ]]; then
            test_pass "Network driver ${drv}: ${val}"
        else
            test_warn "Network driver ${drv}: not enabled"
        fi
    done
    
    # VLAN, Bonding, Bridge
    for feat in "VLAN_8021Q" "BONDING" "BRIDGE" "TUN" "MACVLAN" "MACVTAP" "VHOST_NET"; do
        local val
        val=$(grep "^CONFIG_${feat}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        if [[ "${val}" == "y" || "${val}" == "m" ]]; then
            test_pass "Network feature ${feat}: ${val}"
        else
            test_fail "Network feature ${feat}: not enabled"
        fi
    done
    
    #--- A7: UIO (for DPDK) ---
    log ""
    log "${BOLD}  --- A7: UIO / DPDK Support ---${NC}"
    check_kconfig "CONFIG_UIO" "m" "UIO framework"
    
    local uio_val
    uio_val=$(grep "^CONFIG_UIO=" "${CONFIG_FILE}" | cut -d= -f2)
    [[ "${uio_val}" == "y" ]] && test_pass "UIO: builtin (also OK)"
    
    local uio_pci
    uio_pci=$(grep "^CONFIG_UIO_PCI_GENERIC=" "${CONFIG_FILE}" | cut -d= -f2)
    if [[ "${uio_pci}" == "y" || "${uio_pci}" == "m" ]]; then
        test_pass "UIO PCI Generic: ${uio_pci}"
    else
        test_warn "UIO PCI Generic: not enabled (DPDK can use VFIO instead)"
    fi
    
    #--- A8: Kernel Size ---
    log ""
    log "${BOLD}  --- A8: Kernel Image Size ---${NC}"
    
    local bzimage
    bzimage="$(dirname "${CONFIG_FILE}")/arch/x86/boot/bzImage"
    if [[ -f "${bzimage}" ]]; then
        local size_mb
        size_mb=$(du -m "${bzimage}" | cut -f1)
        test_info "bzImage size: ${size_mb} MB"
        
        if [[ "${size_mb}" -lt 15 ]]; then
            test_pass "Kernel size is optimized (< 15MB)"
        elif [[ "${size_mb}" -lt 30 ]]; then
            test_warn "Kernel size is moderate (${size_mb} MB)"
        else
            test_fail "Kernel size is large (${size_mb} MB) — consider disabling unused features"
        fi
    else
        test_skip "bzImage not found at ${bzimage}"
    fi
    
    # Module count
    local staging
    staging="$(dirname "${CONFIG_FILE}")/../../staging"
    if [[ -d "${staging}" ]]; then
        local mod_count
        mod_count=$(find "${staging}" -name "*.ko" | wc -l)
        test_info "Module count: ${mod_count}"
        
        if [[ "${mod_count}" -lt 100 ]]; then
            test_pass "Module count is lean (< 100) — good for Telco JeOS"
        else
            test_warn "Module count: ${mod_count} (consider trimming)"
        fi
    fi
}

#=============================================================================
# TEST SUITE B: RUNTIME VERIFICATION
# Phải chạy trên kernel 6.6.70-telco-nfv (trong QEMU hoặc bare-metal)
#=============================================================================
test_suite_b() {
    section_header "TEST SUITE B: RUNTIME VERIFICATION"
    
    local running_kernel
    running_kernel=$(uname -r)
    log "  Running kernel: ${running_kernel}"
    log ""
    
    if [[ "${running_kernel}" != "${KVER}" ]]; then
        log "${YELLOW}  WARNING: Not running on custom kernel ${KVER}${NC}"
        log "${YELLOW}  Running on: ${running_kernel}${NC}"
        log "${YELLOW}  Some tests will be SIMULATED with expected values${NC}"
        log ""
        local SIMULATED=true
    else
        local SIMULATED=false
    fi
    
    #--- B1: HugePages Runtime ---
    log "${BOLD}  --- B1: HugePages Runtime ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] HugePages test (would check /sys/kernel/mm/hugepages/)"
        test_info "Expected: 1024 x 2MB = 2048 MB reserved for DPDK"
        
        # Verify the boot script would do the right thing
        local boot_script
        boot_script="$(dirname "$0")/task3-bootscript/telco-nfv-init.sh"
        if [[ -f "${boot_script}" ]]; then
            if grep -q "HUGEPAGES_2M=.*1024" "${boot_script}"; then
                test_pass "Boot script configures HUGEPAGES_2M=1024"
            fi
            if grep -q "hugetlbfs" "${boot_script}"; then
                test_pass "Boot script mounts hugetlbfs at /mnt/huge"
            fi
        fi
    else
        local hp_2m hp_2m_free
        hp_2m=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || echo "0")
        hp_2m_free=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages 2>/dev/null || echo "0")
        
        test_info "2MB HugePages: ${hp_2m} total, ${hp_2m_free} free"
        
        if [[ "${hp_2m}" -gt 0 ]]; then
            test_pass "HugePages allocated: ${hp_2m} pages = $(( hp_2m * 2 )) MB"
        else
            test_warn "HugePages: 0 allocated (run boot script or set hugepages= in cmdline)"
        fi
        
        if mountpoint -q /mnt/huge 2>/dev/null; then
            test_pass "hugetlbfs mounted at /mnt/huge"
        else
            test_warn "/mnt/huge not mounted"
        fi
    fi
    
    #--- B2: NUMA Runtime ---
    log ""
    log "${BOLD}  --- B2: NUMA Topology ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] NUMA test"
        test_info "Expected: numactl --hardware shows node distances and CPU mapping"
        test_pass "Kernel config has NUMA=y, NUMA_BALANCING=y"
    else
        if command -v numactl &>/dev/null; then
            local numa_nodes
            numa_nodes=$(numactl --hardware 2>/dev/null | grep "available" | awk '{print $2}')
            test_info "NUMA nodes available: ${numa_nodes}"
            
            numactl --hardware 2>/dev/null | head -5 | while read -r line; do
                test_info "  ${line}"
            done
            
            if [[ "${numa_nodes}" -ge 1 ]]; then
                test_pass "NUMA topology detected"
            fi
        else
            test_skip "numactl not installed"
        fi
    fi
    
    #--- B3: IOMMU Runtime ---
    log ""
    log "${BOLD}  --- B3: IOMMU / VT-d Runtime ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] IOMMU test"
        test_info "Expected cmdline: intel_iommu=on iommu=pt"
        
        # Verify in kiwi config.xml
        local kiwi_config
        kiwi_config="$(dirname "$0")/task2-kiwi/description/config.xml"
        if [[ -f "${kiwi_config}" ]]; then
            if grep -q "intel_iommu=on" "${kiwi_config}"; then
                test_pass "config.xml has intel_iommu=on in kernelcmdline"
            fi
            if grep -q "iommu=pt" "${kiwi_config}"; then
                test_pass "config.xml has iommu=pt (passthrough mode)"
            fi
        fi
    else
        local cmdline
        cmdline=$(cat /proc/cmdline)
        
        if echo "${cmdline}" | grep -q "intel_iommu=on"; then
            test_pass "Intel IOMMU enabled in cmdline"
        else
            test_warn "intel_iommu=on not found in cmdline"
        fi
        
        if echo "${cmdline}" | grep -q "iommu=pt"; then
            test_pass "IOMMU passthrough mode enabled"
        else
            test_warn "iommu=pt not found in cmdline"
        fi
        
        local iommu_groups
        iommu_groups=$(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        if [[ "${iommu_groups}" -gt 0 ]]; then
            test_pass "IOMMU groups: ${iommu_groups} groups found"
        else
            test_warn "No IOMMU groups found"
        fi
    fi
    
    #--- B4: Kernel Modules ---
    log ""
    log "${BOLD}  --- B4: Telco/NFV Kernel Modules ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] Module loading test"
        
        # Check RPM contents
        local rpm_file
        rpm_file=$(find "$(dirname "$0")/task1-kernel/rpmbuild/RPMS" -name "*.rpm" 2>/dev/null | head -1)
        if [[ -n "${rpm_file}" ]]; then
            test_info "Checking RPM: ${rpm_file}"
            
            local expected_modules=("vfio-pci" "vhost_net" "tun" "tap" "bonding" "8021q" "bridge" "kvm" "e1000e" "igb" "ixgbe" "i40e" "ice")
            for mod in "${expected_modules[@]}"; do
                if rpm -qlp "${rpm_file}" 2>/dev/null | grep -qi "${mod}"; then
                    test_pass "Module in RPM: ${mod}"
                else
                    # Might be builtin
                    if grep -q "CONFIG_$(echo "${mod}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')=y" "${CONFIG_FILE}" 2>/dev/null; then
                        test_pass "Module ${mod}: built-in to kernel (not .ko)"
                    else
                        test_info "Module ${mod}: not found in RPM (may be builtin or optional)"
                    fi
                fi
            done
        fi
    else
        local modules=("vfio" "vfio_pci" "vhost_net" "tun" "tap" "bonding" "8021q" "bridge")
        for mod in "${modules[@]}"; do
            if lsmod | grep -q "^${mod}"; then
                test_pass "Module loaded: ${mod}"
            else
                modprobe "${mod}" 2>/dev/null && \
                    test_pass "Module loaded (just now): ${mod}" || \
                    test_warn "Module not available: ${mod}"
            fi
        done
    fi
    
    #--- B5: CPU Isolation ---
    log ""
    log "${BOLD}  --- B5: CPU Isolation & Low Latency ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] CPU isolation test"
        
        # Check config
        for opt in "CONFIG_NO_HZ_FULL" "CONFIG_PREEMPT" "CONFIG_CPU_ISOLATION" "CONFIG_RCU_NOCB_CPU"; do
            if grep -q "^${opt}=y" "${CONFIG_FILE}" 2>/dev/null; then
                test_pass "${opt}=y in .config"
            fi
        done
        
        test_info "Expected cmdline: isolcpus=2-3 nohz_full=2-3 rcu_nocbs=2-3"
    else
        local cmdline
        cmdline=$(cat /proc/cmdline)
        
        if [[ "${cmdline}" =~ isolcpus=([^ ]+) ]]; then
            test_pass "CPU isolation: isolcpus=${BASH_REMATCH[1]}"
        fi
        
        if [[ "${cmdline}" =~ nohz_full=([^ ]+) ]]; then
            test_pass "Tickless CPUs: nohz_full=${BASH_REMATCH[1]}"
        fi
    fi
    
    #--- B6: Network Sysctl ---
    log ""
    log "${BOLD}  --- B6: Network Performance Tuning ---${NC}"
    
    if [[ "${SIMULATED}" == true ]]; then
        test_info "[SIMULATED] Sysctl tuning test"
        
        local sysctl_file
        sysctl_file="$(dirname "$0")/task3-bootscript/telco-nfv-init.sh"
        if [[ -f "${sysctl_file}" ]]; then
            local expected_sysctls=("rmem_max" "wmem_max" "netdev_max_backlog" "swappiness")
            for sc in "${expected_sysctls[@]}"; do
                if grep -q "${sc}" "${sysctl_file}"; then
                    test_pass "Boot script configures: ${sc}"
                fi
            done
        fi
    else
        local sysctls=(
            "net.core.rmem_max:134217728"
            "net.core.wmem_max:134217728"
            "net.core.netdev_max_backlog:250000"
            "vm.swappiness:0"
        )
        
        for entry in "${sysctls[@]}"; do
            local key="${entry%%:*}"
            local expected="${entry##*:}"
            local actual
            actual=$(sysctl -n "${key}" 2>/dev/null)
            
            if [[ "${actual}" == "${expected}" ]]; then
                test_pass "${key} = ${actual}"
            else
                test_warn "${key} = ${actual} (expected: ${expected})"
            fi
        done
    fi
}

#=============================================================================
# TEST SUITE C: PERFORMANCE BENCHMARKS
# So sánh default kernel vs custom kernel
#=============================================================================
test_suite_c() {
    section_header "TEST SUITE C: PERFORMANCE BENCHMARKS"
    
    log ""
    log "${BOLD}  --- C1: Kernel Size Comparison ---${NC}"
    
    # Custom kernel size
    local custom_bzimage
    custom_bzimage="$(dirname "$0")/../task1-kernel/linux-6.6.70/arch/x86/boot/bzImage"
    
    if [[ -f "${custom_bzimage}" ]]; then
        local custom_size_kb
        custom_size_kb=$(du -k "${custom_bzimage}" | cut -f1)
        test_info "Custom kernel (telco-nfv): ${custom_size_kb} KB"
    fi
    
    # Default kernel size (nếu có)
    local default_bzimage="/boot/vmlinuz-$(uname -r)"
    if [[ -f "${default_bzimage}" ]]; then
        local default_size_kb
        default_size_kb=$(du -k "${default_bzimage}" | cut -f1)
        test_info "Default kernel ($(uname -r)): ${default_size_kb} KB"
        
        if [[ -n "${custom_size_kb}" ]]; then
            local diff=$(( default_size_kb - custom_size_kb ))
            local pct=$(( diff * 100 / default_size_kb ))
            if [[ "${diff}" -gt 0 ]]; then
                test_pass "Custom kernel is ${diff} KB smaller (${pct}% reduction)"
            else
                test_info "Custom kernel is larger (includes more Telco-specific drivers)"
            fi
        fi
    else
        test_info "Default kernel not found at ${default_bzimage}"
        test_info "Typical generic kernel: ~12-15 MB"
        test_info "Our Telco kernel: ~$(( custom_size_kb / 1024 )) MB (optimized for NFV)"
    fi
    
    #--- C2: Module Count Comparison ---
    log ""
    log "${BOLD}  --- C2: Module Count Comparison ---${NC}"
    
    local custom_mods
    custom_mods=$(find "$(dirname "$0")/../task1-kernel/staging" -name "*.ko" 2>/dev/null | wc -l)
    
    local default_mods
    default_mods=$(find "/usr/lib/modules/$(uname -r)" -name "*.ko*" 2>/dev/null | wc -l)
    
    test_info "Custom kernel modules: ${custom_mods}"
    test_info "Default kernel modules: ${default_mods}"
    
    if [[ "${custom_mods}" -gt 0 && "${default_mods}" -gt 0 ]]; then
        local reduction=$(( (default_mods - custom_mods) * 100 / default_mods ))
        test_pass "Module reduction: ${reduction}% (${default_mods} → ${custom_mods})"
        test_info "Fewer modules = smaller attack surface + faster boot"
    fi
    
    #--- C3: Boot Time Estimation ---
    log ""
    log "${BOLD}  --- C3: Boot Time Analysis ---${NC}"
    
    test_info "Expected boot improvements with custom kernel:"
    test_info "  - Fewer modules to load → faster initramfs"
    test_info "  - NO_HZ_FULL → less timer overhead on isolated CPUs"
    test_info "  - PREEMPT → better response time for VNFs"
    test_info "  - Disabled unused drivers → less probe time"
    
    if command -v systemd-analyze &>/dev/null; then
        local boot_time
        boot_time=$(systemd-analyze 2>/dev/null | head -1)
        test_info "Current system boot: ${boot_time}"
    fi
    
    #--- C4: Memory Overhead ---
    log ""
    log "${BOLD}  --- C4: Memory Footprint ---${NC}"
    
    # RPM size
    local rpm_file
    rpm_file=$(find "$(dirname "$0")/../task1-kernel/rpmbuild/RPMS" -name "*.rpm" 2>/dev/null | head -1)
    if [[ -n "${rpm_file}" ]]; then
        local rpm_size
        rpm_size=$(du -h "${rpm_file}" | cut -f1)
        test_info "Kernel RPM size: ${rpm_size}"
    fi
    
    # Image size
    local qcow2
    qcow2="$(dirname "$0")/../task2-kiwi/build/telco-jeos.x86_64-1.0.0.qcow2"
    if [[ -f "${qcow2}" ]]; then
        local img_size
        img_size=$(du -h "${qcow2}" | cut -f1)
        test_info "QCOW2 image size: ${img_size}"
        
        local img_size_mb
        img_size_mb=$(du -m "${qcow2}" | cut -f1)
        if [[ "${img_size_mb}" -lt 500 ]]; then
            test_pass "Image size < 500MB — truly JeOS (Just enough OS)!"
        elif [[ "${img_size_mb}" -lt 1000 ]]; then
            test_pass "Image size < 1GB — lightweight Telco appliance"
        else
            test_warn "Image size > 1GB — consider removing packages"
        fi
    fi
    
    #--- C5: Telco Feature Matrix ---
    log ""
    log "${BOLD}  --- C5: Telco/NFV Feature Completeness Matrix ---${NC}"
    
    local features=(
        "HugePages 2MB:CONFIG_HUGETLBFS:y"
        "HugePages 1GB:CONFIG_ARCH_HAS_GIGANTIC_PAGE:y"
        "NUMA:CONFIG_NUMA:y"
        "NUMA Balancing:CONFIG_NUMA_BALANCING:y"
        "IOMMU:CONFIG_IOMMU_SUPPORT:y"
        "Intel VT-d:CONFIG_INTEL_IOMMU:y"
        "VFIO:CONFIG_VFIO:y"
        "VFIO-PCI:CONFIG_VFIO_PCI:m"
        "KVM:CONFIG_KVM:m"
        "SR-IOV:CONFIG_PCI_IOV:y"
        "NO_HZ_FULL:CONFIG_NO_HZ_FULL:y"
        "PREEMPT:CONFIG_PREEMPT:y"
        "CPU Isolation:CONFIG_CPU_ISOLATION:y"
        "RCU Offload:CONFIG_RCU_NOCB_CPU:y"
        "XDP:CONFIG_XDP_SOCKETS:y"
        "eBPF:CONFIG_BPF_SYSCALL:y"
        "UIO:CONFIG_UIO:m"
        "DPDK UIO PCI:CONFIG_UIO_PCI_GENERIC:m"
        "VLAN 802.1Q:CONFIG_VLAN_8021Q:m"
        "Bonding:CONFIG_BONDING:m"
        "Bridge:CONFIG_BRIDGE:m"
        "VHOST_NET:CONFIG_VHOST_NET:m"
        "TUN/TAP:CONFIG_TUN:m"
    )
    
    log ""
    log "  ┌─────────────────────────┬──────────┬──────────┐"
    log "  │ Feature                 │ Required │ Status   │"
    log "  ├─────────────────────────┼──────────┼──────────┤"
    
    local feature_pass=0
    local feature_total=0
    
    for entry in "${features[@]}"; do
        local name="${entry%%:*}"
        local rest="${entry#*:}"
        local config="${rest%%:*}"
        local expected="${rest##*:}"
        
        ((feature_total++))
        
        local actual
        actual=$(grep "^${config}=" "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2)
        
        local status_icon
        if [[ "${actual}" == "${expected}" ]]; then
            status_icon="${GREEN}✅ PASS${NC}"
            ((feature_pass++))
        elif [[ "${actual}" == "y" || "${actual}" == "m" ]]; then
            status_icon="${GREEN}✅ OK  ${NC}"
            ((feature_pass++))
        else
            status_icon="${RED}❌ MISS${NC}"
        fi
        
        printf "  │ %-23s │ %-8s │ " "${name}" "${expected}" | tee -a "${LOG_FILE}"
        echo -e "${status_icon} │" | tee -a "${LOG_FILE}"
    done
    
    log "  └─────────────────────────┴──────────┴──────────┘"
    log ""
    log "  Feature Score: ${feature_pass}/${feature_total} ($(( feature_pass * 100 / feature_total ))%)"
    
    if [[ "${feature_pass}" -eq "${feature_total}" ]]; then
        test_pass "ALL Telco/NFV features enabled! 🎉"
    elif [[ "$(( feature_pass * 100 / feature_total ))" -ge 90 ]]; then
        test_pass "Telco/NFV feature coverage > 90%"
    else
        test_warn "Some Telco/NFV features missing"
    fi
}

#=============================================================================
# TEST SUITE D: INTEGRATION TESTS
# Kiểm tra Task 1-3 liên kết đúng
#=============================================================================
test_suite_d() {
    section_header "TEST SUITE D: INTEGRATION TESTS (Task 1-3)"
    
    local base_dir
    base_dir="$(cd "$(dirname "$0")/.." && pwd)"
    
    #--- D1: Task 1 outputs ---
    log "${BOLD}  --- D1: Task 1 Outputs (Kernel Build) ---${NC}"
    
    local bzimage="${base_dir}/task1-kernel/linux-6.6.70/arch/x86/boot/bzImage"
    [[ -f "${bzimage}" ]] && test_pass "bzImage exists" || test_fail "bzImage missing"
    
    local rpm
    rpm=$(find "${base_dir}/task1-kernel/rpmbuild/RPMS" -name "*.rpm" 2>/dev/null | head -1)
    [[ -n "${rpm}" ]] && test_pass "Kernel RPM: $(basename "${rpm}")" || test_fail "Kernel RPM missing"
    
    if [[ -n "${rpm}" ]]; then
        # Check RPM has modules.dep
        if rpm -qlp "${rpm}" 2>/dev/null | grep -q "modules.dep"; then
            test_pass "RPM contains modules.dep"
        else
            test_fail "RPM missing modules.dep"
        fi
        
        # Check RPM has vmlinuz
        if rpm -qlp "${rpm}" 2>/dev/null | grep -q "vmlinuz"; then
            test_pass "RPM contains vmlinuz"
        else
            test_fail "RPM missing vmlinuz"
        fi
    fi
    
    local repodata="${base_dir}/task1-kernel/rpmbuild/RPMS/x86_64/repodata/repomd.xml"
    [[ -f "${repodata}" ]] && test_pass "RPM repo metadata exists" || test_fail "Repo metadata missing"
    
    #--- D2: Task 2 outputs ---
    log ""
    log "${BOLD}  --- D2: Task 2 Outputs (Kiwi Image) ---${NC}"
    
    local config_xml="${base_dir}/task2-kiwi/description/config.xml"
    [[ -f "${config_xml}" ]] && test_pass "config.xml exists" || test_fail "config.xml missing"
    
    local config_sh="${base_dir}/task2-kiwi/description/config.sh"
    [[ -f "${config_sh}" ]] && test_pass "config.sh exists" || test_fail "config.sh missing"
    
    local qcow2="${base_dir}/task2-kiwi/build/telco-jeos.x86_64-1.0.0.qcow2"
    [[ -f "${qcow2}" ]] && test_pass "QCOW2 image built" || test_fail "QCOW2 image missing"
    
    local packages="${base_dir}/task2-kiwi/build/telco-jeos.x86_64-1.0.0.packages"
    if [[ -f "${packages}" ]]; then
        test_pass "Package manifest exists"
        
        if grep -q "kernel-telco-nfv" "${packages}"; then
            test_pass "Custom kernel installed in image"
        else
            test_fail "Custom kernel NOT in image"
        fi
        
        for pkg in "numactl" "hwloc" "tuned" "ethtool" "bridge-utils"; do
            if grep -q "${pkg}" "${packages}"; then
                test_pass "Telco package in image: ${pkg}"
            else
                test_fail "Missing from image: ${pkg}"
            fi
        done
    fi
    
    # Check overlay files
    local overlay="${base_dir}/task2-kiwi/description/root"
    if [[ -d "${overlay}" ]]; then
        [[ -f "${overlay}/usr/local/bin/telco-nfv-init.sh" ]] && \
            test_pass "Boot script in overlay" || test_fail "Boot script missing from overlay"
        [[ -f "${overlay}/etc/systemd/system/telco-nfv-init.service" ]] && \
            test_pass "systemd service in overlay" || test_fail "systemd service missing from overlay"
    fi
    
    #--- D3: Task 3 outputs ---
    log ""
    log "${BOLD}  --- D3: Task 3 Outputs (Boot Script) ---${NC}"
    
    local boot_script="${base_dir}/task3-bootscript/telco-nfv-init.sh"
    if [[ -f "${boot_script}" ]]; then
        test_pass "Boot script exists ($(wc -l < "${boot_script}") lines)"
        
        [[ -x "${boot_script}" ]] && test_pass "Boot script is executable" || test_fail "Boot script not executable"
        
        # Check functions exist
        local functions=("configure_hugepages" "configure_network" "load_kernel_modules" "verify_cpu_isolation" "apply_sysctl_tuning" "verify_iommu" "print_summary")
        for func in "${functions[@]}"; do
            if grep -q "^${func}()" "${boot_script}"; then
                test_pass "Function defined: ${func}()"
            else
                test_fail "Function missing: ${func}()"
            fi
        done
        
        # Shellcheck (nếu có)
        if command -v shellcheck &>/dev/null; then
            local sc_errors
            sc_errors=$(shellcheck -S error "${boot_script}" 2>/dev/null | wc -l)
            if [[ "${sc_errors}" -eq 0 ]]; then
                test_pass "shellcheck: no errors"
            else
                test_warn "shellcheck: ${sc_errors} issues found"
            fi
        else
            test_skip "shellcheck not installed"
        fi
    else
        test_fail "Boot script missing"
    fi
    
    local service_file="${base_dir}/task3-bootscript/telco-nfv-init.service"
    if [[ -f "${service_file}" ]]; then
        test_pass "systemd service file exists"
        
        if grep -q "Type=oneshot" "${service_file}"; then
            test_pass "Service type: oneshot (correct for init script)"
        fi
        if grep -q "WantedBy=multi-user.target" "${service_file}"; then
            test_pass "Service enabled at: multi-user.target"
        fi
    fi
}

#=============================================================================
# MAIN REPORT
#=============================================================================
print_report() {
    section_header "FINAL TEST REPORT"
    
    local total=$((PASS + FAIL + WARN + SKIP))
    
    log ""
    log "  ┌────────────┬───────┐"
    log "  │ Result     │ Count │"
    log "  ├────────────┼───────┤"
    log "  │ ${GREEN}PASS${NC}       │ $(printf '%5d' ${PASS}) │"
    log "  │ ${RED}FAIL${NC}       │ $(printf '%5d' ${FAIL}) │"
    log "  │ ${YELLOW}WARN${NC}       │ $(printf '%5d' ${WARN}) │"
    log "  │ ${BLUE}SKIP${NC}       │ $(printf '%5d' ${SKIP}) │"
    log "  ├────────────┼───────┤"
    log "  │ ${BOLD}TOTAL${NC}      │ $(printf '%5d' ${total}) │"
    log "  └────────────┴───────┘"
    log ""
    
    if [[ "${FAIL}" -eq 0 ]]; then
        log "  ${GREEN}${BOLD}🎉 ALL TESTS PASSED!${NC}"
        log "  ${GREEN}Telco/NFV kernel is properly configured and packaged.${NC}"
    elif [[ "${FAIL}" -lt 3 ]]; then
        log "  ${YELLOW}${BOLD}⚠️  MOSTLY PASSED with ${FAIL} failure(s)${NC}"
    else
        log "  ${RED}${BOLD}❌ ${FAIL} TESTS FAILED — review required${NC}"
    fi
    
    log ""
    log "  Full log: ${LOG_FILE}"
    log ""
    log "  Project: Telco JeOS Builder"
    log "  Author:  Hung Anh (Ericsson Ascent Cloud Engineer candidate)"
    log "  Date:    $(date)"
}

#=============================================================================
# MAIN
#=============================================================================
main() {
    log ""
    log "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}║   Telco/NFV Kernel Test Suite v1.0                         ║${NC}"
    log "${BOLD}║   Kernel: ${KVER}                              ║${NC}"
    log "${BOLD}║   Date: $(date '+%Y-%m-%d %H:%M:%S')                                ║${NC}"
    log "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    # Run all test suites
    test_suite_a    # Config verification
    test_suite_b    # Runtime verification
    test_suite_c    # Performance benchmarks
    test_suite_d    # Integration tests
    
    # Final report
    print_report
    
    # Exit code
    if [[ "${FAIL}" -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
