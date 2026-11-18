#!/usr/bin/env bash
# fetch-prebuilt-kernel.sh — 从官方 TWRP 镜像里抽出内核（Image.gz-dtb）
#
# 为什么需要它：kernel_mode=source 要走内核对源码编译，AOSP 9 树 + 4.4 内核 +
# clang 的组合容易在工具链上翻车。官方 TWRP 的 recovery.img 里的内核本来就是
# 为 sagit / msm8998 / 4.4 编好的，直接拿来用最稳（也自带 fb/loop/evdev 等
# 我们第二阶段 Linux 需要的选项）。
#
# 用法：
#   ./fetch-prebuilt-kernel.sh [AOSP源码目录]
# 产出：
#   kernel-prebuilt/Image.gz-dtb   → 传给 TARGET_PREBUILT_KERNEL
set -euo pipefail
trap 'rc=$?; echo "!! 失败于第 $LINENO 行 (rc=$rc): $BASH_COMMAND" >&2' ERR

AOSP_DIR="${1:-${AOSP_DIR:-$PWD}}"
MODEL="${TWRP_MODEL:-twrp-3.7.0_9-0-sagit.img}"
URL="${TWRP_URL:-https://dl.twrp.me/sagit/$MODEL}"
OUTDIR="${OUTDIR:-$PWD/kernel-prebuilt}"

echo ">> AOSP 树：$AOSP_DIR"
echo ">> TWRP 镜像：$URL"
mkdir -p "$OUTDIR"

if [ ! -s "$OUTDIR/$MODEL" ]; then
    curl -fL --retry 3 --retry-delay 5 --max-time 600 -o "$OUTDIR/$MODEL.tmp" "$URL"
    mv "$OUTDIR/$MODEL.tmp" "$OUTDIR/$MODEL"
fi
ls -lh "$OUTDIR/$MODEL"
echo ">> sha256: $(sha256sum "$OUTDIR/$MODEL" | cut -d' ' -f1)"

UNPACK="$AOSP_DIR/system/tools/mkbootimg/unpack_bootimg.py"
[ -f "$UNPACK" ] || { echo "!! 找不到 $UNPACK（先 repo sync）"; exit 1; }

rm -rf "$OUTDIR/unpacked"; mkdir -p "$OUTDIR/unpacked"
# Pie 的 unpack_bootimg.py 参数：--boot_img / --out / --format=mkbootimg
if ! python3 "$UNPACK" --boot_img "$OUTDIR/$MODEL" --out "$OUTDIR/unpacked" --format=mkbootimg 2>"$OUTDIR/unpack.err"; then
    echo ">> --format 参数不被支持，退回旧用法"
    python3 "$UNPACK" --boot_img "$OUTDIR/$MODEL" --out "$OUTDIR/unpacked" 2>&1 | tail -20
fi
ls -lh "$OUTDIR/unpacked" 2>/dev/null || { cat "$OUTDIR/unpack.err"; exit 1; }

K="$OUTDIR/unpacked/kernel"
[ -s "$K" ] || { echo "!! 没抽到 kernel"; exit 1; }
cp "$K" "$OUTDIR/Image.gz-dtb"

# 自检：确认是 gzip 压缩的内核（sagit 是 Image.gz + 追加 dtb）
if gzip -t "$OUTDIR/Image.gz-dtb" 2>/dev/null; then
    echo ">> Image.gz-dtb 有效（gzip 校验通过）"
else
    echo ">> 提示：不是 gzip 流（可能是未压缩 Image 或含 dtb 偏移），大小：$(stat -c %s "$OUTDIR/Image.gz-dtb") 字节"
fi
echo "TARGET_PREBUILT_KERNEL=$OUTDIR/Image.gz-dtb"
