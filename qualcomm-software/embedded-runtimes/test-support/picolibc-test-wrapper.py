#!/usr/bin/env python3

# SPDX-FileCopyrightText: Copyright 2023-2024 Arm Limited and/or its affiliates <open-source-office@arm.com>
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# This is a wrapper script to run picolibc tests with QEMU.

from run_qemu import run_qemu
import argparse
import pathlib
import subprocess
import sys


def run(args, extra_args):
    # Some picolibc tests expect argv[0] to be literally "program-name", not
    # the actual program name.
    argv = ["program-name"] + extra_args
    if args.args:
        # In picolibc v1.8.11 and later, arguments from the picolibc tests
        # will come as a string rather than a list, so append to the first
        # element and let the semihosting library handle the splitting.
        argv[0] += " " + args.args
    if args.qemu_command:
        return run_qemu(
            args.qemu_command,
            args.qemu_machine,
            args.qemu_cpu,
            args.qemu_params.split(":") if args.qemu_params else [],
            args.image,
            argv,
            None,
            pathlib.Path.cwd(),
            args.verbose,
            args.trace,
            # Setting stdin to /dev/null prevents qemu from fiddling with
            # the echo bit of the parent terminal when meson runs multiple
            # tests in parallel. stdin is only tested by picolibc when
            # test-stdin=true, which is not the default.
            stdin=subprocess.DEVNULL,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Run a single test using either qemu"
    )
    main_arg_group = parser.add_mutually_exclusive_group(required=True)
    main_arg_group.add_argument("--qemu-command", help="qemu-system-<arch> path")
    parser.add_argument(
        "--qemu-machine",
        help="name of the machine to pass to QEMU",
    )
    parser.add_argument(
        "--qemu-cpu", required=False, help="name of the cpu to pass to QEMU"
    )
    parser.add_argument(
        "--qemu-params",
        help='list of arguments to pass to qemu, separated with ":"',
    )
    parser.add_argument(
        "--trace",
        type=str,
        default=None,
        help="File to write execution trace to (QEMU only)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print verbose output. This may affect test result, as the output "
        "will be added to the output of the test.",
    )
    parser.add_argument(
        "--args",
        help="String containing optional arguments for the image",
    )
    parser.add_argument("image", help="image file to execute")
    # FIXME: We need to support picolibc versions both with and without
    # https://github.com/picolibc/picolibc/commit/295b45098fb189185c973376b53d48b86b65e4ae.
    # Once all supported picolibc versions have this commit (picolibc v1.8.11
    # or later), `extra_args` should be removed and this can go back to just
    # `parse_args()`.
    args, extra_args = parser.parse_known_args()
    # --qemu-cpu is encoded with colons instead of commas to survive CMake list
    # separator substitution (LIST_SEPARATOR ,).  Decode it back here.
    args.qemu_cpu = args.qemu_cpu.replace(":", ",") if args.qemu_cpu else None
    ret_code = run(args, extra_args)
    sys.exit(ret_code)


if __name__ == "__main__":
    main()
