#!/usr/bin/env bash
#
# nvidia-manager.sh (Dell G15 5530 FINAL VERSION)
#
# ✔ nouveau disable → reboot zorunluluğu
# ✔ reboot sonrası otomatik NVIDIA kurulumu
# ✔ nouveau açıkken kurulum İZİN YOK
# ✔ prime-select on-demand/performance
# ✔ NVIDIA paketleri hold edilir
#
# Kullanım:
#   sudo bash nvidia-manager.sh --prepare      (nouveau disable + reboot)
#   sudo bash nvidia-manager.sh --install      (reboot sonrası NVIDIA kurulum)
#   sudo bash nvidia-manager.sh --remove       (tam temizleme)
#   sudo bash nvidia-manager.sh --performance
#   sudo bash nvidia-manager.sh --on-demand
#

set -euo pipefail

PREPARE=false
INSTALL=false
REMOVE=false
SET_PERFORMANCE=false
SET_ONDEMAND=false

usage() {
cat <<EOF
Usage: sudo bash $0 [options]

Options:
  --prepare        nouveau disable + initramfs update (REBOOT REQUIRED)
  --install        Reboot sonrası NVIDIA 535 sürücüsünü kur
  --remove         NVIDIA sürücülerini kaldır
  --performance    PRIME Performance mode
  --on-demand      PRIME On-Demand mode
  -h, --help       Bu yardım metnini göster

Kurulum akışı:
  1) sudo bash $0 --prepare
  2) reboot
  3) sudo bash $0 --install
EOF
}

# Parse args
[[ $# -eq 0 ]] && { usage; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare) PREPARE=true; shift ;;
    --install) INSTALL=true; shift ;;
    --remove) REMOVE=true; shift ;;
    --performance) SET_PERFORMANCE=true; shift ;;
    --on-demand) SET_ONDEMAND=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen argüman: $1"; exit 1 ;;
  esac
done

# Root check
[[ $EUID -ne 0 ]] && { echo "HATA: sudo ile çalıştır."; exit 1; }

# NVIDIA paket listesi
NVIDIA_PACKAGES=(
  "nvidia-driver-535"
  "nvidia-dkms-535"
  "nvidia-prime"
  "libnvidia-gl-535"
)

# Detect nouveau
nouveau_active() {
    lsmod | grep -q "^nouveau" && return 0 || return 1
}

# Disable nouveau
disable_nouveau() {
    echo ">>> nouveau disable ediliyor..."
    mkdir -p /etc/modprobe.d
    cat <<EOF >/etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
    echo ">>> nouveau disable edildi."
}

# Enable nouveau
enable_nouveau() {
    echo ">>> nouveau yeniden aktif ediliyor..."
    rm -f /etc/modprobe.d/blacklist-nouveau.conf || true
    update-initramfs -u
    echo ">>> nouveau aktifleştirildi. Reboot gerekebilir."
}

# INSTALL NVIDIA DRIVER
install_nvidia() {

    if nouveau_active; then
        echo "======================================================="
        echo " HATA: nouveau RAM’de aktif!"
        echo " Lütfen önce '--prepare' çalıştırıp reboot edin."
        echo "======================================================="
        exit 1
    fi

    echo ">>> NVIDIA 535 kuruluyor..."
    apt update -y
    apt install -y "${NVIDIA_PACKAGES[@]}"

    echo ">>> DKMS derleniyor..."
    dkms autoinstall || true

    echo ">>> initramfs güncelleniyor..."
    update-initramfs -u

    echo ">>> Paketler hold ediliyor..."
    apt-mark hold "${NVIDIA_PACKAGES[@]}"

    echo "======================================================="
    echo " NVIDIA kurulumu tamamlandı!"
    echo " Reboot sonrası aktif olacaktır."
    echo "======================================================="
}

# REMOVE NVIDIA DRIVER
remove_nvidia() {
    apt-mark unhold "${NVIDIA_PACKAGES[@]}" || true
    apt remove --purge -y "${NVIDIA_PACKAGES[@]}" || true
    apt autoremove -y

    enable_nouveau

    echo ">>> NVIDIA tamamen kaldırıldı. Reboot önerilir."
}

# Performance mode
set_performance() {
    prime-select nvidia
    echo ">>> Performance mode aktif olacak (reboot sonrası)"
}

# On-demand mode
set_on_demand() {
    prime-select on-demand
    echo ">>> On-demand mode aktif olacak (reboot sonrası)"
}

# EXECUTION
$PREPARE && { disable_nouveau; echo ">>> Şimdi reboot et ve ardından '--install' çalıştır."; exit 0; }
$INSTALL && install_nvidia
$REMOVE && remove_nvidia
$SET_PERFORMANCE && set_performance
$SET_ONDEMAND && set_on_demand

exit 0
