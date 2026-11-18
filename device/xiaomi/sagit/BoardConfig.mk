#
# BoardConfig.mk — Xiaomi Mi 6 (sagit / msm8998) for Skyward Recovery
# 平台：Qualcomm Snapdragon 835 (msm8998), A-only(无 A/B), 4.4 内核
#
DEVICE_PATH := device/xiaomi/sagit

# ---------------------------------------------------------------- 架构
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := kryo
TARGET_CPU_VARIANT_RUNTIME := kryo

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := kryo
TARGET_2ND_CPU_VARIANT_RUNTIME := kryo

TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_32_BIT_APPS := true
TARGET_SUPPORTS_64_BIT_APPS := true

# ---------------------------------------------------------------- 平台
TARGET_BOARD_PLATFORM := msm8998
TARGET_BOOTLOADER_BOARD_NAME := msm8998
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true

# ---------------------------------------------------------------- 内核
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 androidboot.console=ttyMSM0 \
    androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=a800000.dwc3 \
    msm_rtb.filter=0x237 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 \
    sched_enable_hmp=1 sched_enable_power_aware=1 service_locator.enable=1 \
    swiotlb=2048 loop.max_part=7 androidboot.selinux=permissive

BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_TAGS_OFFSET := 0x01E00000
BOARD_RAMDISK_OFFSET := 0x02000000
BOARD_KERNEL_SECOND_OFFSET := 0x00f00000
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_BOOTIMG_HEADER_VERSION := 0        # sagit 是 v0 头，勿加 dtbo/header v2
BOARD_MKBOOTIMG_ARGS := --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
                        --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
                        --second_offset $(BOARD_KERNEL_SECOND_OFFSET)

TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_SOURCE := kernel/xiaomi/msm8998
TARGET_KERNEL_CONFIG := sagit_defconfig
TARGET_KERNEL_CLANG_COMPILE := false
BOARD_KERNEL_SEPARATED_DT := false

# 内核模块 → recovery ramdisk 的 /vendor/lib/modules（WiFi 必需）
TW_LOAD_VENDOR_MODULES := "qca_cld3_wlan.ko cnss2.ko qca_cld3_*.ko"
BOARD_VENDOR_KERNEL_MODULES := \
    $(TARGET_OUT_VENDOR)/lib/modules

# ---------------------------------------------------------------- 分区
BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS := firmware persist
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SUPPRESS_SECURE_ERASE := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
TARGET_COPY_OUT_VENDOR := vendor
BOARD_PERSISTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_FLASH_BLOCK_SIZE := 131072

# ---------------------------------------------------------------- 显示 / 输入
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TARGET_RECOVERY_DEVICE_DIRS += $(DEVICE_PATH)
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
RECOVERY_SDCARD_ON_DATA := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_RECOVERY_SWIPE := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 4095
TW_DEFAULT_BRIGHTNESS := 2048
TW_SCREEN_BLANK_ON_BOOT := true
TW_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone39/temp"
TW_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true

# ---------------------------------------------------------------- TWRP / Skyward
TW_THEME := portrait_hdpi
TW_DEVICE_VERSION := Skyward-sagit-1.0
TW_EXTRA_LANGUAGES := true
TW_USE_TOOLBOX := true
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_EXCLUDE_TWRPAPP := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_HAS_DOWNLOAD_MODE := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_FUSE_NTFS := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_INCLUDE_PYTHON := false
TW_OZIP_DECRYPT_KEY := 0
TW_NO_BATT_PERCENT := false
TW_CUSTOM_BATTERY_PATH := "/sys/class/power_supply/battery"

# ---------------------------------------------------------------- Wi-Fi（QCA / WCN3990）
BOARD_HAS_QCOM_WLAN := true
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_WLAN_DEVICE := qcwcn
WIFI_DRIVER_MODULE_PATH := "/vendor/lib/modules/qca_cld3_wlan.ko"
WIFI_DRIVER_MODULE_NAME := "qca_cld3_wlan"
WIFI_DRIVER_MODULE_ARG := "con_mode=0"
WIFI_DRIVER_FW_PATH_STA := "/vendor/firmware"
WIFI_DRIVER_FW_PATH_AP := "/vendor/firmware"
WIFI_DRIVER_FW_PATH_P2P := "/vendor/firmware"
WIFI_HIDL_FEATURE_DUAL_INTERFACE := true

# ---------------------------------------------------------------- SELinux
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy
SEPOLICY_IGNORE_NEVERALLOW := true

# ---------------------------------------------------------------- 签名（Skyward 用自家 keys）
# PRODUCT_DEFAULT_DEV_CERTIFICATE := $(DEVICE_PATH)/security/releasekey
