#!/system/bin/sh
# sagit-wifi-daemon.sh — 断线自愈守护（screen 熄屏 / 长时间下载断流时有用）
# 每 20s 检查 wlan0 是否还有 IP，掉了就重来一遍 up 流程
while true; do
    if ! ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '; then
        echo "[wifid] $(date) wlan0 掉线，重试" >>/tmp/sagit-wifi.log
        /system/bin/sh /sbin/sagit-wifi-up.sh
    fi
    sleep 20
done
