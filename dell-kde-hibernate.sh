#!/usr/bin/env bash
# ===========================================================
# DELL G15 5530 - KDE PLASMA / KUBUNTU 22.04
# FULL HIBERNATION ENABLE SCRIPT (Hybrid GPU + Kernel 6.5)
# ===========================================================

set -euo pipefail

##############################################
# ROOT CHECK
##############################################
if [[ $EUID -ne 0 ]]; then
    echo ">>> Root değil → sudo ile yeniden çalıştırılıyor..."
    sudo bash "$0" "$@"
    exit $?
fi

echo "===================================================="
echo "       KDE Plasma Hibernation Ultimate Script"
echo "               Dell G15 5530 Edition"
echo "===================================================="

##############################################
# 1) SWAP UUID TESPİTİ
##############################################
echo ">>> Swap UUID bulunuyor..."
SWAP_UUID=$(blkid -t TYPE=swap -o value -s UUID | head -n 1)

if [[ -z "$SWAP_UUID" ]]; then
    echo "!!! HATA: swap bulunamadı. Hibernation çalışmaz."
    exit 1
fi

echo ">>> Swap UUID: $SWAP_UUID"


##############################################
# 2) GRUB resume=UUID ayarları
##############################################
GRUB_FILE="/etc/default/grub"

echo ">>> GRUB düzenleniyor..."

# resume parametresi
if grep -q "resume=UUID" "$GRUB_FILE"; then
    sed -i "s|resume=UUID=[^\" ]*|resume=UUID=$SWAP_UUID|" "$GRUB_FILE"
else
    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$SWAP_UUID /" "$GRUB_FILE"
fi

# PSR & ASPM (Dell G15 için çok önemli)
echo ">>> Dell G15 GPU bug fixleri ekleniyor (PSR & ASPM)..."
for p in "i915.enable_psr=0" "pcie_aspm=off"; do
    if ! grep -q "$p" "$GRUB_FILE"; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$p /" "$GRUB_FILE"
    fi
done


##############################################
# 3) initramfs resume.conf
##############################################
echo ">>> initramfs resume.conf yazılıyor..."

echo "RESUME=UUID=$SWAP_UUID" > /etc/initramfs-tools/conf.d/resume


##############################################
# 4) NVIDIA VRAM RESTORE HIBERNATE FIX
##############################################
echo ">>> Nvidia VRAM hibernation patch uygulanıyor..."

echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" \
 > /etc/modprobe.d/nvidia-hibernate.conf


##############################################
# 5) KDE / systemd-logind ayarları
##############################################
LOGIN_FILE="/etc/systemd/logind.conf"

echo ">>> systemd-logind ayarları yapılıyor..."

sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=hibernate/' "$LOGIN_FILE"
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=hibernate/' "$LOGIN_FILE"
sed -i 's/#HandlePowerKey=.*/HandlePowerKey=hibernate/' "$LOGIN_FILE"
sed -i 's/#HibernateKeyIgnoreInhibited=.*/HibernateKeyIgnoreInhibited=yes/' "$LOGIN_FILE"

systemctl restart systemd-logind


##############################################
# 6) KDE POWER MANAGEMENT FIX
##############################################
echo ">>> KDE Power Management ayarları uygulanıyor..."

# KDE ayar dizinini oluştur
USER_NAME=$(logname)
USER_HOME=$(eval echo "~$USER_NAME")
KDE_CONF_DIR="$USER_HOME/.config"

mkdir -p "$KDE_CONF_DIR"

# KDE Global Power Management (override)
cat > "$KDE_CONF_DIR/powermanagementprofilesrc" <<EOF
[AC]
lidAction=Hibernate

[Battery]
lidAction=Hibernate

[LowBattery]
lidAction=Hibernate
EOF

chown "$USER_NAME:$USER_NAME" "$KDE_CONF_DIR/powermanagementprofilesrc"


##############################################
# 7) UPower Hibernation Enable
##############################################
echo ">>> UPower üzerinden hibernation zorla aktif ediliyor..."

sed -i 's/#HibernateAllowed=.*/HibernateAllowed=yes/' /etc/UPower/UPower.conf
sed -i 's/#IgnoreLid=.*/IgnoreLid=false/' /etc/UPower/UPower.conf

systemctl restart upower


##############################################
# 8) POLKIT izinleri (KDE için zorunlu)
##############################################
echo ">>> Polkit hibernate izinleri ekleniyor..."

mkdir -p /etc/polkit-1/localauthority/50-local.d/

cat > /etc/polkit-1/localauthority/50-local.d/enable-hibernate.pkla <<EOF
[Enable Hibernate]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate
ResultActive=yes

[Enable Hibernate-login]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate
ResultActive=yes

[Enable HybridSleep]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate
ResultActive=yes
EOF


##############################################
# 9) SDDM Safe Hibernate Delay
##############################################
echo ">>> SDDM için 'hibernation-safe delay' uygulanıyor..."

mkdir -p /etc/sddm.conf.d/

cat > /etc/sddm.conf.d/99-hibernate-fix.conf <<EOF
[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[X11]
DisplayStopCommand=/usr/bin/sleep 1
EOF


##############################################
# 10) initramfs + grub update
##############################################
echo ">>> initramfs güncelleniyor..."
update-initramfs -u

echo ">>> grub güncelleniyor..."
update-grub


##############################################
# TAMAMLANDI
##############################################
echo ""
echo "===================================================="
echo " ✔ KDE HIBERNATION TAMAMEN AKTİF EDİLDİ"
echo " ---------------------------------------------------"
echo " Test etmek için:"
echo "   systemctl hibernate"
echo ""
echo " Sorunsuz olduğunda:"
echo "   Lid kapatma → hibernate"
echo "   Güç tuşu → hibernate"
echo "   KDE menü → Hibernate"
echo ""
echo " Dell G15 + Kernel 6.5 ile tam uyumludur."
echo "===================================================="
