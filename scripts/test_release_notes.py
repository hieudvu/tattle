#!/usr/bin/env python3
"""Tests for release-notes.py. Run: python3 scripts/test_release_notes.py"""
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("release_notes", pathlib.Path(__file__).with_name("release-notes.py"))
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)

CHANGELOG = """# Changelog

## [Unreleased]

### Added

## [0.1.1] - 2026-02-01

### Fixed

- Fix `crash` on **launch**.
  Second line.

## [0.1] - 2026-01-01

Intro.
"""


class ExtractSectionTests(unittest.TestCase):
    def test_matches_version_exactly_not_by_prefix(self):
        section = notes.extract_section(CHANGELOG, "0.1")
        self.assertEqual([line for line in section if line.strip()], ["Intro."])

    def test_returns_none_for_unknown_version(self):
        self.assertIsNone(notes.extract_section(CHANGELOG, "9.9.9"))


class RenderTests(unittest.TestCase):
    def test_renders_heading_and_bullet_with_inline_markup_and_continuation(self):
        html = notes.render(notes.extract_section(CHANGELOG, "0.1.1"))
        self.assertEqual(
            html,
            "<h3>Fixed</h3>\n<ul><li>Fix <code>crash</code> on <strong>launch</strong>. Second line.</li></ul>",
        )

    def test_drops_headings_that_have_no_content(self):
        self.assertEqual(notes.render(notes.extract_section(CHANGELOG, "Unreleased")), "")

    def test_escapes_html_in_text(self):
        self.assertEqual(notes.render(["- a <b> & c"]), "<ul><li>a &lt;b&gt; &amp; c</li></ul>")


if __name__ == "__main__":
    unittest.main()
