# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Used by lldb
choco install swig

# Install pyyaml and psutil. The workflow pins Python via actions/setup-python
# so 'python' here is the same interpreter that cmake and lit will use.
python -m pip install pyyaml psutil

# Install meson. eld support was added in v1.9.0, so we need at least that.
python -m pip install meson==1.10.0
