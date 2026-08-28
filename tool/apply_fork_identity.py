"""Re-assert this fork's release identity after an upstream merge.

Upstream content is merged first; this script then rewrites only the fields that
identify *where a fork user downloads and updates from*. It is deliberately
field-level: taking `assets/version.json` from upstream and rewriting the download
host keeps upstream's version numbers, build number and `version_num` corrections,
which a whole-file "keep ours" merge would have silently frozen at an old release.

Every rule declares anchors that must match. Zero matches, or a different count
than expected, is a hard failure: a restructured upstream file must stop the
pipeline rather than be skipped quietly.

    python tool/apply_fork_identity.py --check            # report only (default)
    python tool/apply_fork_identity.py --write            # rewrite files in place
    python tool/apply_fork_identity.py --only action_pins
    python tool/apply_fork_identity.py --report out.json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import fork_identity as fi

EXIT_OK = 0
EXIT_RULE_FAILURE = 1
EXIT_USAGE = 2


class RuleError(Exception):
    """An anchor was missing, ambiguous, or a protected string disappeared."""


def rel(path: Path) -> str:
    return path.relative_to(fi.ROOT).as_posix()


def read(path) -> tuple[Path, str]:
    path = Path(path)
    if not path.is_absolute():
        path = fi.ROOT / path
    return path, fi.read_text(path)


class Context:
    def __init__(self, write: bool):
        self.write = write
        self.display, self.build, self.tag = fi.release_version()
        self.rows: list[dict] = []
        self.rule = "-"

    def record(self, path: Path, changes: int, status: str) -> dict:
        row = {"rule": self.rule, "path": rel(path), "changes": changes, "status": status}
        self.rows.append(row)
        return row

    def apply_text(self, path: Path, new_text: str) -> dict:
        old_text, = (fi.read_text(path),)
        changed = old_text != new_text
        if changed and self.write:
            # Several upstream files are CRLF; rewriting them to LF would produce a
            # whole-file diff on the next sync, so the original terminator is kept.
            newline = "\r\n" if "\r\n" in (path.read_bytes()[:4096].decode("latin-1")) else "\n"
            path.write_text(new_text.replace("\n", newline), encoding="utf-8", newline="")
        return self.record(path, 1 if changed else 0, "rewritten" if changed else "already_compliant")

    def sub(self, path: Path, pattern, replacement, expected: int | None) -> dict:
        text = fi.read_text(path)
        hits = len(pattern.findall(text))
        if hits == 0:
            raise RuleError(f"{rel(path)}: anchor did not match")
        if expected is not None and hits != expected:
            raise RuleError(f"{rel(path)}: anchor matched {hits} times, expected {expected}")
        return self.apply_text(path, pattern.sub(replacement, text))


# --------------------------------------------------------------------------- rules


def rule_version_json(ctx: Context) -> None:
    path, text = read("assets/version.json")
    feed = json.loads(text)
    expected = 1 + len(feed.get("platforms", {}))
    pattern = re.compile(r'("download_url"\s*:\s*")[^"]*(")')
    ctx.sub(path, pattern, rf"\g<1>{fi.FORK_HTTPS}/releases/tag/{ctx.tag}\g<2>", expected=expected)


def rule_workflow_release_tag_default(ctx: Context) -> None:
    default_line = re.compile(r"(?m)^([ ]+)default:[ ]*(['\"]?)(v[0-9]+\.[0-9]+\.[0-9]+)\2([ ]*)$")
    for name in fi.RELEASE_TAG_WORKFLOWS:
        path, text = read(name)
        header = re.search(r"(?m)^[ ]{6}release_tag:[ ]*$", text)
        if header is None:
            raise RuleError(f"{name}: no 6-indented `release_tag:` dispatch input")
        window = text[header.end():]
        match = default_line.search(window)
        if match is None or window[: match.start()].count("\n") > 6:
            raise RuleError(f"{name}: release_tag input has no `default: vX.Y.Z` within 6 lines")
        fixed = (
            text[: header.end()]
            + window[: match.start()]
            + f"{match.group(1)}default: {match.group(2)}{ctx.tag}{match.group(2)}{match.group(4)}"
            + window[match.end():]
        )
        ctx.apply_text(path, fixed)


def rule_release_body_download_rows(ctx: Context) -> None:
    pattern = re.compile(r"(?m)^([ ]*\|[^\n|]*\|\[pure_live\]\()[^)]*(/releases/latest\)\|)$")
    for name in (".github/workflows/feature-build.yml", fi.RELEASE_WORKFLOW):
        path, _ = read(name)
        ctx.sub(path, pattern, rf"\g<1>{fi.FORK_HTTPS}\g<2>", expected=1)


def point_at_fork(ctx: Context, path: Path, pattern, expected: int, replacement) -> None:
    """Require exactly `expected` identity slots (owned by either side) and aim them at the fork.

    The anchor accepts both the fork and the upstream owner because after a rewrite
    there is nothing upstream-shaped left to match; `apply_text` records
    `already_compliant` when the substitution changes nothing, which keeps
    `--write` idempotent and `--check` honest.
    """
    text = fi.read_text(path)
    if len(list(pattern.finditer(text))) != expected:
        raise RuleError(f"{rel(path)}: expected {expected} identity slots, found {len(list(pattern.finditer(text)))}")
    ctx.apply_text(path, pattern.sub(replacement, text))


def rule_release_body_asset_hrefs(ctx: Context) -> None:
    path, _ = read(fi.RELEASE_WORKFLOW)
    pattern = re.compile(rf"https://github\.com/(?:{fi.FORK_OWNER}|{fi.UPSTREAM_OWNER})/pure_live/releases/download/")
    point_at_fork(ctx, path, pattern, 2, f"{fi.FORK_HTTPS}/releases/download/")


def rule_windows_publisher_url(ctx: Context) -> None:
    owner = f"(?:{fi.FORK_OWNER}|{fi.UPSTREAM_OWNER})"
    targets = (
        ("windows/packaging/exe/make_config.yaml", re.compile(rf"(?m)^(publisher_url: )https://github\.com/{owner}/pure_live/?$")),
        ("windows/packaging/exe/local_release.iss", re.compile(rf"(?m)^(AppPublisherURL=)https://github\.com/{owner}/pure_live/?$")),
    )
    for name, pattern in targets:
        path, _ = read(name)
        point_at_fork(ctx, path, pattern, 1, lambda m: f"{m.group(1)}{fi.FORK_HTTPS}")


def rule_huya_play_config_mirror_owner(ctx: Context) -> None:
    path, _ = read("lib/core/site/huya/huya_site.dart")
    pattern = re.compile(r"GitHubMirror\(owner: '[^']+', repo: 'pure_live', branch: 'master'\)")
    point_at_fork(
        ctx,
        path,
        pattern,
        1,
        lambda m: f"GitHubMirror(owner: '{fi.FORK_OWNER}', repo: 'pure_live', branch: 'master')",
    )


def rule_version_history_feed_source(ctx: Context) -> None:
    path, text = read("lib/modules/about/version_history.dart")
    if "import 'package:pure_live/gen/env.g.dart';" not in text:
        raise RuleError("version_history.dart: reads AppConfig but does not import gen/env.g.dart")
    wanted = (
        "GitHubMirror(\n"
        "        owner: AppConfig.pureliveUpdateOwner,\n"
        "        repo: AppConfig.pureliveUpdateRepository,\n"
        "        branch: 'master',\n"
        "      )"
    )
    appconfig_form = re.compile(
        r"GitHubMirror\(\s*owner:\s*AppConfig\.pureliveUpdateOwner,\s*repo:\s*AppConfig\.pureliveUpdateRepository,"
        r"\s*branch:\s*'master',?\s*\)"
    )
    literal_form = re.compile(r"GitHubMirror\(owner: '[^']+', repo: '[^']+', branch: 'master'\)")
    if len(appconfig_form.findall(text)) == 1:
        ctx.record(path, 0, "already_compliant")
        return
    if len(literal_form.findall(text)) != 1:
        raise RuleError(
            "version_history.dart: expected exactly 1 releases.json GitHubMirror construction "
            f"(AppConfig form {len(appconfig_form.findall(text))}, literal form {len(literal_form.findall(text))})"
        )
    ctx.sub(path, literal_form, lambda m: wanted, expected=1)


def hosted_lock_urls(text: str) -> list[int]:
    """Line indexes of `url:` entries that belong to a `source: hosted` package."""
    lines = text.split("\n")
    result = []
    for index, line in enumerate(lines):
        if line.strip() != "source: hosted":
            continue
        for back in range(index - 1, max(index - 8, -1), -1):
            match = re.match(r'^\s+url: "([^"]+)"\s*$', lines[back])
            if match:
                result.append(back)
                break
    return result


def rule_lockfile_pub_mirror_url(ctx: Context) -> None:
    allowed = {fi.PUB_MIRROR_URL, fi.PUB_DEV_URL}
    for name in fi.LOCKFILES:
        path, text = read(name)
        lines = text.split("\n")
        indexes = hosted_lock_urls("\n".join(lines))
        if not indexes:
            raise RuleError(f"{name}: no hosted package descriptors found")
        hosts = {re.search(r'"([^"]+)"', lines[i]).group(1) for i in indexes}
        unexpected = sorted(hosts - allowed)
        if unexpected:
            raise RuleError(f"{name}: hosted packages resolve from unexpected registries {unexpected}")
        changed = 0
        for index in indexes:
            new_line, count = re.subn(
                rf'^(\s+url: "){re.escape(fi.PUB_DEV_URL)}("\s*)$',
                rf"\g<1>{fi.PUB_MIRROR_URL}\g<2>",
                lines[index],
            )
            if count:
                lines[index] = new_line
                changed += 1
        ctx.record(path, 1 if changed else 0, "rewritten" if changed else "already_compliant")
        if changed and ctx.write:
            path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def rule_action_pins(ctx: Context) -> None:
    registry_path = fi.ROOT / fi.ACTION_PINS_FILE
    if not registry_path.exists():
        raise RuleError(f"{fi.ACTION_PINS_FILE} is missing")
    registry_doc = json.loads(registry_path.read_text(encoding="utf-8"))
    registry = registry_doc.get("actions")
    if not isinstance(registry, dict):
        raise RuleError(f"{fi.ACTION_PINS_FILE} has no `actions` object")
    tracked = subprocess.run(
        ["git", "-C", str(fi.ROOT), "ls-files", ".github/workflows/*.yml"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.splitlines()
    for name in tracked:
        path, text = read(name)
        pending = {}
        for match in fi.ACTION_PATTERN.finditer(text):
            repo, reference = match.group(1), match.group(2)
            if fi.SHA40_PATTERN.match(reference):
                continue
            entry = registry.get(repo, {}).get(reference)
            if not entry:
                raise RuleError(
                    f"{rel(path)}: {repo}@{reference} is not pinned to a commit and is absent from "
                    f"{fi.ACTION_PINS_FILE}. Verify the tag, then add "
                    f'"{repo}": {{"{reference}": {{"sha": "<40-hex>", "verified_at_utc": "<iso8601>"}}}}'
                )
            pending[f"{repo}@{reference}"] = (repo, reference, entry["sha"])
        if not pending:
            continue

        def replace(match):
            key = f"{match.group(1)}@{match.group(2)}"
            if key not in pending:
                return match.group(0)
            repo, reference, sha = pending[key]
            return f"uses: {repo}@{sha} # {reference}"

        ctx.apply_text(path, fi.ACTION_PATTERN.sub(replace, text))


def rule_ensure_release_sync_note(ctx: Context) -> None:
    path, text = read(fi.RELEASE_WORKFLOW)
    original = text
    input_block = (
        "      release_sync_note:\n"
        "        description: Optional note prepended to the release body (e.g. upstream sync description)\n"
        "        required: false\n"
        "        type: string\n"
        '        default: ""\n'
    )
    if "release_sync_note:" not in text:
        anchor = re.search(
            r"(?m)^[ ]{6}release_tag:[ ]*$[\s\S]{0,400}?^[ ]{8}default: ['\"]?v[0-9.]+['\"][ ]*$", text
        )
        if anchor is None:
            raise RuleError(f"{rel(path)}: cannot find the release_tag default line to follow")
        text = text[: anchor.end()] + "\n" + input_block + text[anchor.end() + 1:]
    if "${{ inputs.release_sync_note }}" not in text:
        body = re.compile(r"(cat << EOF > release_body\.txt\n)([ ]{10})# ")
        if body.search(text) is None:
            raise RuleError(f"{rel(path)}: release body heredoc anchor not found")
        text = body.sub(lambda m: f"{m.group(1)}{m.group(2)}${{{{ inputs.release_sync_note }}}}\n{m.group(2)}# ", text, count=1)
    if text == original:
        ctx.record(path, 0, "already_compliant")
    else:
        ctx.apply_text(path, text)


RULES = {
    "version_json_download_url": rule_version_json,
    "workflow_release_tag_default": rule_workflow_release_tag_default,
    "release_body_download_rows": rule_release_body_download_rows,
    "release_body_asset_hrefs": rule_release_body_asset_hrefs,
    "windows_publisher_url": rule_windows_publisher_url,
    "huya_play_config_mirror_owner": rule_huya_play_config_mirror_owner,
    "version_history_feed_source": rule_version_history_feed_source,
    "lockfile_pub_mirror_url": rule_lockfile_pub_mirror_url,
    "action_pins": rule_action_pins,
    "ensure_release_sync_note": rule_ensure_release_sync_note,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Re-assert fork release identity fields")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="report required changes without writing (default)")
    mode.add_argument("--write", action="store_true", help="rewrite files in place")
    parser.add_argument("--only", default="", help="comma separated rule ids to run")
    parser.add_argument("--skip", default="", help="comma separated rule ids to skip")
    parser.add_argument("--report", default="", help="write a JSON summary to this path")
    args = parser.parse_args(argv)

    selected = [item.strip() for item in args.only.split(",") if item.strip()]
    skipped = {item.strip() for item in args.skip.split(",") if item.strip()}
    unknown = (set(selected) | skipped) - set(RULES)
    if unknown:
        print(f"unknown rule ids: {sorted(unknown)}", file=sys.stderr)
        return EXIT_USAGE

    ctx = Context(write=args.write)
    failures = 0
    for rule_id, run in RULES.items():
        if selected and rule_id not in selected:
            continue
        if rule_id in skipped:
            continue
        ctx.rule = rule_id
        try:
            run(ctx)
        except RuleError as error:
            failures += 1
            ctx.rows.append({"rule": rule_id, "status": "failed", "detail": str(error)})
            print(f"RULE {rule_id} FAILED: {error}", file=sys.stderr)

    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(
            json.dumps(
                {"release_tag": ctx.tag, "version": ctx.display, "build_number": ctx.build,
                 "mode": "write" if args.write else "check", "passed": failures == 0, "rows": ctx.rows},
                ensure_ascii=False, indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    changed = [row for row in ctx.rows if row.get("changes")]
    print(f"apply_fork_identity: {len(RULES) - failures}/{len(RULES)} rules ok, "
          f"{len(changed)} entries to change, {failures} failures")
    return EXIT_RULE_FAILURE if failures else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
