#
# skyward_sagit.mk — 产品定义
#
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/embedded.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_full.mk)
$(call inherit-product, $(LOCAL_PATH)/device.mk)

PRODUCT_DEVICE := sagit
PRODUCT_NAME := skyward_sagit
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := MI 6
PRODUCT_MANUFACTURER := Xiaomi

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
TARGET_VENDOR := xiaomi

# recovery 里想同时带一份 "第二阶段 Linux" 引导器（可选，约 3MB）
# PRODUCT_PACKAGES += sagit-linux-launcher
