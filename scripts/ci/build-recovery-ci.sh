#!/usr/bin/env bash
# build-recovery-ci.sh — 在 CI 里同步最小 AOSP 树并产出 sagit 的 recovery.img
#
# 环境变量（由 workflow 注入）：
#   MANIFEST_BRANCH     默认 twrp-9.0
#   KERNEL_MODE         prebuilt | source
#   KERNEL_REPO/KERNEL_BRANCH
#   PREBUILT_KERNEL_URL kernel_mode=prebuilt 时的 Image.gz-dtb 直链
#   KERNEL_CLANG        true 则用 clang 编内核（绕过 jammy 缺 32 位 ncurses）
#   DEVICE_DIR          本仓库里的 device/xiaomi/sagit
#   AOSP_DIR            工作目录，默认 $RUNNER_TEMP/aosp
set -euo pipefail

MANIFEST="${MANIFEST:-https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-twrp-9.0}"
KERNEL_MODE="${KERNEL_MODE:-prebuilt}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/LineageOS/android_kernel_xiaomi_msm8998.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-staging/lineage-16.0}"
KERNEL_CLANG="${KERNEL_CLANG:-false}"
DEVICE_DIR="${DEVICE_DIR:?DEVICE_DIR 未设置}"
AOSP_DIR="${AOSP_DIR:-${RUNNER_TEMP:-/tmp}/aosp}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PWD/artifacts}"
JOBS="${JOBS:-$(nproc)}"

step() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$*"; }

step "0. 环境"
export LC_ALL=C
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_EXEC="$(command -v ccache || echo /usr/bin/ccache)"
export CCACHE_MAXSIZE=12G
export ALLOW_MISSING_DEPENDENCIES=true      # TWRP 最小树必备
export WITH_SU=false
df -h / | tail -1
java -version 2>&1 | head -1
nproc; free -h | head -2

step "1. 同步源码 ($MANIFEST_BRANCH)"
mkdir -p "$AOSP_DIR" && cd "$AOSP_DIR"
if [ ! -d .repo ]; then
    repo init -u "$MANIFEST" -b "$MANIFEST_BRANCH" --depth=1 --no-repo-verify
fi
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --fail-fast
du -sh . 2>/dev/null | tail -1

step "2. 放入设备树"
mkdir -p device/xiaomi
rsync -a --delete "$DEVICE_DIR/" device/xiaomi/sagit/
# 设备树里补一个 Android.mk 聚合入口（若仓库没带）
if [ ! -f device/xiaomi/sagit/Android.mk ]; then
    cat > device/xiaomi/sagit/Android.mk <<'MK'
LOCAL_PATH := $(call my-dir)
ifeq ($(TARGET_DEVICE),sagit)
include $(call all-makefiles-under,$(LOCAL_PATH))
endif
MK
fi

step "3. 内核"
mkdir -p kernel/xiaomi
if [ "$KERNEL_MODE" = "source" ]; then
    if [ ! -d kernel/xiaomi/msm8998 ]; then
        git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" kernel/xiaomi/msm8998
    fi
    DEFCONFIG=kernel/xiaomi/msm8998/arch/arm64/configs/sagit_defconfig
    if ! grep -q 'CONFIG_DRM_FBDEV_EMULATION' "$DEFCONFIG"; then
        echo ">> 追加 WiFi / fbdev 内核选项"
        FRAG="${GITHUB_WORKSPACE:-$PWD}/kernel/sagit-wifi.fragment"
        [ -f "$FRAG" ] || { echo "!! 找不到 $FRAG"; exit 1; }
        cat "$FRAG" >> "$DEFCONFIG"
    fi
    if [ "$KERNEL_CLANG" = "true" ]; then
        echo 'TARGET_KERNEL_CLANG_COMPILE := true' >> device/xiaomi/sagit/BoardConfig.mk
    fi
else
    [ -n "${PREBUILT_KERNEL_URL:-}" ] || {
        echo "!! KERNEL_MODE=prebuilt 但没有 PREBUILT_KERNEL_URL"
        echo "   传一个可用的 Image.gz-dtb 直链，或把 kernel_mode 改成 source"
        exit 1
    }
    echo ">> 下载预编译内核"
    curl -fL --retry 3 -o kernel/Image.gz-dtb "$PREBUILT_KERNEL_URL"
    ls -lh kernel/Image.gz-dtb
    echo "TARGET_PREBUILT_KERNEL := $AOSP_DIR/kernel/Image.gz-dtb" >> device/xiaomi/sagit/BoardConfig.mk
fi

step "4. lunch"
# 关键：repo 的 linkfile 有时不生成，gettop 会失败并让 envsetup 去 source
# /vendor/omni/build/envsetup.sh（报 No such file or directory）。显式补洞：
export TOP="$AOSP_DIR"
[ -e build/core ]        || ln -sfn make/core        build/core
[ -e build/envsetup.sh ] || ln -sfn make/envsetup.sh build/envsetup.sh
[ -e build/target ]      || ln -sfn make/target      build/target
[ -e build/tools ]       || ln -sfn make/tools       build/tools
ls -ld build/core build/envsetup.sh

source build/envsetup.sh
lunch skyward_sagit-eng || { echo "!! lunch 失败：检查 AndroidProducts.mk / 缺模块"; exit 1; }

step "5. 编译 recoveryimage（首次约 50-70 分钟）"
/usr/bin/time -v mka -j"$JOBS" recoveryimage 2>&1 | tail -40 || true
IMG=out/target/product/sagit/recovery.img
[ -f "$IMG" ] || { echo "!! 没有产出 $IMG"; ls -l out/target/product/sagit/ | tail -20; exit 1; }

step "6. 产物"
mkdir -p "$ARTIFACT_DIR"
cp "$IMG" "$ARTIFACT_DIR/recovery.img"
ls -lh "$ARTIFACT_DIR"
echo ">> 完成：$ARTIFACT_DIR/recovery.img"
