# Base Ubuntu 24.04
FROM ubuntu:24.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    lld \
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

# Default working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
