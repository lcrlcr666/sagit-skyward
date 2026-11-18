#
# device.mk — sagit 产品公共部分（Skyward Recovery）
#
# 重要：recovery-only 树（minimal-manifest-twrp twrp-9.0）里没有完整 AOSP 的包，
# 下列「安全清单」都是 TWRP 树里确实存在的模块。凡是不存在的包会在 lunch 阶段
# 报 "module not found"，所以可选项一律先注释，按需打开。
#
LOCAL_PATH := device/xiaomi/sagit

# ---------------------------------------------------------------- 安全清单（必有）
PRODUCT_PACKAGES += \
    libcrypto \
    libssl \
    tune2fs \
    e2fsdroid \
    mke2fs \
    fsck.f2fs \
    tar \
    toybox \
    unzip \
    zip

# ---------------------------------------------------------------- Wi-Fi 用户态
PRODUCT_PACKAGES += \
    libwpa_client \
    wpa_supplicant \
    wpa_supplicant.conf \
    wpa_cli \
    dhcpcd

# ---------------------------------------------------------------- 可选（按树里是否存在打开）
# 注意：wificond / hostapd / dnsmasq / curl / ip / ifconfig / ntfs-3g / exfatprogs
# 在 TWRP 最小树里不一定有。缺哪个就删哪行，或者改用外部预编译二进制
# （放进 device/xiaomi/sagit/prebuilt/bin 并加 Android.mk，见 §5）。
# PRODUCT_PACKAGES += \
#     hostapd \
#     dnsmasq \
#     curl \
#     ip \
#     ifconfig \
#     libnl \
#     p7zip \
#     dosfstools \
#     sgdisk \
#     vim

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