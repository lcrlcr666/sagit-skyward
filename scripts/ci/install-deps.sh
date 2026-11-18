#!/usr/bin/env bash
# install-deps.sh — AOSP 9 / TWRP 构建依赖（jammy 上部分包已不存在，逐个装并容错）
set -uo pipefail

PKGS=(
    git curl wget unzip zip jq bc m4 rsync
    python3 python-is-python3
    ccache bison build-essential flex gperf
    g++-multilib gcc-multilib libc6-dev-i386
    gnupg imagemagick libelf-dev liblz4-tool libssl-dev
    libxml2 libxml2-utils lzop pngcrush schedtool
    squashfs-tools xsltproc zlib1g-dev
    android-sdk-libsparse-utils
    lib32z1 lib32stdc++6
    # 下列在 22.04 可能已移除（预编译 gcc 需要），装不上就跳过
    lib32ncurses5 lib32readline-dev lib32bz2-1.0
)

sudo apt-get update -qq
fail=0
for p in "${PKGS[@]}"; do
    sudo apt-get install -y --no-install-recommends "$p" >/dev/null 2>&1 || {
        echo "  跳过（源里没有）: $p"; fail=$((fail+1)); }
done
echo "依赖安装完成，$fail 个可选项缺失（正常）"

# repo 工具
mkdir -p "$HOME/bin"
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
chmod +x "$HOME/bin/repo"
echo "$HOME/bin" >> "$GITHUB_PATH" 2>/dev/null || true
export PATH="$HOME/bin:$PATH"

git config --global user.name  "ci-sagit-builder"
git config --global user.email "ci@sagit.local"
git config --global color.ui false

java -version 2>&1 | head -2 || true
echo "repo: $(command -v repo)"
