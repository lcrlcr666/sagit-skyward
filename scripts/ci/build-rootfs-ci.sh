#!/usr/bin/env bash
# build-rootfs-ci.sh — CI 里生成浏览器内核镜像（需要 root）
set -euo pipefail

SIZE_MB="${SIZE_MB:-2560}"
WS="${GITHUB_WORKSPACE:-$PWD}"
export SIZE_MB
export ROOT="$WS/build/rootfs"
export IMG="$WS/out/rootfs-sagit.img"

echo "== 生成 ${SIZE_MB}MB ext4 镜像 =="
df -h / | tail -1
bash "$WS/browser/stage2/build-rootfs.sh"

ls -lh "$IMG"
# 抽检：镜像里必须有 chromium 和 fbdev 驱动
mkdir -p /tmp/inspect && mount -o loop,ro "$IMG" /tmp/inspect
for f in usr/bin/chromium usr/lib/xorg/modules/drivers/fbdev_drv.so usr/local/bin/kiosk.sh; do
    if [ -e "/tmp/inspect/$f" ]; then echo "  ✔ $f"; else echo "  ✘ 缺 $f"; fi
done
umount /tmp/inspect
chown -R "$(id -u):$(id -g)" "$WS/out" 2>/dev/null || true
echo "== OK =="
