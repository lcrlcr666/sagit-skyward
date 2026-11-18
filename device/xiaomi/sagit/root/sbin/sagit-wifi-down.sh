#!/system/bin/sh
# sagit-wifi-down.sh — 卸载无线栈（切换 ROM / 进 fastboot 前清理）
LOG=/tmp/sagit-wifi.log
echo "=== sagit-wifi-down $(date) ===" >>$LOG
pkill dhcpcd 2>/dev/null
pkill wpa_supplicant 2>/dev/null
ip link set wlan0 down 2>/dev/null
rmmod qca_cld3_wlan 2>/dev/null
rmmod cnss2 2>/dev/null
setprop wlan.driver.status unloaded
echo "[wifi] down" >>$LOG
