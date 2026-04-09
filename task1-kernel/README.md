# Task 1: Kernel Hacking

Custom Linux Kernel compilation with Telco/NFV optimizations.

## Features Enabled
- HugePages (2MB/1GB)
- NUMA support
- IOMMU (Intel VT-d, AMD-Vi)
- VFIO (PCIe passthrough)
- KVM virtualization
- PREEMPT + NO_HZ_FULL (low latency)
- eBPF/XDP networking
- Telco NIC drivers (i40e, ice, mlx5)

## Files
- `configure-telco-kernel.sh` — Auto-configure kernel for Telco
- `build-kernel.sh` — Build & package kernel as RPM
- `telco-nfv.config` — Kernel .config file
- `kernel-features.md` — Detailed explanation of each feature

## Instructions
Details coming as we progress.