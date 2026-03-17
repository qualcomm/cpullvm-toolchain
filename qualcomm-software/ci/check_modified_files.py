#!/usr/bin/env python3

# Copyright (c) 2025, Arm Limited and affiliates.
# Part of the Arm Toolchain project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Changes from Qualcomm Technologies, Inc. are provided under the following license:
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

"""
A script to check that a list of modified files only includes those that we are allowed
to modify. This is intended to help enforce our policy of making changes only within
a few specific places (.github, qualcomm-software, and some documentation files).
"""

import argparse
import logging
import os
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

CPULLVM_ALLOWED_PATHSPEC_FILE = Path(__file__).parent / "cpullvm_modified_files"


# Test if a path is in the ignore list.
def is_path_ignored(test_path: str, ignored_paths: list[str]) -> bool:
    for ignored_path in ignored_paths:
        # The ignore list contains paths or directories.
        # Anything in an ignored subdirectory should also be ignored.
        if os.path.commonpath([ignored_path, test_path]) == ignored_path:
            logger.debug(f"{test_path} ignored by line {ignored_path}")
            return True
    return False


# Test if a pull request contains a change outside of the allowed list of
# files we may modify.
def has_changes_outside_allowed_list(modified_files: str) -> bool:
    excluded_files = []
    included_files = []
    with open(CPULLVM_ALLOWED_PATHSPEC_FILE, "r") as f:
        ignored_paths = f.read().splitlines()
    with open(modified_files, "r") as f:
        file_list = f.read().splitlines()
    for changed_file in file_list:
        if is_path_ignored(changed_file, ignored_paths):
            excluded_files.append(changed_file)
        else:
            included_files.append(changed_file)
    if len(excluded_files) > 0:
        excluded_list = "\n".join(excluded_files)
        logger.info(f"File modifications excluded by ignore list:\n{excluded_list}")
    if len(included_files) > 0:
        included_list = "\n".join(included_files)
        logger.info(f"File modifications that require tracking:\n{included_list}")
    else:
        logger.info("No modifications to files outside exclude list found.")
    return len(included_files) > 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--modified-files",
        required=True,
        help="File containing the list of files modified"
    )
    args = parser.parse_args()

    if has_changes_outside_allowed_list(args.modified_files):
        logger.info("Check failed, modified files contain changes outside of the allowed locations.")
        sys.exit(1)
    else:
        logger.info("Check passed, modified files contain no changes outside of the allowed locations.")
        sys.exit(0)


if __name__ == "__main__":
    main()