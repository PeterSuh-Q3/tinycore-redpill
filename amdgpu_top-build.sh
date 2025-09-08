#!/bin/bash
set -e

# 1. 필수 패키지 업데이트 및 build-essential 설치 (gcc, make 등 포함)
echo "Updating package lists and installing build-essential..."
apt update
apt install -y build-essential git curl libdrm-dev libdrm-amdgpu1

# 2. rustup 공식 설치 스크립트로 Rust 설치 (최신 Rust + Cargo 포함)
echo "Installing Rust via rustup official script..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 3. Rust 환경 변수 설정 (현재 쉘 세션)
source $HOME/.cargo/env

# 4. amdgpu_top 소스 클론 및 빌드
echo "Cloning amdgpu_top repository..."
if [ ! -d "amdgpu_top" ]; then
  git clone https://github.com/Umio-Yasuno/amdgpu_top.git
fi
cd amdgpu_top

echo "Building amdgpu_top with cargo..."
cargo build --release

echo "Build complete. Binary located at ./target/release/amdgpu_top"
