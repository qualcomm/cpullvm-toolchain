#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Installs CMake 3.31.0 for the Linux x86_64 self-hosted runner (cpullvm-ubuntu24-x86_64).

set -euo pipefail

CMAKE_VERSION="3.31.0"
CMAKE_INSTALL_PREFIX="/opt/cmake-${CMAKE_VERSION}"

if [[ ! -x "${CMAKE_INSTALL_PREFIX}/bin/cmake" ]]; then
     echo "Error: CMake ${CMAKE_VERSION} not found at ${CMAKE_INSTALL_PREFIX}"
     exit 1
fi

echo "${CMAKE_INSTALL_PREFIX}/bin" >> "${GITHUB_PATH}"

echo "CMake version found:"
"${CMAKE_INSTALL_PREFIX}/bin/cmake" --version
