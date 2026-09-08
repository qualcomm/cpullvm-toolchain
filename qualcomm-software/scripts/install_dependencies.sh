# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

CLANG_VERSION = 22

sudo apt-get update

# Add LLVM APT repo (required for clang-22)
wget -qO llvm.sh https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh ${CLANG_VERSION}

# Install swig and libedit-dev used by lldb and
# libc++-dev required for eld tests
sudo apt-get install -y swig libedit-dev libc++-${CLANG_VERSION}-dev

# Set default clang version to clang-22
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 100
sudo update-alternatives --set clang /usr/bin/clang-${CLANG_VERSION}
sudo update-alternatives --set clang++ /usr/bin/clang++-${CLANG_VERSION}

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0