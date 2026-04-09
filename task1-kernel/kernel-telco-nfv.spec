Name:       kernel-telco-nfv
Version:    6.6.70
Release:    1
Summary:    Linux Kernel 6.6.70 for Telco/NFV workloads
License:    GPL-2.0
Group:      System/Kernel
BuildArch:  x86_64

%description
Linux Kernel 6.6.70-telco-nfv
Configured for Telco/NFV: HugePages, NUMA, IOMMU, VFIO, KVM,
PREEMPT, NO_HZ_FULL, XDP/eBPF, Intel/Mellanox NIC drivers.

%install
# Copy pre-built artifacts from BUILDROOT (no rebuild)
mkdir -p %{buildroot}/boot
mkdir -p %{buildroot}/lib/modules

cp -a /home/etoxanh/telco-lab/telco-jeos-builder/task1-kernel/rpmbuild/BUILDROOT/kernel-6.6.70-telco-nfv/boot/* \
    %{buildroot}/boot/

cp -a /home/etoxanh/telco-lab/telco-jeos-builder/task1-kernel/rpmbuild/BUILDROOT/kernel-6.6.70-telco-nfv/lib/modules/6.6.70-telco-nfv \
    %{buildroot}/lib/modules/

%files
%defattr(-,root,root)
/boot/vmlinuz-6.6.70-telco-nfv
/boot/System.map-6.6.70-telco-nfv
/boot/config-6.6.70-telco-nfv
/lib/modules/6.6.70-telco-nfv

%changelog
* Wed Apr 09 2025 Hung Anh <etoxanh> - 6.6.70-1
- Initial Telco/NFV kernel build
- HugePages, NUMA, IOMMU, VFIO, KVM, PREEMPT, NO_HZ_FULL, XDP
