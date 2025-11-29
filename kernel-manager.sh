#!/usr/bin/env bash
#
# smart-kernel-manager-v3.sh
#
# FINAL VERSION — İsmail için özel
# Kernel 6.5'i default yapar, GRUB_DEFAULT=saved düzeltmesi yapar,
# reboot sonrası 6.8 kernel'i otomatik siler.
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
echo " Smart Kernel Manager v3"
echo " Target kernel: ${TARGET_KERNEL}"
echo "====================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Lütfen sudo ile çalıştır."
  exit 1
fi

ACTIVE_KERNEL=$(uname -r)
echo ">>> Aktif kernel: ${ACTIVE_KERNEL}"

# -----------------------------------------------------------
# GRUB_DEFAULT = saved fix
# -----------------------------------------------------------
echo ">>> GRUB_DEFAULT=saved kontrol ediliyor..."

if grep -q '^GRUB_DEFAULT=0' "$GRUB_FILE"; then
    echo ">>> GRUB_DEFAULT=0 bulundu → düzeltiliyor..."
    sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' "$GRUB_FILE"
else
    # GRUB_DEFAULT=saved yoksa yine ekleyelim
    if ! grep -q '^GRUB_DEFAULT=saved' "$GRUB_FILE"; then
        echo ">>> GRUB_DEFAULT=saved ekleniyor..."
        sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' "$GRUB_FILE" || \
        echo 'GRUB_DEFAULT=saved' >> "$GRUB_FILE"
    else
        echo ">>> GRUB_DEFAULT zaten saved."
    fi
fi

# -----------------------------------------------------------
# Eğer aktif kernel 6.5 ise → 6.8 kernel’leri sil
# -----------------------------------------------------------
if [[ "$ACTIVE_KERNEL" == "$TARGET_KERNEL" ]]; then
    echo ">>> 6.5 kernel aktif — 6.8 kernel paketleri temizleniyor..."

    REMOVE_LIST=$(dpkg -l | grep 'linux-image-6.8' | awk '{print $2}' || true)

    if [[ -z "$REMOVE_LIST" ]]; then
        echo ">>> 6.8 kernel bulunamadı. İşlem tamam."
    else
        echo ">>> Silinecek paketler:"
        echo "$REMOVE_LIST" | sed 's/^/  - /'

        apt purge -y $REMOVE_LIST || true
        apt autoremove -y || true

        echo ">>> 6.8 kernel tamamen silindi."
    fi

    # GRUB fix sonrası update-grub yap
    update-grub
    exit 0
fi

# -----------------------------------------------------------
# 6.5 aktif değilse → kurulacak
# -----------------------------------------------------------
echo ">>> 6.5 kernel kuruluyor / yenileniyor..."

apt update -y

for pkg in "${KERNEL_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        echo ">>> Installing: $pkg"
        apt install --reinstall -y "$pkg"
    else
        echo ">>> Paket bulunamadı, atlanıyor: $pkg"
    fi
done

update-initramfs -u -k "${TARGET_KERNEL}"

# -----------------------------------------------------------
# Kernel optimizasyon parametreleri
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
# GRUB default kernel ayarı
# -----------------------------------------------------------
echo ">>> GRUB default kernel ayarlanıyor (saved_entry sistemi ile)..."

TARGET_ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}"
grub-set-default "${TARGET_ENTRY}" || {
    echo "UYARI: grub-set-default hata verdi. Menü isimleri değişmiş olabilir."
}

update-grub

echo ""
echo "====================================================="
echo "  Kernel 6.5 kurulumu tamamlandı!"
echo ""
echo "  Şimdi sistemi yeniden başlatın:"
echo "     sudo reboot"
echo ""
echo "  Reboot sonrası tekrar bu script'i çalıştırırsan:"
echo "     → 6.8 kernel otomatik olarak silinir."
echo "====================================================="
