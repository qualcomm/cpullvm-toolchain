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

# LLVM requires CMake 3.31.0. Install it only for Linux x86_64 jobs; other
# runner types either provide a suitable version or use a different toolchain.
if [[ "$(uname -m)" == "x86_64" ]]; then
    CMAKE_VERSION=3.31.0
    CMAKE_ROOT="${RUNNER_TEMP:-/tmp}/cmake-${CMAKE_VERSION}"
    CMAKE_INSTALLER="${RUNNER_TEMP:-/tmp}/install-cmake.sh"

    wget "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh" \
        -O "${CMAKE_INSTALLER}"
    bash "${CMAKE_INSTALLER}" \
        --prefix="${CMAKE_ROOT}" \
        --exclude-subdir \
        --skip-license

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        echo "${CMAKE_ROOT}/bin" >> "${GITHUB_PATH}"
    fi
    export PATH="${CMAKE_ROOT}/bin:${PATH}"
    rm -f "${CMAKE_INSTALLER}"
fi
