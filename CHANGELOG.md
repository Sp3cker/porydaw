# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
The initial release, in progress.

### Added
- Same-tick events in the MIDI event list can be reordered: drag a row
  between its siblings, press Alt+Up/Down, or use the context menu's
  "Move up/down within tick". Order at a tick is meaningful to mid2agb, so
  moves stay within the tick (retime via the Tick cell) and keep setup
  events ahead of notes and note ends ahead of note-ons.

## [0.1.0] - 2026-07-28
Test of the release process.

[Unreleased]: https://github.com/huderlem/porydaw/compare/0.1.0...HEAD
[0.1.0]: https://github.com/huderlem/porydaw/releases/tag/0.1.0
