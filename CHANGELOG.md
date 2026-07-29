# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
The initial release, in progress.

### Added
- View → Use System Font: swap the bundled Atkinson Hyperlegible typeface for
  the platform font other Qt applications use (persisted, applies live).

### Fixed
- On Linux setups whose desktop tooling (qt5ct/qt6ct-style platform themes)
  overrides Qt application fonts, changing the theme no longer flips the UI
  onto a different font than startup showed.

## [0.1.0] - 2026-07-28
Test of the release process.

[Unreleased]: https://github.com/huderlem/porydaw/compare/0.1.0...HEAD
[0.1.0]: https://github.com/huderlem/porydaw/releases/tag/0.1.0
