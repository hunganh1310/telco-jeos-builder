#!/bin/bash
# ===========================================================================
# config.sh — Kiwi-NG post-install script
#
# Runs inside the image rootfs AFTER all packages are installed.
# All filesystem overlay files from image/root/ have already been copied
# into the rootfs by kiwi before this script executes.
#
# This script handles:
#   1. Creating directories needed by the boot-time initializer
#   2. Appending the hugetlbfs fstab entry (idempotent)
#   3. Enabling/disabling systemd services
#   4. Setting hostname and sudoers
#
# Note: sysctl and modules-load configs are delivered via the root overlay
#       (etc/sysctl.d/90-telco-nfv.conf, etc/modules-load.d/telco-nfv.conf)
#       and do NOT need to be created here.
# ===========================================================================

set -euo pipefail

# Source kiwi environment
test -f /.kconfig  && . /.kconfig
test -f /.profile  && . /.profile

# ---------------------------------------------------------------------------
# Logging helper (minimal — shared lib may not be available in chroot)
# ---------------------------------------------------------------------------
_log() {
    echo "[$(date '+%H:%M:%S')] [config.sh] $*"
}

_log "============================================"
_log "  Telco JeOS Post-Install Configuration"
_log "============================================"

# ---------------------------------------------------------------------------
# 1. Create runtime directories
# ---------------------------------------------------------------------------
_log "[1/5] Creating runtime directories..."

mkdir -p /etc/telco-nfv
mkdir -p /mnt/huge
mkdir -p /var/log

# ---------------------------------------------------------------------------
# 2. HugePages fstab entry (idempotent)
# ---------------------------------------------------------------------------
_log "[2/5] Configuring HugePages fstab..."

if ! grep -qF "hugetlbfs" /etc/fstab 2>/dev/null; then
    cat >> /etc/fstab << 'FSTAB'
# HugePages for DPDK
hugetlbfs /mnt/huge hugetlbfs defaults,pagesize=2M 0 0
FSTAB
    _log "  Added hugetlbfs entry to /etc/fstab"
else
    _log "  hugetlbfs already in /etc/fstab, skipping"
fi

# ---------------------------------------------------------------------------
# 3. Systemd services
# ---------------------------------------------------------------------------
_log "[3/5] Configuring systemd services..."

# Enable essential services
systemctl enable sshd              2>/dev/null || true
systemctl enable wicked            2>/dev/null || true

# Enable telco-nfv-init boot-time initializer (installed via overlay)
if [[ -f /etc/systemd/system/telco-nfv-init.service ]]; then
    systemctl enable telco-nfv-init.service 2>/dev/null || true
    _log "  Enabled telco-nfv-init.service"
fi

# Disable unnecessary services for a JeOS image
systemctl disable auditd           2>/dev/null || true
systemctl disable bluetooth        2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Hostname
# ---------------------------------------------------------------------------
_log "[4/5] Setting hostname..."

echo "telco-jeos" > /etc/hostname

# ---------------------------------------------------------------------------
# 5. Sudoers
# ---------------------------------------------------------------------------
_log "[5/5] Configuring sudoers..."

echo "telco ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/telco
chmod 0440 /etc/sudoers.d/telco

_log "============================================"
_log "  Post-install configuration COMPLETE"
_log "============================================"
