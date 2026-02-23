# Contributing to CPULLVM Toolchain

Thank you for your interest in the CPULLVM Toolchain.

The CPULLVM Toolchain repository is a fork of the [llvm-project](https://github.com/llvm/llvm-project/). It includes an additional qualcomm-software directory containing build scripts used to produce the CPULLVM Toolchain, as well as documentation and CI workflow scripts. Additionally, the CPULLVM Toolchain allows for integration with external projects such as the Picolibc C-library and MUSL.

# Contribution Policy

The CPULLVM Toolchain repository is synchronized with the upstream llvm-project (including main and release branches). As such, we do not accept external code contributions or pull requests for core components. Any changes that can be made in the upstream project must be made in the upstream project.

**For guidance on how to contribute to the upstream projects see:**

[Contributing to LLVM](https://llvm.org/docs/Contributing.html)

[Contributing to Picolibc](https://github.com/picolibc/picolibc/blob/main/CONTRIBUTING.md)

[Contributing to ELD](https://github.com/qualcomm/eld/blob/main/CONTRIBUTING.md)

# Accepted Contributions

While core code changes must go upstream, we welcome contributions to this repository that improve:

- Build and Test infrastructure
- Configurations to build
- Packaging
- Documentation

# Reporting Issues

The CPULLVM Toolchain is heavily dependent on the LLVM, Picolibc, and ELD projects. If you identify an issue that is generic to one of these upstream projects, please submit it directly to the respective upstream repository.

**For CPULLVM Toolchain specific issues:**

[CPULLVM Toolchain Issue Tracker](https://github.com/qualcomm/cpullvm-toolchain/issues)

**Other upstream projects:**

[LLVM Issue Tracker](https://github.com/llvm/llvm-project/issues)

[Picolibc Issue Tracker](https://github.com/picolibc/picolibc/issues)

[ELD Issue Tracker](https://github.com/qualcomm/eld/issues)

## Branching Strategy

In general, contributors should develop on branches based off of `qualcomm-software` and pull requests should be made against `qualcomm-software`.

## Submitting a pull request

1. Please read our [code of conduct](CODE_OF_CONDUCT.md) and [license](LICENSE.TXT).  
2. [Fork](https://github.com/qualcomm/cpullvm-toolchain/fork) and clone the repository.

    ```bash
    git clone https://github.com/<username>/<REPLACE-ME>.git
    ```

3. Create a new branch based on `qualcomm-software`:

    ```bash
    git checkout -b <my-branch-name> qualcomm-software
    ```

4. Create an upstream `remote` to make it easier to keep your branches up-to-date:

    ```bash
    git remote add upstream https://github.com/qualcomm/cpullvm-toolchain.git
    ```

5. Make your changes, add tests, and make sure the tests still pass.
6. Commit your changes using the [DCO](https://developercertificate.org/). You can attest to the DCO by committing with the **-s** or **--signoff** options or manually adding the "Signed-off-by":

    ```bash
    git commit -s -m "Really useful commit message"
    ```

7. After committing your changes on the topic branch, sync it with the upstream branch:

    ```bash
    git pull --rebase upstream qualcomm-software
    ```

8. Push to your fork.

    ```bash
    git push -u origin <my-branch-name>
    ```

    The `-u` is shorthand for `--set-upstream`. This will set up the tracking reference so subsequent runs of `git push` or `git pull` can omit the remote and branch.

9. [Submit a pull request](https://github.com/qualcomm/cpullvm-toolchain/pulls) from your branch to `qualcomm-software`.
10. Pat yourself on the back and wait for your pull request to be reviewed.
    
## Security Analysis of Pull Requests

To maintain the security and integrity of this project, all pull requests from external contributors are automatically scanned using [Semgrep](https://github.com/semgrep/semgrep) to detect insecure coding patterns and potential security flaws.

**Static Analysis with Semgrep:**  We use Semgrep to perform lightweight, fast static analysis on every PR. This helps identify risky code patterns and logic flaws early in the development process.

**Contributor Responsibility:** If any issues are flagged, contributors are expected to resolve them before the PR can be merged.

**Continuous Improvement:** Our Semgrep ruleset evolves over time to reflect best practices and emerging security concerns.

By submitting a PR, you agree to participate in this process and help us keep the project secure for everyone.

Here are a few things you can do that will increase the likelihood of your pull request to be accepted:

- Keep your change as focused as possible.
  If you want to make multiple independent changes, please consider submitting them as separate pull requests.
- Write a [good commit message](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html).
