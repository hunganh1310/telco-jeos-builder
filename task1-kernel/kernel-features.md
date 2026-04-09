# Kernel Features - Linux 6.6.70-telco-nfv

## Mục tiêu
Kernel tối ưu cho Telco/NFV workloads: DPDK, KVM, VNF (Virtual Network Functions).

## Features đã bật

### Memory Management

| Config | Value | Mục đích |
|--------|-------|----------|
| `HUGETLBFS` | =y | Mount point cho HugePages. DPDK **bắt buộc** cần |
| `HUGETLB_PAGE` | =y | Cấp phát trang 2MB/1GB. Giảm TLB miss từ ~30% xuống <1% |
| `TRANSPARENT_HUGEPAGE` | =y | Kernel tự gộp 4KB → 2MB |
| `NUMA` | =y | Multi-socket server: allocate memory gần CPU xử lý. Giảm latency 40-50% |
| `ACPI_NUMA` | =y | Detect NUMA topology từ ACPI/SRAT tables |
| `NUMA_BALANCING` | =y | Auto-migrate pages đến gần CPU đang dùng |

### IOMMU & Device Passthrough

| Config | Value | Mục đích |
|--------|-------|----------|
| `IOMMU_SUPPORT` | =y | Framework DMA remapping |
| `INTEL_IOMMU` | =y | Intel VT-d — PCIe passthrough an toàn vào VM |
| `INTEL_IOMMU_DEFAULT_ON` | =y | Bật VT-d mặc định, không cần boot param |
| `AMD_IOMMU` | =y | AMD equivalent của VT-d |
| `VFIO` | =y | Userspace driver framework — DPDK bind NIC qua vfio-pci |
| `VFIO_PCI` | =m | PCI device driver cho VFIO |
| `VFIO_IOMMU_TYPE1` | =y | IOMMU backend cho VFIO |
| `UIO` | =m | Legacy userspace I/O (older DPDK) |

### Virtualization (KVM)

| Config | Value | Mục đích |
|--------|-------|----------|
| `KVM` | =m | Kernel-based Virtual Machine hypervisor |
| `KVM_INTEL` | =m | KVM cho Intel VT-x |
| `KVM_AMD` | =m | KVM cho AMD-V |
| `VHOST_NET` | =m | In-kernel virtio-net backend. 2-3x throughput vs QEMU userspace |
| `VIRTIO_NET` | =y | Paravirtualized NIC cho VMs |
| `VIRTIO_PCI` | =y | PCI transport cho virtio |

### Networking

| Config | Value | Mục đích |
|--------|-------|----------|
| `BRIDGE` | =m | Linux bridge — virtual switch cho VMs |
| `VLAN_8021Q` | =m | VLAN tagging — traffic isolation giữa VNFs |
| `BONDING` | =m | NIC bonding — HA + bandwidth aggregation |
| `TUN` | =m | Virtual NIC (OpenVPN, QEMU) |
| `BPF_SYSCALL` | =y | eBPF — programmable in-kernel networking |
| `BPF_JIT` | =y | JIT compiler cho eBPF — near-native performance |
| `XDP_SOCKETS` | =y | eXpress Data Path — xử lý packet tại driver level (~24Mpps) |

### CPU & Scheduling

| Config | Value | Mục đích |
|--------|-------|----------|
| `PREEMPT` | =y | Fully preemptible kernel. Worst-case latency: ~1ms (vs ~10ms) |
| `NO_HZ_FULL` | =y | Tickless trên isolated CPUs. Loại bỏ timer jitter cho DPDK |
| `HIGH_RES_TIMERS` | =y | Nanosecond-precision timers |
| `CPUSETS` | =y | CPU isolation qua cgroups (dùng với `isolcpus=`) |

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
- **Modules**: 34 (JeOS - Just enough OS)

## References
- [DPDK System Requirements](https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html)
- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)
- [Red Hat NFV Tuning Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/virtualization_tuning_and_optimization_guide/)
