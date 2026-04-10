#!/bin/bash
#
# config.sh - Kiwi post-install script
# Chạy bên trong rootfs SAU KHI tất cả packages được install
#

set -e

test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

echo "============================================"
echo "  Telco JeOS Post-Install Configuration"
echo "============================================"

# -----------------------------------------------
# 1. COPY BOOT SCRIPT
# -----------------------------------------------
echo "[1/6] Installing telco-nfv-init boot script..."

# Script đã được copy vào image qua kiwi overlay
# Hoặc tạo trực tiếp ở đây:

mkdir -p /etc/telco-nfv
mkdir -p /mnt/huge

# -----------------------------------------------
# 2. HUGEPAGES FSTAB
# -----------------------------------------------
echo "[2/6] Configuring HugePages fstab..."

cat >> /etc/fstab << 'FSTAB'
# HugePages for DPDK
hugetlbfs /mnt/huge hugetlbfs defaults,pagesize=2M 0 0
FSTAB

# -----------------------------------------------
# 3. SYSCTL CONFIG
# -----------------------------------------------
echo "[3/6] Configuring sysctl..."

cat > /etc/sysctl.d/90-telco-nfv.conf << 'SYSCTL'
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
vm.swappiness = 0
vm.nr_hugepages = 1024
kernel.numa_balancing = 1
SYSCTL

# -----------------------------------------------
# 4. KERNEL MODULES AUTOLOAD
# -----------------------------------------------
echo "[4/6] Configuring kernel module autoload..."

cat > /etc/modules-load.d/telco-nfv.conf << 'MODULES'
vfio
vfio-pci
vhost_net
tun
tap
bonding
8021q
bridge
MODULES

# -----------------------------------------------
# 5. SYSTEMD SERVICES
# -----------------------------------------------
echo "[5/6] Configuring systemd services..."

systemctl enable sshd 2>/dev/null || true
systemctl enable wicked 2>/dev/null || true

# Enable telco-nfv-init service (nếu file tồn tại)
if [[ -f /etc/systemd/system/telco-nfv-init.service ]]; then
    systemctl enable telco-nfv-init.service 2>/dev/null || true
fi

systemctl disable auditd 2>/dev/null || true
systemctl disable bluetooth 2>/dev/null || true

# -----------------------------------------------
# 6. MISC
# -----------------------------------------------
echo "[6/6] Final configuration..."

echo "telco-jeos" > /etc/hostname

# sudo without password for telco user
echo "telco ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/telco

echo ""
echo "============================================"
echo "  Post-install configuration COMPLETE!"
echo "============================================"
