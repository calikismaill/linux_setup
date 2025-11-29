#!/usr/bin/env bash
#
# smart-kernel-manager.sh
# Ubuntu 22.04 için "akıllı kernel script"
#
#   ✔ 6.5 kernel yüklü ve aktifse → 6.8 kernel'leri tamamen siler.
#   ✔ Default kernel 6.8 ise → 6.5 kurar, default yapar.
#   ✔ 6.5 kurulu değilse → kurar.
#   ✔ Kernel parametre optimizasyonları ekler (PSR/ASPM/RCU)
#   ✔ Reboot sonrası tekrar çalıştırıldığında otomatik temizlik yapar.
#
#  NVIDIA'ya dokunmaz. Sadece kernel yönetir.
#

set -euo pipefail

TARGET_KERNEL="6.5.0-45-generic"
GRUB_FILE="/etc/default/grub"

KERNEL_PACKAGES=(
  "linux-image-${TARGET_KERNEL}"
  "linux-headers-${TARGET_KERNEL}"
  "linux-modules-${TARGET_KERNEL}"
  "linux-modules-extra-${TARGET_KERNEL}"
)

OPT_PARAMS=(
  "i915.enable_psr=0"
  "pcie_aspm=off"
  "rcu_nocbs=0-15"
)

echo "====================================================="
echo " Smart Kernel Manager"
echo " Target kernel: ${TARGET_KERNEL}"
echo "====================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Lütfen sudo ile çalıştır."
  exit 1
fi

ACTIVE_KERNEL=$(uname -r)

echo ">>> Aktif kernel: ${ACTIVE_KERNEL}"

# -----------------------------------------------------------
# 1) Eğer aktif kernel zaten 6.5 ise → 6.8 kernel'leri sil
# -----------------------------------------------------------
if [[ "$ACTIVE_KERNEL" == "$TARGET_KERNEL" ]]; then
    echo ">>> 6.5 kernel zaten aktif — şimdi sistemdeki 6.8 kernel paketleri kaldırılıyor..."

    REMOVE_LIST=$(dpkg -l | grep 'linux-image-6.8' | awk '{print $2}' || true)

    if [[ -z "$REMOVE_LIST" ]]; then
        echo ">>> Silinecek 6.8 kernel bulunamadı. İşlem tamam."
        exit 0
    fi

    echo ">>> Kaldırılacak paketler:"
    echo "$REMOVE_LIST" | sed 's/^/  - /'

    apt purge -y $REMOVE_LIST || true
    apt autoremove -y || true

    echo ">>> 6.8 kernel tamamen silindi."
    exit 0
fi

# -----------------------------------------------------------
# 2) 6.5 kurulu mu kontrol et — değilse kur
# -----------------------------------------------------------
echo ">>> 6.5 kernel aktif değil — şimdi kurulacak veya yeniden kurulacak."

apt update -y

for pkg in "${KERNEL_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        echo ">>> Installing: $pkg"
        apt install --reinstall -y "$pkg"
    else
        echo ">>> Paket bulunamadı, atlandı: $pkg"
    fi
done

echo ">>> initramfs güncelleniyor..."
update-initramfs -u -k "${TARGET_KERNEL}"

# -----------------------------------------------------------
# 3) Kernel parametre optimizasyonları
# -----------------------------------------------------------
echo ">>> Kernel optimizasyon parametreleri ekleniyor..."

CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | sed -e 's/.*="//' -e 's/"$//')

for opt in "${OPT_PARAMS[@]}"; do
    if ! grep -qw "$opt" <<< "$CURRENT"; then
        CURRENT="$CURRENT $opt"
        echo "  + $opt"
    else
        echo "  - $opt (zaten var)"
    fi
done

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT}\"|" "$GRUB_FILE"

# -----------------------------------------------------------
# 4) GRUB default entry olarak 6.5 kernel'i seç
# -----------------------------------------------------------
echo ">>> GRUB default kernel ayarlanıyor..."

TARGET_ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}"
grub-set-default "${TARGET_ENTRY}" || {
    echo "UYARI: grub-set-default başarısız olabilir. Menü isimleri değişmiş olabilir."
}

update-grub

echo ""
echo "====================================================="
echo " Kernel 6.5 kurulumu tamamlandı!"
echo " Şimdi reboot et:"
echo "   sudo reboot"
echo ""
echo " Reboot sonrası tekrar bu script'i çalıştırırsan:"
echo "   → 6.8 kernel otomatik olarak silinecek."
echo "====================================================="