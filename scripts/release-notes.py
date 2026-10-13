#!/usr/bin/env python3
"""Render one CHANGELOG.md section as release notes.

Usage:  release-notes.py --version 0.1.0 [--changelog CHANGELOG.md] [--format html|markdown]

html      the fragment Sparkle shows in its update window. HTML, not Markdown: the notes are
          rendered by the Sparkle inside the app being *updated*, and HTML is the one format
          every Sparkle 2 build has always read.
markdown  the raw section body, for the GitHub Release.

The `## [version] - date` heading itself is dropped: both Sparkle's window and the GitHub
Release already name the version. Only the Markdown subset the changelog uses is understood in
html mode: `###` headings, `- ` bullets with indented continuation lines, paragraphs, `code`,
**bold** and [links](url). Fails when the section is missing or empty, so a release can't ship
without notes.
"""
import argparse
import html
import re
import sys


def fail(message):
    sys.exit(f"!! release-notes: {message}")


def extract_section(text, version):
    """Lines of the `## [version]` section, heading excluded."""
    lines = []
    found = False
    for line in text.splitlines():
        if line.startswith("## ["):
            if found:
                break
            # Exact match, not a prefix: `0.1` must not pick up `0.1.1`.
            found = line.startswith(f"## [{version}]")
            continue
        if found:
            lines.append(line)
    return lines if found else None


def inline(text):
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(
        r"\[([^\]]+)\]\(([^)\s]+)\)",
        lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>',
        out,
    )
    return out


def render(lines):
    blocks = []
    paragraph = []
    bullets = []

    def flush_paragraph():
        if paragraph:
            blocks.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_list():
        if bullets:
            items = "".join(f"<li>{inline(' '.join(b))}</li>" for b in bullets)
            blocks.append(f"<ul>{items}</ul>")
            bullets.clear()

    # A heading is only kept if something follows it before the next heading:
    # the `[Unreleased]` scaffold (`### Added` / `### Changed` / `### Fixed`) is
    # copied into every new section, and an empty "Changed" heading in the update
    # window reads as if the notes failed to load.
    pending_heading = None

    def emit():
        nonlocal pending_heading
        if pending_heading is not None:
            blocks.append(pending_heading)
            pending_heading = None

    for raw in lines:
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            flush_paragraph()
            flush_list()
            continue
        if stripped.startswith("#"):
            flush_paragraph()
            flush_list()
            title = stripped.lstrip("#").strip()
            pending_heading = f"<h3>{inline(title)}</h3>" if title else None
            continue
        if stripped.startswith(("- ", "* ")):
            flush_paragraph()
            emit()
            bullets.append([stripped[2:].strip()])
            continue
        if bullets and line[:1].isspace():
            bullets[-1].append(stripped)
            continue
        flush_list()
        emit()
        paragraph.append(stripped)

    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--format", choices=("html", "markdown"), default="html")
    args = parser.parse_args()

    try:
        with open(args.changelog, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        fail(f"cannot read {args.changelog}: {error}")

    section = extract_section(text, args.version)
    if section is None:
        fail(f"no ## [{args.version}] section in {args.changelog}")
    rendered = render(section) if args.format == "html" else "\n".join(section).strip()
    if not rendered:
        fail(f"## [{args.version}] in {args.changelog} is empty, the release would ship with blank notes")
    print(rendered)


if __name__ == "__main__":
    main()
