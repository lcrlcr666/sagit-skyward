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

# ---------------------------------------------------------------------------
# AOSP 9 (Pie) 的预编译 clang-4691093 是 2018 年的二进制，动态依赖
# libtinfo.so.5 / libncurses.so.5（ncurses 5.x）。Ubuntu 22.04 只剩 so.6，
# 于是在第一次 host 编译时就炸：
#   clang.real: error while loading shared libraries: libtinfo.so.5
# 这是 AOSP 9 在 jammy 上最经典的拦路虎。三步应对：真包 → 兜底软链 → 校验。
# ---------------------------------------------------------------------------
NCURL="http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses"
if ! ldconfig -p | grep -q 'libtinfo\.so\.5'; then
    echo ">> 安装 ncurses5 兼容库（focal 包，jammy 已移除）"
    pushd /tmp >/dev/null
    for f in libtinfo5_6.2-0ubuntu2.1_amd64.deb libncurses5_6.2-0ubuntu2.1_amd64.deb; do
        curl -fsSLO --retry 3 --max-time 120 "$NCURL/$f" || echo "  下载失败: $f"
    done
    sudo dpkg -i libtinfo5_*.deb libncurses5_*.deb 2>/dev/null || \
        sudo apt-get install -f -y >/dev/null 2>&1 || true
    popd >/dev/null
    sudo ldconfig
fi

if ! ldconfig -p | grep -q 'libtinfo\.so\.5'; then
    echo ">> 兜底：把 libtinfo.so.6 软链成 so.5（clang 只用它做诊断着色，ABI 足够）"
    sudo ln -sf /lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/libtinfo.so.5
    sudo ldconfig
fi

echo "--- ncurses 5/6 现状 ---"
ldconfig -p | grep -E 'libtinfo\.so\.(5|6)|libncurses\.so\.5' || echo "!! 仍缺 ncurses5 兼容库，构建会失败"

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
