#!/usr/bin/env python3

"""
Script to copy target libraries into the build tree.
Building libraries can take a very long time on some platforms so
building them on another platform and copying them in can be a big
time saver.
"""

import argparse
import glob
import os
import shutil
import tarfile
import tempfile


def move_folder(src_glob, dest):
    """
    Move the folder given by `src_glob` to `dest`. `src_glob` is treated
    as a glob, but is assumed to point to only one folder.
    """

    for src_dir in glob.glob(src_glob):
        break
    else:
        raise RuntimeError("Extracted distribution directory not found")

    shutil.move(src_dir, dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--distribution-file",
        required=True,
        help="""Copy from this distribution tarfile. This is a glob to make
        things easier on Windows.""",
    )
    parser.add_argument(
        "--build-dir",
        required=True,
        help="The build root directory to copy into",
    )
    parser.add_argument(
        "--include-linux-libraries",
        action="store_true",
        help="Whether to copy Linux libraries in addition to embedded libraries",
    )
    args = parser.parse_args()

    # Find the distribution. This is a glob because scripts may not
    # know the version number and we can't rely on the Windows shell to
    # do it.
    for distribution_file in glob.glob(args.distribution_file):
        break
    else:
        raise RuntimeError(f"Distribution glob '{args.distribution_file}' not found")

    lib_dir = os.path.join(args.build_dir, "llvm", "lib")
    os.makedirs(lib_dir, exist_ok=True)

    destination = os.path.join(lib_dir, "clang-runtimes")

    if os.path.isdir(destination):
        shutil.rmtree(destination)

    if args.include_linux_libraries:
        # The "linux-libraries" build folder is our own construct, so assume
        # there is nothing we need to preserve.
        linux_lib_dir = os.path.join(args.build_dir, "llvm", "linux-libraries")
        if os.path.isdir(linux_lib_dir):
            shutil.rmtree(linux_lib_dir)
        os.makedirs(linux_lib_dir)

    with tempfile.TemporaryDirectory(
        dir=args.build_dir,
    ) as tmp:
        # Extract the distribution package.
        with tarfile.open(distribution_file) as tf:
            tf.extractall(tmp)

        # Move directories containing the target libraries into
        # position. The rest of the files in the distribution folder
        # will be deleted automatically when the tmp object goes out of
        # scope.
        move_folder(os.path.join(tmp, "*", "lib", "clang-runtimes"), lib_dir)

        if args.include_linux_libraries:
            # Move the entire resource directory
            move_folder(
                os.path.join(tmp, "*", "lib", "clang", "*"),
                os.path.join(linux_lib_dir, "resource-dir")
            )
            # Move the libc/libc++ directories one-by-one
            linux_lib_folders = [
                "aarch64-unknown-linux-musl",
                "arm-unknown-linux-musleabi",
                "riscv32-unknown-linux-musl",
                "riscv64-unknown-linux-musl",
            ]
            for folder in linux_lib_folders:
                move_folder(os.path.join(tmp, "*", folder), linux_lib_dir)


if __name__ == "__main__":
    main()
