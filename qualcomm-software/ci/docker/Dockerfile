# Base Ubuntu 24.04
FROM ubuntu:24.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Declare LLVM version (change in one place)
ARG LLVM_VERSION=19
ENV LLVM_VERSION=${LLVM_VERSION}

# Install required packages
RUN apt-get update && apt-get install -y \
    build-essential \
    clang-${LLVM_VERSION} \
    lld-${LLVM_VERSION} \
    llvm-${LLVM_VERSION} \
    git \
    cmake \
    ninja-build \
    python3 \
    python3-pip \
    python3-yaml \
    zlib1g-dev \
    make \
    gcc-arm-linux-gnueabi \
    libc6-dev-i386 \
    libstdc++-11-dev \
    libstdc++-12-dev \
    libstdc++-11-dev-arm64-cross \
    libstdc++-12-dev-arm64-cross \
    && python3 -m pip install --no-cache-dir --break-system-packages meson==1.10.1 \
    && rm -rf /var/lib/apt/lists/*

# Optional but recommended: make clang-${LLVM_VERSION} the default clang
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 100 \
 && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 100 \
 && update-alternatives --install /usr/bin/ld ld /usr/bin/lld-${LLVM_VERSION} 100

# Default working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
