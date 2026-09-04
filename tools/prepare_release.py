#!/usr/bin/env python3
"""Prepare a release consistently across the Alpine RedPill source tree.

The tool updates both functions files, writes their three release-history views,
and creates English and Korean release-note files. History summaries deliberately
allow only letters, digits, and whitespace so shell heredocs and workflow commit
messages cannot receive punctuation or control characters from release input.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FUNCTION_FILES = (ROOT / "functions.sh", ROOT / "functions_t.sh")
RELEASE_NOTES_DIR = ROOT / "release-notes"
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+\.\d+$")
DATE_PATTERN = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")


def fail(message: str) -> None:
    raise ValueError(message)


def validate_version(value: str) -> str:
    if not VERSION_PATTERN.fullmatch(value):
        fail("version must use four numeric components, for example 1.4.2.7")
    return value


def validate_build_date(value: str) -> str:
    if not DATE_PATTERN.fullmatch(value):
        fail("build date must use YYYY.MM.DD, for example 2026.08.07")
    try:
        dt.datetime.strptime(value, "%Y.%m.%d")
    except ValueError as error:
        fail(f"invalid build date: {error}")
    return value


def validate_history_summary(label: str, value: str) -> str:
    summary = " ".join(value.split())
    if not summary:
        fail(f"{label} history summary is empty")
    if any(not (character.isalnum() or character.isspace()) for character in summary):
        fail(
            f"{label} history summary contains a special character; "
            "use only letters numbers and spaces"
        )
    return summary


def read_release_body(path: Path | None, fallback: str, language: str) -> str:
    if path is None:
        return fallback + "\n"
    if not path.is_file():
        fail(f"{language} release-note file does not exist: {path}")
    body = path.read_text(encoding="utf-8").strip()
    if not body:
        fail(f"{language} release-note file is empty: {path}")
    return body + "\n"


def history_comment(date: str, version: str, summary: str) -> str:
    lines = textwrap.wrap(summary, width=96, break_long_words=False, break_on_hyphens=False)
    return "\n".join([f"# {date} v{version}", *(f"# {line}" for line in lines)]) + "\n"


def history_function_entry(version: str, summary: str) -> str:
    lines = textwrap.wrap(summary, width=91, break_long_words=False, break_on_hyphens=False)
    return "\n".join([f"    {version} {lines[0]}", *(f"             {line}" for line in lines[1:])]) + "\n"


def replace_once(content: str, old: str, new: str, description: str) -> str:
    occurrences = content.count(old)
    if occurrences != 1:
        fail(f"expected one {description}, found {occurrences}")
    return content.replace(old, new, 1)


def update_variables(content: str, version: str, build_date: str) -> str:
    content, changed = re.subn(
        r'^rploaderver="[^"]+"$', f'rploaderver="{version}"', content, count=1, flags=re.MULTILINE
    )
    if changed != 1:
        fail("rploaderver variable was not found")

    if re.search(r'^builddate="[^"]+"$', content, flags=re.MULTILINE):
        content, changed = re.subn(
            r'^builddate="[^"]+"$', f'builddate="{build_date}"', content, count=1, flags=re.MULTILINE
        )
        if changed != 1:
            fail("builddate variable could not be updated")
    else:
        content = replace_once(
            content,
            f'rploaderver="{version}"\n',
            f'rploaderver="{version}"\nbuilddate="{build_date}"\n',
            "rploaderver insertion point",
        )
    return content


def append_histories(content: str, date: str, version: str, summary: str) -> str:
    if f"v{version}" in content:
        fail(f"version v{version} is already present in a functions history")

    function_entry = history_function_entry(version, summary)
    separator = "    --------------------------------------------------------------------------------------\nEOF\n}"
    content = replace_once(
        content, separator, function_entry + "    --------------------------------------------------------------------------------------\nEOF\n}", "history function terminator"
    )

    comment_entry = history_comment(date, version, summary)
    showlastupdate_marker = "\nfunction showlastupdate() {"
    content = replace_once(
        content,
        showlastupdate_marker,
        "\n" + comment_entry + showlastupdate_marker,
        "history block before showlastupdate",
    )

    start = content.index("function showlastupdate() {")
    end = content.index("\nEOF\n}", start)
    # Keep a visual separator between history entries printed by showlastupdate.
    content = content[:end] + "\n\n" + comment_entry.rstrip("\n") + content[end:]
    return content


def build_release_note(version: str, body: str) -> str:
    return f"# alpine-redpill v{version}\n\n{body}"


def apply_release(version: str, build_date: str, history_en: str, release_en: str, release_ko: str, dry_run: bool) -> None:
    updated_files: dict[Path, str] = {}
    for path in FUNCTION_FILES:
        if not path.is_file():
            fail(f"missing functions file: {path}")
        content = path.read_text(encoding="utf-8")
        content = update_variables(content, version, build_date)
        updated_files[path] = append_histories(content, build_date, version, history_en)

    en_path = RELEASE_NOTES_DIR / f"RELEASE_NOTES_v{version}_en.md"
    ko_path = RELEASE_NOTES_DIR / f"RELEASE_NOTES_v{version}_ko.md"
    if en_path.exists() or ko_path.exists():
        fail(f"release-note file already exists for v{version}")

    if dry_run:
        print(f"Would update: {', '.join(str(path.relative_to(ROOT)) for path in updated_files)}")
        print(f"Would create: {en_path.relative_to(ROOT)}, {ko_path.relative_to(ROOT)}")
        return

    for path, content in updated_files.items():
        path.write_text(content, encoding="utf-8")
    RELEASE_NOTES_DIR.mkdir(exist_ok=True)
    en_path.write_text(build_release_note(version, release_en), encoding="utf-8")
    ko_path.write_text(build_release_note(version, release_ko), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Update release metadata and create bilingual release notes.")
    parser.add_argument("--version", required=True, help="Four-part version without v, for example 1.4.2.7")
    parser.add_argument("--build-date", required=True, help="Build date as YYYY.MM.DD")
    parser.add_argument("--history-en", required=True, help="English history summary: letters, numbers, and spaces only")
    parser.add_argument("--history-ko", required=True, help="Korean fallback release-note summary: letters, numbers, and spaces only")
    parser.add_argument("--release-en-file", type=Path, help="Optional UTF-8 Markdown body for the English release note")
    parser.add_argument("--release-ko-file", type=Path, help="Optional UTF-8 Markdown body for the Korean release note")
    parser.add_argument("--dry-run", action="store_true", help="Validate and report changes without writing files")
    return parser.parse_args()


def main() -> int:
    try:
        args = parse_args()
        version = validate_version(args.version)
        build_date = validate_build_date(args.build_date)
        history_en = validate_history_summary("English", args.history_en)
        history_ko = validate_history_summary("Korean", args.history_ko)
        release_en = read_release_body(args.release_en_file, history_en, "English")
        release_ko = read_release_body(args.release_ko_file, history_ko, "Korean")
        apply_release(version, build_date, history_en, release_en, release_ko, args.dry_run)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
