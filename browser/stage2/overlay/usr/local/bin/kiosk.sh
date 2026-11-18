#!/bin/sh
# kiosk.sh — 在 chroot 的 Alpine 里把整块屏幕交给 Chromium
# 由 recovery 的 /sbin/linux-boot.sh 调起；退出（崩溃或点“重启”）即回到 recovery
set -u
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/xdg
export HOME=/home/kiosk
export LANG=zh_CN.UTF-8
mkdir -p "$XDG_RUNTIME_DIR" /tmp/.X11-unix
chmod 700 "$XDG_RUNTIME_DIR"

# 时区 / 网络（沿用 recovery 的 wlan0，已有 IP）
[ -f /etc/localtime ] || cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null
printf 'nameserver 223.5.5.5\nnameserver 1.1.1.1\n' > /etc/resolv.conf

# 声音：ALSA 直出（云游戏必须有声才好玩）
[ -f /etc/asound.conf ] || cat > /etc/asound.conf <<'EOF'
pcm.!default { type hw; card 0 }
ctl.!default { type hw; card 0 }
EOF

# 本地 web 服务：给 kiosk 首页用（/srv/www，端口 8080）
busybox httpd -p 8080 -h /srv/www >/dev/null 2>&1
for i in 1 2 3 4 5; do
    wget -qO- http://127.0.0.1:8080/ >/dev/null 2>&1 && break
    sleep 1
done

# X：fbdev 驱动，直接吃 /dev/fb0；不切换 VT（recovery 只有一个屏）
Xorg :0 -ac -nolisten tcp -novtswitch -keeptty -br \
     -logfile /var/log/Xorg.0.log vt1 >/var/log/x.log 2>&1 &
XPID=$!
for i in $(seq 1 30); do
    [ -e /tmp/.X11-unix/X0 ] && break
    sleep 1
done

# 关屏保/DPMS，亮度拉满（Mi6 背光节点）
xset s off -dpms 2>/dev/null
echo 4095 > /sys/class/leds/lcd-backlight/brightness 2>/dev/null

# 触摸：evdev 自动识别；若坐标错乱，用 xinput 校准
xinput list 2>/dev/null | grep -i -E 'touch|synaptics' | head -3

# 窗口管理器：有 openbox 就用（kiosk 全屏其实不依赖 WM），没有就裸跑
if command -v openbox >/dev/null 2>&1; then
    openbox >/dev/null 2>&1 &
    sleep 1
elif command -v matchbox-window-manager >/dev/null 2>&1; then
    matchbox-window-manager -use_titlebar no >/dev/null 2>&1 &
    sleep 1
fi

CHROME_FLAGS="
 --no-sandbox --no-first-run --no-default-browser-check
 --disable-dev-shm-usage --disable-features=TranslateUI,MediaRouter
 --kiosk --start-fullscreen --disable-pinch --overscroll-history-navigation=0
 --user-data-dir=$HOME/.config/chromium
 --autoplay-policy=no-user-gesture-required
 --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader
 --ignore-gpu-blocklist --enable-webgl --enable-webgl2-compute-context
 --enable-features=WebRTCPipeWireCapturer,CanvasOopRasterization
 --enable-accelerated-video-decode=false
 --window-size=1080,1920
"

# 下载目录直接指到 sdcard，退出 kiosk 后 TWRP 里就能看到
mkdir -p /home/kiosk/Downloads
[ -e /sdcard ] && ln -sfn /sdcard/Download /home/kiosk/Downloads/sdcard 2>/dev/null

exec chromium $CHROME_FLAGS --app=http://127.0.0.1:8080/
