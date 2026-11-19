# Mi 6 (sagit) · Skyward Recovery 适配 + WiFi 修复 + 内置浏览器内核

一套可直接落地的工程化方案：设备树、WiFi 修复链路、浏览器内核（双阶段 Linux + Chromium）、
构建/刷入/验证脚本。全部内容在 `D:\AndroidBuilds\sagit-skyward\` 下。

---

## 0. 先把三条硬约束说清楚（决定方案形状）

| 需求 | 现实 | 本方案的解法 |
|---|---|---|
| 适配 Skyward Recovery | sagit 是 **A-only / msm8998 / v0 boot header**，官方 TWRP 树可复用 90% | 生成标准 `device/xiaomi/sagit` + `skyward_sagit` 产品，`recovery.img` 直接产出 |
| 修复 WiFi | recovery 没有 telephony/keystore，WiFi 挂掉的三个真因：①`/persist/wlan_mac.bin` 空或全 0 ②vendor 固件没带 ③`qca_cld3_wlan.ko` 路径/参数不对 | `sagit-wifi-up.sh` 逐项自愈 + `extract_firmware.sh` 从 MIUI 现取固件 |
| 内置浏览器内核 | **recovery 本体（minui 单 framebuffer 的 C 程序）放不下 Chromium**，它没有窗口系统 | 把 Chromium 跑在 recovery **内核**之上的第二个用户空间：Alpine + Xorg(fbdev) + Chromium kiosk，共用同一块 `/dev/fb0`，退出即回 recovery |

关于「玩云原神」：
- 云·原神的网页版要 **Chrome ≥100 + WebRTC + WebGL2 + H.264 解码**。
- Mi6 的 `msm_vidc`（4.4 内核）只暴露私有 ioctl，**不提供 V4L2 stateful decoder**，Chromium 拿不到硬解 → 走 **SwiftShader + 软解**。
- 实测预期：**720p30 可玩，1080p 掉帧明显**；WebGL 靠 SwiftShader（CPU 光栅），UI 流畅、画面有轻微迟滞。
- 想要 1080p60 原生体验，只能走「Android 系统里的 Chrome」——见 §5 方案 A。

---

## 1. 目录结构

```
sagit-skyward/
├─ device/xiaomi/sagit/
│  ├─ BoardConfig.mk          分区/内核/显示/TWRP 与 WiFi 全部开关
│  ├─ device.mk               recovery 包清单 + ramdisk 覆盖
│  ├─ AndroidProducts.mk / skyward_sagit.mk
│  ├─ recovery.fstab          by-name 全分区表（A-only）
│  ├─ root/
│  │  ├─ init.recovery.qcom.rc     挂固件分区 + 起 wlan 服务
│  │  ├─ sbin/sagit-wifi-up.sh     ★ WiFi 修复主脚本
│  │  ├─ sbin/sagit-wifi-down.sh / sagit-wifi-daemon.sh
│  │  ├─ sbin/romget.sh            ★ 终端下载器（断点续传 + 校验）
│  │  ├─ sbin/linux-boot.sh        ★ 拉起第二阶段 Linux
│  │  └─ etc/{wpa_supplicant.conf, WCNSS_qcom_cfg.ini}
│  └─ sepolicy/recovery_wlan.te
├─ wifi/extract_firmware.sh   从 adb / vendor.img 提取固件与模块
├─ kernel/sagit-wifi.fragment 内核选项（WLAN + DRM_FBDEV + LOOP + EVDEV）
├─ browser/stage2/
│  ├─ build-rootfs.sh         ★ 生成 3.6G ext4 镜像（Alpine+Chromium）
│  └─ overlay/usr/local/bin/kiosk.sh    Xorg + 首页 + Chromium 参数
└─ scripts/{build-recovery.sh, flash-and-verify.sh}
```

---

## 2. 快速开始（4 步）

```bash
# ① 取固件（设备连着 MIUI 并已 adb root）
chmod +x wifi/extract_firmware.sh && ./wifi/extract_firmware.sh adb
# 没 root 就拿官方 ROM 解包的目录当参数：./wifi/extract_firmware.sh /path/to/vendor

# ② 编 recovery（Ubuntu/WSL2，产出 recovery.img）
chmod +x scripts/build-recovery.sh && ./scripts/build-recovery.sh ~/skyward

# ③ 刷入并逐项自检
chmod +x scripts/flash-and-verify.sh && ./scripts/flash-and-verify.sh \
    ~/skyward/out/target/product/sagit/recovery.img

# ④ 造浏览器镜像并推进去（root 权限，约 900MB 下载）
chmod +x browser/stage2/build-rootfs.sh && sudo ./browser/stage2/build-rootfs.sh
adb shell "mkdir -p /data/linux"
adb push out/rootfs-sagit.img /data/linux/rootfs.img
adb shell "/system/bin/sh /sbin/linux-boot.sh; tail -50 /tmp/linux-boot.log"
```

刷完后：recovery 内 `WiFi 设置页` 能连网；`adb shell romget.sh <url>` 能断点续传下 ROM；
`linux-boot.sh` 会把屏幕交给 Chromium，首页四个入口（云原神 / 云星铁 / ROM 下载 / 已下文件）。

---

## 3. WiFi 修复：三个必要条件 + 排错表

### 3.1 必要条件
1. **`/persist/wlan_mac.bin` 有效**：12 字节（wlan0 MAC + p2p MAC）。Mi6 刷第三方 recovery 后
   这个文件常被写成 `00:00:00:00:00:00`，此时 `qca_cld3_wlan` 会在 probe 阶段直接失败，
   日志是 `wlan: invalid MAC address`。脚本用 SoC 序列号派生一个本地管理 MAC 并写回（幂等，不覆盖有效值）。
2. **vendor 固件齐**：`bdwlan30.bin` / `qwlan30.bin` / `otp30.bin` 在 `/vendor/firmware/`
   （部分版本在 `firmware_mnt/image/`），缺一个就 `firmware download timed out`。
3. **模块路径正确**：`/vendor/lib/modules/qca_cld3_wlan.ko` + `cnss2.ko`（WCN3990 走 PCIe，
   缺 cnss2 表现为 `probe failed -2`）。`BoardConfig.mk` 里已用 `TW_LOAD_VENDOR_MODULES` 带上。

### 3.2 排错表
| 现象 | 判据 | 处理 |
|---|---|---|
| `insmod: not found` | 模块不在 ramdisk | 检查 `TW_LOAD_VENDOR_MODULES`、`/vendor` 是否挂载 |
| `cnss2: probe failed -2` | `dmesg \| grep cnss` | 先 insmod cnss2，再 insmod wlan；确认固件路径 |
| `firmware download timed out` | `dmesg \| grep firmware` | 固件缺失或 `/vendor/firmware` 未挂载 |
| 有 `wlan0` 但无 IP | `ip -4 addr` | `wpa_supplicant` 未连：检查 `/etc/wpa_supplicant.conf` SSID/PSK |
| 连上秒断 | `dmesg \| grep -i roam` | 关 `gFastRoamEnabled`、加大 `gStaKeepAlivePeriod`（ini 已调） |
| 扫描不到 5G | `iw dev wlan0 info` | 监管域没设：ini 强制 `gCountryCode=CN`（已含） |

日志统一在 `/tmp/sagit-wifi.log`，可 `adb pull` 出来。

---

## 4. 内置浏览器内核：两条路，按需取

| | 方案 A：`linux-boot.sh` + Chromium（本仓库已实现） | 方案 B：留在 Android 提权 Chrome |
|---|---|---|
| 内核算力 | recovery 内核 + 第二阶段用户空间 | 完整 Android |
| 硬解 | ❌（msm_vidc 非 V4L2） | ✅ MediaCodec |
| 云原神 | 720p30 可玩 | 1080p60 顺 |
| 装法 | 推一个 img 到 `/data/linux` | 需刷完整 ROM |
| 适用 | 「recovery 里就想刷网页/下 ROM」 | 「就要最高画质云游戏」 |

方案 A 的关键实现点（都在 `kiosk.sh`）：
- `Xorg -novtswitch vt1` + `xf86-video-fbdev` 吃 `/dev/fb0`（**不用 wlroots**：msm-4.4 的 DRM 缺 GBM，cage/weston 起不来，这是最常见的翻车点）。
- Chromium 必须带：`--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader`（Chrome 119+ 不带这个 flag 直接禁 WebGL，云游戏黑屏）。
- `--autoplay-policy=no-user-gesture-required`：不然进游戏页面要点一下才出声。
- `--disable-dev-shm-usage`：`/dev/shm` 在 recovery 环境很小，不带就随机 `Aw, Snap`。
- 触摸用 `xf86-input-evdev` 直读 `/dev/input/event*`；坐标错乱时用 `xinput map-to-output` 或写 `Evdev` 的 `Calibration`。

---

## 5. 下载 ROM 的两条路

1. **图形（方案 A 已内置）**：首页 → LineageOS/TWRP 链接 → 直接下到 `/home/kiosk/Downloads`，
   已软链到 `/sdcard/Download`；退出 kiosk 后 TWRP「安装」里就能选到。
2. **终端（无图形 / 只想后台拉）**：
   ```bash
   adb shell "/system/bin/sh /sbin/romget.sh -l https://.../lineage-21-sagit.zip"   # 看大小
   adb shell "/system/bin/sh /sbin/romget.sh -c https://.../rom.zip <sha256>"      # 下+校验
   ```
   `romget.sh` 自带 5 次重试、`-C -` 断点续传、掉线自动重跑 `sagit-wifi-up.sh`、zip 完整性检查。

---

## 6. 已知风险 / 必须知道的坑

- **解锁 BL 会清空数据**，Mi6 走 Mi Unlock，等 72 小时；刷 recovery 后首次进系统可能触发 `dm-verity`（本方案 recovery 不动 `system`，安全）。
- **FBE 加密**：MIUI 上是文件级加密，recovery 里 `/data` 解密要 `TW_INCLUDE_CRYPTO_FBE`（已开）；解密失败时 `linux-boot.sh` 会退化成只读挂载 → 先把镜像放到 `/sdcard`，脚本支持传参 `linux-boot.sh /sdcard/rootfs.img`。
- **内存**：Chromium 单进程基线 ~600MB，Mi6 有 6G 版和 4G 版；4G 版建议把 `SIZE_MB` 降到 3072 并加 `--renderer-process-limit=2`。
- **发热**：SwiftShader 跑 WebGL 会 30 秒上 70℃，长时间云游戏建议贴散热或降到 720p。
- **二级系统镜像占空间**：3.6G 落在 `/data`，刷 ROM 前记得留够空间。

---

## 7. 验收清单

- [ ] `fastboot flash recovery` 后能进 Skyward 界面，触摸/亮度/电量正常
- [ ] `ls /persist/wlan_mac.bin` 存在且非全 0
- [ ] `ip -4 addr show wlan0` 拿到 IP，`ping 223.5.5.5` 通
- [ ] `romget.sh -l <url>` 返回 `content-length`
- [ ] `linux-boot.sh` 后屏幕出现 Chromium 首页，能打开云原神并进入游戏画面
- [ ] 首页「已下载文件」能看到刚下的 ROM
- [ ] 点「重启到 Recovery」回到 TWRP 主界面

---

## 8. 走 GitHub Actions（不用本地装 AOSP）

`.github/workflows/build.yml` 三个 job，改完直接 push 就能出 `recovery.img` 和浏览器镜像，
本地只需要一台能跑 `fastboot` 的 Windows。

| job | runner | 耗时 | 产出 |
|---|---|---|---|
| `lint` | ubuntu-22.04 | 1 分钟 | shellcheck + 设备树关键开关自检 |
| `recovery` | ubuntu-22.04 | 50~70 分钟（首次） | `recovery.img` + sha256 |
| `rootfs` | ubuntu-22.04 | 20~35 分钟 | `rootfs-sagit.img.part-00/01` + sha256 |
| `release` | — | 1 分钟 | 打 tag 或勾 `make_release` 时自动发 Release |

### 8.1 上手
```bash
git init && git add -A && git commit -m "sagit skyward + wifi + browser kernel"
git remote add origin git@github.com:<你>/sagit-skyward.git && git push -u origin main
# 触发：网页 Actions → build → Run workflow；或 git tag v1.0 && git push --tags
```

### 8.2 三个必须知道的 CI 现实
1. **内核默认走 `prebuilt`**。`kernel_mode=source` 需要预编译 gcc，而预编译 gcc 依赖
   `lib32ncurses5`——ubuntu-22.04 已经删了这个包，硬编内核会在 `checking build system type` 阶段挂。
   所以默认用预编译 `Image.gz-dtb` 直链（`prebuilt_kernel_url` 必填）；要走源码就打开
   `KERNEL_CLANG=true`（脚本会往 BoardConfig 追加 `TARGET_KERNEL_CLANG_COMPILE := true`）。
2. **磁盘只有 14GB**。`scripts/ci/free-disk.sh` 删掉 dotnet/swift/Android SDK/CodeQL 腾出 ~40GB，
   再建 8G swap（`mka` 链接阶段没有 swap 必 OOM）。
3. **单文件 >2GB 传不上 artifact**。`assemble-parts.sh split` 把 2.5G 镜像切 1200M 分卷；
   下载后 `cat rootfs-sagit.img.part-* > rootfs.img`（或 `assemble-parts.sh join`）再校验 sha256。

### 8.3 加速 / 省钱
- ccache 已开（`~/.ccache`，12G 上限），缓存键 `ccache-sagit-`，第二次构建能省 ~30 分钟。
- `concurrency` 已配 `cancel-in-progress`，连推多次只跑最后一版。
- 私有仓库按分钟计费：`recovery` 约 4 vCPU × 70min ≈ 280 分钟/次，建议 fork 到公开仓库或用自建 runner。
- 不想每次都跑内核相关改动，可以把 `recovery` job 加 `paths` 过滤，只改 `browser/**` 时跳过。

### 8.4 触发参数速查
```yaml
kernel_mode:        prebuilt | source      # 默认 prebuilt
prebuilt_kernel_url: <Image.gz-dtb 直链>    # prebuilt 必填
manifest_branch:    twrp-9.0               # 也可 twrp-8.1
rootfs_size_mb:     2560                   # 4G 内存机改 3072（更小更稳）
make_release:       true                   # 直接发 Release
```

---

## 9. CI 构建实录（已验证成功）

`run 44463423597` 用时 **32 分钟**，产出 `recovery.img`：

```
32,899,072 字节    sha256 08c09f593000784bfa182b05d79ecd9e818c49585eafb3d766ba4f557ef02cdf
头：ANDROID! v0, page_size 4096, kernel 15.2MB, ramdisk 17.6MB
Release: https://github.com/lcrlcr666/sagit-skyward/releases/tag/v0.1-sagit-recovery
```

ramdisk 内容已用 `scripts/ci/verify_ramdisk.py` 解 cpio 逐项核对（3499 个条目）：

```
init.recovery.qcom.rc            1072
etc/sagit/sagit-wifi-up.sh       6198
etc/sagit/sagit-wifi-down.sh      380
etc/sagit/sagit-wifi-daemon.sh    421
etc/WCNSS_qcom_cfg.ini            994
etc/wpa_supplicant.conf           489
sbin/recovery / adbd / toybox / magiskboot
```

### 9.1 AOSP 9 在 Ubuntu 22.04 runner 上的 8 个坑（全部已解决）

| # | 现象 | 根因 | 解法 |
|---|---|---|---|
| 1 | `apk: matchbox-window-manager no such package` | Alpine 包名错 | 改 `openbox` / `font-dejavu`（对照 APKINDEX 33107 个包核对） |
| 2 | `envsetup.sh: version: unbound variable` | 脚本 `set -u` 与 envsetup 冲突 | source 期间 `set +u` |
| 3 | `/usr/bin/time: cannot run mka` | `mka` 是 shell 函数 | 直接调用并 `tee` 日志 |
| 4 | `clang.real: libtinfo.so.5` | jammy 只有 ncurses6 | 装 focal 的 `libtinfo5`/`libncurses5`，失败则软链 `so.5 -> so.6` |
| 5 | `check_radio_versions.py` SyntaxError | `python-is-python3` 让 py2 脚本跑在 py3 | `python` 指回 python2（`/usr/local/bin/python`） |
| 6 | 内核 `clang-stable/bin/clang` 不存在 | TWRP 最小树无该软链；且 `ln -sfn` 撞已存在目录时无效 | 先 `rm -rf` 再从可用 `clang-*` 里选一个建链 |
| 7 | `multiple definition of yylloc`（dtc） | GCC 10+ 默认 `-fno-common` | 给 dtc 各目标补 `HOSTCFLAGS_*.o += -fcommon` |
| 8 | `unknown type persist_file`（checkpolicy） | 自定义 .te 引用了 tree 里不存在的 type | 删自定义策略，靠 `androidboot.selinux=permissive` |

另外两个设备树层面的问题：

- **`PRODUCT_COPY_FILES` 不能指定 `recovery/root/` 的子目录**（`sbin/`、`etc/` 不会被创建）→ 改用 `TARGET_RECOVERY_DEVICE_DIRS` 机制，文件放 `device/xiaomi/sagit/recovery/root/`
- **`sbin/` 在 baseline ramdisk 里不能安全合并**（`cp -rf` 报 `Not a directory`）→ 脚本改放 `recovery/root/etc/sagit/`，由 `init.recovery.qcom.rc` 用 `/system/bin/sh` 调用（不依赖可执行位）

### 9.2 内核策略

`kernel_mode=source` + `kernel_branch=staging/lineage-16.0` + `kernel_clang=false`（gcc 4.9）。

注意：**不要追加 `kernel/sagit-wifi.fragment`**。里面 `CONFIG_WCNSS_CORE=y` 会让 `wcnss_wlan.c` 走该内核版本不存在的调试路径，报 `implicit declaration of 'wcnss_get_mux_control'`。WiFi 模块本来就在 `/vendor/lib/modules`，运行时 insmod，不依赖内核配置。需要试验时用 `KERNEL_FRAGMENT=true`。

`kernel_mode=prebuilt` 的两级回退：官方 TWRP 镜像（twrp.me 会返回 HTML，有 `ANDROID!` 魔数校验）→ LineageOS 官方 ROM（`download.lineageos.org/api/v2/devices/sagit/builds`，sagit 至今仍有 nightly）。

### 9.3 验证脚本

```bash
# 解 recovery.img 头 + 抽 kernel/ramdisk
python scripts/ci/unpack_bootimg_v0.py --boot_img recovery.img --out out/
# 解 ramdisk 的 cpio 并核对关键文件
python scripts/ci/verify_ramdisk.py out/ramdisk
```
