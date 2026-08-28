#!/usr/bin/env python3
"""Resolve an upstream merge commit-by-commit the way this fork merges.

The nightly sync used to resolve conflicts inside a YAML heredoc with
`git checkout --ours/--theirs` over a directory list. That had two defects this
script removes:

* `git add -A` ran *before* the unmerged-path check, which stages the conflicted
  worktree bytes (conflict markers included) and clears the unmerged index state,
  so the check could never find anything and the markers were committed;
* whole-file "keep ours" on files such as `assets/version.json` froze a stale
  version number and silently rejected upstream fixes.

Strategy is expressed per path, from the index stages, never from a directory
pathspec:

  stages 2+3  -> tier table: keep_ours, or take upstream (identity fields are
                 re-asserted afterwards by apply_fork_identity.py)
  stage 2     -> keep our side (upstream deleted a fork-only addition)
  stage 3     -> abort (upstream added a path this fork deliberately removed)
  stages 1+2  -> abort (upstream deleted a file this fork modified: the shape of
                 a lost lifecycle hook or a removed wiring)
  stages 1+3  -> abort (this fork deleted a file upstream then changed)
  stage 1     -> both deleted: drop the path
Anything else, and symlinks/gitlinks, aborts too. `--allow-unknown-theirs`
downgrades only the three abort cases; it never overrides a tier decision.

Exit codes: 0 resolved, 78 unclassifiable (caller must abort the merge), 1 tooling
or conflict-marker failure.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import fork_identity as fi

EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_UNCLASSIFIABLE = 78

STAGE_NAMES = {1: "base", 2: "ours", 3: "theirs"}


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(fi.ROOT), *args], capture_output=True, check=check)


def unmerged_entries() -> dict[str, dict[int, tuple[str, str]]]:
    """`git ls-files -u -z` grouped per path: stage -> (mode, object id)."""
    raw = git("ls-files", "-u", "-z").stdout
    entries: dict[str, dict[int, tuple[str, str]]] = {}
    for record in raw.split(b"\0"):
        if not record:
            continue
        meta, _, path = record.partition(b"\t")
        mode, sha, stage = meta.decode().split(" ", 2)
        entries.setdefault(path.decode("utf-8", "surrogateescape"), {})[int(stage)] = (mode, sha)
    return entries


def blob_size(diff_range: str, path: str) -> int:
    """Lines upstream changed in `path`, used to size what a keep-ours drops."""
    out = git("diff", "--numstat", diff_range, "--", path, check=False)
    text = out.stdout.decode("utf-8", "replace").strip()
    if not text:
        return 0
    added, deleted, _ = text.split("\t", 2)
    if "-" in (added, deleted):
        return 1  # binary: worth reviewing, but line counts are meaningless
    return int(added) + int(deleted)


def take_side(path: str, stage: int) -> None:
    side = "--ours" if stage == 2 else "--theirs"
    git("checkout", side, "--", path)
    git("add", "--", path)


def drop_path(path: str) -> None:
    git("rm", "-f", "--ignore-unmatch", "--", path, check=False)


def scan_for_markers(paths: list[str]) -> list[str]:
    offenders = []
    for path in paths:
        target = fi.ROOT / path
        if not target.is_file():
            continue
        data = target.read_bytes()
        if b"\0" in data[:8192]:
            continue
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            continue
        if fi.CONFLICT_PATTERN.search(text):
            offenders.append(path)
    return offenders


def resolve(base: str, upstream: str, allow_unknown_theirs: bool) -> tuple[int, dict]:
    diff_range = f"{base}..{upstream}"
    entries = unmerged_entries()
    decisions: list[dict] = []
    abort_reason = ""
    touched: list[str] = []

    for path, stages in sorted(entries.items()):
        stage_set = set(stages)
        modes = {mode for mode, _ in stages.values()}
        record = {"path": path, "stages": sorted(STAGE_NAMES[s] for s in stage_set)}

        if "120000" in modes or "160000" in modes:
            record.update(action="abort", detail="symlink or submodule entry")
            abort_reason = abort_reason or f"{path}: symlink/gitlink conflict needs manual resolution"
            decisions.append(record)
            continue

        if stage_set == {1}:
            record.update(action="drop", detail="deleted by both sides")
            drop_path(path)
        elif {2, 3} <= stage_set:
            # Both sides have content: the ordinary both-modified conflict carries
            # the base stage as well, so this must be tested before the partial sets.
            tier = fi.tier_of(path)
            if tier == "keep_ours":
                dropped = blob_size(diff_range, path)
                record.update(action="keep_ours", tier=tier, dropped_upstream_lines=dropped)
                take_side(path, 2)
            else:
                record.update(action="take_theirs", tier=tier)
                take_side(path, 3)
                touched.append(path)
        elif stage_set == {2}:
            record.update(action="keep_ours", detail="added by us, deleted by upstream")
            take_side(path, 2)
        elif stage_set == {3}:
            record.update(action="abort", detail="added by upstream, deleted by this fork")
            abort_reason = abort_reason or f"{path}: upstream re-added a path this fork removed"
        elif stage_set == {1, 2}:
            if allow_unknown_theirs:
                record.update(action="accept_upstream_deletion", detail="unreviewed", unreviewed=True)
                drop_path(path)
            else:
                record.update(action="abort", detail="modified by us, deleted by upstream")
                abort_reason = abort_reason or f"{path}: upstream deleted a file this fork modified"
        elif stage_set == {1, 3}:
            if allow_unknown_theirs:
                record.update(action="take_theirs", detail="unreviewed", unreviewed=True)
                take_side(path, 3)
                touched.append(path)
            else:
                record.update(action="abort", detail="deleted by us, modified by upstream")
                abort_reason = abort_reason or f"{path}: upstream changed a file this fork deleted"
        else:
            record.update(action="abort", detail=f"unhandled stage combination {sorted(stage_set)}")
            abort_reason = abort_reason or f"{path}: unhandled conflict shape {sorted(stage_set)}"
        decisions.append(record)

    report = {
        "base": base,
        "upstream": upstream,
        "allow_unknown_theirs": allow_unknown_theirs,
        "unmerged_paths": len(entries),
        "abort_reason": abort_reason,
        "decisions": decisions,
        "conflict_markers": [],
    }

    leftover = sorted(unmerged_entries())
    if leftover and not abort_reason:
        abort_reason = f"paths still unmerged: {leftover[:5]}"
    report["leftover_unmerged"] = leftover
    if not abort_reason:
        markers = scan_for_markers([d["path"] for d in decisions if d.get("action", "").startswith(("take", "keep"))])
        report["conflict_markers"] = markers
        if markers:
            return EXIT_FAILURE, report
    return (EXIT_UNCLASSIFIABLE if abort_reason else EXIT_OK), report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Resolve an upstream merge for this fork")
    parser.add_argument("--base", required=True, help="merge base commit")
    parser.add_argument("--upstream", required=True, help="upstream commit being merged")
    parser.add_argument("--report", default="", help="write the decision ledger to this JSON path")
    parser.add_argument(
        "--allow-unknown-theirs",
        action="store_true",
        help="take upstream for deletion/renaming conflicts instead of aborting",
    )
    args = parser.parse_args(argv)

    code, report = resolve(args.base, args.upstream, args.allow_unknown_theirs)
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for decision in report["decisions"]:
        print("%-26s %-28s %s" % (decision["action"], decision["path"], decision.get("detail", "")))
    if report["conflict_markers"]:
        print("CONFLICT MARKERS left in staged content: %s" % report["conflict_markers"], file=sys.stderr)
    if report["abort_reason"]:
        print(f"UNCLASSIFIABLE: {report['abort_reason']}", file=sys.stderr)

    dropped = [d for d in report["decisions"] if d.get("dropped_upstream_lines")]
    print(f"merge_upstream: {report['unmerged_paths']} unmerged paths, "
          f"{len([d for d in report['decisions'] if d['action'] == 'take_theirs'])} took upstream, "
          f"{len(dropped)} kept fork side (upstream lines dropped: {sum(d['dropped_upstream_lines'] for d in dropped)})")
    return code


if __name__ == "__main__":
    sys.exit(main())
