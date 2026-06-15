# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.3.0 - 2026-06-16

### Added

- "Recipes" section in the README: one-line standup, daily activity graph,
  team-activity counts, cross-repo ticket tracking, fzf browsing, stale repos.

### Changed

- **Breaking:** renamed `--minterleave` to `--mtimeline`. The behaviour is
  unchanged; "interleave" was unclear, especially for non-native English
  speakers, and read like a `git merge`.
- Reworded `--help` and the README in plainer language (shorter sentences,
  common words) to make usage easier to read at a glance.

## 1.2.0 - 2026-06-15

### Added

- `--msummary`: one aggregated line per repository (commit count, last activity,
  authors), sorted most-recently-active first. Honors git log filters and needs
  no commit-message conventions.
- `--mstale DURATION`: list repositories whose last commit is older than a given
  age (`30d`, `2w`, `6m`, `1y`, or a bare number of days); repos with no commits
  are reported too. Useful for spotting abandoned services.

## 1.1.0 - 2026-06-15

### Added

- `--minterleave`: merge commits from all repositories into a single stream,
  sorted newest-first by commit date across repos, each tagged with its repo.
- `--mjson`: emit a JSON array of commit objects (requires `jq`), with commit
  text correctly escaped. Replaces the fragile hand-rolled `--pretty` JSON hack.
- Repository discovery now uses [`fd`](https://github.com/sharkdp/fd) when
  available (faster on large trees), falling back to `find`.
- Test suite (bats) and CI (shellcheck + bats).

### Changed

- Parallel mode passes paths/args to `git log` as positional arguments instead
  of interpolating them into a command string, fixing breakage and a command
  injection vector with paths containing spaces or shell metacharacters.
- Commit text with backslashes is now preserved verbatim (`printf` instead of
  `echo -e`).
- `--mroot` tilde expansion no longer uses `eval`.
- Linked worktrees and submodules (which use a `.git` *file*) are now discovered.

### Removed

- **Breaking:** the `MGITLOG_BEFORE_CMD` / `MGITLOG_AFTER_CMD` hooks. For
  running arbitrary commands across repos, use a dedicated multi-repo tool
  (e.g. `mr`, `gita`) or a shell loop; `mgitlog` now focuses on reading logs.

## 1.0.0 - 2024-12-10

### Added

- Initial release
