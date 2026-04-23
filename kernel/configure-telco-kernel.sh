#!/bin/bash
# ===========================================================================
# configure-telco-kernel.sh
#
# Auto-configure Linux Kernel for Telco/NFV workloads.
# Must be executed from inside the kernel source tree.
#
# Usage:
#   cd /path/to/linux-6.6.70
#   bash /path/to/telco-jeos-builder/kernel/configure-telco-kernel.sh
#
# Options:
#   --verify-only   Only run verification on existing .config (no changes)
#
# Environment:
#   KERNEL_VERSION  Override the expected kernel version (default: 6.6.70)
#
# Author: Hung Anh — Ascent Cloud Engineer Lab @ Ericsson
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve project root and source shared libraries
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logger.sh
source "${PROJECT_ROOT}/lib/logger.sh"
# shellcheck source=../lib/utils.sh
source "${PROJECT_ROOT}/lib/utils.sh"
# shellcheck source=../lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
VERIFY_ONLY=false

for arg in "$@"; do
    case "${arg}" in
        --verify-only) VERIFY_ONLY=true ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--verify-only]"
            echo "  --verify-only  Only verify existing .config, do not modify"
            exit 0
            ;;
        *)
            die "Unknown argument: ${arg}. Use --help for usage."
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Precondition checks
# ---------------------------------------------------------------------------
if [[ ! -f "Makefile" ]] || ! grep -q "^VERSION = " Makefile; then
    die "Please run this script from inside the kernel source directory.
  Example:
    cd ${TELCO_BUILD_DIR}/kernel/linux-${KERNEL_VERSION}
    bash ${SCRIPT_DIR}/$(basename "$0")"
fi

require_command make "make"
require_command gcc  "gcc"

log_section "Telco/NFV Kernel Configuration"
log_info "Target: Linux ${KERNEL_RELEASE}"
log_info "Mode:   $(${VERIFY_ONLY} && echo 'VERIFY ONLY' || echo 'CONFIGURE')"

if "${VERIFY_ONLY}"; then
    # Jump straight to verification
    log_info "Skipping configuration, verifying existing .config..."
else

# ---------------------------------------------------------------------------
# [1/9] Base defconfig
# ---------------------------------------------------------------------------
log_info "[1/9] Creating base defconfig..."
make defconfig

# ---------------------------------------------------------------------------
# [2/9] Memory Management — HugePages, NUMA
# ---------------------------------------------------------------------------
log_info "[2/9] Configuring Memory Management (HugePages, NUMA)..."

# HugePages — MANDATORY for DPDK
# Allocates 2MB/1GB pages instead of 4KB → reduces TLB misses dramatically
scripts/config --enable CONFIG_HUGETLBFS
scripts/config --enable CONFIG_HUGETLB_PAGE

# Transparent HugePages — kernel auto-merges 4KB → 2MB
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE

# NUMA (Non-Uniform Memory Access)
# Multi-socket servers: allocate memory close to processing CPU
# Reduces memory latency 40-50%
scripts/config --enable CONFIG_NUMA
scripts/config --enable CONFIG_ACPI_NUMA
scripts/config --enable CONFIG_NUMA_BALANCING

# ---------------------------------------------------------------------------
# [3/9] IOMMU & Device Passthrough — VT-d, VFIO
# ---------------------------------------------------------------------------
log_info "[3/9] Configuring IOMMU & Device Passthrough (VT-d, VFIO)..."

# IOMMU framework — hardware DMA remapping
scripts/config --enable CONFIG_IOMMU_SUPPORT
scripts/config --enable CONFIG_IOMMU_API

# Intel VT-d (most Telco servers use Intel Xeon)
scripts/config --enable CONFIG_INTEL_IOMMU
scripts/config --enable CONFIG_INTEL_IOMMU_DEFAULT_ON

# AMD IOMMU (also supports AMD EPYC)
scripts/config --enable CONFIG_AMD_IOMMU

# VFIO — userspace driver framework (DPDK, QEMU passthrough)
# DPDK binds NIC to vfio-pci to bypass kernel networking stack entirely
scripts/config --enable CONFIG_VFIO
scripts/config --module CONFIG_VFIO_PCI
scripts/config --enable CONFIG_VFIO_IOMMU_TYPE1

# UIO — legacy userspace driver framework (older DPDK)
scripts/config --module CONFIG_UIO
scripts/config --module CONFIG_UIO_PCI_GENERIC

# ---------------------------------------------------------------------------
# [4/9] Virtualization — KVM, vhost-net, virtio
# ---------------------------------------------------------------------------
log_info "[4/9] Configuring Virtualization (KVM, vhost-net, virtio)..."

# KVM — hypervisor for VNFs (Virtual Network Functions)
scripts/config --enable CONFIG_VIRTUALIZATION
scripts/config --module CONFIG_KVM
scripts/config --module CONFIG_KVM_INTEL
scripts/config --module CONFIG_KVM_AMD

# vhost-net — in-kernel virtio-net backend
# Processes packets in kernel instead of QEMU userspace → 2-3x throughput
scripts/config --module CONFIG_VHOST_NET
scripts/config --module CONFIG_VHOST

# virtio — paravirtualized I/O for VMs
scripts/config --enable CONFIG_VIRTIO
scripts/config --enable CONFIG_VIRTIO_PCI
scripts/config --enable CONFIG_VIRTIO_NET
scripts/config --enable CONFIG_VIRTIO_BLK
scripts/config --enable CONFIG_VIRTIO_BALLOON
scripts/config --enable CONFIG_VIRTIO_CONSOLE

# vsock — VM ↔ host communication
scripts/config --module CONFIG_VIRTIO_VSOCKETS

# ---------------------------------------------------------------------------
# [5/9] Networking — Bridge, VLAN, Bonding, XDP
# ---------------------------------------------------------------------------
log_info "[5/9] Configuring Networking (Bridge, VLAN, Bonding, XDP)..."

# Linux Bridge — virtual switch for VMs
scripts/config --module CONFIG_BRIDGE

# VLAN 802.1Q — traffic isolation between VNFs
scripts/config --module CONFIG_VLAN_8021Q

# Bonding — aggregate multiple NICs (HA + bandwidth)
scripts/config --module CONFIG_BONDING

# macvlan/macvtap — sub-interface with unique MAC
scripts/config --module CONFIG_MACVLAN
scripts/config --module CONFIG_MACVTAP

# TUN/TAP — virtual NIC (OpenVPN, QEMU)
scripts/config --module CONFIG_TUN

# eBPF — programmable in-kernel networking
# XDP processes packets at driver level: ~24Mpps vs ~1Mpps iptables
scripts/config --enable CONFIG_BPF
scripts/config --enable CONFIG_BPF_SYSCALL
scripts/config --enable CONFIG_BPF_JIT
scripts/config --enable CONFIG_XDP_SOCKETS

# Netfilter (iptables/nftables) — basic firewall
scripts/config --module CONFIG_NETFILTER
scripts/config --module CONFIG_NF_CONNTRACK
scripts/config --module CONFIG_NF_NAT
scripts/config --module CONFIG_IP_NF_IPTABLES
scripts/config --module CONFIG_IP_NF_NAT
scripts/config --module CONFIG_IP_NF_FILTER

# ---------------------------------------------------------------------------
# [6/9] CPU & Scheduling — PREEMPT, NO_HZ_FULL
# ---------------------------------------------------------------------------
log_info "[6/9] Configuring CPU & Scheduling (PREEMPT, NO_HZ_FULL)..."

# Preemptible kernel — allow interrupting kernel code anytime
# Reduces worst-case latency from ~10ms to ~1ms
scripts/config --enable CONFIG_PREEMPT
scripts/config --disable CONFIG_PREEMPT_VOLUNTARY
scripts/config --disable CONFIG_PREEMPT_NONE

# Tickless (NO_HZ_FULL) — disable timer interrupt on isolated CPUs
# DPDK poll-mode driver needs 100% CPU, timer tick causes jitter
scripts/config --enable CONFIG_NO_HZ_FULL
scripts/config --enable CONFIG_NO_HZ

# CPU isolation support — use with boot param: isolcpus=2-7
scripts/config --enable CONFIG_CPUSETS
scripts/config --enable CONFIG_CGROUP_CPUACCT
scripts/config --enable CONFIG_CGROUP_SCHED

# High-resolution timers — nanosecond precision
scripts/config --enable CONFIG_HIGH_RES_TIMERS

# cgroups — resource management for containers/VNFs
scripts/config --enable CONFIG_CGROUPS

# ---------------------------------------------------------------------------
# [7/9] NIC Drivers (Telco-grade)
# ---------------------------------------------------------------------------
log_info "[7/9] Configuring NIC Drivers (Intel, Mellanox)..."

# Intel NICs (most common in Telco/DC)
scripts/config --module CONFIG_E1000E         # Intel 1GbE (desktop/lab)
scripts/config --module CONFIG_IGB            # Intel 1GbE server (I350)
scripts/config --module CONFIG_IXGBE          # Intel 10GbE (X520, X540)
scripts/config --module CONFIG_I40E           # Intel 25/40GbE (XL710, XXV710)
scripts/config --module CONFIG_ICE            # Intel 100GbE (E810) — latest

# Mellanox/NVIDIA ConnectX NICs
scripts/config --module CONFIG_MLX4_EN        # ConnectX-3
scripts/config --module CONFIG_MLX5_CORE      # ConnectX-4/5/6/7

# ---------------------------------------------------------------------------
# [8/9] Filesystem & Misc
# ---------------------------------------------------------------------------
log_info "[8/9] Configuring Filesystems & Misc..."

scripts/config --enable CONFIG_EXT4_FS
scripts/config --enable CONFIG_XFS_FS
scripts/config --enable CONFIG_BTRFS_FS
scripts/config --enable CONFIG_TMPFS
scripts/config --enable CONFIG_PROC_FS
scripts/config --enable CONFIG_SYSFS

# Block devices for VM
scripts/config --enable CONFIG_BLK_DEV_LOOP
scripts/config --module CONFIG_BLK_DEV_NBD

# Crypto (for IPsec between VNFs)
scripts/config --enable CONFIG_CRYPTO
scripts/config --enable CONFIG_CRYPTO_AES
scripts/config --enable CONFIG_CRYPTO_SHA256
scripts/config --enable CONFIG_CRYPTO_GCM

scripts/config --enable CONFIG_SYSCTL

# ---------------------------------------------------------------------------
# [9/9] Custom kernel name
# ---------------------------------------------------------------------------
log_info "[9/9] Setting kernel version suffix to '${KERNEL_LOCALVERSION}'..."

scripts/config --set-str CONFIG_LOCALVERSION "${KERNEL_LOCALVERSION}"
scripts/config --disable CONFIG_LOCALVERSION_AUTO

# ---------------------------------------------------------------------------
# Resolve dependencies
# ---------------------------------------------------------------------------
log_info "Resolving config dependencies with olddefconfig..."
make olddefconfig

fi  # end of !VERIFY_ONLY

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
log_section "Configuration Verification"

if [[ -f ".config" ]]; then
    log_info "Kernel version: $(make kernelrelease 2>/dev/null || echo 'unknown')"
else
    die ".config not found — cannot verify"
fi

verify_group() {
    local group_name="$1"
    shift
    echo ""
    log_info "--- ${group_name} ---"
    local pattern="$1"
    grep -E "${pattern}" .config 2>/dev/null || log_warn "(some options not found)"
}

verify_group "MEMORY" \
    "^CONFIG_(HUGETLBFS|HUGETLB_PAGE|TRANSPARENT_HUGEPAGE|NUMA|NUMA_BALANCING|ACPI_NUMA)="

verify_group "IOMMU & PASSTHROUGH" \
    "^CONFIG_(IOMMU_SUPPORT|INTEL_IOMMU|AMD_IOMMU|VFIO|VFIO_PCI|VFIO_IOMMU_TYPE1|UIO)="

verify_group "VIRTUALIZATION" \
    "^CONFIG_(KVM|KVM_INTEL|KVM_AMD|VHOST_NET|VIRTIO_NET|VIRTIO_PCI)="

verify_group "NETWORKING" \
    "^CONFIG_(BRIDGE|VLAN_8021Q|BONDING|TUN|BPF_SYSCALL|BPF_JIT|XDP_SOCKETS)="

verify_group "SCHEDULING" \
    "^CONFIG_(PREEMPT|PREEMPT_VOLUNTARY|PREEMPT_NONE|NO_HZ_FULL|NO_HZ|HIGH_RES_TIMERS)="

verify_group "NIC DRIVERS" \
    "^CONFIG_(E1000E|IGB|IXGBE|I40E|ICE|MLX4_EN|MLX5_CORE)="

verify_group "LOCALVERSION" \
    "CONFIG_LOCALVERSION"

log_section "Done"
log_ok ".config saved in: $(pwd)/.config"
log_info "Next step: make -j\$(nproc)"
