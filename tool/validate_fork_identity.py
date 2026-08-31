#!/usr/bin/env python3
"""Assert this fork's identity and feature invariants.

Upstream ships `tool/validate_build_policy.ps1` and `tool/audit_repository.py`,
but both encode the *upstream* repository's identity (they require `download_url`
and `.env.prod` to say `liuchuancong`), so neither can ever pass here. This
checker asserts the fork's own invariants instead, and is what the nightly sync
job gates on before it dares to push to `master`.

    python tool/validate_fork_identity.py
    python tool/validate_fork_identity.py --github-annotations --output report.json

Exit codes: 0 clean, 1 violations found, 2 usage or unreadable repository.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import apply_fork_identity as apply_rules
import fork_identity as fi

EXIT_OK = 0
EXIT_VIOLATIONS = 1
EXIT_USAGE = 2

GH_ANNOTATION = re.compile(r"(?m)^[ ]*gh workflow run (\S+)[\s\S]{0,800}?(-f ([A-Za-z0-9_]+=)+)")
DISPATCH_INPUT = re.compile(r"-f\s+([A-Za-z0-9_]+)=")


class Report:
    def __init__(self) -> None:
        self.checks: list[dict] = []
        self.errors: list[dict] = []
        self.warnings: list[dict] = []

    def check(self, rule: str, target: str, detail: str = "", ok: bool = True) -> None:
        self.checks.append({"rule": rule, "target": target, "status": "pass" if ok else "fail", "detail": detail})
        if not ok:
            self.errors.append({"rule": rule, "path": target, "detail": detail})

    def warn(self, rule: str, target: str, detail: str) -> None:
        self.warnings.append({"rule": rule, "path": target, "detail": detail})


def tracked_files(pattern: str = "") -> list[str]:
    out = subprocess.run(["git", "-C", str(fi.ROOT), "ls-files", *([pattern] if pattern else [])],
                         capture_output=True, text=True, encoding="utf-8").stdout
    return [line for line in out.splitlines() if line]


def check_update_owner(report: Report) -> None:
    for name in (".env", ".env.dev", ".env.prod"):
        text = fi.read_text(Path(name))
        ok = f"PURELIVE_UPDATE_OWNER={fi.FORK_OWNER}" in text and f"PURELIVE_UPDATE_REPOSITORY={fi.FORK_REPO}" in text
        report.check("V1_update_owner", name, f"expected {fi.FORK_OWNER}/{fi.FORK_REPO}", ok)
    generated = fi.read_text(Path("lib/gen/env.g.dart"))
    ok = (f"pureliveUpdateOwner = '{fi.FORK_OWNER}'" in generated
          and f"pureliveUpdateRepository = '{fi.FORK_REPO}'" in generated)
    report.check("V2_generated_env", "lib/gen/env.g.dart", "generated AppConfig must target the fork", ok)


def check_version_identity(report: Report) -> None:
    display, build, tag = fi.release_version()
    feed = json.loads(fi.read_text(Path("assets/version.json")))
    blocks = {"top-level": feed} | dict(feed.get("platforms", {}))
    for name, block in blocks.items():
        report.check(
            "V3_version_feed", f"assets/version.json:{name}",
            f"version {block.get('version')} build {block.get('build_number')} must be {display}/{build}",
            str(block.get("version")) == display and int(block.get("build_number", -1)) == build,
        )
        url = str(block.get("download_url", ""))
        report.check("V3_download_url", f"assets/version.json:{name}",
                     f"download_url must point at the fork release {tag}",
                     url == f"{fi.FORK_HTTPS}/releases/tag/{tag}", )
    msix = fi.read_text(Path("windows/packaging/msix/make_config.yaml"))
    report.check("V4_msix_version", "windows/packaging/msix/make_config.yaml",
                 f"msix_version must be {display}.{build}",
                 re.search(rf"(?m)^msix_version:\s*{re.escape(display)}\.{build}\s*$", msix) is not None)
    for name in fi.RELEASE_TAG_WORKFLOWS:
        text = fi.read_text(Path(name))
        report.check("V4_workflow_tag", name, f"release_tag default must be {tag}",
                     re.search(rf"(?m)^[ ]+default:[ ]*['\"]?{re.escape(tag)}['\"]?[ ]*$", text) is not None)


def check_action_pins(report: Report) -> None:
    registry = json.loads((fi.ROOT / fi.ACTION_PINS_FILE).read_text(encoding="utf-8")).get("actions", {})
    reverse: dict[str, set[str]] = {}
    for repo, versions in registry.items():
        for version, entry in versions.items():
            reverse.setdefault(f"{repo}@{entry['sha']}", set()).add(version)
    for name in tracked_files(".github/workflows/*.yml"):
        text = fi.read_text(Path(name))
        for match in fi.ACTION_PATTERN.finditer(text):
            repo, reference = match.group(1), match.group(2)
            if not fi.SHA40_PATTERN.match(reference):
                report.check("V5_action_pin", name, f"{repo}@{reference} is not pinned to a commit", False)
                continue
            if f"{repo}@{reference}" not in reverse:
                report.check("V5_action_registry", name,
                             f"{repo}@{reference} is not recorded in {fi.ACTION_PINS_FILE}", False)


def check_lockfiles(report: Report) -> None:
    for name in fi.LOCKFILES:
        text = fi.read_text(Path(name))
        lines = text.split("\n")
        indexes = apply_rules.hosted_lock_urls(text)
        hosts = {re.search(r'"([^"]+)"', lines[i]).group(1) for i in indexes}
        report.check("V6_lockfile_registry", name,
                     f"hosted packages must resolve from the fork mirror, found {sorted(hosts)}",
                     bool(hosts) and hosts == {fi.PUB_MIRROR_URL})


def check_dispatch_contract(report: Report) -> None:
    """Every `-f key=` a workflow passes must be declared by the workflow it dispatches."""
    for name in tracked_files(".github/workflows/*.yml"):
        text = fi.read_text(Path(name))
        for block in re.finditer(r"(?m)gh workflow run (\S+)([\s\S]{0,1200})", text):
            target, body = block.group(1), block.group(2)
            target_path = fi.ROOT / ".github" / "workflows" / target
            if not target_path.exists():
                report.check("V8_dispatch_inputs", name, f"dispatches unknown workflow {target}", False)
                continue
            passed = set(DISPATCH_INPUT.findall(body.split("\n\n")[0] if "\n\n" in body else body))
            declared = fi.workflow_inputs(target_path)
            missing = sorted(passed - declared)
            report.check("V8_dispatch_inputs", f"{name} -> {target}",
                         f"undeclared inputs {missing}; workflow declares {sorted(declared)}" if missing
                         else f"{len(passed)} inputs declared", not missing)


def check_fork_features(report: Report) -> None:
    for marker in ("lib/modules/multiview/multiview_page.dart", "lib/modules/account/web_cookie_capture.dart",
                   "lib/player/utils/pip_window_widget.dart", "test/multiview_test.dart"):
        report.check("V9_fork_feature", marker, "fork-only file must exist", (fi.ROOT / marker).exists())
    for symbol, declaring_file in fi.MUST_HAVE_CALLERS.items():
        users = [p for p in tracked_files("lib/*.dart")
                 if p != declaring_file and re.search(rf"\b{symbol}\(", fi.read_text(Path(p)))]
        report.check("V10_wiring", symbol,
                     f"declared in {declaring_file} but never called; upstream deleted its only caller once already",
                     bool(users))


def check_protected_upstream(report: Report) -> None:
    for name, anchor in fi.MUST_STAY_UPSTREAM.items():
        path = fi.ROOT / name
        if not path.exists():
            continue
        ok = re.search(anchor, fi.read_text(path)) is not None
        report.check("V12_upstream_preserved", name, f"must keep {anchor!r} (this fork does not host it)", ok)


def check_conflict_markers(report: Report, staged: bool) -> None:
    if staged:
        for path in subprocess.run(["git", "-C", str(fi.ROOT), "ls-files", "-u"],
                                   capture_output=True, text=True).stdout.splitlines():
            if path:
                report.check("V11_unmerged", path, "path is still unmerged in the index", False)
    suffixes = {".dart", ".yml", ".yaml", ".json", ".md", ".ps1", ".py", ".kts", ".gradle",
                ".xml", ".sh", ".iss", ".txt", ".txt"}
    for name in tracked_files():
        path = fi.ROOT / name
        if not path.is_file() or path.suffix.lower() not in suffixes:
            continue
        data = path.read_bytes()
        if b"\0" in data[:8192]:
            continue
        if fi.CONFLICT_PATTERN.search(data.decode("utf-8-sig", "replace")):
            report.check("V11_conflict_markers", name, "conflict marker present", False)


def check_identity_drift(report: Report) -> None:
    """Re-run the rewrite rules in check mode: any pending change is drift."""
    ctx = apply_rules.Context(write=False)
    for rule_id, run in apply_rules.RULES.items():
        ctx.rule = rule_id
        try:
            run(ctx)
        except apply_rules.RuleError as error:
            report.check("V0_identity_rule", rule_id, str(error), False)
    for row in ctx.rows:
        if row.get("changes"):
            report.check("V0_identity_rule", row["rule"], f"{row['path']} needs re-application")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate this fork's identity invariants")
    parser.add_argument("--output", default="", help="write a JSON report to this path")
    parser.add_argument("--github-annotations", action="store_true", help="emit ::error:: lines for Actions logs")
    parser.add_argument("--staged", action="store_true", help="also scan index entries for conflict markers")
    args = parser.parse_args(argv)

    report = Report()
    try:
        check_update_owner(report)
        check_version_identity(report)
        check_action_pins(report)
        check_lockfiles(report)
        check_dispatch_contract(report)
        check_fork_features(report)
        check_protected_upstream(report)
        check_identity_drift(report)
        check_conflict_markers(report, staged=args.staged)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"validate_fork_identity could not run: {error}", file=sys.stderr)
        return EXIT_USAGE

    payload = {
        "schema_version": 1,
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_commit": subprocess.run(["git", "-C", str(fi.ROOT), "rev-parse", "HEAD"],
                                        capture_output=True, text=True).stdout.strip(),
        "checks": report.checks,
        "errors": report.errors,
        "warnings": report.warnings,
        "passed": not report.errors,
        "fingerprint": hashlib.sha256(
            json.dumps([c["status"] + c["target"] for c in report.checks], sort_keys=True).encode()
        ).hexdigest(),
    }
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for error in report.errors:
        line = f"{error['rule']} {error['path']}: {error['detail']}"
        if args.github_annotations:
            print(f"::error::{line}")
        else:
            print(line)
    print(f"validate_fork_identity: {len(report.checks)} checks, {len(report.errors)} errors, "
          f"{len(report.warnings)} warnings")
    return EXIT_OK if not report.errors else EXIT_VIOLATIONS


if __name__ == "__main__":
    sys.exit(main())
