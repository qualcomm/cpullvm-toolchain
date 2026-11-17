# -*- Python -*-

import os
import shutil
import sys

import lit.formats

from lit.llvm import llvm_config
from lit.llvm.subst import FindTool, ToolSubst

# Configuration file for the 'lit' test runner.

config.name = "package"
config.test_format = lit.formats.ShTest()
config.suffixes = [".c", ".cpp", ".test"]
config.excludes = ["CMakeLists.txt", "README.md"]
config.test_source_root = os.path.dirname(__file__)


# Copy-pasted from use_default_substitutions in
# llvm-project/llvm/utils/lit/lit/llvm/config.py
# FileCheck is not packaged so we need to get it from a different directory.
tool_patterns = [
    ToolSubst("FileCheck", unresolved="fatal"),
    # Handle these specially as they are strings searched for during
    # testing.
    ToolSubst(
        r"\| \bcount\b",
        command=FindTool("count"),
        verbatim=True,
        unresolved="fatal",
    ),
    ToolSubst(
        r"\| \bnot\b",
        command=FindTool("not"),
        verbatim=True,
        unresolved="fatal",
    ),
]
llvm_config.config.substitutions.append(("%python", '"%s"' % (sys.executable)))
llvm_config.add_tool_substitutions(
    tool_patterns, [os.path.join(config.llvm_obj_root, "bin")]
)
llvm_config.add_err_msg_substitutions()
llvm_config.use_clang()
llvm_config.config.substitutions.append(
    ("%unpack_directory", '"%s"' % config.unpack_directory)
)

# Compiler options and QEMU command line for each supported target, matching
# the targets supported by the samples. Each target provides the substitutions
# %{target-<target>} with the compiler options and %{qemu-<target>} with the
# QEMU command line, which takes the image to load as its argument. Targets
# whose QEMU executable is optional are only run if it is found.
qemu_semihosting = (
    "-nographic -chardev stdio,mux=on,id=stdio0 "
    "-semihosting-config enable=on,chardev=stdio0 -monitor none -serial none"
)
targets = {
    "arm": (
        "--target=arm-none-eabi -march=armv7m -mfpu=none -mfloat-abi=soft",
        "qemu-system-arm -M mps2-an385 -cpu cortex-m3",
        False,
    ),
    "aarch64": (
        "--target=aarch64-none-elf -march=armv8-a",
        "qemu-system-aarch64 -M virt -cpu cortex-a57",
        False,
    ),
    "riscv32": (
        "--target=riscv32-unknown-elf -march=rv32imac -mabi=ilp32",
        "qemu-system-riscv32 -M virt -cpu rv32 -bios none",
        False,
    ),
    "riscv32-xqci": (
        "--target=riscv32-unknown-elf "
        "-march=rv32ima_zawrs_zacas_zabha_zba_zbb_zbs_zca_zcb_zilsd_zclsd_"
        "xqcia_xqciac_xqcibi_xqcibm_xqcicli_xqcicm_xqcics_xqcicsr_xqciint_"
        "xqciio_xqcilb_xqcili_xqcilia_xqcilo_xqcilsm_xqcisim_xqcisls_"
        "xqcisync_xqccmp_xqccmt0p1 -menable-experimental-extensions "
        "-mabi=ilp32",
        "qemu-system-riscv32-xqci -M virt -cpu rv32,zcd=false,d=false,a=true,"
        "zawrs=true,zacas=true,zabha=true,zcb=true,zcmp=false,zilsd=true,"
        "zclsd=true,f=false,zfa=false,xqci=true,xqccmp=true,zca=true,"
        "xqccmt=true -bios none",
        True,
    ),
    "riscv64": (
        "--target=riscv64-unknown-elf -march=rv64imac -mabi=lp64 -mcmodel=medany",
        "qemu-system-riscv64 -M virt -cpu rv64 -bios none",
        False,
    ),
}
for target, (target_flags, qemu, _) in targets.items():
    config.substitutions.append(("%{target-" + target + "}", target_flags))
    config.substitutions.append(
        ("%{qemu-" + target + "}", "%s %s -kernel" % (qemu, qemu_semihosting))
    )

# Link options for a semihosted program using the C library's default linker
# script. ELD does not rescan archives, so libsemihost must come after libc.
config.substitutions.append(
    (
        "%{link-semihost}",
        "-fuse-ld=eld -nostartfiles -lcrt0-semihost -lc -lsemihost -T picolibcpp.ld",
    )
)

# Programs can always be built, but are only run if QEMU testing is enabled.
# Each QEMU executable has its own feature, e.g. qemu-system-riscv32 provides
# "qemu-riscv32". As with the library tests, the standard QEMU executables are
# required when QEMU testing is enabled, while the Xqci build is optional.
if config.enable_qemu_testing:
    for target, (_, qemu, optional) in targets.items():
        executable = qemu.split()[0]
        if not optional or shutil.which(executable):
            config.available_features.add("qemu-" + target)
        else:
            lit_config.note(
                "%s not found, %s tests will be built but not run"
                % (executable, target)
            )

config.environment["CLANG_NO_DEFAULT_CONFIG"] = "1"
