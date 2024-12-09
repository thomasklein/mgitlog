# mgitlog (Multi git log)

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/thomasklein/mgitlog/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Run `git log` across multiple repositories.

> **Note**: Compatible with Unix-like systems (Linux, macOS). Windows is not supported.

```bash
$ mgitlog --mroot ~/projects --mheader \
--author=jane.smith@example.com --since "1 week ago"

MESSAGING-SERVICE [/home/jane/projects/messaging-service]
━━━━━━━━━━━━━━━━━━━━

commit fd7fc4397f0e8267babc03cb9ee93c8d535a2fd0
Author: Jane Smith <jane.smith@example.com>
Date:   Wed Nov 20 14:20:25 2024 +0100

    feat: implement OAuth2 token validation and refresh mechanism

MONITORING-SERVICE [/home/jane/projects/monitoring-service]
━━━━━━━━━━━━━━━━━━━━

commit fd7fc4397f0e8267babc03cb9ee93c8xxxxxxx01
Author: Jane Smith <jane.smith@example.com>
Date:   Thu Nov 20 13:20:25 2024 +0100

    feat: implement OAuth2 token validation and refresh mechanism
// ... more commits
```

## Installation

```bash
# Install
git clone https://github.com/thomasklein/mgitlog
cd mgitlog && chmod +x mgitlog.sh

# Optional: Make globally available
sudo ln -s "$(pwd)/mgitlog.sh" /usr/local/bin/mgitlog
```

## Options

Note: Append any `git log` option. Below are the exclusive `mgitlog` options.

```bash
Options:
  --mroot DIR               Specify root directory. Defaults to current directory 
                              and checks direct subdirectorties (can be used multiple times)
  --mheader                 Show repository headers
  --mexclude PATTERN        Exclude repository path(s) from scanning (can be used multiple times)
                              Supports partial matches (e.g., 'test' excludes 'test-repo')
  --mparallelize [NUMBER]   Enable parallel processing with optional number of processes (default: 4)
  --help                    Show this help message
  --version                 Show version information
```

[Contributing](CONTRIBUTING.md) | [Changelog](CHANGELOG.md) | [MIT](LICENSE)
