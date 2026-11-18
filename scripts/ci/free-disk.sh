#!/usr/bin/env bash
# free-disk.sh — GitHub runner 上腾磁盘 + 建 swap
# ubuntu-22.04 runner 默认只有 ~14GB 可用，AOSP 9 recovery 构建需要 ~45GB。
set -euo pipefail

echo "== 清理前 =="; df -h / /mnt 2>/dev/null || df -h /

# 只删确定与本次构建无关的大件（别动 node，后续 Actions 还要用）
sudo rm -rf \
    /usr/share/dotnet \
    /usr/local/lib/android \
    /opt/ghc \
    /opt/hostedtoolcache/CodeQL \
    /usr/local/share/boost \
    /usr/share/swift \
    /opt/az \
    /usr/local/aws-cli \
    /usr/lib/jvm/temurin-11-jdk-amd64 \
    /usr/local/share/powershell \
    2>/dev/null || true

sudo docker image prune -af >/dev/null 2>&1 || true
sudo apt-get clean || true

# swap：AOSP 的 linking 阶段（libart / libc++）在 7G 内存上必 OOM
if ! swapon --show | grep -q swapfile; then
    sudo fallocate -l 8G /swapfile 2>/dev/null || \
        sudo dd if=/dev/zero of=/swapfile bs=1M count=8192 status=none
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
    sudo swapon /swapfile
fi

echo "== 清理后 =="; df -h / ; free -h
