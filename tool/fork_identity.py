"""Single source of truth for this maintenance fork's identity invariants.

`yanxiatao/pure_live` merges upstream `liuchuancong/pure_live` on a schedule. Two
properties have to survive every one of those merges: upstream's implementation
wins everywhere, and this fork's release identity plus its own feature modules
stay intact. Only the owner can notice when a merge quietly breaks the second
half, so the rules live here and `apply_fork_identity.py` /
`validate_fork_identity.py` / `merge_upstream.py` all read them from this module
instead of each keeping a copy that can drift.

Upstream's own checkers cannot be reused for this: `tool/validate_build_policy.ps1`
asserts `download_url` and `.env.prod` equal `liuchuancong`, which is the opposite
of what this fork needs.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FORK_OWNER = "yanxiatao"
FORK_REPO = "pure_live"
UPSTREAM_OWNER = "liuchuancong"
UPSTREAM_REPO = "pure_live"
UPSTREAM_REMOTE_URL = "https://github.com/liuchuancong/pure_live.git"
FORK_HTTPS = f"https://github.com/{FORK_OWNER}/{FORK_REPO}"
UPSTREAM_HTTPS = f"https://github.com/{UPSTREAM_OWNER}/{UPSTREAM_REPO}"

# tool/flutterw.ps1 forces this host unless PUB_HOSTED_URL is already set, so a
# committed lockfile that records pub.dev cannot be re-resolved with
# --enforce-lockfile on the maintainer's machine.
PUB_MIRROR_URL = "https://mirrors.cloud.tencent.com/dart-pub/"
PUB_DEV_URL = "https://pub.dev"
LOCKFILES = ("pubspec.lock", "plugins/flame_barrage/pubspec.lock")

# Workflows that expose a manual `release_tag` dispatch input. Their defaults must
# match pubspec.yaml, otherwise a dispatch without an explicit tag publishes a
# GitHub Release whose name disagrees with the shipped binary.
RELEASE_TAG_WORKFLOWS = (
    ".github/workflows/feature-build.yml",
    ".github/workflows/build_pure_live_release.yml",
    ".github/workflows/publish-staged-release.yml",
    ".github/workflows/stage-hosted-artifacts.yml",
)

# The fork's nightly release path. Upstream maintains this file for its own
# repository and drops the input this fork's automation passes to it.
RELEASE_WORKFLOW = ".github/workflows/build_pure_live_release.yml"

# Files whose *content* comes from upstream, but whose release/download identity
# fields this fork must re-assert after the merge. Resolving these with a whole
# file "keep ours" would freeze a stale version number and discard upstream fixes.
THEIRS_THEN_REWRITE = (
    "assets/version.json",
    "windows/packaging/exe/make_config.yaml",
    "windows/packaging/exe/local_release.iss",
    "lib/core/site/huya/huya_site.dart",
    "lib/modules/about/version_history.dart",
    RELEASE_WORKFLOW,
    *RELEASE_TAG_WORKFLOWS,
    *LOCKFILES,
)

# Fork-only implementation. Upstream has no equivalent behaviour, so an overlap
# here means upstream touched something this fork owns; keeping our side is the
# product invariant, and merge_upstream.py records how many upstream bytes were
# dropped so the next human review can look at exactly those hunks.
KEEP_OURS = (
    ".env",
    ".env.dev",
    ".env.prod",
    "lib/gen/env.g.dart",
    "lib/modules/multiview",
    "lib/modules/account",
    "lib/modules/version",
    "lib/core/common/web_socket_util.dart",
    "lib/core/site/twitch",
    "lib/common/services/settings/cookie_settings_controller.dart",
    "lib/common/services/settings/proxy_settings_controller.dart",
    "lib/player/utils/pip_window_widget.dart",
    "lib/player/utils/window_helper.dart",
    "test/multiview_test.dart",
    "test/release_asset_urls_test.dart",
    "README.md",
    ".github/workflows/sync-upstream.yml",
    ".github/workflows/sign-staged-android.yml",
    ".github/workflows/publish-signed-android.yml",
    ".github/workflows/local-signed-android.yml",
    "tool/flutterw.ps1",
    "tool/build_local_release.ps1",
    "tool/fork_identity.py",
    "tool/apply_fork_identity.py",
    "tool/validate_fork_identity.py",
    "tool/merge_upstream.py",
    "tool/action_pins.json",
)

# Upstream-owned references that must NOT be rewritten to the fork: this fork does
# not host those repositories or release assets, so replacing them produces 404s.
# validate_fork_identity.py asserts each anchor is still present.
MUST_STAY_UPSTREAM = {
    "assets/releases.json": rf"{UPSTREAM_HTTPS}",
    "pubspec.yaml": r"url: https://github\.com/liuchuancong/screen_retriever\.git",
    "lib/plugins/font_download_manager.dart": r"repo: 'fonts'",
    "lib/common/models/release_model.dart": rf"name: '{UPSTREAM_OWNER}'",
    ".github/ISSUE_TEMPLATE/config.yml": rf"{UPSTREAM_HTTPS}/issues/new/choose",
}

# Fork features whose wiring a merge can silently disconnect. Each symbol must be
# referenced somewhere in lib/ outside the file that declares it; upstream deleted
# the WidgetsBindingObserver in video_player.dart once already, which turned these
# two PlayerManager methods into uncalled dead code.
MUST_HAVE_CALLERS = {
    "commitAudioOnlyPowerSaving": "lib/player/core/player_manager.dart",
    "prepareAudioOnlyVideoRestore": "lib/player/core/player_manager.dart",
}

# Registry of action references verified by a maintainer: repo -> version tag ->
# 40-character commit. Keeping the mapping in a file (rather than resolving tags at
# build time) means an automated merge can never silently upgrade an action.
ACTION_PINS_FILE = "tool/action_pins.json"

# Patterns shared with tool/audit_repository.py so the fixer and the whole-repo
# auditor cannot disagree about what counts as pinned or as a conflict marker.
ACTION_PATTERN = re.compile(r"\buses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([^\s#]+)")
SHA40_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")
CONFLICT_PATTERN = re.compile(r"^(?:<{7}(?: .*)?|={7}|>{7}(?: .*)?)$", re.MULTILINE)
PUBSPEC_VERSION = re.compile(r"(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$")


def read_text(path: Path) -> str:
    """Read a repository text file.

    `.env*` are written with a UTF-8 BOM, which silently breaks a leading `^`
    anchor in a multiline regex unless the signature is stripped here.
    """
    return (ROOT / path).read_text(encoding="utf-8-sig")


def read_bytes(path: Path) -> bytes:
    return (ROOT / path).read_bytes()


def release_version() -> tuple[str, int, str]:
    """Return `(display version, build number, release tag)` from pubspec.yaml."""
    match = PUBSPEC_VERSION.search(read_text(Path("pubspec.yaml")))
    if match is None:
        raise ValueError("pubspec.yaml must expose `version: X.Y.Z+N`")
    return match.group(1), int(match.group(2)), f"v{match.group(1)}"


def tier_of(path: str) -> str:
    """Classify a conflicted path into the merge strategy that owns it."""
    if any(path == prefix or path.startswith(prefix.rstrip("/") + "/") for prefix in KEEP_OURS):
        return "keep_ours"
    if path in THEIRS_THEN_REWRITE:
        return "rewrite_after_upstream"
    return "upstream"


def workflow_inputs(path: Path) -> set[str]:
    """Names declared under `on.workflow_dispatch.inputs` of a workflow file."""
    inputs: set[str] = set()
    in_inputs = False
    indent = 0
    for line in read_text(path).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        current = len(line) - len(line.lstrip())
        if stripped == "inputs:":
            in_inputs = True
            indent = current
            continue
        if in_inputs:
            if current <= indent:
                break
            if current == indent + 2 and stripped.endswith(":"):
                inputs.add(stripped[:-1].strip())
    return inputs
