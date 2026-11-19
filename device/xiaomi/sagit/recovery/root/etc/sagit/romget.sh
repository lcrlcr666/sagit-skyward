#!/system/bin/sh
# romget.sh — recovery 内无图形界面也能下载 ROM / 固件 / 二级系统镜像
# 用法：
#   romget.sh <url> [目标目录]        # 默认 /sdcard/Download
#   romget.sh -l <url>                # 只看大小/支持断点情况
#   romget.sh -c <url> <sha256>       # 下载并校验
# 特性：断点续传、失败重试、WiFi 守护、下载完自动校验 zip 完整性

set -u
DL_DIR=/sdcard/Download
[ $# -ge 1 ] || { echo "usage: romget.sh <url> [dir]"; exit 1; }

case "$1" in
    -l)
        if command -v curl >/dev/null 2>&1; then
            curl -sIL "$2" | tr -d '\r' | grep -iE '^(HTTP/|content-length|location)'
        else
            wget --spider -S "$2" 2>&1 | grep -iE 'HTTP/|Length' | head -10
        fi
        exit 0 ;;
    -c) URL="$2"; WANT="$3" ;;
    *)  URL="$1"; WANT="" ;;
esac
[ $# -ge 2 ] && [ "$1" != "-c" ] && DL_DIR="$2"

mkdir -p "$DL_DIR"
OUT="$DL_DIR/$(basename "${URL%%\?*}")"

# 确保联网（WiFi 未起则先修）
if ! ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '; then
    echo "[romget] wlan0 无 IP，先执行 sagit-wifi-up.sh"
    /system/bin/sh /etc/sagit/sagit-wifi-up.sh
fi

echo "[romget] -> $OUT"

# 下载器优先级：curl（最全，能续传+限速）> wget > busybox wget
DL=""
command -v curl >/dev/null 2>&1 && DL=curl
[ -z "$DL" ] && command -v wget >/dev/null 2>&1 && DL=wget
[ -z "$DL" ] && busybox wget --help >/dev/null 2>&1 && DL=busybox
[ -z "$DL" ] && { echo "[romget] 没有 curl/wget，先 busybox 装一个或改用浏览器首页下载"; exit 4; }
echo "[romget] 使用 $DL"

n=0
while [ $n -lt 5 ]; do
    n=$((n+1))
    case "$DL" in
      curl)
        curl -L --fail --retry 3 --retry-delay 5 --retry-all-errors \
             -C - --connect-timeout 20 --speed-time 60 --speed-limit 1024 \
             -o "$OUT" "$URL" && break ;;
      wget)
        wget -c -T 20 -t 2 -O "$OUT" "$URL" && break ;;
      busybox)
        busybox wget -c -T 20 -O "$OUT" "$URL" && break ;;
    esac
    echo "[romget] 第 $n 次失败，5s 后重试"
    sleep 5
    /system/bin/sh /etc/sagit/sagit-wifi-up.sh
done
[ $n -ge 5 ] && { echo "[romget] 放弃"; exit 2; }

SIZE=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
echo "[romget] 完成，$SIZE 字节"

if [ -n "$WANT" ]; then
    GOT=$(sha256sum "$OUT" | cut -d' ' -f1)
    [ "$GOT" = "$WANT" ] && echo "[romget] sha256 OK" || { echo "[romget] sha256 不匹配: $GOT"; exit 3; }
fi

case "$OUT" in
    *.zip) unzip -tq "$OUT" >/dev/null 2>&1 && echo "[romget] zip 完整" || echo "[romget] !! zip 损坏，删除后可重下" ;;
esac
exit 0
