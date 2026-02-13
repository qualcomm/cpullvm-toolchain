# CPULLVM Development Notes

This document aims to provide additional documentation that may be helpful to developers working on CPULLVM
or users who need to further customize the CPULLVM configuration and build.

## Configuring

CPULLVM is structured as a CMake project and will include LLVM as a subdirectory. So, generally, any CMake
cache variable one would set for LLVM is also applicable to CPULLVM. For example, setting `CMAKE_BUILD_TYPE`
to `Release` when configuring CPULLVM will result in a `Release` LLVM build, as usual.

Note though that not all options are propagated to the runtime builds.

Additionally, some LLVM-specific CMake variables are given different defaults in CPULLVM
(`LLVM_TARGETS_TO_BUILD`, for example) but these can be overriden as usual CMake cache variables.

CPULLVM also defines its own project-specifc cache variables, a few of which are described below.

### Notable CPULLVM-related CMake variables
**ENABLE_LINUX_LIBRARIES**:BOOL  
Whether to include additional library variants for use on Linux targets. This option
is only supported when building on Linux hosts.

**ENABLE_QEMU_TESTING**:BOOL  
Enable tests that use QEMU.

**LLVM_TOOLCHAIN_LIBRARY_VARIANTS**:STRING  
Semicolon separated string of the embedded library variants to build, or "all". Variant names as listed in
multilib.json should be used.

**LLVM_TOOLCHAIN_C_LIBRARY**:STRING  
Which embedded C library to use. Note that not all libraries are supported on all host and target platforms.
picolibc is the default, musl-embedded may also be used for Arm and AArch4 targets.

## Customizing

### Adding new embedded variants
To build additional embedded library variants, add the variant-specific JSON file under
[embedded-multilib/json/variants](../embedded-multilib/json/variants/) and add an entry referencing it in
[multilib.json](../embedded-multilib/json/multilib.json).

Corresponding multilib tests should be added in [test/multilib](../test/multilib/) as well.

#### Specifying multilib and compile flags for variants
Note that the flags listed the multilib.json entry are used differently than those in the variant-specific JSON
file. Those in the multilib.json entry are used for multilib selection *only*--the flags listed in the
variant-specific JSON file are used when actually building the runtimes.

There's a few important things to note about the multilib selection flags (those in multilib.json):
* The flags don't necessarily need to be valid compiler flags. One notable example of this is the `armvX`
  feature flags used in some AArch64 variants. These should be the exception though.
* Multilib flag matching generally happens on the normalized user input. So, normalized forms of triples
  (`aarch64-unknown-none-elf` instead of `aarch64-none-elf`) and arch strings (`armv8.5-a` instead of
  `armv8.5a`) should be used. The notable exception here is RISC-V arch strings--our CMake normalizes
  the input `-march` strings automatically so non-normalized forms may be used.

#### Enabling additional extensions for RISC-V in QEMU
Some of our variants enable extensions that are not enabled by default in QEMU. For now, these can be
enabled by passing the appropriate extensions through the `QEMU_CPU` variable in the variant-specific
JSON file (ex: `"QEMU_CPU": "rv32,i=true,m=false<extra extensions>"`).

Note that may also have to explicitly disable extensions which QEMU enables by default if it conflicts with
what you're enabling.

### Adding new Linux variants

Currently, Linux variants must be added by directly modifying [build_linux_runtimes.sh](../scripts/build_linux_runtimes.sh).

In most cases, you should only have to modify the `VARIANTS`, `VARIANT_BUILD_FLAGS`,
and `VARIANT_MUSL_CONFIGS` variables. Doing so will enable the appropriate compiler-rt, musl/musl-embedded,
and libc++/libc++abi/libunwind libraries for the variant.

## Building

### Re-running CMake
Unless you have manually checked out and patched CPULLVM's various dependencies (see "Manually checking out
and patching dependencies" below), CPULLVM's CMake will automatically checkout and patch the dependencies'
Git repositories. Note that it will *always* try to patch these repos, even if the patches have already been
applied. So, if you rerun CMake (either by manually invoking it or by modifying a file in some way that CMake
automatically reruns when rebuilding), you'll likely encounter errors.

To work around this, after the first time you invoke CMake, you can include `-DFETCHCONTENT_FULLY_DISCONNECTED=ON`
in your CMake command to tell it to stop updating and patching. Worst case, you can also manually remove the
cloned repostories (located in `<build>/_deps`).

### Manually checking out and patching dependencies
It is also possible to manually checkout CPULLVM's dependencies. If you do so, you must ensure the
correct (or compatible) revisions are checked out and necessary patches are applied.

Once you do so, you can tell CMake about these repositories by adding `FETCHCONTENT_SOURCE_DIR_<PROJECT_NAME>`
variables to your CMake invocation. For example:

```
cmake .. -GNinja \
    -DFETCHCONTENT_SOURCE_DIR_PICOLIBC=/path/to/your/picolibc \
    -DFETCHCONTENT_SOURCE_DIR_ELD=/path/to/your/eld
```

Then build as usual.

### Building subsets of library variants
When building the toolchain, specific subsets of embedded library variants to build can be selected by
setting `LLVM_TOOLCHAIN_LIBRARY_VARIANTS`.

For example, the command below would build only the 'aarch64a' and 'riscv32imac_ilp32' variants:
```
cmake .. -GNinja -DLLVM_TOOLCHAIN_LIBRARY_VARIANTS="aarch64a;riscv32imac_ilp32"
ninja llvm-toolchain
```

Additionally, the [embedded-multilib](../embedded-multilib/CMakeLists.txt) and [embedded-runtimes](../embedded-runtimes/CMakeLists.txt)
projects can be manually invoked to build a set of variants and appropriate multilib.yaml or an
individual library variant, respectively, without having to rebuild the toolchain itself (or, using
an existing set of LLVM tools). 

## Testing the toolchain
Running `ninja check-all-llvm-toolchain` as described in [building.md](building.md) will test the entire
toolchain (LLVM tests like `check-clang`, eld tests, any enabled library tests). But, it is also possible
to test these components separately. A non-exhaustive list of `check-` targets CPULLVM provides:
* `check-clang`, `check-llvm`, and the other usual LLVM `check-` targets are all still valid
* `check-eld` works as usual
* `check-llvm-toolchain-lit` runs only the built-in [multilib tests](../test/multilib/)
* `check-<component>` targets (where component is ex: picolibc) will run any enabled tests for that component across all variants
* `check-<component>-<variant>` targets will run the given component tests for the specified variant
