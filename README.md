## 🎯 Objective

Build a minimal, performance-tuned Linux OS (JeOS) optimized for Telco/NFV workloads:
- Custom-compiled Linux Kernel with HugePages, NUMA, IOMMU, VFIO, DPDK-ready features
- Packaged as QCOW2 image using Kiwi-ng
- Auto-configured at boot for Telco workloads
- Benchmarked to prove performance improvements

## 📋 Lab Tasks

| Task | Description | Status |
|------|-------------|--------|
| [Task 1](task1-kernel/) | Kernel Hacking — Compile custom kernel with Telco features | 🔄 In progress |
| [Task 2](task2-kiwi/) | Kiwi-ng — Package OS as QCOW2 image | ⏳ Pending |
| [Task 3](task3-bootscript/) | Boot Script — Auto-configure IP & HugePages | ⏳ Pending |
| [Task 4](task4-testing/) | Testing — Benchmark & validate | ⏳ Pending |

## 🏗️ Architecture
```text
┌─────────────────────────────────────────────┐
│              QCOW2 Image (Kiwi-ng)          │
│  ┌────────────────────────────────────────┐ │
│  │  Custom Kernel 6.6.70-telco-nfv        │ │
│  │  ├── HugePages (2MB/1GB)               │ │
│  │  ├── NUMA-aware scheduling             │ │
│  │  ├── IOMMU (VT-d / AMD-Vi)             │ │
│  │  ├── VFIO (PCIe passthrough)           │ │
│  │  ├── PREEMPT + NO_HZ_FULL              │ │
│  │  └── eBPF/XDP networking               │ │
│  ├────────────────────────────────────────┤ │
│  │  openSUSE JeOS (minimal)               │ │
│  ├────────────────────────────────────────┤ │
│  │  Boot Script (telco-init.service)      │ │
│  │  ├── Auto-configure HugePages          │ │
│  │  ├── Auto-configure networking         │ │
│  │  └── CPU isolation setup               │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```


## 🛠️ Tech Stack

- **Base OS**: openSUSE Tumbleweed / SLES 15
- **Kernel**: Linux 6.6.70 LTS (custom compiled)
- **Image Builder**: Kiwi-ng
- **Build Environment**: WSL2 on Windows

## 📖 Key Kernel Features Enabled

| Category | Features | Purpose |
|----------|----------|---------|
| Memory | HugePages, THP, NUMA | Reduce TLB misses, memory-local allocation |
| Virtualization | KVM, VFIO, vhost-net | VM hosting & PCIe passthrough |
| IOMMU | Intel VT-d, AMD-Vi | Safe DMA remapping for passthrough |
| Networking | Bridge, VLAN, Bonding, XDP | High-performance virtual networking |
| Scheduling | PREEMPT, NO_HZ_FULL | Low-latency, CPU isolation |
| NIC Drivers | i40e, ice, mlx5 | Intel/Mellanox Telco NICs |

## 🚀 Quick Start

```bash
# Task 1: Build custom kernel
cd task1-kernel
bash configure-telco-kernel.sh
# (See task1-kernel/README.md for full instructions)
```

## 📚 References
- Linux Kernel Documentation
- DPDK System Requirements
- Red Hat NFV Tuning Guide
- Kiwi-ng Documentation
- openSUSE JeOS

## 👤 Author
- Hung Anh To | anh.to@ericsson.com | hunganh1310.work@gmail.com

