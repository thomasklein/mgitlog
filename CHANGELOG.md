# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2024-12-05

### Added

- New "lastweek" date range option for easier time filtering
- Added option --files to show detailed file changes in output

## [1.0.0] - 2024-03-21

### Added

- Initial release
- Support for filtering commits by date range (today, week, custom dates)
- Multiple author support
- Multiple repository directory scanning
- Two output formats: detailed and minimal
- File change statistics
- Modified files listing
- Cross-platform support (Linux and macOS)
- Verbose mode for debugging
- Custom format string support
- Timeout protection for git commands
- Proper error handling and input validation
- Help and version information

### Technical Details

- Bash script with POSIX compatibility
- Modular design with separate functions for:
  - Date handling
  - Git processing
  - Commit formatting
  - Repository scanning
- Support for both local and remote branches
- Efficient handling of large repositories
- Memory-efficient processing of git logs
