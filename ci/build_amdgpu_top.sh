#!/bin/bash
set -euxo pipefail

sudo sed -i 's|http://apt.synology.inc|http://deb.debian.org/debian|g' /etc/apt/sources.list
sudo apt-get update

export DEBIAN_FRONTEND=noninteractive
export LC_ALL="C"

apt-get update
apt-get install -y curl git build-essential pkg-config libdrm-dev clang llvm cmake libdrm-amdgpu1

# Rust 설치
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="/root/.cargo/bin:$PATH"

# amdgpu_top 소스
git clone https://github.com/Umio-Yasuno/amdgpu_top.git /amdgpu_top_src
cd /amdgpu_top_src

echo "Building amdgpu_top with TUI mode..."
cargo build --release --locked --no-default-features --features="tui"

mkdir -p /output
cp target/release/amdgpu_top /output/
