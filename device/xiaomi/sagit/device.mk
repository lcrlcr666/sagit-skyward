#
# device.mk — sagit 产品公共部分（Skyward Recovery）
#
# 重要：recovery-only 树（minimal-manifest-twrp twrp-9.0）里没有完整 AOSP 的包，
# 下列「安全清单」都是 TWRP 树里确实存在的模块。凡是不存在的包会在 lunch 阶段
# 报 "module not found"，所以可选项一律先注释，按需打开。
#
LOCAL_PATH := device/xiaomi/sagit

# ---------------------------------------------------------------- 安全清单（必有）
# 教训：minimal-manifest（twrp-9.0）是 Android 9.0.0_r47 的裁剪树，
# `unzip` / `zip` / `tar` / `libwpa_client` / `wpa_cli` / `wpa_supplicant.conf`
# 这些「看起来该有」的模块名在树里并不存在，写进 PRODUCT_PACKAGES 会在 lunch
# 阶段直接报 "module not found" 而中断。TWRP 镜像本身已经带了 toybox / mke2fs /
# f2fs-tools / unzip，所以这里只声明 recovery 里确实需要、且确认存在的模块：
PRODUCT_PACKAGES += \
    wpa_supplicant \
    dhcpcd

# ---------------------------------------------------------------- 可选（按树里是否存在打开）
# 已核对 manifest：external/wpa_supplicant_8、external/dhcpcd-6.8.2、
# external/curl、external/dnsmasq、external/libnl、external/toybox、
# external/e2fsprogs、external/f2fs-tools、external/squashfs-tools 都在；
# external/hostapd 不在（所以 hostapd 永远别打开）。
# PRODUCT_PACKAGES += \
#     curl \
#     dnsmasq \
#     libnl \
#     squashfs-tools

# 若树里有 curl 才打开（romget.sh 优先用 curl，没有则退 wget / busybox wget）
# TWRP 最小 manifest 不一定带了 external/curl，开了会报 "module curl not found"
# PRODUCT_PACKAGES += curl

# ---------------------------------------------------------------- recovery ramdisk 覆盖
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/root/init.recovery.qcom.rc:recovery/root/init.recovery.qcom.rc \
    $(LOCAL_PATH)/root/sbin/sagit-wifi-up.sh:recovery/root/sbin/sagit-wifi-up.sh \
    $(LOCAL_PATH)/root/sbin/sagit-wifi-down.sh:recovery/root/sbin/sagit-wifi-down.sh \
    $(LOCAL_PATH)/root/sbin/sagit-wifi-daemon.sh:recovery/root/sbin/sagit-wifi-daemon.sh \
    $(LOCAL_PATH)/root/sbin/romget.sh:recovery/root/sbin/romget.sh \
    $(LOCAL_PATH)/root/sbin/linux-boot.sh:recovery/root/sbin/linux-boot.sh \
    $(LOCAL_PATH)/root/etc/wpa_supplicant.conf:recovery/root/etc/wpa_supplicant.conf \
    $(LOCAL_PATH)/root/etc/WCNSS_qcom_cfg.ini:recovery/root/etc/WCNSS_qcom_cfg.ini

# ---------------------------------------------------------------- 固件（可选，体积大）
# 不建议塞进 ramdisk（sagit recovery 分区 ~64MB）。cns2 会直接读已挂载的
# /vendor/firmware；只有在你连 /vendor 都不想挂的时候才用 prebuilt 方式：
# include $(LOCAL_PATH)/prebuilt/Android.mk

# ---------------------------------------------------------------- 属性
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware=qcom \
    ro.board.platform=msm8998 \
    wifi.interface=wlan0 \
    wifi.direct.interface=p2p0 \
    ro.vendor.wlan.fw.path=/vendor/firmware