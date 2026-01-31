#!/usr/bin/env python3

# SPDX-FileCopyrightText: Copyright 2024-2025 Arm Limited and/or its affiliates <open-source-office@arm.com>
#
# ​​​​​Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

"""This script will generate a list of tests where the expected result in the
source files needs to be overridden via the lit command line or environment
variables.
It can also be used to track where downstream testing diverges from
upstream, and why."""

import argparse
import os
import re
import subprocess

from enum import Enum
from typing import Callable, NamedTuple, List


class NewResult(Enum):
    """Enum storing the potential new result a test."""

    XFAILED = "FAILED"  # Replace a failure with an expected failure.
    PASSED = "PASSED"  # Replace an unexpected pass with a pass.
    EXCLUDE = "EXCLUDE"  # Exclude a test, so that it is not run at all.


class XFail(NamedTuple):
    """Class to collect information about an xfail."""

    name: str  # Name to identify the xfail.
    testnames: List[str]  # The tests to include.
    result: NewResult  # The expected result.
    project: str  # Affected project.
    variants: List[str] = None  # Affected library variants, if applicable.
    conditional: Callable = None  # A function that will test whether an xfail applies.
    issue_link: str = None  # Optional link to a GitHub issue.
    description: str = None  # Optional field for notes.


def main():
    arg_parser = argparse.ArgumentParser(
        prog="xfailgen",
        description="A script that generates lit environment variables to xfail or filter tests.",
    )
    arg_parser.add_argument(
        "--variant",
        help="For library specific projects, the variant being tested.",
    )
    arg_parser.add_argument(
        "--libc",
        help="For library specific projects, the C library that was used.",
    )
    arg_parser.add_argument(
        "--clang",
        help="Path to clang for conditional testing.",
    )
    arg_parser.add_argument(
        "--project",
        required=True,
        help="Project to generate xfails for.",
    )
    arg_parser.add_argument(
        "--output-args",
        help="Write the test lists to a file with --xfail and --xfail-not"
        "parameters, which can be read directly by lit by prefixing with @.",
    )
    args = arg_parser.parse_args()

    # Test whether there is a multilib error from -frwpi
    def check_frwpi_error():
        test_args = [
            args.clang,
            "--print-multi-directory",
            "-target",
            "arm-none-eabi",
            "-frwpi",
        ]
        p = subprocess.run(test_args, capture_output=True, check=False)
        return p.returncode != 0

    # Test whether there is a multilib warning from -mcpu=cortex-r52
    def check_r52_warning():
        test_args = [
            args.clang,
            "--print-multi-directory",
            "-target",
            "arm-none-eabi",
            "-mcpu=cortex-r52",
            "-Werror",
        ]
        p = subprocess.run(test_args, capture_output=True, check=False)
        return p.returncode != 0

    xfails = [
        XFail(
            name="no frwpi",
            testnames=[
                "Driver/ropi-rwpi.c",
                "Preprocessor/arm-pic-predefines.c",
            ],
            result=NewResult.XFAILED,
            conditional=check_frwpi_error,
            project="clang",
            description="The multilib built by ATfE will generate a configuration error if -frwpi is used. Will pass if run before the multilib is installed.",
        ),
        XFail(
            name="no r52",
            testnames=[
                "Driver/arm-fpu-selection.s",
            ],
            result=NewResult.XFAILED,
            conditional=check_r52_warning,
            project="clang",
            description="If the installed default multilib does not have a library available for -mcpu=cortex-r52, this test will fail.",
        ),
    ]

    tests_to_xfail = []
    tests_to_upass = []
    tests_to_exclude = []

    for xfail in xfails:
        if args.project != xfail.project:
            continue
        if xfail.variants is not None:
            if args.variant is None:
                raise ValueError(
                    f"--variant must be specified for project {args.project}"
                )
            if args.variant not in xfail.variants:
                continue
        if xfail.conditional is not None:
            if not xfail.conditional():
                continue
        if xfail.result == NewResult.XFAILED:
            tests_to_xfail.extend(xfail.testnames)
        elif xfail.result == NewResult.PASSED:
            tests_to_upass.extend(xfail.testnames)
        elif xfail.result == NewResult.EXCLUDE:
            tests_to_exclude.extend(xfail.testnames)

    tests_to_xfail.sort()
    tests_to_upass.sort()
    tests_to_exclude.sort()

    if args.output_args:
        os.makedirs(os.path.dirname(args.output_args), exist_ok=True)
        with open(args.output_args, "w", encoding="utf-8") as f:
            if len(tests_to_xfail) > 0:
                # --xfail and --xfail-not expect a comma separated list of test names.
                f.write("--xfail=")
                f.write(";".join(tests_to_xfail))
                f.write("\n")
            if len(tests_to_upass) > 0:
                f.write("--xfail-not=")
                f.write(";".join(tests_to_upass))
                f.write("\n")
            if len(tests_to_exclude) > 0:
                # --filter-out expects a regular expression to match any test names.
                escaped_testnames = [
                    re.escape(testname) for testname in tests_to_exclude
                ]
                f.write("--filter-out=")
                f.write("|".join(escaped_testnames))
                f.write("\n")
        print(f"xfail list written to {args.output_args}")
    else:
        if len(tests_to_xfail) > 0:
            print("xfailed tests:")
            for testname in tests_to_xfail:
                print(testname)
        if len(tests_to_upass) > 0:
            print("xfail removed from tests:")
            for testname in tests_to_upass:
                print(testname)
        if len(tests_to_exclude) > 0:
            print("excluded tests:")
            for testname in tests_to_exclude:
                print(testname)


if __name__ == "__main__":
    main()
