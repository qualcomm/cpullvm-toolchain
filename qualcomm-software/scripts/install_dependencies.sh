# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

sudo apt-get update
# Used by lldb
sudo apt-get install swig libedit-dev

# Install meson. eld support was added in v1.9.0, so we need at least that.
pip install meson==1.10.0
