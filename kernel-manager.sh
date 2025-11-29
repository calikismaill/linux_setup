#!/usr/bin/env bash
#
# kernel-manager.sh
# Ubuntu 22.04 / Xubuntu 22.04 için kernel yönetim scripti
#
# Özellikler:
#  - Belirtilen kernel sürümünü kurar / yeniden kurar
#  - GRUB'da belirtilen kernel'i varsayılan yapar (başlığa göre)
#  - İsteğe bağlı: GRUB_CMDLINE_LINUX_DEFAULT içine ekstra parametre ekler (PSR/ASPM fix gibi)
#  - İsteğe bağlı: Kernel paketlerini apt-mark hold ile sabitler
#
# Örnek kullanımlar:
#   sudo bash kernel-manager.sh --kernel 6.5.0-45-generic --set-default
#   sudo bash kernel-manager.sh --kernel 6.5.0-45-generic --set-default --hold
#   sudo bash kernel-manager.sh --kernel 6.5.0-45-generic --set-default --tweak-grub --hold
#
# UYARI:
#   - Sadece Ubuntu 22.04 tabanlı sistemler (Ubuntu, Xubuntu, Kubuntu vs.) için tasarlanmıştır.
#   - GRUB kullanıldığı varsayılmıştır (systemd-boot değil).
#

set -euo pipefail

# --------------------------
# Varsayılanlar
# --------------------------
KERNEL_VERSION="6.5.0-45-generic"
SET_DEFAULT=false
DO_HOLD=false
TWEAK_GRUB=false   # PSR/ASPM gibi ek parametreler
NONINTERACTIVE=false

# --------------------------
# Yardım metni
# --------------------------
usage() {
  cat <<EOF
Usage: sudo bash $0 [options]

Options:
  --kernel VERSION      Kurulacak kernel sürümü (varsayılan: ${KERNEL_VERSION})
                        Örn: 6.5.0-45-generic
  --set-default         Bu kernel'i GRUB'da varsayılan giriş yap
  --hold                Bu kernel ile ilişkili paketleri apt-mark hold ile sabitle
  --tweak-grub          GRUB_CMDLINE_LINUX_DEFAULT içine ekstra parametre ekle
                        (i915.enable_psr=0 pcie_aspm=off)
  --non-interactive     apt komutlarını non-interaktif çalıştır (CI/CD için)
  -h, --help            Bu yardım metnini göster

Örnek:
  sudo bash $0 --kernel 6.5.0-45-generic --set-default --hold --tweak-grub
EOF
}

# --------------------------
# Argüman parse
# --------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel)
      KERNEL_VERSION="$2"
      shift 2
      ;;
    --set-default)
      SET_DEFAULT=true
      shift
      ;;
    --hold)
      DO_HOLD=true
      shift
      ;;
    --tweak-grub)
      TWEAK_GRUB=true
      shift
      ;;
    --non-interactive)
      NONINTERACTIVE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Bilinmeyen argüman: $1"
      usage
      exit 1
      ;;
  esac
done

# --------------------------
# Root kontrol
# --------------------------
if [[ $EUID -ne 0 ]]; then
  echo ">>> Lütfen script'i sudo ile çalıştırın."
  echo "Örnek:"
  echo "  sudo bash $0 --kernel ${KERNEL_VERSION} --set-default"
  exit 1
fi

# --------------------------
# Distro ve GRUB kontrolü
# --------------------------
if ! grep -qi "Ubuntu 22.04" /etc/os-release; then
  echo "UYARI: Bu script Ubuntu 22.04 için tasarlandı. /etc/os-release:"
  cat /etc/os-release
  echo "Yine de devam etmek istiyorsanız ENTER'a basın, iptal için Ctrl+C."
  read -r _
fi

if ! command -v update-grub >/dev/null 2>&1; then
  echo "HATA: update-grub komutu bulunamadı. GRUB kullanmıyor olabilirsiniz."
  exit 1
fi

# --------------------------
# apt non-interactive ayarı
# --------------------------
if $NONINTERACTIVE; then
  export DEBIAN_FRONTEND=noninteractive
fi

echo "============================================="
echo " Kernel Manager"
echo "  - Hedef kernel : ${KERNEL_VERSION}"
echo "  - Varsayılan yap: ${SET_DEFAULT}"
echo "  - Hold (sabit):  ${DO_HOLD}"
echo "  - GRUB tweak:    ${TWEAK_GRUB}"
echo "============================================="

# --------------------------
# 1) APT update
# --------------------------
echo ">>> APT index güncelleniyor..."
apt update -y

# --------------------------
# 2) Kernel paketlerini kur / yeniden kur
# --------------------------
IMAGE_PKG="linux-image-${KERNEL_VERSION}"
HEADERS_PKG="linux-headers-${KERNEL_VERSION}"
MODULES_PKG="linux-modules-${KERNEL_VERSION}"
EXTRA_PKG="linux-modules-extra-${KERNEL_VERSION}"

echo ">>> Kernel paketleri kuruluyor/yenileniyor:"
echo "    - ${IMAGE_PKG}"
echo "    - ${HEADERS_PKG}"
echo "    - ${MODULES_PKG}"
echo "    - ${EXTRA_PKG}"

apt install --reinstall -y \
  "${IMAGE_PKG}" \
  "${HEADERS_PKG}" \
  "${MODULES_PKG}" \
  "${EXTRA_PKG}" \
  linux-firmware

# --------------------------
# 3) initramfs güncelle
# --------------------------
echo ">>> initramfs ${KERNEL_VERSION} için güncelleniyor..."
update-initramfs -u -k "${KERNEL_VERSION}"

GRUB_FILE="/etc/default/grub"

# --------------------------
# 4) GRUB CMDLINE parametrelerini isteğe bağlı tweak et
# --------------------------
if $TWEAK_GRUB; then
  echo ">>> GRUB_CMDLINE_LINUX_DEFAULT parametreleri güncelleniyor (i915.enable_psr=0 pcie_aspm=off)..."

  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" \
      | sed -e 's/^GRUB_CMDLINE_LINUX_DEFAULT="//' -e 's/"$//')
  else
    CURRENT="quiet splash"
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT}\"" >> "$GRUB_FILE"
  fi

  for opt in "i915.enable_psr=0" "pcie_aspm=off"; do
    if ! grep -qw "$opt" <<< "$CURRENT"; then
      CURRENT="$CURRENT $opt"
    fi
  done

  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT}\"|" "$GRUB_FILE"
fi

# --------------------------
# 5) GRUB default entry ayarla (isteğe bağlı)
# --------------------------
if $SET_DEFAULT; then
  echo ">>> GRUB default kernel girişini ayarlama işlemi başlıyor..."

  TARGET_TITLE="Ubuntu, with Linux ${KERNEL_VERSION}"

  if ! grep -q "${TARGET_TITLE}" /boot/grub/grub.cfg; then
    echo "UYARI: /boot/grub/grub.cfg içinde '${TARGET_TITLE}' bulunamadı."
    echo "GRUB menu entry isimleri şunlar:"
    grep "menuentry '" /boot/grub/grub.cfg | sed "s/.*menuentry '\(.*\)'.*/\1/" | sed 's/^/  - /'
    echo ""
    echo "GRUB_DEFAULT değerini manuel ayarlaman gerekebilir."
  else
    # Advanced options başlığını varsayıyoruz
    ADV_TITLE="Advanced options for Ubuntu"
    GRUB_DEFAULT_VALUE="${ADV_TITLE}>${TARGET_TITLE}"

    if grep -q '^GRUB_DEFAULT=' "$GRUB_FILE"; then
      sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${GRUB_DEFAULT_VALUE}\"|" "$GRUB_FILE"
    else
      echo "GRUB_DEFAULT=\"${GRUB_DEFAULT_VALUE}\"" >> "$GRUB_FILE"
    fi

    echo ">>> GRUB_DEFAULT=\"${GRUB_DEFAULT_VALUE}\" olarak ayarlandı."
  fi
fi

# --------------------------
# 6) GRUB yeniden oluştur
# --------------------------
echo ">>> GRUB yeniden oluşturuluyor..."
update-grub

# --------------------------
# 7) Kernel paketlerini HOLD et (isteğe bağlı)
# --------------------------
if $DO_HOLD; then
  echo ">>> Kernel paketleri apt-mark hold ile sabitleniyor..."
  apt-mark hold "${IMAGE_PKG}" \
                "${HEADERS_PKG}" \
                "${MODULES_PKG}" \
                "${EXTRA_PKG}" || true

  # Eğer HWE meta paketi varsa, onu da kilitle
  if dpkg -l | grep -q '^ii  linux-generic-hwe-22.04'; then
    echo ">>> linux-generic-hwe-22.04 paketi de hold ediliyor..."
    apt-mark hold linux-generic-hwe-22.04 || true
  fi
fi

echo ""
echo "============================================="
echo "  Kernel işlemi tamamlandı!"
echo "  Seçilen kernel: ${KERNEL_VERSION}"
echo ""
echo "  Şimdi sistemi yeniden başlatmanız önerilir:"
echo "    sudo reboot"
echo ""
echo "  Yeniden başladıktan sonra doğrulamak için:"
echo "    uname -r"
echo "  Beklenen çıktı:"
echo "    ${KERNEL_VERSION}"
echo "============================================="