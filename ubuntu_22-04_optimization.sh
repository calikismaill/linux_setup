#!/usr/bin/env bash
#
# ubuntu-optimize.sh
# Ubuntu 22.04 GNOME için hız + kararlılık optimizasyon scripti
# Dell G15 / NVIDIA / hybrid GPU laptoplar için özel ayarlar içerir
#

set -euo pipefail

echo "======================================================"
echo " Ubuntu 22.04 GNOME Optimize Script (Dell G15 Edition)"
echo "======================================================"

if [[ $EUID -ne 0 ]]; then
    echo "Lütfen sudo ile çalıştır: sudo ./ubuntu-optimize.sh"
    exit 1
fi

# ------------------------------
# 1) GNOME Animations OFF
# ------------------------------
echo ">>> GNOME animasyonları kapatılıyor..."
sudo -u "$SUDO_USER" gsettings set org.gnome.desktop.interface enable-animations false

# ------------------------------
# 2) Tracker indexer kapatma
# ------------------------------
echo ">>> Tracker hizmetleri disable ediliyor..."

systemctl --user mask tracker-miner-fs-3.service || true
systemctl --user mask tracker-miner-rss-3.service || true
systemctl --user mask tracker-extract-3.service || true
systemctl --user mask tracker-store-3.service || true

# disable at system level too
systemctl mask tracker-miner-fs-3.service || true
systemctl mask tracker-miner-rss-3.service || true
systemctl mask tracker-extract-3.service || true
systemctl mask tracker-store-3.service || true

# ------------------------------
# 3) Wayland → X11
# ------------------------------
echo ">>> Wayland devre dışı bırakılıyor (GNOME için X11 zorlanıyor)..."

GDM_FILE="/etc/gdm3/custom.conf"

if ! grep -q "^WaylandEnable=false" "$GDM_FILE"; then
    sed -i 's/#WaylandEnable=false/WaylandEnable=false/' "$GDM_FILE" || true
    echo "WaylandEnable=false" >> "$GDM_FILE"
fi

# ------------------------------
# 4) Kernel psr/aspm param kontrol
# ------------------------------
echo ">>> Kernel parametreleri (psr/aspm) kontrol ediliyor..."

GRUB_FILE="/etc/default/grub"

KPARAMS=("i915.enable_psr=0" "pcie_aspm=off")

CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | sed -e 's/.*="//' -e 's/"$//')

CHANGED=false
for opt in "${KPARAMS[@]}"; do
    if ! grep -qw "$opt" <<< "$CURRENT"; then
        CURRENT="$CURRENT $opt"
        CHANGED=true
        echo "  + Ekleniyor: $opt"
    fi
done

if $CHANGED; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${CURRENT}\"|" "$GRUB_FILE"
    update-grub
fi

# ------------------------------
# 5) GDM GPU fix
# ------------------------------
echo ">>> GNOME GDM scaling ve GPU fix uygulanıyor..."

mkdir -p /etc/dconf/db/local.d/

cat >/etc/dconf/db/local.d/01-gdm <<EOF
[org/gnome/mutter]
experimental-features=['scale-monitor-framebuffer']
EOF

dconf update

# ------------------------------
# 6) Gereksiz GNOME extension disable
# ------------------------------
echo ">>> Gereksiz GNOME extension'lar devre dışı bırakılıyor..."

sudo -u "$SUDO_USER" gnome-extensions disable ubuntu-appindicators@ubuntu.com || true
sudo -u "$SUDO_USER" gnome-extensions disable ubuntu-dock@ubuntu.com || true

# ------------------------------
# 7) systemd servis optimizasyonu
# ------------------------------
echo ">>> Gereksiz arka plan servisleri durduruluyor..."

systemctl disable --now motd-news.service || true
systemctl disable --now motd-news.timer || true
systemctl disable --now networkd-dispatcher.service || true
systemctl disable --now whoopsie.service || true

# ------------------------------
# 8) Log hızlandırma (tmpfs)
# ------------------------------
echo ">>> /var/log tmpfs hızlandırma aktif (isteğe bağlı)"
echo "tmpfs   /var/log    tmpfs   defaults,noatime,mode=755 0 0" >> /etc/fstab

# ------------------------------
# 9) Snap update disable
# ------------------------------
echo ">>> Snap otomatik güncellemeleri devre dışı (isteğe bağlı)..."

systemctl stop snapd.refresh.timer || true
systemctl disable snapd.refresh.timer || true

echo ""
echo "======================================================"
echo " OPTİMİZASYON TAMAMLANDI!"
echo " GNOME artık daha hızlı, stabil ve NVIDIA ile uyumlu."
echo ""
echo " Şimdi reboot etmen önerilir:"
echo "   sudo reboot"
echo "======================================================"
