# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

sudo apt-get update
# Install swig and libedit-dev used by lldb and
# libc++-dev required for eld tests
sudo apt-get install -y swig libedit-dev clang-19 libc++-19-dev

# Set default clang version to clang-19
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100
sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0

# psutil is used to set per-test timeouts in lit
pip install psutil
