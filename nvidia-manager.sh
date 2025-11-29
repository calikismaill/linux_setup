#!/usr/bin/env bash
#
# nvidia-manager.sh
# Dell G15 5530 + Ubuntu/Xubuntu 22.04 için NVIDIA 535 tam otomatik kurulum scripti
#
# Özellikler:
#   ✔ NVIDIA 535 sürücüsünü kurar
#   ✔ nvidia-dkms kurulumu
#   ✔ nouveau tamamen disable edilir
#   ✔ PRIME (on-demand / performance) optimize edilir
#   ✔ NVIDIA modülleri için initramfs günceller
#   ✔ NVIDIA paketlerini apt-mark hold ile sabitler
#
# Kullanım:
#   sudo bash nvidia-manager.sh --install
#   sudo bash nvidia-manager.sh --remove
#   sudo bash nvidia-manager.sh --performance
#   sudo bash nvidia-manager.sh --on-demand
#

set -euo pipefail

INSTALL=false
REMOVE=false
SET_PERFORMANCE=false
SET_ONDEMAND=false

usage() {
cat <<EOF
Usage: sudo bash $0 [options]

Options:
  --install         NVIDIA 535 sürücüsünü kur
  --remove          NVIDIA sürücülerini kaldır (nouveau geri açılır)
  --performance     NVIDIA PRIME Performance mode aktif et
  --on-demand       PRIME On-Demand moda geçir (önerilen)
  -h, --help        Bu yardım metnini göster

Örnek:
  sudo bash $0 --install
  sudo bash $0 --performance
EOF
}

# ---------------------------------------------------
# Argüman işle
# ---------------------------------------------------
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=true; shift ;;
    --remove) REMOVE=true; shift ;;
    --performance) SET_PERFORMANCE=true; shift ;;
    --on-demand) SET_ONDEMAND=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Bilinmeyen argüman: $1"
      usage
      exit 1
      ;;
  esac
done

# ---------------------------------------------------
# Root kontrol
# ---------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "HATA: Script'i sudo ile çalıştırmalısın."
    exit 1
fi

# ---------------------------------------------------
# Bellek
# ---------------------------------------------------
NVIDIA_PACKAGES=(
    "nvidia-driver-535"
    "nvidia-dkms-535"
    "nvidia-prime"
    "libnvidia-gl-535"
)

# ---------------------------------------------------
# Nouveau blacklist
# ---------------------------------------------------
disable_nouveau() {
    echo ">>> nouveau sürücüsü disable ediliyor..."
    mkdir -p /etc/modprobe.d
    cat <<EOF >/etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
}

enable_nouveau() {
    echo ">>> nouveau yeniden etkinleştiriliyor..."
    rm -f /etc/modprobe.d/blacklist-nouveau.conf || true
    update-initramfs -u
}

# ---------------------------------------------------
# NVIDIA yükle
# ---------------------------------------------------
install_nvidia() {
    echo "=========================================="
    echo "     NVIDIA 535 KURULUMU BAŞLIYOR"
    echo "=========================================="

    disable_nouveau

    apt update -y
    apt install -y "${NVIDIA_PACKAGES[@]}"

    echo ">>> DKMS modülleri derleniyor..."
    dkms autoinstall || true

    echo ">>> initramfs güncelleniyor..."
    update-initramfs -u

    echo ">>> NVIDIA paketleri hold ediliyor..."
    apt-mark hold "${NVIDIA_PACKAGES[@]}"

    echo ""
    echo ">>> NVIDIA kurulumu tamamlandı!"
    echo "Sistemi yeniden başlatmanız önerilir:"
    echo "    sudo reboot"
}

# ---------------------------------------------------
# NVIDIA kaldır
# ---------------------------------------------------
remove_nvidia() {
    echo "=========================================="
    echo "     NVIDIA SÜRÜCÜLERİ KALDIRILIYOR"
    echo "=========================================="

    apt-mark unhold "${NVIDIA_PACKAGES[@]}" || true
    apt remove --purge -y "${NVIDIA_PACKAGES[@]}" || true
    apt autoremove -y

    enable_nouveau

    echo ">>> NVIDIA kaldırıldı. Reboot önerilir."
}

# ---------------------------------------------------
# NVIDIA PRIME Mod değiştir
# ---------------------------------------------------
set_performance() {
    echo ">>> PRIME Performance mode etkinleştiriliyor..."
    prime-select nvidia
    echo ">>> Reboot sonrası aktif olur."
}

set_on_demand() {
    echo ">>> PRIME On-Demand mode etkinleştiriliyor..."
    prime-select on-demand
    echo ">>> Reboot sonrası aktif olur."
}

# ---------------------------------------------------
# İşlemleri çalıştır
# ---------------------------------------------------
$INSTALL && install_nvidia
$REMOVE && remove_nvidia
$SET_PERFORMANCE && set_performance
$SET_ONDEMAND && set_on_demand

exit 0