#!/usr/bin/env python3
"""Version Info.plist and release notes together; no Node/package manager needed."""
import argparse
from datetime import date
import os
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"


def next_version(version, part="patch"):
    if not re.fullmatch(VERSION_PATTERN, version):
        raise ValueError("Version must be MAJOR.MINOR.PATCH without a prefix")
    pieces = [int(value) for value in version.split(".")]
    index = {"major": 0, "minor": 1, "patch": 2}[part]
    pieces[index] += 1
    pieces[index + 1:] = [0] * (2 - index)
    return ".".join(map(str, pieces))


def read_metadata(root=ROOT):
    with (root / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version = info["CFBundleShortVersionString"]
    if not isinstance(version, str) or not re.fullmatch(VERSION_PATTERN, version):
        raise ValueError("Invalid CFBundleShortVersionString")
    build = info["CFBundleVersion"]
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("CFBundleVersion must be a positive integer")
    return info


def validate_tag(version, tag):
    if tag and tag != "v" + version:
        raise ValueError(f"Tag {tag!r} does not match Info.plist version v{version}")


def bump(root, part="patch", notes=""):
    info = read_metadata(root)
    version = next_version(info["CFBundleShortVersionString"], part)
    changelog_path = root / "CHANGELOG.md"
    changelog = changelog_path.read_text()
    marker = "## [Unreleased]\n"
    if changelog.count(marker) != 1:
        raise ValueError("CHANGELOG.md must contain exactly one Unreleased heading")
    prefix, tail = changelog.split(marker, 1)
    boundary = re.search(r"^## \[", tail, re.MULTILINE)
    pending = tail[:boundary.start()].strip() if boundary else tail.strip()
    history = tail[boundary.start():] if boundary else ""
    release_notes = pending
    if notes.strip():
        release_notes += ("\n\n" if release_notes else "") + notes.strip()
    release_notes = release_notes or "- Maintenance release."
    updated = f"{prefix}{marker}\n## [{version}] - {date.today().isoformat()}\n\n{release_notes}\n\n{history}"
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = str(int(info["CFBundleVersion"]) + 1)
    (root / "Resources/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
    changelog_path.write_text(updated)
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("current")
    check = commands.add_parser("check")
    check.add_argument("--tag", default="")
    check.add_argument("--bundle", type=Path)
    increment = commands.add_parser("bump")
    increment.add_argument("--part", choices=["patch", "minor", "major"], default="patch")
    increment.add_argument("--notes", default=os.environ.get("RELEASE_NOTES", ""))
    commands.add_parser("notes")
    args = parser.parse_args()
    info = read_metadata()
    version = info["CFBundleShortVersionString"]
    if args.command == "current":
        print(version)
    elif args.command == "bump":
        print(bump(ROOT, args.part, args.notes))
    elif args.command == "check":
        validate_tag(version, args.tag)
        if args.bundle:
            with (args.bundle / "Contents/Info.plist").open("rb") as stream:
                built = plistlib.load(stream)
            for key in ["CFBundleShortVersionString", "CFBundleVersion"]:
                if built[key] != info[key]:
                    raise ValueError("App bundle is stale; run scripts/build.sh first")
        print(f"Version OK: {version} (build {info['CFBundleVersion']})")
    elif args.command == "notes":
        changelog = (ROOT / "CHANGELOG.md").read_text()
        match = re.search(r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)", changelog, re.MULTILINE | re.DOTALL)
        if not match:
            raise ValueError(f"Missing changelog entry for {version}")
        print(match.group(1).strip())
        print("\n---\nUniversal macOS app (macOS 13+), ad-hoc signed; not Apple notarized.\n")
        print("首次使用需自行授权辅助功能。下载文件可能受到 Gatekeeper 限制。")


if __name__ == "__main__":
    main()
