#!/usr/bin/env bash
# build-rootfs.sh — 为 Mi6 生成「第二阶段 Linux + Chromium 浏览器内核」镜像
# 宿主要求：Ubuntu 20.04+ / WSL2，root，bzip2、curl、qemu-user-static、e2fsprogs
#   sudo apt install -y binfmt-support qemu-user-static e2fsprogs curl bzip2
# 产物：out/rootfs-sagit.img（ext4，稀疏，默认 3.6G）+ out/linux-stage2.zip
#
# 为什么是这个方案：
#   recovery 是 minui 单 framebuffer 的 C 程序，塞不进浏览器；
#   正确做法是把浏览器跑在 recovery 内核之上的第二个用户空间里 ——
#   同一块 /dev/fb0，Xorg(fbdev) + Chromium kiosk，退出 kiosk 就回到 recovery 界面。
set -euo pipefail

VER=${ALPINE_VER:-3.19}
ARCH=aarch64
ROOT=${ROOT:-$PWD/build/rootfs}
IMG=${IMG:-$PWD/out/rootfs-sagit.img}
SIZE_MB=${SIZE_MB:-3686}
MIRROR=${MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
TARBALL=alpine-minirootfs-${VER}.0-${ARCH}.tar.gz

need() { command -v "$1" >/dev/null || { echo "缺 $1，请先 apt install"; exit 1; }; }
need curl; need tar; need mke2fs; need chroot
[ "$(id -u)" = 0 ] || { echo "请用 root 运行（chroot 需要）"; exit 1; }

if [ ! -f "build/$TARBALL" ]; then
    mkdir -p build
    echo ">> 下载 Alpine $VER rootfs"
    curl -fL --retry 3 -o "build/$TARBALL" \
      "$MIRROR/v$VER/releases/$ARCH/$TARBALL"
fi

echo ">> 展开到 $ROOT"
rm -rf "$ROOT"; mkdir -p "$ROOT"
tar -xzf "build/$TARBALL" -C "$ROOT"

# qemu 用户态 + binfmt，让 aarch64 程序在 x86 宿主上跑（apk 的 post-install 需要）
if [ -f /usr/bin/qemu-aarch64-static ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOT/usr/bin/"
    update-binfmts --enable qemu-aarch64 2>/dev/null || true
else
    echo "!! 无 qemu-aarch64-static：将以 --no-scripts 安装，部分 post-install 需手动补"
fi

cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
mkdir -p "$ROOT/etc/apk"
cat > "$ROOT/etc/apk/repositories" <<EOF
$MIRROR/v$VER/main
$MIRROR/v$VER/community
EOF

PKGS="
xorg-server xf86-video-fbdev xf86-input-evdev xf86-input-libinput xinput
matchbox-window-manager xset xrandr xinit
chromium chromium-chromedriver
font-noto font-noto-cjk font-noto-emoji ttf-dejavu
alsa-utils alsa-plugins pulseaudio pulseaudio-utils
busybox curl wget tzdata
mesa mesa-egl mesa-gles
"
echo ">> 安装用户空间（约 900MB 下载，慢）"
chroot "$ROOT" /sbin/apk add --no-cache --update $PKGS || {
    echo ">> 重试：跳过 post-install 脚本"
    chroot "$ROOT" /sbin/apk add --no-cache --no-scripts $PKGS
}

# ---------------------------------------------------------------- overlay
OVL="$(dirname "$0")/overlay"
if [ -d "$OVL" ]; then
    echo ">> 拷入 overlay"
    cp -a "$OVL/." "$ROOT/"
fi

# kiosk 用户与目录
chroot "$ROOT" /bin/sh -c '
    addgroup -g 1000 kiosk 2>/dev/null; adduser -D -u 1000 -G kiosk kiosk 2>/dev/null
    mkdir -p /home/kiosk/Downloads /home/kiosk/.config/chromium /srv/www/cgi-bin /var/log
    chown -R 1000:1000 /home/kiosk
    chmod +x /usr/local/bin/kiosk.sh /srv/www/cgi-bin/*.sh 2>/dev/null || true
'

# 首页 + CGI（浏览器里点按钮就能重启/读取下载目录）
cat > "$ROOT/srv/www/index.html" <<'HTML'
<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>sagit recovery browser</title>
<style>
 :root{color-scheme:dark}
 body{margin:0;font:15px/1.5 -apple-system,"Noto Sans CJK SC",sans-serif;background:#0b0f14;color:#e6edf3}
 header{padding:14px 16px;background:#111820;border-bottom:1px solid #223}
 h1{font-size:17px;margin:0}
 main{padding:12px 14px;display:grid;gap:10px;grid-template-columns:1fr 1fr}
 a.card,button.card{display:block;padding:14px;border-radius:12px;background:#151d26;
   border:1px solid #22303d;color:#e6edf3;text-decoration:none;font-weight:600}
 a.card small{display:block;font-weight:400;color:#8b9bab;margin-top:4px}
 .full{grid-column:1/-1}
</style>
<header><h1>Mi 6 · Skyward Recovery 浏览器</h1></header>
<main>
  <a class="card" href="https://cloud.genshin.mihoyo.com/">云·原神 网页版<small>需 Chrome ≥100，软解 720p30</small></a>
  <a class="card" href="https://cloud.starrail.mihoyo.com/">云·星穹铁道<small>同上</small></a>
  <a class="card full" href="https://download.lineageos.org/devices/sagit">LineageOS sagit 下载<small>ROM 会存到 Downloads</small></a>
  <a class="card" href="https://twrp.me/xiaomi/xiaomimi6.html">TWRP 官方镜像</a>
  <a class="card" href="http://127.0.0.1:8080/list">已下载文件</a>
  <button class="card full" onclick="fetch('/cgi-bin/reboot.sh').then(()=>document.body.innerHTML='<h2 style=padding:20px>重启中…</h2>')">重启到 Recovery</button>
</main>
HTML

cat > "$ROOT/srv/www/cgi-bin/reboot.sh" <<'SH'
#!/bin/sh
echo "Content-Type: text/plain"; echo
echo reboot-to-recovery
sleep 1
sync
reboot recovery 2>/dev/null || echo b > /proc/sysrq-trigger
SH

cat > "$ROOT/srv/www/cgi-bin/list.sh" <<'SH'
#!/bin/sh
echo "Content-Type: text/html; charset=utf-8"; echo
echo "<body style='background:#0b0f14;color:#e6edf3;font-family:monospace'>"
ls -lh /home/kiosk/Downloads 2>/dev/null | sed 's/$/<br>/'
echo "</body>"
SH
chmod +x "$ROOT/srv/www/cgi-bin/"*.sh

# 卸载 qemu，减小体积
rm -f "$ROOT/usr/bin/qemu-aarch64-static"

# ---------------------------------------------------------------- 打镜像
echo ">> 生成 ext4 镜像 $IMG (${SIZE_MB}MB，稀疏)"
mkdir -p "$(dirname "$IMG")"
rm -f "$IMG"
mke2fs -q -t ext4 -F -L linux-sagit -b 4096 -m 0 -d "$ROOT" "$IMG" "$((SIZE_MB*1024))"

echo ">> 打包可直刷 zip"
( cd "$(dirname "$IMG")" && \
  cp "$(basename "$IMG")" linux-rootfs.img && \
  zip -q -9 linux-stage2.zip linux-rootfs.img && rm -f linux-rootfs.img )

echo ">> 完成：$IMG"
echo ">> 推入设备：adb push $IMG /data/linux/rootfs.img   (recovery 内先建目录 /data/linux)"
