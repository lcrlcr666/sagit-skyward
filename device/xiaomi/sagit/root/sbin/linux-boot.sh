#!/system/bin/sh
# linux-boot.sh — 在 recovery 内启动 "第二阶段 Linux"（浏览器内核所在环境）
# 前置：/data/linux/rootfs.img（由 browser/stage2/build-rootfs.sh 产出并推入）
# 原理：recovery 内核已带 CONFIG_DRM_MSM + CONFIG_FB + EVDEV，
#       直接 chroot 进 Alpine rootfs，用 Xorg(fbdev) + Chromium kiosk 占屏。
# 退出：Ctrl+C 无效，只能长按电源键重启；或在 kiosk 里点 "Reboot" 链接（调用 reboot）

set -u
IMG=${1:-/data/linux/rootfs.img}
MNT=/linux
LOG=/tmp/linux-boot.log

exec >>$LOG 2>&1
echo "=== linux-boot $(date) img=$IMG ==="

[ -f "$IMG" ] || { echo "缺 $IMG"; exit 1; }

mountpoint -q /data || mount -t f2fs -o rw /dev/block/bootdevice/by-name/userdata /data

mkdir -p $MNT
mountpoint -q $MNT || mount -t ext4 -o loop,rw,noatime "$IMG" $MNT || { echo "loop 挂载失败"; exit 1; }

# 最小 chroot 骨架
for d in dev proc sys tmp run dev/pts dev/dri dev/input; do mkdir -p $MNT/$d; done
mountpoint -q $MNT/dev     || mount --bind /dev     $MNT/dev
mountpoint -q $MNT/proc    || mount -t proc  proc  $MNT/proc
mountpoint -q $MNT/sys     || mount -t sysfs sysfs $MNT/sys
mountpoint -q $MNT/tmp     || mount -t tmpfs tmpfs $MNT/tmp
mountpoint -q $MNT/dev/pts || mount --bind /dev/pts $MNT/dev/pts

# 屏幕/输入设备确认（没有 /dev/fb0 或 /dev/input/event* 就别浪费时间了）
[ -e /dev/fb0 ] || echo "警告：无 /dev/fb0，确认内核 CONFIG_FB + CONFIG_DRM_FBDEV_EMULATION=y"
ls /dev/input/event* >/dev/null 2>&1 || echo "警告：无 input event 节点，触摸/音量键不可用"

# 停掉 recovery 自己的 adbd 之外的服务，避免抢 framebuffer
setprop twrp.keep.screen.off 0 2>/dev/null

chroot $MNT /usr/local/bin/kiosk.sh
echo "=== kiosk 退出 rc=$? ==="
