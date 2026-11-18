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
mkdir -p "$OUTDIR"

# boot image 前 8 字节必须是 "ANDROID!"。twrp.me 对没有浏览器的请求会返回
# 下载页 HTML（实测 6.8KB 的页面），直接当 img 用会导致后续解包全部错乱。
is_bootimg() {
    [ -s "$1" ] || return 1
    [ "$(head -c 8 "$1" 2>/dev/null)" = "ANDROID!" ]
}

CANDIDATES="${TWRP_URLS:-https://dl.twrp.me/sagit/$MODEL https://eu.dl.twrp.me/sagit/$MODEL https://dl.twrp.me/sagit/$MODEL.html}"

if is_bootimg "$OUTDIR/$MODEL"; then
    echo ">> 已有本地镜像，跳过下载"
else
    for url in $CANDIDATES; do
        echo ">> 尝试下载：$url"
        rm -f "$OUTDIR/$MODEL" "$OUTDIR/$MODEL.tmp"
        if ! curl -fL --retry 2 --retry-delay 3 --max-time 600 \
                -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' \
                -o "$OUTDIR/$MODEL.tmp" "$url"; then
            echo "   下载失败"; continue
        fi
        if is_bootimg "$OUTDIR/$MODEL.tmp"; then
            mv "$OUTDIR/$MODEL.tmp" "$OUTDIR/$MODEL"
            echo "   OK（ANDROID! 校验通过）"
            break
        fi
        echo "   !! 不是 boot image，前 40 字节：$(head -c 40 "$OUTDIR/$MODEL.tmp" | tr -d '\0' | tr '\n' ' ')"
        echo "      大概率是 twrp.me 的下载页 HTML，需要直链镜像"
        rm -f "$OUTDIR/$MODEL.tmp"
    done
fi

is_bootimg "$OUTDIR/$MODEL" || {
    echo "!! 取不到可用的 TWRP 镜像。两条出路："
    echo "   ① 用 twrp_urls 输入指定一个真直链（如自建镜像/网盘直链）"
    echo "   ② 改用 kernel_mode=source（脚本会自动修 clang-stable 软链）"
    exit 1
}
ls -lh "$OUTDIR/$MODEL"
echo ">> sha256: $(sha256sum "$OUTDIR/$MODEL" | cut -d' ' -f1)"

UNPACK="$AOSP_DIR/system/tools/mkbootimg/unpack_bootimg.py"
[ -f "$UNPACK" ] || { echo "!! 找不到 $UNPACK（先 repo sync）"; exit 1; }

rm -rf "$OUTDIR/unpacked"; mkdir -p "$OUTDIR/unpacked"

# AOSP 9 的 unpack_bootimg.py 可能是 py2 语法，也可能 py3，逐个解释器试。
# （CI 里 `python` 已被我们指回 python2，所以三种都覆盖到）
try_unpack() {
    local py="$1"; shift
    command -v "$py" >/dev/null 2>&1 || return 1
    rm -rf "$OUTDIR/unpacked"; mkdir -p "$OUTDIR/unpacked"
    "$py" "$UNPACK" --boot_img "$OUTDIR/$MODEL" --out "$OUTDIR/unpacked" "$@" 2>"$OUTDIR/unpack.err"
}

ok=0
for py in python3 python2 python; do
    for extra in "--format=mkbootimg" ""; do
        # shellcheck disable=SC2086
        if try_unpack "$py" $extra && [ -s "$OUTDIR/unpacked/kernel" ]; then
            echo ">> 解包成功：$py $extra"
            ok=1; break 2
        fi
    done
done
if [ $ok -ne 1 ]; then
    echo "!! unpack_bootimg 全部尝试失败，最后一次错误："
    cat "$OUTDIR/unpack.err" 2>/dev/null | tail -15
    ls -lh "$OUTDIR/unpacked" 2>/dev/null
    exit 1
fi
ls -lh "$OUTDIR/unpacked"

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
