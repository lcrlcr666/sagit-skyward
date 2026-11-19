#!/usr/bin/env bash
# fetch-kernel-from-los.sh — 从 LineageOS 官方 ROM 包里抽 sagit 内核
#
# 为什么用这个源：
#   twrp.me 的下载链接对非浏览器请求返回 HTML 下载页（实测 6.8KB），
#   而 LineageOS 的 mirrorbits 给的是真直链，且 sagit 至今仍在出 nightly
#   （lineage-22.2-…-nightly-sagit-signed.zip 里就是 4.4 内核的 boot.img）。
#
# 用法：  ./fetch-kernel-from-los.sh [输出目录]
# 产出：  <out>/Image.gz-dtb
set -euo pipefail
trap 'rc=$?; echo "!! 失败于第 $LINENO 行 (rc=$rc): $BASH_COMMAND" >&2' ERR

OUTDIR="${1:-${OUTDIR:-$PWD/kernel-prebuilt}}"
mkdir -p "$OUTDIR"

API="https://download.lineageos.org/api/v2/devices/sagit/builds"
echo ">> 查询 LineageOS 最新 sagit 构建"
curl -fsSL --retry 3 --max-time 60 -o "$OUTDIR/los-builds.json" "$API"

read -r ZIPNAME ZIPURL < <(python3 - "$OUTDIR/los-builds.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for b in d:                       # 已按时间倒序
    for f in b.get("files", []):
        fn = f.get("filename", "")
        if fn.endswith(".zip") and "sagit" in fn:
            print(fn, "https://download.lineageos.org" + f["filepath"])
            raise SystemExit
raise SystemExit(1)
PY
) || { echo "!! 解析 API 失败（sagit 可能已 EOL）"; exit 1; }

echo ">> 最新包：$ZIPNAME"
echo ">> 直链：$ZIPURL"

ZIP="$OUTDIR/$ZIPNAME"
if [ ! -s "$ZIP" ]; then
    echo ">> 下载（约 1GB，GHA 上通常 30-60 秒）"
    curl -fL --retry 3 --retry-delay 5 --max-time 1800 -C - -o "$ZIP" "$ZIPURL"
else
    echo ">> 已有本地副本，跳过下载"
fi
ls -lh "$ZIP"

echo ">> 从 zip 里取 boot.img"
rm -rf "$OUTDIR/boot"; mkdir -p "$OUTDIR/boot"
unzip -o -j "$ZIP" 'boot.img' -d "$OUTDIR/boot" || {
    echo "!! zip 里没有 boot.img，列出前 40 项供排查："
    unzip -l "$ZIP" | head -40
    exit 1
}
ls -lh "$OUTDIR/boot/boot.img"

UNPACK="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/ci/unpack_bootimg_v0.py"
echo ">> 解包 boot.img：$UNPACK"
rm -rf "$OUTDIR/unpacked"; mkdir -p "$OUTDIR/unpacked"
python3 "$UNPACK" --boot_img "$OUTDIR/boot/boot.img" --out "$OUTDIR/unpacked"

[ -s "$OUTDIR/unpacked/kernel" ] || { echo "!! 没抽到 kernel"; exit 1; }
cp "$OUTDIR/unpacked/kernel" "$OUTDIR/Image.gz-dtb"
ls -lh "$OUTDIR/Image.gz-dtb"

if gzip -t "$OUTDIR/Image.gz-dtb" 2>/dev/null; then
    echo ">> Image.gz-dtb 有效（gzip 校验通过）"
else
    echo ">> 提示：不是 gzip 流（LOS 可能发未压缩 Image），大小 $(stat -c %s "$OUTDIR/Image.gz-dtb") 字节"
fi
echo "TARGET_PREBUILT_KERNEL=$OUTDIR/Image.gz-dtb"
