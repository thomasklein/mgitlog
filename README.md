# Multi Git Log

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/thomasklein/mgitlog/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Generate beautiful, readable work logs from your git commits across multiple git repos. Perfect for:

- 🎯 Daily standups
- 📊 Weekly reports
- 🔍 Tracking work across multiple repos

```bash
$ mgitlog -r ~/business-unit-a -r ~/projects/business-unit-b -d week

Git logs Nov 18 - Nov 24, 2024
Base directories: /home/jane/projects/business-unit-a, /home/jane/projects/business-unit-b

BUSINESS-UNIT-A [/home/jane/projects/business-unit-a]
━━━━━━━━━━━━━━━━━━━━

commit fd7fc4397f0e8267babc03cb9ee93c8d535a2fd0
Author: Jane Smith <jane.smith@example.com>
Date:   Wed Nov 20 14:20:25 2024 +0100

    feat: implement OAuth2 token validation and refresh mechanism
 5 files changed, 122 insertions(+), 84 deletions(-)

commit f0ecb7c09edac9fc3a9a66ead6dd79495223a0ec
Author: Jane Smith <jane.smith@example.com>
Date:   Mon Nov 18 16:20:10 2024 +0100

    fix: improve connection pool management and error handling
 2 files changed, 45 insertions(+), 12 deletions(-)

NOTIFICATION-SERVICE [/home/jane/projects/business-unit-b/notification-service]
━━━━━━━━━━━━━━━━━━━━

// ... more commits
```

## Quick Start

```bash
# Install
git clone https://github.com/thomasklein/mgitlog
cd mgitlog && chmod +x mgitlog.sh

# Optional: Make globally available
sudo ln -s "$(pwd)/mgitlog.sh" /usr/local/bin/mgitlog
```

## Options

```bash
Options:
    -r, --repo PATH        Specify repository path(s) to include.
                          Default: all Git repositories under current directory.
    -e, --exclude PATH     Exclude specified repository path(s).
    -d, --date RANGE      Specify date range for commits.
                          Available options: YYYY-MM-DD, "today", "yesterday",
                          "week", "YYYY-MM-DD..", "YYYY-MM-DD..YYYY-MM-DD"
    --log STRING          Custom git log options (replaces default --shortstat)
    --json               Output in JSON format
                         (Ignores --log option if specified)
    --help               Show this help message
    --version            Show version information
```

## Output Formats

### Default Format

The default output shows a human-readable format with commit messages, statistics, and repository grouping.

### JSON Format

Use `--json` for structured data output, perfect for parsing and integration with other tools:

```bash
$ mgitlog --json -d today
{
  "date_range": "2024-03-20..2024-03-20",
  "authors": [
    "jane.smith@example.com"
  ],
  "repositories": [
    {
      "repository": "/path/to/repo",
      "commits": [
        {
          "commit": "hash",
          "author": "Jane Smith",
          "author_email": "jane.smith@example.com",
          "author_date": "Wed Mar 20 14:20:25 2024 +0100",
          "subject": "feat: implement OAuth2 token validation",
          "body": "Detailed description of the changes",
          "changes": {
            "src/auth/oauth.ts": {
              "additions": 45,
              "deletions": 12
            },
            "src/auth/tokens.ts": {
              "additions": 77,
              "deletions": 72
            }
          }
        }
      ]
    }
  ]
}
```

[🤝 Contributing](CONTRIBUTING.md) | [📋 Changelog](CHANGELOG.md)

## Author

Thomas Klein <thomas.klein@swissmarketplace.group>

Licensed under [MIT](LICENSE)
