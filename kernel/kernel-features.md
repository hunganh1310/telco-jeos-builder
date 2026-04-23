# Kernel Features — Linux 6.6.70-telco-nfv

## Goal

Kernel optimized for Telco/NFV workloads: DPDK, KVM, VNF (Virtual Network Functions).

## Enabled Features

### Memory Management

| Config | Value | Purpose |
|--------|-------|---------|
| `HUGETLBFS` | =y | Mount point for HugePages. **Required** by DPDK |
| `HUGETLB_PAGE` | =y | Allocate 2MB/1GB pages. Reduces TLB miss from ~30% to <1% |
| `TRANSPARENT_HUGEPAGE` | =y | Kernel auto-merges 4KB → 2MB pages |
| `NUMA` | =y | Multi-socket server: allocate memory near processing CPU. Reduces latency 40-50% |
| `ACPI_NUMA` | =y | Detect NUMA topology from ACPI/SRAT tables |
| `NUMA_BALANCING` | =y | Auto-migrate pages closer to the CPU that uses them |

### IOMMU & Device Passthrough

| Config | Value | Purpose |
|--------|-------|---------|
| `IOMMU_SUPPORT` | =y | Framework for DMA remapping |
| `INTEL_IOMMU` | =y | Intel VT-d — safe PCIe passthrough into VMs |
| `INTEL_IOMMU_DEFAULT_ON` | =y | Enable VT-d by default, no boot param needed |
| `AMD_IOMMU` | =y | AMD equivalent of VT-d |
| `VFIO` | =y | Userspace driver framework — DPDK binds NIC via vfio-pci |
| `VFIO_PCI` | =m | PCI device driver for VFIO |
| `VFIO_IOMMU_TYPE1` | =y | IOMMU backend for VFIO |
| `UIO` | =m | Legacy userspace I/O (older DPDK) |

### Virtualization (KVM)

| Config | Value | Purpose |
|--------|-------|---------|
| `KVM` | =m | Kernel-based Virtual Machine hypervisor |
| `KVM_INTEL` | =m | KVM for Intel VT-x |
| `KVM_AMD` | =m | KVM for AMD-V |
| `VHOST_NET` | =m | In-kernel virtio-net backend. 2-3x throughput vs QEMU userspace |
| `VIRTIO_NET` | =y | Paravirtualized NIC for VMs |
| `VIRTIO_PCI` | =y | PCI transport for virtio |

### Networking

| Config | Value | Purpose |
|--------|-------|---------|
| `BRIDGE` | =m | Linux bridge — virtual switch for VMs |
| `VLAN_8021Q` | =m | VLAN tagging — traffic isolation between VNFs |
| `BONDING` | =m | NIC bonding — HA + bandwidth aggregation |
| `TUN` | =m | Virtual NIC (OpenVPN, QEMU) |
| `BPF_SYSCALL` | =y | eBPF — programmable in-kernel networking |
| `BPF_JIT` | =y | JIT compiler for eBPF — near-native performance |
| `XDP_SOCKETS` | =y | eXpress Data Path — packet processing at driver level (~24Mpps) |

### CPU & Scheduling

| Config | Value | Purpose |
|--------|-------|---------|
| `PREEMPT` | =y | Fully preemptible kernel. Worst-case latency: ~1ms (vs ~10ms) |
| `NO_HZ_FULL` | =y | Tickless on isolated CPUs. Removes timer jitter for DPDK |
| `HIGH_RES_TIMERS` | =y | Nanosecond-precision timers |
| `CPUSETS` | =y | CPU isolation via cgroups (used with `isolcpus=`) |

### NIC Drivers (Telco-grade)

| Config | Value | Hardware |
|--------|-------|----------|
| `E1000E` | =m | Intel 1GbE (desktop/lab) |
| `IGB` | =m | Intel 1GbE server (I350) |
| `IXGBE` | =m | Intel 10GbE (X520, X540) |
| `I40E` | =m | Intel 25/40GbE (XL710, XXV710) |
| `ICE` | =m | Intel 100GbE (E810) |
| `MLX4_EN` | =m | Mellanox ConnectX-3 |
| `MLX5_CORE` | =m | Mellanox ConnectX-4/5/6/7 |

## Build Info

- **Kernel**: Linux 6.6.70 LTS
- **Compiler**: GCC 13.4.0 (SUSE Linux)
- **Target**: x86_64
- **RPM**: `kernel-telco-nfv-6.6.70-1.x86_64.rpm`
- **Modules**: 34 (JeOS — Just Enough OS)

## References

- [DPDK System Requirements](https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html)
- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)
- [Red Hat NFV Tuning Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/virtualization_tuning_and_optimization_guide/)
