#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, json, os, subprocess, sys, textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

PY_MIN = (3, 8)
if sys.version_info < PY_MIN:
    print(f"Python {PY_MIN[0]}.{PY_MIN[1]}+ is required.", file=sys.stderr)
    sys.exit(2)

def sh(*cmd: str, cwd: Optional[Path] = None, check: bool = False, capture: bool = False):
    return subprocess.run(cmd, cwd=str(cwd) if cwd else None,
                          text=True, capture_output=capture, check=check)

def git(*args: str, cwd: Path, check: bool = False, capture: bool = False):
    return sh("git", *args, cwd=cwd, check=check, capture=capture)

def load_yaml(path: Path) -> dict:
    # JSON-in-YAML
    import re
    content = path.read_text(encoding="utf-8")
    lines = [ln for ln in content.splitlines() if not ln.strip().startswith("#")]
    try:
        return json.loads("\n".join(lines))
    except json.JSONDecodeError:
        raise SystemExit(f"Use JSON-compatible YAML for {path} or switch to a YAML parser.")

def compute_series_hash(files: List[Path]) -> str:
    h = hashlib.sha256()
    for p in files:
        h.update(p.name.encode())
        h.update(p.read_bytes())
    return h.hexdigest()[:12]

@dataclass
class PatchSet:
    name: str
    repo: Path
    patch_dir: Path
    method: str
    three_way: bool
    restore_on_fail: bool
    ignore_whitespace: bool
    reset_to: str
    ensure_identity: Optional[dict]

@dataclass
class RepoSnapshot:
    head: str

STATE_DIR = Path(".git") / "patchctl"
STATE_FILE = STATE_DIR / "state.json"

def collect_patches(d: Path) -> List[Path]:
    if not d.exists():
        return []
    return sorted([p for p in d.glob("*.patch") if p.is_file()])

def preflight_apply_check(repo: Path, patches: List[Path], three_way: bool, ignore_ws: bool) -> bool:
    # Dry-run using 'git apply --check' for each patch
    for patch in patches:
        cmd = ["apply", "--check"]
        if ignore_ws: cmd.append("--ignore-whitespace")
        if three_way: cmd.append("--3way")
        cmd.append(str(patch))
        rc = git(*cmd, cwd=repo).returncode
        if rc != 0:
            print(f"[preflight] {repo} would fail on: {patch.name}")
            return False
    return True

def read_state(repo: Path) -> dict:
    f = repo / STATE_FILE
    if f.exists():
        try:
            return json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}

def write_state(repo: Path, data: dict):
    f = repo / STATE_FILE
    (repo / STATE_DIR).mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, indent=2), encoding="utf-8")

def snapshot_repo(repo: Path) -> RepoSnapshot:
    head = git("rev-parse", "HEAD", cwd=repo, capture=True).stdout.strip()
    return RepoSnapshot(head=head)

def reset_repo(repo: Path, to: str):
    git("reset", "--hard", to, cwd=repo, check=True)
    git("clean", "-fdx", cwd=repo, check=True)

def already_applied(repo: Path, patchset_name: str, series_hash: str) -> bool:
    st = read_state(repo)
    return st.get("patchsets", {}).get(patchset_name, "") == series_hash

def stamp_applied(repo: Path, patchset_name: str, series_hash: str):
    st = read_state(repo)
    ps = st.get("patchsets", {})
    ps[patchset_name] = series_hash
    st["patchsets"] = ps
    write_state(repo, st)

def apply_with_am(repo: Path, patches: List[Path], three_way: bool, ignore_ws: bool) -> int:
    args = ["am", "-k"]
    if three_way: args.append("--3way")
    if ignore_ws: args.append("--ignore-whitespace")
    args += [str(p) for p in patches]
    r = git(*args, cwd=repo, capture=True)
    sys.stdout.write(r.stdout or "")
    sys.stderr.write(r.stderr or "")
    if r.returncode != 0:
        # try abort if needed
        git("am", "--abort", cwd=repo)
    return r.returncode

def apply_with_apply(repo: Path, patches: List[Path], three_way: bool, ignore_ws: bool) -> int:
    applied: List[Path] = []
    for p in patches:
        check = ["apply", "--check"]
        if ignore_ws: check.append("--ignore-whitespace")
        if three_way: check.append("--3way")
        check.append(str(p))
        if git(*check, cwd=repo).returncode != 0:
            if applied:
                # rollback
                for prev in reversed(applied):
                    rev = ["apply", "--reverse"]
                    if ignore_ws: rev.append("--ignore-whitespace")
                    if three_way: rev.append("--3way")
                    rev.append(str(prev))
                    git(*rev, cwd=repo)
            return 1
        # apply
        args = ["apply"]
        if ignore_ws: args.append("--ignore-whitespace")
        if three_way: args.append("--3way")
        args.append(str(p))
        if git(*args, cwd=repo).returncode != 0:
            return 1
        applied.append(p)
    # stage and commit to make changes durable
    git("add", "-A", cwd=repo, check=True)
    msg = f"patchctl: applied {len(applied)} patches"
    git("commit", "-m", msg, cwd=repo, check=True)
    return 0

def parse_manifest(mpath: Path) -> List[PatchSet]:
    doc = load_yaml(mpath)
    defaults = doc.get("defaults", {})
    defm = defaults.get("method", "am")
    thw = bool(defaults.get("three_way", True))
    rof = bool(defaults.get("restore_on_fail", True))
    igw = bool(defaults.get("ignore_whitespace", True))
    ident = defaults.get("ensure_identity", None)
    out: List[PatchSet] = []
    base = mpath.parent
    for ps in doc.get("patchsets", []):
        out.append(PatchSet(
            name=ps["name"],
            repo=(base / ps["repo"]).resolve(),
            patch_dir=(base / ps["patches"]).resolve(),
            method=ps.get("method", defm),
            three_way=bool(ps.get("three_way", thw)),
            restore_on_fail=bool(ps.get("restore_on_fail", rof)),
            ignore_whitespace=bool(ps.get("ignore_whitespace", igw)),
            reset_to=str(ps.get("reset_to", "") or ""),
            ensure_identity=ps.get("ensure_identity", ident),
        ))
    return out

def cmd_apply(manifest: Path) -> int:
    patchsets = parse_manifest(manifest)

    # Collect all patches and preflight across repos first (transaction-friendly).
    repo_to_data = []
    for ps in patchsets:
        if not (ps.repo / ".git").exists():
            print(f"[error] Not a git repo: {ps.repo}")
            return 2
        patches = collect_patches(ps.patch_dir)
        if not patches:
            print(f"[info] no patches for {ps.name} at {ps.patch_dir} — skipping")
            continue
        series_hash = compute_series_hash(patches)
        if already_applied(ps.repo, ps.name, series_hash):
            print(f"[skip] {ps.name} already applied (series {series_hash})")
            continue
        if ps.reset_to:
            print(f"[info] resetting {ps.name} to {ps.reset_to}")
        snap = snapshot_repo(ps.repo)
        repo_to_data.append((ps, patches, series_hash, snap))

    # preflight all
    for (ps, patches, _, _) in repo_to_data:
        if ps.reset_to:
            reset_repo(ps.repo, ps.reset_to)
        if ps.ensure_identity:
            ensure_identity(ps.repo, ps.ensure_identity)
        if not preflight_apply_check(ps.repo, patches, ps.three_way, ps.ignore_whitespace):
            print(f"[preflight] failed for {ps.name}. Aborting.")
            # restore any resets
            for (pps, _, __, snap) in repo_to_data:
                reset_repo(pps.repo, snap.head)
            return 1

    # apply, transactional across repos
    applied_ok: List[tuple[PatchSet, str, RepoSnapshot]] = []
    for (ps, patches, series_hash, snap) in repo_to_data:
        print(f"[apply] {ps.name}: {len(patches)} patches via {ps.method}")
        rc = apply_with_am(ps.repo, patches, ps.three_way, ps.ignore_whitespace) \
             if ps.method == "am" else \
             apply_with_apply(ps.repo, patches, ps.three_way, ps.ignore_whitespace)

        if rc != 0:
            print(f"[fail] {ps.name} (rc={rc}). Rolling back previously-applied repos...")
            # rollback those already done
            for (done_ps, _, done_snap) in applied_ok:
                reset_repo(done_ps.repo, done_snap.head)
            # and rollback this one
            reset_repo(ps.repo, snap.head)
            return rc
        # success
        stamp_applied(ps.repo, ps.name, series_hash)
        applied_ok.append((ps, series_hash, snap))
        print(f"[ok] {ps.name} applied (series {series_hash})")

    print("[done] all patchsets applied")
    return 0

def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(
        prog="patchctl",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=textwrap.dedent("""
        patchctl — cross-platform patch orchestrator for multi-repo workspaces.

        Typical usage:
          patchctl apply -f embedded/patchsets.yaml
        """)
    )
    sub = p.add_subparsers(dest="cmd", required=True)
    p_apply = sub.add_parser("apply", help="Apply patchsets defined in the manifest")
    p_apply.add_argument("-f", "--file", required=True, type=Path, help="Manifest path (YAML/JSON)")
    args = p.parse_args(argv)

    if args.cmd == "apply":
        return cmd_apply(args.file)

    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

