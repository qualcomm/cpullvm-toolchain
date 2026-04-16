e#!/bin/bash
set -e

REPO=$1
BRANCH=$2

cd /workspace

echo "Cloning toolchain repo..."
git clone "$REPO"
cd cpullvm-toolchain

echo "Checking out branch..."
git checkout "$BRANCH"

echo "Applying patches..."
python3 qualcomm-software/cmake/patch_repo.py \
  --method apply \
  qualcomm-software/patches/llvm-project

echo "Entering software directory..."
cd qualcomm-software

echo "Creating build directory..."
rm -rf build
mkdir -p build
cd build

echo "Running CMake configuration..."
cmake .. -GNinja \
  -DFETCHCONTENT_QUIET=OFF \
  -DENABLE_QEMU_TESTING=OFF \
  -DBUILD_IN_DOCKER=OFF \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
  -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld"

echo "✅ Setup complete"
