#!/usr/bin/env bash
# flash-and-verify.sh — 刷入 + 逐项验证（WiFi / 浏览器 / 下载）
# 前提：Mi6 已解锁 BL；`adb`、`fastboot` 在 PATH
set -uo pipefail
IMG=${1:-}
[ -n "$IMG" ] || { echo "usage: $0 recovery.img"; exit 1; }

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

say "刷入"
adb reboot bootloader 2>/dev/null || true
sleep 8
fastboot devices
fastboot flash recovery "$IMG"
fastboot erase cache
say "进入 recovery"
fastboot reboot recovery 2>/dev/null || fastboot oem reboot-recovery
sleep 20
adb wait-for-device
adb shell 'getprop ro.twrp.version; getprop ro.hardware'

say "1. 分区与挂载"
adb shell 'ls /dev/block/bootdevice/by-name | tr "\n" " "; echo; mount | grep -E "vendor|persist|data"'

say "2. WiFi 固件与模块"
adb shell 'ls -l /vendor/firmware/ | head -20; ls -l /vendor/lib/modules/ 2>/dev/null; ls -l /persist/wlan_mac.bin'

say "3. 手动跑一次 WiFi 修复"
adb shell '/system/bin/sh /sbin/sagit-wifi-up.sh; cat /tmp/sagit-wifi.log'

say "4. 接口状态"
adb shell 'lsmod | grep -E "wlan|cnss"; ip -4 addr show wlan0; dmesg | grep -iE "wlan|cnss" | tail -20'

say "5. 配 WiFi 并联网（改 SSID/PSK）"
cat <<'TIP'
  adb shell "sed -i 's/TARGET_SSID/你的SSID/;s/TARGET_PSK/你的密码/' /etc/wpa_supplicant.conf"
  adb shell "pkill wpa_supplicant; wpa_supplicant -B -iwlan0 -Dnl80211 -c/etc/wpa_supplicant.conf"
  adb shell "dhcpcd -b -t 15 wlan0"
  adb shell "ping -c 3 223.5.5.5"
TIP

say "6. 浏览器环境"
adb shell 'ls -l /dev/fb0 /dev/input/ | head; ls -l /data/linux/rootfs.img 2>/dev/null'

say "7. 下载 ROM（无图形界面时）"
adb shell '/system/bin/sh /sbin/romget.sh -l https://download.lineageos.org/devices/sagit'

say "8. 启动浏览器（第二阶段 Linux）"
echo '  adb shell "mkdir -p /data/linux"'
echo '  adb push out/rootfs-sagit.img /data/linux/rootfs.img'
echo '  adb shell "/system/bin/sh /sbin/linux-boot.sh; tail -50 /tmp/linux-boot.log"'

say "9. 崩溃日志（失败时抓）"
echo '  adb shell dmesg > dmesg.txt; adb shell cat /tmp/sagit-wifi.log > wifi.txt'
echo '  adb pull /data/linux/var/log/Xorg.0.log .'
