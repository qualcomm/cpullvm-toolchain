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
            name="no hardware atomics cxxabi",
            testnames=[
                "test_exception_storage.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            variants=[
                "riscv32im_xqci_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_nothreads_nopic",
                "riscv32imc_ilp32_scs_nothreads_nopic",
                "riscv32imc_zba_zbb_zbc_zbs_ilp32_nothreads_nopic",
                "riscv64imc_lp64_nothreads_nopic",
                "riscv64imc_lp64_scs_nothreads_nopic",
            ],
            description="These variants are built without the RISC-V A (atomic) extension "
                "so no hardware atomic instructions are available. "
                "test_exception_storage.pass.cpp links against libc++, which pulls in "
                "ios_base::xalloc() from ios.cpp. That function unconditionally uses "
                "std::atomic<int>, which lowers to a __atomic_fetch_add_4 call on targets "
                "without hardware atomics. This symbol has no provider on these targets "
                "since compiler-rt's atomic.c requires lock-free hardware CAS to compile.",
        ),
        XFail(
            name="Insufficient RAM",
            testnames=[
                "dynamic_cast14.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            variants=[
                "armv7m_hard_fpv5_d16_nopic",
                "armv7m_soft_nofp",
                "armv7m_soft_nofp_nopic",
            ],
            description="dynamic_cast14.pass.cpp (cxxabi test) fails due to"
                "insufficient memory. It requires at-least 10MB RAM."
        ),
        XFail(
            name="flat-container-oom-armv7m",
            testnames=[
                "std/containers/container.adaptors/flat.map/flat.map.capacity/size.pass.cpp",
                "std/containers/container.adaptors/flat.set/flat.set.capacity/size.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            variants=[
                "armv7m_soft_nofp",
                "armv7m_soft_nofp_nopic",
                "armv7m_hard_fpv5_d16_nopic",
            ],
            description="flat.map/size and flat.set/size insert 1,000,000 elements at "
                        "runtime, exceeding the 8MB RAM on armv7m bare-metal QEMU targets. "
                        "armv7a/armv8 have 16MB RAM and pass. The test aborts with exit 1.",
        ),
        XFail(
            name="sort-heap-complexity-armv7m",
            testnames=[
                "std/algorithms/alg.sorting/alg.heap.operations/sort.heap/complexity.pass.cpp",
                "std/algorithms/alg.sorting/alg.heap.operations/sort.heap/ranges_sort_heap.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            variants=[
                "armv7m_soft_nofp",
                "armv7m_soft_nofp_nopic",
                "armv7m_hard_fpv5_d16_nopic",
            ],
            description="sort.heap complexity tests use std::random_device which falls "
                        "back to a fixed seed on armv7m bare-metal, causing the complexity "
                        "assertion to fail. armv7a/armv8 pass. Exits with code 1.",
        ),
        XFail(
            name="simd-unary-compiler-crash-armv7a",
            testnames=[
                "std/experimental/simd/simd.class/simd_unary.pass.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                "armv7a_soft_neon",
                "armv8_soft_neon",
            ],
            description="simd_unary.pass.cpp triggers a clang assertion failure "
                        "(ScalarizeVecOp_VSETCC: expected v1i1 type) in "
                        "LegalizeVectorTypes.cpp when compiling std::experimental::simd "
                         "on ARMv7-A/ARMv8 with NEON. Compiler bug; exclude until fixed.",
        ),
        XFail(
            name="long-double-picolibc-aarch64",
            testnames=[
                "std/strings/string.conversions/stold.pass.cpp",
                "std/strings/string.conversions/to_string.pass.cpp",
                "std/localization/locale.categories/category.monetary/locale.money.get/locale.money.get.members/get_long_double_overlong.pass.cpp",
                "std/localization/locale.categories/category.numeric/locale.nm.put/facet.num.put.members/put_long_double.hex.pass.cpp",
                "std/localization/locale.categories/category.numeric/locale.nm.put/facet.num.put.members/put_long_double.pass.cpp",
                "std/input.output/iostream.format/output.streams/ostream.formatted/ostream.inserters.arithmetic/long_double.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            variants=[
                "aarch64a_tlsie",
            ],
            description="Long double is 128-bit on AArch64 and conversion between 128-bit "
                        "types and strings is broken in picolibc. ARM 32-bit is unaffected "
                        "(64-bit long double).",
        ),
        XFail(
            name="aeabi-unwind-cpp-pr0-missing-arm",
            testnames=[
                "std/language.support/support.coroutines/end.to.end/",
                "std/language.support/support.coroutines/coroutine.handle/coroutine.handle.noop/",
                "std/language.support/support.coroutines/coroutine.handle/coroutine.handle.prom/",
                "extensions/libcxx/odr_signature.exceptions.sh.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                "armv8_soft_neon",
                "armv7a_soft_neon",
                "armv7a_soft_nofp",
                "armv7a_hard_vfpv3",
                "armv7m_soft_nofp",
                "armv7m_soft_nofp_nopic",
                "armv7m_hard_fpv5_d16_nopic",
            ],
            description="Tests that emit .ARM.exidx unwind tables referencing "
                        "__aeabi_unwind_cpp_pr0, which is absent in the bare-metal "
                        "semihosting runtime. Affects coroutine tests (which emit unwind "
                        "tables even with -fno-exceptions) and odr_signature.exceptions "
                        "(which mixes -fexceptions and -fno-exceptions TUs).",
        ),
        XFail(
            name="at_exit",
            testnames=[
                "std/language.support/support.start.term/quick_exit.pass.cpp",
            ],
            result=NewResult.XFAILED,
            project="libcxx",
            description="at_quick_exit symbol is not found in the picolibc semihosting runtime.",
        ),
        XFail(
            name="uchar-cuchar-xpass-picolibc",
            testnames=[
                "std/depr/depr.c.headers/uchar_h.compile.pass.cpp",
                "std/strings/c.strings/cuchar.compile.pass.cpp",
            ],
            result=NewResult.PASSED,
            project="libcxx",
            description="uchar_h and cuchar compile tests are XFAIL upstream for picolibc "
                        "(mbrtoc16 not defined), but picolibc does define mbrtoc16/c16rtomb "
                        "so they pass on all our bare-metal variants. Suppress XPASS.",
        ),
        XFail(
            name="cas-non-power-of-2-no-generic-atomic",
            testnames=[
                "std/atomics/atomics.types.generic/cas_non_power_of_2.pass.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            variants=[
                "armv8_soft_neon",
                "armv7a_soft_neon",
                "armv7a_soft_nofp",
                "armv7a_hard_vfpv3",
                "armv7m_soft_nofp",
                "armv7m_soft_nofp_nopic",
                "armv7m_hard_fpv5_d16_nopic",
            ],
            description="cas_non_power_of_2.pass.cpp tests atomic operations on structs of "
                        "sizes 3, 5, and 6 bytes, which require the generic (unsized) libcalls "
                        "__atomic_load / __atomic_compare_exchange.  These lock-based fallbacks "
                        "are not provided by libclang_rt.builtins.a on our bare-metal ARM targets.",
        ),
        XFail(
            name="no-c8rtomb-verify-picolibc",
            testnames=[
                "std/strings/c.strings/no_c8rtomb_mbrtoc8.verify.cpp",
            ],
            result=NewResult.EXCLUDE,
            project="libcxx",
            description="Picolibc provides c8rtomb/mbrtoc8, so the verify test's expected "
                        "errors ('no member named c8rtomb') do not fire. Exclude since the "
                        "test premise does not apply to picolibc targets.",
        ),
        XFail(
            name="emulated crash signals",
            testnames=[
                "aarch64/emupac.c",
            ],
            result=NewResult.XFAILED,
            project="compiler-rt",
            variants=[
                "aarch64a_tlsie",
                "aarch64a_soft_nofp_tlsie",
            ],
            description="QEMU does not deliver crash signals. The emupac test uses "
                "%expect_crash which requires the OS to deliver a signal back to the "
                "test runner when PAC authentication fails. QEMU semihosting does not "
                "support this capability. This test is also xfailed in the ATfE "
                "toolchain (arm/arm-toolchain) for the same reason.",
        ),
        XFail(
            name="sme-string-test missing cxx headers",
            testnames=[
                "sme-string-test.cpp",
            ],
            result=NewResult.XFAILED,
            project="compiler-rt",
            variants=[
                "aarch64a_soft_nofp_tlsie",
            ],
            description="The test fails to compile because the 'cassert' header is not "
                "found. This variant has ENABLE_CXX_LIBS=OFF so libcxx headers are not "
                "installed in the sysroot. ATfE does not encounter this failure because "
                "their aarch64a_soft_nofp variant has ENABLE_CXX_LIBS=ON.",
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
