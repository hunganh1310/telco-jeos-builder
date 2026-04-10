#!/bin/bash
#
# config.sh - Kiwi post-install script
# Chạy bên trong rootfs SAU KHI tất cả packages được install
#
# Mục đích: Cấu hình OS cho Telco/NFV workloads
#

set -e

# Load kiwi helper functions
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

echo "============================================"
echo "  Telco JeOS Post-Install Configuration"
echo "============================================"

# -----------------------------------------------
# 1. HUGEPAGES SETUP
# -----------------------------------------------
echo "[1/5] Configuring HugePages..."

# Mount hugetlbfs tự động khi boot
mkdir -p /mnt/huge

# Thêm vào /etc/fstab
cat >> /etc/fstab << 'FSTAB'
# HugePages for DPDK
hugetlbfs /mnt/huge hugetlbfs defaults,pagesize=2M 0 0
FSTAB

# Cấu hình số lượng hugepages lúc boot (512 x 2MB = 1GB)
echo "vm.nr_hugepages = 512" >> /etc/sysctl.d/90-telco-nfv.conf

# -----------------------------------------------
# 2. NETWORK PERFORMANCE TUNING
# -----------------------------------------------
echo "[2/5] Configuring network performance..."

cat > /etc/sysctl.d/90-telco-nfv.conf << 'SYSCTL'
# Telco/NFV Network Tuning
# Tăng buffer size để xử lý burst traffic
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535

# HugePages
vm.nr_hugepages = 512
vm.hugetlb_shm_group = 0

# Disable swap (Telco workloads không muốn swap latency)
vm.swappiness = 0

# NUMA balancing
kernel.numa_balancing = 1
SYSCTL

# -----------------------------------------------
# 3. CPU ISOLATION GRUB CONFIG
# -----------------------------------------------
echo "[3/5] Configuring CPU isolation boot params..."

# Thêm kernel boot params cho DPDK CPU isolation
# isolcpus=2-7: Reserve CPUs 2-7 cho DPDK poll-mode driver
# nohz_full=2-7: Tắt timer tick trên isolated CPUs
# rcu_nocbs=2-7: Offload RCU callbacks khỏi isolated CPUs
GRUB_CMDLINE="console=ttyS0,115200 console=tty0 net.ifnames=0 biosdevname=0"
GRUB_CMDLINE="${GRUB_CMDLINE} hugepagesz=2M hugepages=512"
GRUB_CMDLINE="${GRUB_CMDLINE} iommu=pt intel_iommu=on"
GRUB_CMDLINE="${GRUB_CMDLINE} isolcpus=2-3 nohz_full=2-3 rcu_nocbs=2-3"

sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${GRUB_CMDLINE}\"|" \
    /etc/default/grub 2>/dev/null || true

# -----------------------------------------------
# 4. VFIO/DPDK SETUP
# -----------------------------------------------
echo "[4/5] Configuring VFIO for DPDK..."

# Load vfio-pci module tự động khi boot
cat > /etc/modules-load.d/telco-nfv.conf << 'MODULES'
# Telco/NFV kernel modules
vfio
vfio-pci
vhost_net
MODULES

# udev rule: cho phép user bind NIC vào vfio-pci
cat > /etc/udev/rules.d/90-telco-vfio.rules << 'UDEV'
# Allow telco user to use VFIO devices (for DPDK)
SUBSYSTEM=="vfio", OWNER="root", GROUP="telco", MODE="0660"
UDEV

# -----------------------------------------------
# 5. SYSTEMD SERVICES
# -----------------------------------------------
echo "[5/5] Configuring systemd services..."

# Enable essential services
systemctl enable sshd 2>/dev/null || true
systemctl enable wicked 2>/dev/null || true
systemctl enable systemd-networkd 2>/dev/null || true

# Disable unnecessary services (giảm boot time)
systemctl disable auditd 2>/dev/null || true
systemctl disable bluetooth 2>/dev/null || true
systemctl disable cups 2>/dev/null || true

# Set hostname
echo "telco-jeos" > /etc/hostname

echo ""
echo "============================================"
echo "  Post-install configuration COMPLETE!"
echo "============================================"
