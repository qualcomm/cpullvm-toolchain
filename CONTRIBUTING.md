# Contributing to CPULLVM Toolchain

Thank you for your interest in the CPULLVM Toolchain.

The CPULLVM Toolchain repository is a fork of the [llvm-project](https://github.com/llvm/llvm-project/). It includes an additional qualcomm-software directory containing build scripts
used to produce the CPULLVM Toolchain, as well as documentation and CI workflow scripts. Additionally,the CPULLVM Toolchain allows for integration with external projects such as the Picolibc C-library and MUSL.

# Contribution Policy
The CPULLVM Toolchain repository is synchronized with the upstream llvm-project (including main and release branches). As such, we do not accept external code contributions or pull requests for core components.
Any changes that can be made in the upstream project must be made in the upstream project.

**For guidance on how to contribute to the upstream projects see:**

[Contributing to LLVM](https://llvm.org/docs/Contributing.html)

[Contributing to Picolibc](https://github.com/picolibc/picolibc/blob/main/CONTRIBUTING.md)

[Contribution to ELD](https://github.com/qualcomm/eld/blob/main/CONTRIBUTING.md)

# Accepted Contributions
While core code changes must go upstream, we welcome contributions to this repository that improve:

- Build and Test infrastructure
- Configurations to build
- Packaging
- Documentation

# Reporting Issues
The CPULLVM Toolchain is heavily dependent on the LLVM, Picolibc, and ELD projects. If you identify an issue that is generic to one of these upstream projects, please submit it directly to the respective upstream repository. 

**For CPULLVM Toolchain specific issues :**

[CPULLVM-Toolchain](https://github.com/qualcomm/cpullvm-toolchain/issues)

**Other upstream projects :**

[LLVM Issue Tracker](github.com/llvm/llvm-project/issues)

[Picolibc Issue Tracker](github.com/picolibc/picolibc/issues)

[ELD Issue Tracker](github.com/qualcomm/eld/issues)


## Branching Strategy

In general, contributors should develop on branches based off of `main` and pull requests should be made against `main`.

## Submitting a pull request

1. Please read our [code of conduct](CODE-OF-CONDUCT.md) and [license](LICENSE.txt).
1. [Fork](https://github.com/qualcomm/<REPLACE-ME>/fork) and clone the repository.

    ```bash
    git clone https://github.com/<username>/<REPLACE-ME>.git
    ```

1. Create a new branch based on `main`:

    ```bash
    git checkout -b <my-branch-name> main
    ```

1. Create an upstream `remote` to make it easier to keep your branches up-to-date:

    ```bash
    git remote add upstream https://github.com/qualcomm/<REPLACE-ME>.git
    ```

1. Make your changes, add tests, and make sure the tests still pass.
1. Commit your changes using the [DCO](https://developercertificate.org/). You can attest to the DCO by commiting with the **-s** or **--signoff** options or manually adding the "Signed-off-by":

    ```bash
    git commit -s -m "Really useful commit message"`
    ```

1. After committing your changes on the topic branch, sync it with the upstream branch:

    ```bash
    git pull --rebase upstream main
    ```

1. Push to your fork.

    ```bash
    git push -u origin <my-branch-name>
    ```

    The `-u` is shorthand for `--set-upstream`. This will set up the tracking reference so subsequent runs of `git push` or `git pull` can omit the remote and branch.

1. [Submit a pull request](https://github.com/qualcomm/<REPLACE-ME>/pulls) from your branch to `main`.
1. Pat yourself on the back and wait for your pull request to be reviewed.
