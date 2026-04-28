#!/usr/bin/env python3

# SPDX-FileCopyrightText: Copyright 2024-2025 Arm Limited and/or its affiliates <open-source-office@arm.com>
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
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
                "Clang :: Driver/ropi-rwpi.c",
                "Clang :: Preprocessor/arm-pic-predefines.c",
            ],
            result=NewResult.XFAILED,
            conditional=check_frwpi_error,
            project="clang",
            description="The multilib built by ATfE will generate a configuration error if -frwpi is used. Will pass if run before the multilib is installed.",
        ),
        XFail(
            name="no r52",
            testnames=[
                "Clang :: Driver/arm-fpu-selection.s",
            ],
            result=NewResult.XFAILED,
            conditional=check_r52_warning,
            project="clang",
            description="If the installed default multilib does not have a library available for -mcpu=cortex-r52, this test will fail.",
        ),
        XFail(
            name="picolibc rv32/64gc",
            testnames=[
                "math_errhandling.test",
                "test-fma.test",
            ],
            result=NewResult.XFAILED,
            project="picolibc",
            variants=[
                "riscv32gc_ilp32d",
                "riscv64gc_lp64d_nopic",
                "riscv64gc_zba_zbb_lp64d_nopic",
                "riscv64gc_lp64_nopic",
                "riscv64gc_zba_zbb_lp64_nopic"
            ],
            description="Disable the tests for now while the issue is being fixed upstream (https://github.com/picolibc/picolibc/pull/1072).",
        ),
        XFail(
            name="picolibc_rv32imafc",
            testnames=[
                "math_errhandling.test",
                "rounding-mode.test",
                "test-fma.test",
            ],
            result=NewResult.XFAILED,
            project="picolibc",
            variants=[
                "riscv32imafc_ilp32f",
                "riscv32imafc_zba_zbb_ilp32f",
                "riscv32imafc_zcb_zcmp_zba_zbb_ilp32f"
            ],
            description="Disable the tests for now while the issue is being fixed upstream (https://github.com/picolibc/picolibc/pull/1072).",
        ),
        XFail(
            name="picolibc_rv32im_xqci",
            testnames=[
                "test-except.test"
            ],
            result=NewResult.EXCLUDE,
            project="picolibc",
            variants=[
                "riscv32im_xqci_ilp32_nothreads_nopic"
            ],
            description="This test times out for some reason and we will most probably need a fix in QEMU. Disable until we have one.",
        ),
        XFail(
            name="math_errhandling rv32 no f",
            project="picolibc",
            testnames=[
                "math_errhandling.test"
            ],
            result=NewResult.XFAILED,
            variants=[
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv32im_xqci_ilp32_nothreads_nopic",
                "riscv32imac_ilp32",
                "riscv32imac_ilp32_nopic",
                "riscv32imac_zba_zbb_ilp32",
                "riscv32imac_zba_zbb_ilp32_nopic",
                "riscv32imac_zcb_zcmp_ilp32_nopic",
                "riscv32imac_zcb_zcmp_zba_zbb_ilp32_nopic",
            ],
            description="This test is now failing for these additional variants, xfail it while we investigate",
        ),
        XFail(
            name="no-c8rtomb-mbrtoc8-picolibc",
            testnames=[
                "std/strings/c.strings/no_c8rtomb_mbrtoc8.verify.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            description="picolibc unconditionally declares c8rtomb() and mbrtoc8() in uchar.h, "
                        "but _LIBCPP_HAS_C8RTOMB_MBRTOC8 is 0 (no source change to __config). "
                        "The test expects these symbols to be absent, which is false for picolibc. "
                        "Exclude rather than patching upstream libcxx headers.",
        ),
        XFail(
            name="no-atomic-builtins riscv nothreads",
            testnames=[
                "std/atomics/",
                "extensions/libcxx/atomics/",
                "libcxx/thread/thread.stoptoken/intrusive_shared_ptr.pass.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                # These variants use -march without the 'a' (atomic) extension.
                # libclang_rt.builtins.a is built with COMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON
                # so __atomic_* libcalls emitted by Clang are unresolved at link time.
                # riscv32imac_ilp32_scs_nothreads_nopic is intentionally excluded here
                # as it uses -march=rv32imac which includes the atomic extension.
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_scs_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv32im_xqci_ilp32_nothreads_nopic",
                "riscv64imc_lp64_nothreads_nopic",
                "riscv64imc_lp64_scs_nothreads_nopic",
            ],
            description="Exclude atomics tests for RISC-V variants without the A (atomic) extension. "
                        "These targets have no hardware atomics and libclang_rt.builtins.a does not "
                        "provide software __atomic_* fallbacks (COMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON).",
        ),
        XFail(
            name="long-double-simd riscv32 nothreads",
            testnames=[
                "std/experimental/simd/",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                # riscv32 has 16-byte long double but the experimental simd
                # __choose_mask_type<long double> has no specialization for it,
                # causing a static_assert failure at compile time.
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_scs_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv32im_xqci_ilp32_nothreads_nopic",
            ],
            description="experimental::simd does not support long double on riscv32 (16-byte long double "
                        "has no __choose_mask_type specialization). Exclude until upstream adds support.",
        ),
        XFail(
            name="cmath-hypot3-riscv32imc-nothreads",
            testnames=[
                "std/numerics/c.math/cmath.pass.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_scs_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv32im_xqci_ilp32_nothreads_nopic",
            ],
            description="std::hypot 3-argument form fails a precision assertion on riscv32imc "
                        "(no F extension, software float). Exclude until the math library is fixed.",
        ),
        XFail(
            name="mem-res-no-atomic-builtins riscv nothreads",
            testnames=[
                # All mem.res tests: these link against memory_resource.o which calls
                # __atomic_load_4/__atomic_exchange_4 (because _LIBCPP_HAS_ATOMIC_HEADER=1
                # for Clang regardless of _LIBCPP_HAS_THREADS). On targets without the
                # 'A' extension, these libcalls are unresolved at link time.
                "std/utilities/utility/mem.res/",
                "libcxx/mem/mem.res/",
                "libcxx/utilities/utility/mem.res/",
                # Container/stream tests that construct pmr objects (e.g. monotonic_buffer_resource),
                # which call get_default_resource() / set_default_resource() internally,
                # pulling in memory_resource.o at link time.
                "std/containers/container.adaptors/flat.map/flat.map.cons/deduct_pmr.pass.cpp",
                "std/containers/container.adaptors/flat.map/flat.map.cons/pmr.pass.cpp",
                "std/containers/container.adaptors/flat.multimap/flat.multimap.cons/deduct_pmr.pass.cpp",
                "std/containers/container.adaptors/flat.multimap/flat.multimap.cons/pmr.pass.cpp",
                "std/containers/container.adaptors/flat.multiset/flat.multiset.cons/deduct_pmr.pass.cpp",
                "std/containers/container.adaptors/flat.multiset/flat.multiset.cons/pmr.pass.cpp",
                "std/containers/container.adaptors/flat.set/flat.set.cons/deduct_pmr.pass.cpp",
                "std/containers/container.adaptors/flat.set/flat.set.cons/pmr.pass.cpp",
                "std/input.output/string.streams/istringstream/istringstream.members/str.allocator_propagation.pass.cpp",
                "std/input.output/string.streams/ostringstream/ostringstream.members/str.allocator_propagation.pass.cpp",
                "std/input.output/string.streams/stringstream/stringstream.members/str.allocator_propagation.pass.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                # Same set as no-atomic-builtins: RISC-V variants without the 'A' extension.
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_scs_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv32im_xqci_ilp32_nothreads_nopic",
                "riscv64imc_lp64_nothreads_nopic",
                "riscv64imc_lp64_scs_nothreads_nopic",
            ],
            description="memory_resource.cpp includes <atomic> unconditionally when "
                        "_LIBCPP_HAS_ATOMIC_HEADER=1 (always true for Clang), causing "
                        "__atomic_load_4/__atomic_exchange_4 libcalls that are unresolved "
                        "on targets without the 'A' extension (COMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON). "
                        "Exclude all tests that link against memory_resource.o.",
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
