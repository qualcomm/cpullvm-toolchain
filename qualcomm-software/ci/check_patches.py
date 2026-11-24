#!/usr/bin/env python3

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

"""
Verify patch files under qualcomm-software/patches/.

Two checks are performed for each supplied directory:

1. Format: every .patch file must be a well-formed git format-patch output
   (valid mbox email envelope with Author, Email, Subject, Date headers and a
   non-empty diff section), verified via `git mailinfo`.

2. Ordering: no two .patch files in the same directory may share the same
   leading numeric prefix (e.g. both "0001-a.patch" and "0001-b.patch" in the
   same folder is an error).
"""

import argparse
import logging
import subprocess
import sys
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def check_patch_format(patch_path: Path) -> list[str]:
    """Return a list of error strings; empty if the patch is well-formed."""
    errors = []

    with tempfile.NamedTemporaryFile(suffix=".msg") as msg_file, \
            tempfile.NamedTemporaryFile(suffix=".diff") as diff_file:
        with open(patch_path, "rb") as f:
            result = subprocess.run(
                ["git", "mailinfo", msg_file.name, diff_file.name],
                stdin=f,
                capture_output=True,
                text=True,
            )

        if result.returncode != 0:
            errors.append(f"git mailinfo failed: {result.stderr.strip()}")
            return errors

        # git mailinfo writes "Key: value" lines to stdout for the patch metadata
        fields: dict[str, str] = {}
        for line in result.stdout.splitlines():
            if ":" in line:
                key, _, value = line.partition(":")
                fields[key.strip()] = value.strip()

        for required in ("Author", "Email", "Subject", "Date"):
            if not fields.get(required):
                errors.append(f"missing or empty '{required}' field in patch header")

        if not Path(diff_file.name).read_bytes().strip():
            errors.append("patch has no diff content")

    return errors


def check_ordering(patch_dir: Path) -> list[str]:
    """Return errors for duplicate leading numeric prefixes within a directory."""
    errors = []
    seen: dict[str, str] = {}  # prefix -> first filename with that prefix

    for patch_file in sorted(patch_dir.glob("*.patch")):
        prefix = ""
        for ch in patch_file.name:
            if ch.isdigit():
                prefix += ch
            else:
                break

        if not prefix:
            continue  # no numeric prefix; skip ordering check for this file

        if prefix in seen:
            errors.append(
                f"duplicate prefix '{prefix}': '{seen[prefix]}' and '{patch_file.name}'"
            )
        else:
            seen[prefix] = patch_file.name

    return errors


def check_directory(patch_dir: Path) -> bool:
    """Run format and ordering checks for all patches in patch_dir. Returns True on success."""
    passed = True
    patch_files = sorted(patch_dir.glob("*.patch"))

    if not patch_files:
        logger.warning("%s: no .patch files found", patch_dir)
        return True

    for patch_file in patch_files:
        errors = check_patch_format(patch_file)
        if errors:
            passed = False
            for err in errors:
                logger.error("%s: %s", patch_file, err)
        else:
            logger.info("%s: format OK", patch_file)

    for err in check_ordering(patch_dir):
        logger.error("%s: %s", patch_dir, err)
        passed = False

    return passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "patch_dirs",
        nargs="+",
        type=Path,
        metavar="DIR",
        help="Patch directory to check (e.g. qualcomm-software/patches/picolibc)",
    )
    args = parser.parse_args()

    passed = True
    for patch_dir in args.patch_dirs:
        if not patch_dir.is_dir():
            logger.error("%s: not a directory", patch_dir)
            passed = False
            continue
        logger.info("Checking %s ...", patch_dir)
        if not check_directory(patch_dir):
            passed = False

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
