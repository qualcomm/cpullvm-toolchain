# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

sudo apt-get update
# Install swig and libedit-dev required for lldb and
# libc++-dev required for eld tests
sudo apt-get install -y swig libedit-dev libc++-dev

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0
