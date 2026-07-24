#!/usr/bin/env python3

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import argparse
import json
import logging
import subprocess
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

REMOTE_NAME = "origin"


def run_cmd(cmd: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(
        cmd,
        check=True,
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return result.stdout.strip()


def update_repo_version(
    repo_path: Path,
    repo_name: str,
    repo_info: dict,
) -> None:
    versions_file = repo_path / "qualcomm-software" / "versions.json"

    tag_type = repo_info.get("tagType")
    repo_url = repo_info.get("url")
    current_tag = repo_info.get("tag")

    logger.info("Repo: %s", repo_name)
    logger.info("URL: %s", repo_url)
    logger.info("tagType: %s", tag_type)
    logger.info("Current tag: %s", current_tag)

    # Only update repositories already using commit hashes
    if tag_type != "commithash":
        logger.info(
            "Skipping %s because tagType is '%s'",
            repo_name,
            tag_type,
        )
        return

    tracking_branch = repo_info.get("trackingBranch")

    if not tracking_branch:
        logger.info(
            "Skipping %s because 'trackingBranch' is not set",
            repo_name,
        )
        return

    branch_ref = f"refs/heads/{tracking_branch}"
    logger.info("Tracking ref: %s", branch_ref)

    latest_sha = run_cmd(
        ["git", "ls-remote", repo_url, branch_ref]
    ).split()[0]

    logger.info("Latest SHA: %s", latest_sha)

    if latest_sha == current_tag:
        logger.info("%s already up to date", repo_name)
        return

    # Reload the file to reflect any updates from previous repo iterations
    with open(versions_file, encoding="utf-8") as f:
        data = json.load(f)

    # Update only tag
    data["repos"][repo_name]["tag"] = latest_sha

    with open(versions_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    logger.info("Updated versions.json for %s", repo_name)

    # Stage and commit one commit per repo
    run_cmd(
        ["git", "-C", str(repo_path), "add", str(versions_file)]
    )

    commit_msg = f"Automerge: Update {repo_name} to {latest_sha}"

    run_cmd(
        [
            "git",
            "-C",
            str(repo_path),
            "commit",
            "-m",
            commit_msg,
        ]
    )

    logger.info("Created commit: %s", commit_msg)


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--repo-path",
        default=Path.cwd(),
        type=Path,
    )

    parser.add_argument(
        "--to-branch",
        required=True,
        help="Target cpullvm branch",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
    )

    args = parser.parse_args()

    versions_file = args.repo_path / "qualcomm-software" / "versions.json"

    logger.info("Switching to branch %s", args.to_branch)
    run_cmd(["git", "-C", str(args.repo_path), "switch", args.to_branch])

    logger.info("Loading %s", versions_file)

    with open(versions_file, encoding="utf-8") as f:
        data = json.load(f)

    repos = data.get("repos", {})

    original_head = run_cmd(["git", "-C", str(args.repo_path), "rev-parse", "HEAD"])

    for repo_name, repo_info in repos.items():
        try:
            update_repo_version(
                repo_path=args.repo_path,
                repo_name=repo_name,
                repo_info=repo_info,
            )
        except subprocess.CalledProcessError as error:
            logger.error(
                'Failed to run command: "%s"\nstdout:\n%s\nstderr:\n%s',
                " ".join(error.cmd),
                error.stdout,
                error.stderr,
            )
            raise SystemExit(1)

        except Exception as error:
            logger.exception(
                "Failed to update repository '%s': %s",
                repo_name,
                str(error),
            )
            raise SystemExit(1)

    current_head = run_cmd(["git", "-C", str(args.repo_path), "rev-parse", "HEAD"])

    if current_head == original_head:
        logger.info("All tracked repositories are already up to date")
        return

    if args.dry_run:
        logger.info("Dry run; skipping push")
        return

    run_cmd(
        [
            "git",
            "-C",
            str(args.repo_path),
            "push",
            REMOTE_NAME,
            f"HEAD:{args.to_branch}",
        ]
    )
    logger.info("Push complete")


if __name__ == "__main__":
    main()
