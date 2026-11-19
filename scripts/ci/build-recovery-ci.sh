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
export CCACHE_MAXSIZE=8G      # GitHub cache 上限 10G，留余量
export CCACHE_COMPRESS=true
export CCACHE_COMPRESSLEVEL=6
export CCACHE_SLOPPINESS=time_macros,include_file_ctime,include_file_mtime
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
# 注意：Android 9 (Pie) 的 mkbootimg 在 system/core/mkbootimg，
# `system/tools/mkbootimg` 是 Android 10 才独立出来的项目。
# 之前误加过 local_manifests 去拉 system/tools/mkbootimg，
# 结果 repo sync 直接 SyncFailFastError（该 tag 下没有这个 project）。
# system/core 本来就在 manifest 里，所以什么都不用补。
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags --fail-fast
du -sh . 2>/dev/null | tail -1
if [ -f system/core/mkbootimg/Android.mk ] || [ -f system/core/mkbootimg/Android.bp ]; then
    echo ">> mkbootimg (system/core/mkbootimg) 已就位"
else
    echo "!! 缺 system/core/mkbootimg，打包 recovery.img 会失败"
fi

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
    # 内核 fragment 默认不追加。原因：LineageOS 的 sagit_defconfig 已经包含了
    # wcnss/qca_cld 相关选项，硬塞 CONFIG_WCNSS_CORE=y 会让
    # drivers/net/wireless/wcnss/wcnss_wlan.c 走一条该内核版本里并不存在的
    # 调试路径，编译报：
    #   implicit declaration of function 'wcnss_get_mux_control' [-Werror]
    # WiFi 本来也不依赖它：模块在 /vendor/lib/modules，由运行时脚本 insmod。
    # 需要试验性选项时再打开：KERNEL_FRAGMENT=true
    # 片段选择：false=不追加 / debug=只加 WiFi 调试 / drm=换 DRM 显示栈 / wifi=旧址
    case "${KERNEL_FRAGMENT:-false}" in
        false|"")
            echo ">> 跳过内核 fragment（沿用 vendor defconfig）"
            ;;
        debug)
            FRAG="${GITHUB_WORKSPACE:-$PWD}/kernel/sagit-debug.fragment"
            echo ">> 追加 WiFi 调试片段：$FRAG"
            cat "$FRAG" >> "$DEFCONFIG"
            ;;
        drm)
            FRAG="${GITHUB_WORKSPACE:-$PWD}/kernel/sagit-drm.fragment"
            echo ">> 追加 DRM 片段：$FRAG"
            cat "$FRAG" >> "$DEFCONFIG"
            ;;
        *)
            FRAG="${GITHUB_WORKSPACE:-$PWD}/kernel/sagit-${KERNEL_FRAGMENT}.fragment"
            echo ">> 追加片段：$FRAG"
            [ -f "$FRAG" ] && cat "$FRAG" >> "$DEFCONFIG"
            ;;
    esac
    if [ "$KERNEL_CLANG" = "true" ]; then
        echo 'TARGET_KERNEL_CLANG_COMPILE := true' >> device/xiaomi/sagit/BoardConfig.mk
    fi

    # gcc 10+ 默认 -fno-common，而 4.4 内核的 dtc 依赖 tentative definition：
    # dtc-lexer.lex.o 与 dtc-parser.tab.o 都定义 yylloc，链接时报
    #   multiple definition of `yylloc'; ... first defined here
    # 给这两个目标加回 -fcommon 即可（内核 4.x 在 GCC 10+ 上的经典补丁）。
    DTC_MK=kernel/xiaomi/msm8998/scripts/dtc/Makefile
    if [ -f "$DTC_MK" ] && ! grep -q 'fcommon' "$DTC_MK"; then
        echo ">> 给 dtc 打 -fcommon 补丁（GCC 10+ 环境）"
        {
            echo ''
            echo '# added by CI: GCC 10+ 默认 -fno-common，dtc 的 yylloc 需要 tentative definition'
            echo 'HOSTCFLAGS_dtc-lexer.lex.o += -fcommon'
            echo 'HOSTCFLAGS_dtc-parser.tab.o += -fcommon'
            echo 'HOSTCFLAGS_dtc.o += -fcommon'
            echo 'HOSTCFLAGS_flattree.o += -fcommon'
            echo 'HOSTCFLAGS_fstree.o += -fcommon'
            echo 'HOSTCFLAGS_data.o += -fcommon'
            echo 'HOSTCFLAGS_livetree.o += -fcommon'
            echo 'HOSTCFLAGS_treesource.o += -fcommon'
            echo 'HOSTCFLAGS_srcpos.o += -fcommon'
            echo 'HOSTCFLAGS_checks.o += -fcommon'
            echo 'HOSTCFLAGS_util.o += -fcommon'
        } >> "$DTC_MK"
    fi
else
    # prebuilt 模式：有直链就用直链，没有就自动从官方 TWRP 镜像里抽内核
    if [ -n "${PREBUILT_KERNEL_URL:-}" ]; then
        echo ">> 下载预编译内核：$PREBUILT_KERNEL_URL"
        curl -fL --retry 3 --max-time 600 -o kernel/Image.gz-dtb "$PREBUILT_KERNEL_URL"
    else
        echo ">> 未提供直链：先试官方 TWRP，失败则从 LineageOS 官方 ROM 抽内核"
        OUTDIR="$AOSP_DIR/kernel-prebuilt" \
            bash "${GITHUB_WORKSPACE:-$PWD}/scripts/ci/fetch-prebuilt-kernel.sh" "$AOSP_DIR" \
        || {
            echo ">> TWRP 源不可用，切换到 LineageOS nightlies"
            OUTDIR="$AOSP_DIR/kernel-los" \
                bash "${GITHUB_WORKSPACE:-$PWD}/scripts/ci/fetch-kernel-from-los.sh" "$AOSP_DIR/kernel-los"
            cp "$AOSP_DIR/kernel-los/Image.gz-dtb" "$AOSP_DIR/kernel-prebuilt/Image.gz-dtb"
        }
        cp "$AOSP_DIR/kernel-prebuilt/Image.gz-dtb" kernel/Image.gz-dtb
    fi
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

# envsetup.sh / vendor/omni/vendorsetup.sh 里有未定义变量（实测 `version`），
# 本脚本开着 set -u 会直接 "version: unbound variable" 退出。
# source 与 mka 期间统一关掉 nounset。
set +u
source build/envsetup.sh
lunch skyward_sagit-eng || { echo "!! lunch 失败：检查 AndroidProducts.mk / 缺模块"; exit 1; }

# ---------------------------------------------------------------------------
# 内核 clang 自愈：TWRP 最小树里 prebuilts/clang/host/linux-x86/clang-stable
# 这个软链可能不存在（或指向未同步的版本），内核对源码编译时会用它当 CC，
# 于是报 "clang-stable/bin/clang: No such file" 并连带
# "Cannot use CONFIG_CC_STACKPROTECTOR_STRONG"（其实是编译器根本没跑起来）。
# 这里挑一个真实存在且可执行的 clang-* 版本建软链。
# ---------------------------------------------------------------------------
CLDIR=prebuilts/clang/host/linux-x86
if [ -d "$CLDIR" ]; then
    if [ ! -x "$CLDIR/clang-stable/bin/clang" ]; then
        echo ">> clang-stable 不可用，挑选可用版本建软链"
        # clang-stable 可能是：不存在的软链 / 指向缺失版本的断链 / 一个空目录。
        # `ln -sfn` 在目标是目录时会往目录里面建链接（等于没修），所以先删干净。
        rm -rf "$CLDIR/clang-stable"
        for v in $(ls -d "$CLDIR"/clang-r* "$CLDIR"/clang-[0-9]* 2>/dev/null | sort -V -r); do
            if [ -x "$v/bin/clang" ]; then
                ln -sfn "$(basename "$v")" "$CLDIR/clang-stable"
                echo ">> clang-stable -> $(basename "$v")"
                break
            fi
        done
    fi
    echo "--- 可用 clang ---"
    ls -d "$CLDIR"/clang-* 2>/dev/null | head -8
    if [ -x "$CLDIR/clang-stable/bin/clang" ]; then
        echo ">> clang-stable 可执行：$("$CLDIR/clang-stable/bin/clang" --version 2>/dev/null | head -1)"
    else
        echo "!! 仍无可用 clang-stable（本次若不设 kernel_clang=true 则不影响）"
    fi
fi

# 编译前先验一次 host 预编译 clang 能不能跑（缺 libtinfo.so.5 时在这里就报清楚，
# 不用等到 40 秒后 ninja 报一个含糊的 FAILED）
PRECLANG=$(ls -d prebuilts/clang/host/linux-x86/clang-*/bin/clang 2>/dev/null | head -1)
if [ -n "$PRECLANG" ]; then
    if "$PRECLANG" --version >/dev/null 2>&1; then
        echo ">> host clang OK: $PRECLANG ($("$PRECLANG" --version 2>/dev/null | head -1))"
    else
        echo "!! host clang 无法运行：$PRECLANG"
        ldd "$PRECLANG" 2>/dev/null | grep -E 'not found' || true
        echo "   典型原因：缺 libtinfo.so.5（ncurses5），见 scripts/ci/install-deps.sh"
    fi
fi

step "5. 编译 recoveryimage（首次约 50-70 分钟）"
# 注意：mka 是 envsetup.sh 定义的 shell 函数，不能用 `/usr/bin/time` 包装
# （会报 "cannot run mka: No such file or directory"）。整段输出落盘，失败可查。
set -o pipefail
if ! mka -j"$JOBS" recoveryimage > >(tee /tmp/mka.log) 2>&1; then
    echo "!! 构建失败，日志尾部："
    tail -60 /tmp/mka.log
fi
tail -15 /tmp/mka.log
set -u
IMG=out/target/product/sagit/recovery.img
[ -f "$IMG" ] || {
    echo "!! 没有产出 $IMG"
    ls -l out/target/product/sagit/ 2>/dev/null | tail -20
    mkdir -p "$ARTIFACT_DIR"
    cp /tmp/mka.log "$ARTIFACT_DIR/mka.log" 2>/dev/null
    exit 1
}

step "6. 产物"
mkdir -p "$ARTIFACT_DIR"
cp "$IMG" "$ARTIFACT_DIR/recovery.img"
cp /tmp/mka.log "$ARTIFACT_DIR/mka.log" 2>/dev/null || true
ls -lh "$ARTIFACT_DIR"
echo ">> 完成：$ARTIFACT_DIR/recovery.img"
