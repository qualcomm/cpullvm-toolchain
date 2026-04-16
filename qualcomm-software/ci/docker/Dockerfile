# Base Ubuntu 24.04 OS
FROM ubuntu:24.04

# Avoid Prompts during Installation
ENV DEBIAN_FRONTEND=noninteractive

	# 1. Installing Required Packages
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

WORKDIR /workspace

# ---repo access-----
ARG TOOLCHAIN_REPO=https://github.com/qualcomm/cpullvm-toolchain.git
ARG TOOLCHAIN_BRANCH=release/qualcomm-software/22.x

# Set compiler env before setup
ENV CC=clang
ENV CXX=clang++

# -----Copy Setup + entrypoint------
COPY scripts/setup.sh ./scripts/
COPY entrypoint.sh .

RUN sed -i 's/\r$//' ./scripts/setup.sh ./entrypoint.sh && \
    chmod +x ./scripts/setup.sh ./entrypoint.sh

# ------clone + setup ------
RUN ./scripts/setup.sh "$TOOLCHAIN_REPO" "$TOOLCHAIN_BRANCH"

WORKDIR /workspace/cpullvm-toolchain/qualcomm-software/build

ENTRYPOINT ["/workspace/entrypoint.sh"]
