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


def move_files(src_glob, dest):
    """
    Move the files given by `src_glob` to `dest`. `src_glob` is treated
    as a glob. It must match at least one file and all matching files are
    moved.
    """

    files = glob.glob(src_glob)
    if not files:
        raise RuntimeError(f"No files matching '{src_glob}' found")
    for f in files:
        shutil.move(f, dest)


def recreate_folder(dir):
    """
    Create the directory pointed to by `dir`. It is deleted first if it
    already exists.
    """

    if os.path.isdir(dir):
        shutil.rmtree(dir)
    os.makedirs(dir)


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
    parser.add_argument(
        "--include-library-info",
        action="store_true",
        help="Whether to copy files containing information about the libraries (VERSION.txt, license files).",
    )
    parser.add_argument(
        "--library-info-dest-dir",
        help="Destination directory for library info files (required if --include-library-info is set)",
    )
    args = parser.parse_args()

    if args.include_library_info and args.library_info_dest_dir is None:
        parser.error("--library-info-dest is required when --include-library-info is set")

    if args.library_info_dest_dir is not None and not args.include_library_info:
        parser.error("--library-info-dest requires --include-library-info")

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

    if args.include_library_info:
        # This directory is our own construct, assume we don't need to preserve anything.
        recreate_folder(args.library_info_dest_dir)

    if args.include_linux_libraries:
        # The "linux-libraries" build folder is our own construct, so assume
        # there is nothing we need to preserve.
        linux_lib_dir = os.path.join(args.build_dir, "llvm", "linux-libraries")
        recreate_folder(linux_lib_dir)

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

        if args.include_library_info:
            move_folder(os.path.join(tmp, "*", "third-party-licenses"), args.library_info_dest_dir)
            move_files(os.path.join(tmp, "*", "VERSION*.txt"), args.library_info_dest_dir)

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
