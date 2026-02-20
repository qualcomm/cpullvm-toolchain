# Contributing to CPULLVM Toolchain

Thank you for your interest in the CPULLVM Toolchain.

The CPULLVM Toolchain repository is a fork of the llvm-project. It includes an additional Qualcomm-software directory containing build scripts
used to produce the CPULLVM Toolchain for Embedded and CPULLVM Toolchain for Linux, as well as documentation and samples. Additionally,
the CPULLVM Toolchain for Embedded allows for integration with external projects such as the picolibc C-library and MUSL via an overlay package.

For guidance on how to contribute to the upstream projects see:

llvm-project [Contributing to LLVM](https://llvm.org/docs/Contributing.html)
picolibc [Contributing to picolibc](https://github.com/picolibc/picolibc/blob/main/CONTRIBUTING.md)
eld [Contribution to eld](https://github.com/qualcomm/eld/blob/main/CONTRIBUTING.md)
cpullvm-toolchain GitHub : https://github.com/qualcomm/cpullvm-toolchain/issues

# Contribution Policy
The CPULLVM Toolchain repository is synchronized with the upstream llvm-project (including main and release branches). As such, we do not accept external code contributions or pull requests for core components at this time.

# Upstream First
Any changes that can be made in the upstream project must be made in the upstream project. Please refer to the specific project guidelines for contributing:

# Reporting Upstream Issues
The CPULLVM Toolchain is heavily dependent on the LLVM, picolibc, and eld projects. If you identify an issue that is generic to one of these upstream projects, please submit it directly to the respective community. This ensures you can interact directly with the broader community, including Qualcomm's development team who monitor these trackers.

[LLVM Issue Tracker](github.com/llvm/llvm-project/issues)
[Picolibc Issue Tracker](github.com/picolibc/picolibc/issues)
[eld Issue Tracker](github.com/qualcomm/eld/issues)

# Accepted Contributions
While core code changes must go upstream, we welcome contributions to this repository that improve.

Build and Test infrastructure
Packaging
Documentation

# CPULLVM Toolchain Issues
If the issue is specific to the Qualcomm Toolchain build scripts, packaging, or documentation—or if you are unsure where the issue originates—please create an issue in our repository:
[Qualcomm Toolchain Issue Tracker](github.com/qualcomm/cpullvm-toolchain/issues)

