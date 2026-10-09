#!/usr/bin/env python3

"""
A script to automatically perform the merge of incoming changes from a branch
in upstream LLVM into a downstream branch.

Supports pathspec patterns with negation to selectively ignore or keep files
during the merge process. Files matching ignore patterns are restored to the
destination branch version, while files matching keep patterns (prefixed with '!')
are accepted from the upstream branch.
"""

import argparse
import json
import logging
import shlex
import subprocess
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


MERGE_CONFLICT_LABEL = "automerge_conflict"
AUTOMERGE_BRANCH = "automerge"
REMOTE_NAME = "origin"
MERGE_IGNORE_PATHSPEC_FILE = Path(__file__).parent / "cpullvm_modified_files"


class MergeConflictError(Exception):
    """
    An exception representing a failed merge from upstream due to a conflict.
    """

    def __init__(self, commit_hash: str) -> None:
        super().__init__()
        self.commit_hash = commit_hash


class Git:
    """
    A helper class for running Git commands on a repository that lives in a
    specific path.
    """

    def __init__(self, repo_path: Path) -> None:
        self.repo_path = repo_path

    def get_repo_path(self) -> Path:
        return self.repo_path

    def run_cmd(self, args: list[str], check: bool = True) -> str:
        git_cmd = ["git", "-C", str(self.repo_path)] + args
        logger.debug("Running git command: %s", git_cmd)
        git_process = subprocess.run(
            git_cmd, check=check, capture_output=True, text=True
        )
        logger.debug("Stdout:\n%s\nStderr:\n%s", git_process.stdout, git_process.stderr)
        return git_process.stdout


def is_merge_in_progress(git_repo: Git) -> bool:
    # The `.git/MERGE_HEAD` file only exists when a merge operation is in progress.
    merge_head_path = Path(git_repo.repo_path) / ".git" / "MERGE_HEAD"
    return merge_head_path.exists()


def parse_pathspec_file(pathspec_file: Path) -> tuple[list[str], list[str]]:
    """
    Parse pathspec file and separate into include and exclude patterns.

    Lines starting with '!' are exclusions (files to KEEP from upstream).
    Other lines are inclusions (files to IGNORE from upstream).

    Returns:
        (ignore_patterns, keep_patterns)
    """
    ignore_patterns = []
    keep_patterns = []

    with open(pathspec_file) as f:
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue

            if line.startswith('!'):
                # Negation pattern - files to KEEP from upstream
                keep_patterns.append(line[1:])  # Remove the '!'
            else:
                # Regular pattern - files to IGNORE from upstream
                ignore_patterns.append(line)

    return ignore_patterns, keep_patterns


def get_files_matching_pathspec(git_repo: Git, patterns: list[str]) -> list[str]:
    """
    Get list of files matching the given pathspec patterns.
    """
    if not patterns:
        return []

    # Use git ls-files to find files matching patterns
    try:
        output = git_repo.run_cmd(["ls-files", "--"] + patterns)
        return output.strip().splitlines()
    except subprocess.CalledProcessError:
        return []


def get_conflicted_files(git_repo: Git, patterns: list[str]) -> list[str]:
    """
    Get list of conflicted files matching the given patterns.
    """
    if not patterns:
        return []

    try:
        output = git_repo.run_cmd(
            ["diff", "--name-only", "--diff-filter=U", "--"] + patterns
        )
        return output.strip().splitlines()
    except subprocess.CalledProcessError:
        return []


def restore_changes_to_ignored_files(
    git_repo: Git,
    ignore_patterns: list[str],
    keep_patterns: list[str]
) -> None:
    """
    Restore ignored files to destination branch version, but keep files
    matching keep_patterns from upstream.
    """
    if not ignore_patterns:
        return

    # Get all files that match ignore patterns
    all_ignored_files = get_conflicted_files(git_repo, ignore_patterns)

    if not all_ignored_files:
        logger.debug("No conflicted files matching ignore patterns")
        return

    # Get files that should be kept from upstream (negation patterns)
    files_to_keep_from_upstream = []
    if keep_patterns:
        files_to_keep_from_upstream = get_files_matching_pathspec(git_repo, keep_patterns)

    # Filter out files that should be kept from upstream
    files_to_restore = [
        f for f in all_ignored_files
        if f not in files_to_keep_from_upstream
    ]

    if not files_to_restore:
        logger.debug("No files to restore after applying keep patterns")
        return

    logger.debug(f"Restoring {len(files_to_restore)} files to destination version")
    logger.debug(f"Keeping {len(files_to_keep_from_upstream)} files from upstream")

    # First, deal with any conflicting changes to files in the ignore list,
    # keeping the version from the destination branch
    git_repo.run_cmd(["restore", "--ours", "--worktree"] + files_to_restore)

    # Next, any files still unmerged are the ones deleted on the destination branch.
    # Make sure they stay deleted.
    deleted_by_us = get_conflicted_files(git_repo, files_to_restore)
    if deleted_by_us:
        git_repo.run_cmd(["rm"] + deleted_by_us)

    # Finally, restore all other ignored files
    git_repo.run_cmd(["restore", "--staged", "--worktree"] + files_to_restore)


def has_unresolved_conflicts(git_repo: Git) -> bool:
    diff_output = git_repo.run_cmd(["diff", "--name-only", "--diff-filter=U"])
    diff_output = diff_output.strip()
    return bool(diff_output)


def prefix_current_commit_message(git_repo: Git) -> None:
    log_output = git_repo.run_cmd(
        ["log", "HEAD", "--max-count=1", "--pretty=format:%B"]
    )
    commit_msg = f"Automerge: {log_output}"
    git_repo.run_cmd(["commit", "--amend", "--message=" + commit_msg])


def merge_commit(
    git_repo: Git,
    to_branch: str,
    commit_hash: str,
    ignore_patterns: list[str],
    keep_patterns: list[str],
    dry_run: bool,
    verbose: bool,
) -> None:
    logger.info("Merging commit %s into %s", commit_hash, to_branch)
    git_repo.run_cmd(["switch", to_branch])
    if verbose:
        current_head = git_repo.run_cmd(
            ["log", "--no-walk", "HEAD", "--pretty=reference"]
        )
        logger.debug("Current HEAD of %s is %s", to_branch, current_head)
    # `git merge` will return a non-zero exit status if there's a conflict, but
    # the conflict might be resolved by applying our ignore list. We work around
    # that by not checking the exist status and validating that a merge is in
    # progress after `git merge` runs.
    git_repo.run_cmd(["merge", commit_hash, "--no-commit", "--no-ff"], check=False)
    if not is_merge_in_progress(git_repo):
        raise RuntimeError("Unexpected error occurred when running git merge")
    restore_changes_to_ignored_files(git_repo, ignore_patterns, keep_patterns)
    if has_unresolved_conflicts(git_repo):
        logger.info("Merge failed")
        git_repo.run_cmd(["merge", "--abort"])
        raise MergeConflictError(commit_hash)
    git_repo.run_cmd(["commit", "--reuse-message", commit_hash])
    prefix_current_commit_message(git_repo)
    if verbose:
        merge_reference = git_repo.run_cmd(
            ["log", "--no-walk", "HEAD", "--pretty=reference"]
        )
        logger.debug("Merge commit finalized: %s", merge_reference)
    if dry_run:
        logger.info("Dry run. Skipping push into remote repository.")
    else:
        git_repo.run_cmd(["push", REMOTE_NAME, to_branch])
    logger.info("Merge successful")


def create_pull_request(git_repo: Git, to_branch: str) -> None:
    logger.info("Creating Pull Request")
    log_output = git_repo.run_cmd(
        ["log", "HEAD", "--max-count=1", "--pretty=format:%s"]
    )
    pr_title = f"Automerge conflict: {log_output}"
    subprocess.run(
        [
            "gh",
            "pr",
            "create",
            "--head",
            AUTOMERGE_BRANCH,
            "--base",
            to_branch,
            "--fill",
            "--title",
            pr_title,
            "--label",
            MERGE_CONFLICT_LABEL,
        ],
        cwd=git_repo.get_repo_path(),
        check=True,
    )


def process_conflict(
    git_repo: Git, commit_hash: str, to_branch: str, dry_run: bool
) -> None:
    logger.info("Processing conflict for %s", commit_hash)
    git_repo.run_cmd(["switch", "--force-create", AUTOMERGE_BRANCH, commit_hash])
    if dry_run:
        logger.info("Dry run, skipping push and creation of PR.")
        return
    git_repo.run_cmd(["push", REMOTE_NAME, AUTOMERGE_BRANCH])
    logger.info("Publishing Pull Request for conflict")
    create_pull_request(git_repo, to_branch)


def get_merge_commit_list(git_repo: Git, from_branch: str, to_branch: str) -> list[str]:
    logger.info(
        "Calculating list of commits to be merged from %s to %s", from_branch, to_branch
    )
    merge_base_output = git_repo.run_cmd(["merge-base", from_branch, to_branch])
    merge_base_commit = merge_base_output.strip()
    log_output = git_repo.run_cmd(
        ["log", f"{merge_base_commit}..{from_branch}", "--pretty=format:%H"]
    )
    commit_list = log_output.strip()
    if not commit_list:
        logger.info("No commits to be merged")
        return []
    commit_list = commit_list.split("\n")
    commit_list.reverse()
    logger.info("Found %d commits to be merged", len(commit_list))
    return commit_list


def pr_exist_for_label(project_name: str, label: str) -> bool:
    logger.info("Fetching list of open PRs for label '%s'.", label)
    gh_process = subprocess.run(
        ["gh", "pr", "list", "--label", label, "--repo", project_name, "--json", "id"],
        check=True,
        capture_output=True,
        text=True,
    )
    return len(json.loads(gh_process.stdout)) > 0


def is_worktree_clean(git_repo: Git) -> bool:
    # `git status --porcelain` returns an empty result if worktree is clean
    status_output = git_repo.run_cmd(["status", "--porcelain"]).strip()
    return len(status_output) == 0


def main():
    arg_parser = argparse.ArgumentParser(
        prog="automerge",
        description="A script that automatically merges individual commits from one branch into another.",
    )
    arg_parser.add_argument(
        "--project-name",
        required=True,
        metavar="OWNER/REPO",
        help="The name of the project in GitHub.",
    )
    arg_parser.add_argument(
        "--from-branch",
        required=True,
        metavar="BRANCH_NAME",
        help="The branch where the incoming commits are found.",
    )
    arg_parser.add_argument(
        "--to-branch",
        required=True,
        metavar="BRANCH_NAME",
        help="The target branch for merging incoming commits",
    )
    arg_parser.add_argument(
        "--repo-path",
        metavar="PATH",
        default=Path.cwd(),
        help="The path to the existing local checkout of the repository (default: working directory)",
    )
    arg_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Process changes locally, but don't merge them into the remote repository and don't create PRs",
    )
    arg_parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print verbose log messages during automerge run",
    )

    args = arg_parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    try:
        if pr_exist_for_label(args.project_name, MERGE_CONFLICT_LABEL):
            logger.error("There are pending automerge PRs. Cannot continue.")
            sys.exit(1)
        logger.info("No pending merge conflicts. Proceeding with automerge.")

        git_repo = Git(args.repo_path)

        if not is_worktree_clean(git_repo):
            logger.error("The repository worktree is not clean. Cannot continue.")
            sys.exit(1)

        # Parse pathspec file with negation support
        ignore_patterns, keep_patterns = parse_pathspec_file(MERGE_IGNORE_PATHSPEC_FILE)

        logger.info(f"Loaded {len(ignore_patterns)} ignore patterns")
        logger.info(f"Loaded {len(keep_patterns)} keep patterns")
        if args.verbose:
            logger.debug(f"Ignore patterns: {ignore_patterns}")
            logger.debug(f"Keep patterns: {keep_patterns}")

        merge_commits = get_merge_commit_list(
            git_repo, args.from_branch, args.to_branch
        )
        for commit_hash in merge_commits:
            merge_commit(
                git_repo,
                args.to_branch,
                commit_hash,
                ignore_patterns,
                keep_patterns,
                args.dry_run,
                args.verbose,
            )
    except MergeConflictError as conflict:
        process_conflict(
            git_repo,
            conflict.commit_hash,
            args.to_branch,
            args.dry_run,
        )
    except subprocess.CalledProcessError as error:
        logger.error(
            'Failed to run command: "%s"\nstdout:\n%s\nstderr:\n%s',
            shlex.join(error.cmd),
            error.stdout,
            error.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
