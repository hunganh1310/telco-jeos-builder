# ===========================================================================
# kernel-telco-nfv.spec — RPM spec for custom Telco/NFV kernel
#
# This spec packages pre-built kernel artifacts (vmlinuz, modules, etc.)
# into an installable RPM without rebuilding from source.
#
# Usage:
#   rpmbuild -bb --define "_topdir /path/to/rpmbuild" kernel-telco-nfv.spec
#
# The BUILDROOT must be pre-populated with boot/ and lib/modules/ trees.
# ===========================================================================

%define kversion    6.6.70
%define krelease    telco-nfv
%define kfullver    %{kversion}-%{krelease}

Name:       kernel-telco-nfv
Version:    %{kversion}
Release:    1
Summary:    Linux Kernel %{kfullver} for Telco/NFV workloads
License:    GPL-2.0
Group:      System/Kernel
BuildArch:  x86_64

%description
Custom Linux Kernel %{kfullver} optimized for Telco/NFV environments.

Enabled features:
  - HugePages (2MB/1GB), NUMA, NUMA balancing
  - IOMMU (Intel VT-d, AMD-Vi), VFIO passthrough
  - KVM hypervisor, vhost-net, virtio
  - PREEMPT, NO_HZ_FULL (low-latency scheduling)
  - XDP/eBPF (high-performance packet processing)
  - Intel (E810/ICE, XL710/I40E, X520/IXGBE) and Mellanox ConnectX NIC drivers

%install
# Copy pre-built artifacts from the staging area.
# The staging directory must be populated before rpmbuild is invoked.
# Expected layout under %{_topdir}/BUILDROOT/kernel-%{kfullver}/:
#   boot/vmlinuz-%{kfullver}
#   boot/System.map-%{kfullver}
#   boot/config-%{kfullver}
#   lib/modules/%{kfullver}/

mkdir -p %{buildroot}/boot
mkdir -p %{buildroot}/lib/modules

cp -a %{_topdir}/BUILDROOT/kernel-%{kfullver}/boot/* \
    %{buildroot}/boot/

cp -a %{_topdir}/BUILDROOT/kernel-%{kfullver}/lib/modules/%{kfullver} \
    %{buildroot}/lib/modules/

%files
%defattr(-,root,root)
/boot/vmlinuz-%{kfullver}
/boot/System.map-%{kfullver}
/boot/config-%{kfullver}
/lib/modules/%{kfullver}

%post
# Rebuild module dependency list after install
depmod -a %{kfullver} || true

%changelog
* Wed Apr 09 2025 Hung Anh <etoxanh> - 6.6.70-1
- Initial Telco/NFV kernel build
- HugePages, NUMA, IOMMU, VFIO, KVM, PREEMPT, NO_HZ_FULL, XDP
