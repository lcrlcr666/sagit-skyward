#!/usr/bin/env bash
# assemble-parts.sh — 大镜像分卷（split）/ 还原（join）
# GitHub artifact 单文件 >2G 会失败；本脚本把 img 切成 1200M 分卷并写校验和
set -euo pipefail

MODE="${1:-split}"
ART="${ARTIFACT_DIR:-${GITHUB_WORKSPACE:-$PWD}/artifacts}"
SRC="${2:-${GITHUB_WORKSPACE:-$PWD}/out/rootfs-sagit.img}"

case "$MODE" in
  split)
    mkdir -p "$ART"
    CHUNK=$((1200*1024*1024))
    split -b "$CHUNK" -d -a 2 "$SRC" "$ART/rootfs-sagit.img.part-"
    ( cd "$ART" && sha256sum rootfs-sagit.img.part-* > rootfs-sagit.sha256 )
    ls -lh "$ART"
    ;;
  join)
    OUT="${3:-rootfs.img}"
    cat "$SRC".part-* > "$OUT"
    sha256sum "$OUT"
    echo ">> 还原完成：$OUT"
    ;;
  *) echo "usage: $0 split|join [img/part 前缀] [输出]"; exit 1 ;;
esac
