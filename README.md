# mgitlog (Multi git log)

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/thomasklein/mgitlog/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Run `git log` across multiple repositories.

> **Note**: Compatible with Unix-like systems (Linux, macOS). Windows is supported over WSL.

## Overview

`mgitlog` is a wrapper around `git log`, allowing you to run it over multiple repositories at once. You can specify one or more "root" directories, and `mgitlog` will find and list logs from all discovered Git repositories. This tool is especially helpful for engineers who work across many projects.

You can pipe its output into standard Unix tools like `grep`, `awk`, `sed`, or use interactive tools like `fzf` to quickly locate, filter, and analyze commit data (examples below). You can also leverage all the usual `git log` arguments to narrow results by author, date range, commit message patterns, and more.

## Example Usage

```bash
$ mgitlog --mroot ~/projects --mheader \
  --author=jane.smith@example.com --since "1 week ago"

FRONTEND-SERVICE [/home/jane/work/projects/frontend-service]
----------------------------------------

commit a1b2c3d4e5f6a7b8c9d0e1f2g3h4i5j6k7l8m9n0
Author: Jane Smith <jane.smith@example.com>
Date:   Mon Dec 1 09:45:12 2024 +0100

    fix: correct login form validation error messages

commit c0f9e8d7c6b5a4e3f2g1h2i3j4k5l6m7n8o9p0q
Author: Jane Smith <jane.smith@example.com>
Date:   Tue Dec 2 16:10:53 2024 +0100

    refactor(ui): simplify header component structure

API-GATEWAY [/home/jane/work/projects/api-gateway]
----------------------------------------

commit d1e2f3g4h5i6j7k8l9m0n1o2p3q4r5s6t7u8v9w
Author: Jane Smith <jane.smith@example.com>
Date:   Wed Dec 3 11:32:00 2024 +0100

    feat: add rate limiting middleware for partner APIs

AUTH-SERVICE [/home/jane/work/projects/auth-service]
----------------------------------------

commit f0e1d2c3b4a59687abcdefabcdefabcdefabc
Author: Jane Smith <jane.smith@example.com>
Date:   Fri Dec 5 14:05:00 2024 +0100

    chore: update dependency versions for security patches
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

mgitlog-specific options:

```bash
  --mroot DIR               Specify root directory. Defaults to current directory 
                              and checks direct subdirectories (can be used multiple times)
  --mheader                 Show repository headers
  --mexclude PATTERN        Exclude repository path(s) from scanning (can be used multiple times)
                              Supports partial matches (e.g., 'test' excludes 'test-repo')
  --mparallelize [NUMBER]   Enable parallel processing with optional number of processes (default: 4)
  --help                    Show this help message
  --version                 Show version information
  ```

All other arguments are passed directly to git log. For example:

- `--author="Jane Doe"`
- `--since="2 weeks ago"`
- `--grep="JIRA-123"`
- `--before="2024-01-01"`
- Specify branches or other git log arguments as needed

## Making the Most of mgitlog

Below are some tips and best practices that can make mgitlog even more powerful for your workflow, without altering its base functionality or output.

1. **Use environment variables or aliases for common queries:**

```bash
export MGITLOG_DEFAULT_ARGS='--since="1 week ago" --author="jane.smith@example.com"'
alias mgitlog-weekly='mgitlog --mroot ~/projects $MGITLOG_DEFAULT_ARGS'
```

1. **Pipe into standard Unix tools:**

```bash
# Page through results
mgitlog --mroot ~/projects | less

# Extract just commit hashes (if output is in standard git log format)
mgitlog --mroot ~/projects --color=never | awk '/^commit/ {print $2}'

# Use fzf for interactive filtering
mgitlog --mroot ~/projects --color=never | fzf
```

1. **Collect and analyze commit logs:**

```bash
# Collect recent commit logs from all repos
mgitlog --mroot ~/projects --color=never --since="1 month ago" > all_commits.log

# Count commits per author
grep "Author:" all_commits.log | sort | uniq -c | sort -nr

# Count commits per day
grep "^Date:" all_commits.log | sed 's/^Date:[[:space:]]*//' \
    | awk '{print $1, $2, $3, $5}' \
    | sort \
    | uniq -c \
    | sort -nr
```

1. **Use `jq` for JSON output:**

By leveraging `git log`’s `--pretty` format option, you can output commit information as JSON and then pipe it through `jq` for easy filtering and formatting:

```bash
mgitlog --mroot ~/projects \
  --pretty=format:'{"commit":"%H","author":"%an <%ae>","date":"%ad","message":"%f"}' \
  | jq
```

This produces a JSON stream of all commits in the specified repositories, which you can then query with jq:

```bash
# Example: Filter commits by a specific author
mgitlog --mroot ~/projects \
  --pretty=format:'{"commit":"%H","author":"%an","email":"%ae","date":"%ad","message":"%s"}' \
  | jq 'select(.author == "Jane Smith")'
```

[Contributing](CONTRIBUTING.md) | [Changelog](CHANGELOG.md) | [MIT](LICENSE)
