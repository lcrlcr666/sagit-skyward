#!/usr/bin/env bash
# build-recovery.sh — 一键拉源码 + 生成 Skyward Recovery (sagit)
# 宿主：Ubuntu 22.04 / WSL2，≥200GB 磁盘，≥16GB RAM
# 用法：./build-recovery.sh [源码目录，默认 ~/skyward]
set -euo pipefail

SRC=${1:-$HOME/skyward}
DEV=$(cd "$(dirname "$0")/../device/xiaomi" && pwd)
KFRAG=$(cd "$(dirname "$0")/../kernel" && pwd)/sagit-wifi.fragment
JOBS=$(nproc)

echo "== 1/6 依赖 =="
sudo apt update
sudo apt install -y git curl python3 openjdk-8-jdk bc bison build-essential ccache \
    flex g++-multilib gcc-multilib git gnupg gperf imagemagick lib32ncurses5-dev \
    lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev \
    libwxgtk3.0-gtk3-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev android-tools-adb android-tools-fastboot \
    repo 2>/dev/null || sudo apt install -y repo

mkdir -p "$SRC" && cd "$SRC"

echo "== 2/6 同步 manifest（recovery 最小树，Android 9 / Pie）=="
if [ ! -d .repo ]; then
    repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git \
              -b twrp-9.0 --depth=1
fi
repo sync -j"$JOBS" --force-sync --no-clone-bundle --no-tags

echo "== 3/6 内核 =="
if [ ! -d kernel/xiaomi/msm8998 ]; then
    git clone --depth=1 -b lineage-18.1 \
        https://github.com/LineageOS/android_kernel_xiaomi_msm8998.git kernel/xiaomi/msm8998
fi
# 追加 WiFi / fbdev 选项
if ! grep -q "CONFIG_DRM_FBDEV_EMULATION" kernel/xiaomi/msm8998/arch/arm64/configs/sagit_defconfig; then
    echo ">> 追加内核 fragment"
    cat "$KFRAG" >> kernel/xiaomi/msm8998/arch/arm64/configs/sagit_defconfig
fi

echo "== 4/6 设备树 =="
mkdir -p device/xiaomi
rm -rf device/xiaomi/sagit
cp -a "$DEV/sagit" device/xiaomi/sagit

echo "== 5/6 预置固件 =="
if [ -d device/xiaomi/sagit/prebuilt/firmware ]; then
    cat > device/xiaomi/sagit/prebuilt/Android.mk <<'MK'
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := sagit_wifi_firmware
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/vendor/firmware
LOCAL_SRC_FILES := $(wildcard $(LOCAL_PATH)/firmware/*)
include $(BUILD_PREBUILT)
MK
    echo "   已找到 prebuilt/firmware"
else
    echo "   !! 未找到固件，先跑 wifi/extract_firmware.sh（否则 WiFi 一定不通）"
fi

echo "== 6/6 编译 =="
. build/envsetup.sh
lunch skyward_sagit-eng
mka -j"$JOBS" recoveryimage

OUT="$SRC/out/target/product/sagit/recovery.img"
[ -f "$OUT" ] && ls -lh "$OUT" && echo ">> 产物：$OUT" || { echo "!! 编译失败，看 out/error.log"; exit 1; }
