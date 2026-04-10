# Telco JeOS Builder

Build a minimal Linux JeOS image optimized for Telco/NFV workloads.

This repository is organized as a step-by-step lab:
- Task 1: Configure and package a custom Linux kernel (`6.6.70-telco-nfv`).
- Task 2: Build a QCOW2 image with Kiwi-NG.
- Task 3: Apply boot-time Telco tuning (HugePages, networking, modules, sysctl).
- Task 4: Validate kernel features and run benchmark-oriented checks.

## Goal

Produce a lightweight QCOW2 image suitable for NFV/VNF environments with:
- HugePages and NUMA-aware behavior.
- IOMMU + VFIO readiness for passthrough workloads.
- KVM/virtio/vhost-net support.
- Low-latency tuning (`PREEMPT`, `NO_HZ_FULL`) and Telco NIC drivers.

## Repository Structure

```text
.
|-- docs/
|-- task1-kernel/
|   |-- configure-telco-kernel.sh
|   |-- kernel-telco-nfv.spec
|   |-- telco-nfv.config
|   `-- kernel-features.md
|-- task2-kiwi/
|   `-- description/
|       |-- config.xml
|       |-- config.sh
|       `-- root/
|           |-- etc/systemd/system/telco-nfv-init.service
|           |-- etc/telco-nfv/config
|           `-- usr/local/bin/telco-nfv-init.sh
|-- task3-bootscript/
|   |-- telco-nfv-init.sh
|   |-- telco-nfv-init.service
|   `-- telco-nfv-config.sample
`-- task4-testing/
	`-- telco-kernel-test.sh
```

## End-to-End Workflow

### 1) Kernel configuration and build prep

`task1-kernel/configure-telco-kernel.sh` must be executed inside the Linux kernel source tree.

Example:

```bash
cd /path/to/linux-6.6.70
bash /path/to/telco-jeos-builder/task1-kernel/configure-telco-kernel.sh
```

What it does:
- Starts from `defconfig`.
- Enables Telco/NFV options (HugePages, NUMA, IOMMU, VFIO, KVM, XDP/eBPF, NIC drivers).
- Applies `-telco-nfv` local version.
- Runs `olddefconfig` and prints verification output.

### 2) Build JeOS image with Kiwi-NG

Main definition: `task2-kiwi/description/config.xml`.

Current image profile highlights:
- Format: `qcow2`.
- Base: openSUSE Tumbleweed packages.
- Includes custom RPM `kernel-telco-nfv` from local repository path in `config.xml`.
- Kernel cmdline pre-sets IOMMU/HugePages-related boot parameters.

Post-install customization is handled by `task2-kiwi/description/config.sh`:
- Creates HugePages mountpoint and fstab entry.
- Adds sysctl tuning.
- Configures module autoload.
- Enables required services (including `telco-nfv-init.service` when present).

### 3) Boot-time initialization

Standalone boot script artifacts are in `task3-bootscript/`:
- `telco-nfv-init.sh`: runtime setup for HugePages, network mode, module loading, NUMA checks, and sysctl tuning.
- `telco-nfv-init.service`: systemd unit to run the script at startup.
- `telco-nfv-config.sample`: optional override file for `/etc/telco-nfv/config`.

### 4) Verification and benchmark-oriented testing

Run:

```bash
bash task4-testing/telco-kernel-test.sh
```

The test suite covers:
- Offline `.config` validation (feature matrix).
- Runtime checks when booted with the custom kernel.
- Image/kernel/module-size and readiness comparisons.

## Key Files

- `task1-kernel/configure-telco-kernel.sh`: kernel option automation for NFV use cases.
- `task1-kernel/kernel-telco-nfv.spec`: RPM packaging spec for custom kernel.
- `task2-kiwi/description/config.xml`: Kiwi image definition.
- `task2-kiwi/description/config.sh`: post-install provisioning inside image build.
- `task3-bootscript/telco-nfv-init.sh`: first-boot/runtime Telco initializer.
- `task4-testing/telco-kernel-test.sh`: validation and benchmark helper.

## Notes

- Repository is designed for Linux build environments (WSL2 is acceptable).
- Some paths in scripts/configs are environment-specific (for example local RPM repository path). Adjust to your machine before full build.
- For detailed kernel option rationale, see `task1-kernel/kernel-features.md`.

## References

- Linux Kernel Documentation: https://www.kernel.org/doc/html/latest/
- DPDK System Requirements: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
- Kiwi-NG Docs: https://osinside.github.io/kiwi/

## Author

Hung Anh To  
anh.to@ericsson.com  
hunganh1310.work@gmail.com

