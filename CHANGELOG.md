# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions: [SemVer](https://semver.org).

## [1.0.0] - 2026-10-11

First public release.

### Added
- Menu bar popover for fans, water purifiers and locks.
- Local control of fans over UDP, with a one-tap network check.
- Cloud fallback that spends one call per command and one per refresh.
- Per-request call journal (`calls.log`) and a daily call counter.
- Settings, FAQ, and a one-line network policy: one cloud host, UDP 5625 and 5600, nothing else.
