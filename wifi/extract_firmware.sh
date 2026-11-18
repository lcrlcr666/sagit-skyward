#!/usr/bin/env bash
# extract_firmware.sh — 从 MIUI / 官方 ROM / 本机 vendor 分区提取 Mi6 WiFi 固件
# 用法（在 AOSP 源码根目录执行）：
#   ./extract_firmware.sh                      # 从 adb 设备（MIUI 系统）直接拉
#   ./extract_firmware.sh vendor.img           # 从解包的 vendor.img 目录拉
#   ./extract_firmware.sh --check              # 只检查现有固件是否齐全
# 产出：device/xiaomi/sagit/prebuilt/firmware/{...} + 一份清单 firmware.sha256
set -euo pipefail

DEST="device/xiaomi/sagit/prebuilt/firmware"
MODDEST="device/xiaomi/sagit/prebuilt/modules"
MODE="${1:-adb}"

need_fw=(bdwlan30.bin qwlan30.bin otp30.bin bdwlan30c.bin qwlan30c.bin \
         WCNSS_qcom_cfg.ini p2p_supplicant.conf wpa_supplicant_overlay.conf)
need_mod=(qca_cld3_wlan.ko cnss2.ko)

check() {
    local ok=1
    for f in "${need_fw[@]}"; do
        find device/xiaomi/sagit -name "$f" -print -quit | grep -q . || { echo "缺 $f"; ok=0; }
    done
    for m in "${need_mod[@]}"; do
        find device/xiaomi/sagit -name "$m" -print -quit | grep -q . || echo "（可选）缺模块 $m"
    done
    [ $ok -eq 1 ] && echo "固件齐全 ✔"
}

mkdir -p "$DEST" "$MODDEST"

pull_adb() {
    echo ">> 从设备拉取（需已 root 且 adb root 可用）"
    adb root || true; sleep 2; adb wait-for-device
    adb shell 'ls /vendor/firmware | head -50'
    for f in "${need_fw[@]}"; do
        for p in "/vendor/firmware/$f" "/vendor/firmware/wlan/qca_cld/$f" \
                 "/system/etc/firmware/$f" "/vendor/firmware_mnt/image/$f"; do
            if adb shell "[ -f $p ]" 2>/dev/null; then
                adb pull "$p" "$DEST/$f" && echo "  取到 $p"
                break
            fi
        done
    done
    for m in "${need_mod[@]}"; do
        for p in "/vendor/lib/modules/$m" "/system/lib/modules/$m"; do
            if adb shell "[ -f $p ]" 2>/dev/null; then
                adb pull "$p" "$MODDEST/$m" && echo "  取到 $p"
                break
            fi
        done
    done
    # persist 里的出厂 MAC：有就带上，没有则运行时派生
    adb pull /persist/wlan_mac.bin "$DEST/wlan_mac.bin.factory" 2>/dev/null || \
        echo "  无出厂 MAC（正常，运行时会派生）"
}

pull_dir() {
    local src="$1"
    echo ">> 从目录 $src 复制"
    for f in "${need_fw[@]}"; do
        find "$src" -name "$f" -print -quit | while read -r p; do
            cp -f "$p" "$DEST/"; echo "  取到 $p"
        done
    done
    for m in "${need_mod[@]}"; do
        find "$src" -name "$m" -print -quit | while read -r p; do
            cp -f "$p" "$MODDEST/"; echo "  取到 $p"
        done
    done
}

case "$MODE" in
    --check) check; exit 0 ;;
    adb)     pull_adb ;;
    *)       pull_dir "$MODE" ;;
esac

check
( cd "$DEST" && sha256sum * > firmware.sha256 ) 2>/dev/null || true
echo ">> 固件已就位：$DEST"
echo ">> 内核 defconfig 核对：grep -E 'CNSS|WLAN|QCA_CLD' arch/arm64/configs/sagit_defconfig"
