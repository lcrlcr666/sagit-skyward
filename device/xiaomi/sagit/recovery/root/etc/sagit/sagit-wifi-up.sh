#!/system/bin/sh
# sagit-wifi-up.sh — 小米6 (sagit / msm8998 + QCA6174A/WCN3990) recovery 内 WiFi 修复
# 修复点：
#   1. /persist/wlan_mac.bin 缺失或全 0/全 FF → 从设备序列号派生并写回（否则驱动加载即失败）
#   2. WCNSS_qcom_cfg.ini 丢失 → 用 ramdisk 内置 /etc/WCNSS_qcom_cfg.ini 覆盖到 vendor
#   3. cnss2 / qca_cld3_wlan 模块路径与参数不对 → 按 vendor 实际文件名加载
#   4. wlan0 无 IP → wpa_supplicant + dhcpcd 兜底
# 日志：/tmp/sagit-wifi.log，同时 dmesg 过滤 wlan 关键行

LOG=/tmp/sagit-wifi.log
FW=/vendor/firmware
CFG=$FW/wlan/qca_cld/WCNSS_qcom_cfg.ini
PERSIST=/persist
MACFILE=$PERSIST/wlan_mac.bin
MODDIR=/vendor/lib/modules

mkdir -p /tmp
exec >>$LOG 2>&1
echo "=== sagit-wifi-up $(date) ==="

log() { echo "[wifi] $*"; }

# ---------------------------------------------------------------- 0. 等分区就绪
i=0
while [ ! -e /dev/block/bootdevice/by-name/userdata ] && [ $i -lt 10 ]; do
    i=$((i+1)); sleep 1
done

# TWRP 的 toybox 不一定带 mountpoint，用 /proc/mounts 自己判断
ismounted() { grep -q " $1 " /proc/mounts; }

ismounted /persist || mount -t ext4 -o rw,nosuid,nodev /dev/block/bootdevice/by-name/persist /persist
ismounted /vendor  || mount -t ext4 -o ro /dev/block/bootdevice/by-name/vendor /vendor
ismounted /vendor/firmware_mnt || \
    mount -t vfat -o ro /dev/block/bootdevice/by-name/modem /vendor/firmware_mnt

# 部分版本固件放在 modem 分区（firmware_mnt/image）而不是 vendor
if [ ! -f "$FW/bdwlan30.bin" ] && [ -f /vendor/firmware_mnt/image/bdwlan30.bin ]; then
    mkdir -p $FW
    for f in bdwlan30.bin qwlan30.bin otp30.bin qca_cld3_wlan.ko; do
        [ -f /vendor/firmware_mnt/image/$f ] && cp -f /vendor/firmware_mnt/image/$f $FW/ 2>/dev/null
    done
fi

# ---------------------------------------------------------------- 1. MAC 修复
hexbyte() { printf '%02x' "$1"; }

rand_mac() {
    # 从 SoC 序列号派生：稳定、本地管理位置 1
    sn=$(cat /sys/devices/soc0/serial_number 2>/dev/null)
    [ -z "$sn" ] && sn=$(getprop ro.serialno)
    [ -z "$sn" ] && sn="sagit-fallback"
    h=$(echo "$sn" | md5sum | cut -c1-12)
    b0=$((0x$(echo $h | cut -c1-2) & 0xfc | 0x02))   # local + unicast
    echo "$(hexbyte $b0):$(echo $h | cut -c3-4):$(echo $h | cut -c5-6):$(echo $h | cut -c7-8):$(echo $h | cut -c9-10):$(echo $h | cut -c11-12)"
}

mac_valid() {
    [ -f "$MACFILE" ] || return 1
    [ "$(stat -c %s "$MACFILE" 2>/dev/null)" -ge 6 ] || return 1
    m=$(od -An -tx1 -N6 "$MACFILE" | tr -d ' \n')
    case "$m" in
        000000000000|ffffffffffff) return 1 ;;
    esac
    [ "${m:0:2}" = "00" ] && return 1     # 00:xx 大概率未烧录
    return 0
}

if ! mac_valid; then
    NEW=$(rand_mac)
    log "MAC 无效/缺失，写入派生值 $NEW"
    o1=$(printf '%d' 0x$(echo $NEW | cut -d: -f1)); o2=$(printf '%d' 0x$(echo $NEW | cut -d: -f2))
    o3=$(printf '%d' 0x$(echo $NEW | cut -d: -f3)); o4=$(printf '%d' 0x$(echo $NEW | cut -d: -f4))
    o5=$(printf '%d' 0x$(echo $NEW | cut -d: -f5)); o6=$(printf '%d' 0x$(echo $NEW | cut -d: -f6))
    p6=$(( (o6 + 1) % 256 ))
    # wlan_mac.bin 结构：6 字节 wlan0 MAC + 6 字节 p2p MAC
    printf "\\x$(hexbyte $o1)\\x$(hexbyte $o2)\\x$(hexbyte $o3)\\x$(hexbyte $o4)\\x$(hexbyte $o5)\\x$(hexbyte $o6)" >  $MACFILE.tmp
    printf "\\x$(hexbyte $o1)\\x$(hexbyte $o2)\\x$(hexbyte $o3)\\x$(hexbyte $o4)\\x$(hexbyte $o5)\\x$(hexbyte $p6)" >> $MACFILE.tmp
    mv -f $MACFILE.tmp $MACFILE
    chmod 644 $MACFILE
    sync
else
    log "MAC 正常：$(od -An -tx1 -N6 "$MACFILE" | tr -d ' \n' | sed 's/../&:/g;s/:$//')"
fi

# ---------------------------------------------------------------- 2. 配置文件
mkdir -p $FW/wlan/qca_cld
if [ ! -s "$CFG" ]; then
    log "WCNSS_qcom_cfg.ini 缺失，用 ramdisk 内置版本"
    cp -f /etc/WCNSS_qcom_cfg.ini $CFG 2>/dev/null || \
      cp -f /etc/WCNSS_qcom_cfg.ini $CFG 2>/dev/null
fi
# 强制本机 MAC（部分固件不读 persist，只读 ini）
if [ -s "$CFG" ]; then
    MACSTR=$(od -An -tx1 -N6 "$MACFILE" | tr -d ' \n' | sed 's/../&:/g;s/:$//')
    sed -i '/^Intf0MacAddress=/d;/^gSetMacAddr=/d' $CFG
    echo "Intf0MacAddress=$MACSTR" >> $CFG
fi

# ---------------------------------------------------------------- 3. 载入驱动
if lsmod | grep -q qca_cld3_wlan; then
    log "qca_cld3_wlan 已加载"
else
    if [ -f $MODDIR/qca_cld3_wlan.ko ]; then
        MOD=$MODDIR/qca_cld3_wlan.ko
    elif [ -f $MODDIR/qca_cld_wlan.ko ]; then
        MOD=$MODDIR/qca_cld_wlan.ko
    else
        MOD=$(find /vendor/lib/modules /system/lib/modules -name '*wlan*.ko' 2>/dev/null | head -1)
    fi

    # cnss2 先于 wlan（WCN3990 走 PCIe，缺少 cnss2 会报 probe failed -2）
    for m in cnss2 cnss; do
        [ -f $MODDIR/$m.ko ] && ! lsmod | grep -q "^$m" && insmod $MODDIR/$m.ko && log "insmod $m ok"
    done

    if [ -n "$MOD" ] && [ -f "$MOD" ]; then
        insmod "$MOD" con_mode=0 && log "insmod $(basename $MOD) ok"
    else
        log "!! 找不到 wlan 模块，尝试内建驱动路径"
        echo 1 > /sys/module/qca_cld3_wlan/parameters/con_mode 2>/dev/null
    fi
fi

# ---------------------------------------------------------------- 4. 拉起接口
setprop wlan.driver.status ok
for n in 1 2 3 4 5 6 7 8 9 10; do
    ip link show wlan0 >/dev/null 2>&1 && break
    sleep 1
done
ip link set wlan0 up 2>/dev/null
echo 0 > /sys/module/wlan/parameters/con_mode 2>/dev/null

# firmware 是否真的下载成功（关键判据）
dmesg | grep -iE 'wlan.*(fw|firmware).*(fail|timeout)|cnss.*(fail|error)' | tail -5

# ---------------------------------------------------------------- 5. 连接（可选）
if [ -f /etc/wpa_supplicant.conf ] && grep -q 'ssid=' /etc/wpa_supplicant.conf 2>/dev/null; then
    pkill wpa_supplicant 2>/dev/null
    wpa_supplicant -B -i wlan0 -Dnl80211 -c /etc/wpa_supplicant.conf -f /tmp/wpa.log
    sleep 6
    dhcpcd -b -t 15 wlan0 2>/dev/null || udhcpc -i wlan0 -n -q -t 8 2>/dev/null
fi

ip -4 addr show wlan0 2>/dev/null | grep -q 'inet ' && log "WiFi OK: $(ip -4 addr show wlan0 | awk '/inet /{print $2}')" || log "WiFi 未拿到 IP（驱动在但未关联）"
echo "=== done ==="
