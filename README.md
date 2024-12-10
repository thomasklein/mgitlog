# mgitlog (Multi git log)

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](https://github.com/thomasklein/mgitlog/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Run `git log` across multiple repositories.

> **Note**: Compatible with Unix-like systems (Linux, macOS). Windows is supported over WSL.

## Table of Contents

- [Overview](#overview)
- [Example Usage](#example-usage)
- [Installation](#installation)
- [Options & Environment Variables](#options--environment-variables)
- [Tips & Tricks](#tips--tricks)
- [JSON Output & `jq` Integration](#json-output--jq-integration)

## Overview

`mgitlog` is a wrapper around `git log`, allowing you to run it over multiple repositories at once. You can specify one or more "root" directories, and `mgitlog` will find and list logs from all discovered Git repositories. This tool is especially helpful for engineers who work across many projects.

You can pipe its output into standard Unix tools like `grep`, `awk`, `sed`, or use interactive tools like `fzf` to quickly locate, filter, and analyze commit data (examples below). You can also leverage all the usual `git log` arguments to narrow results by author, date range, commit message patterns, and more.

## Example Usage

```bash
$ mgitlog --mroot ~/projects --mheader \
  --author=jane.smith@example.com --since "1 week ago"

FRONTEND-SERVICE [/home/jane/work/projects/frontend-service]
----------------------------------------

commit a1b2c3...
Author: Jane Smith <jane.smith@example.com>
Date:   Mon Dec 1 09:45:12 2024 +0100

    fix: correct login form validation error messages

commit c0f9e8...
Author: Jane Smith <jane.smith@example.com>
Date:   Tue Dec 2 16:10:53 2024 +0100

    refactor(ui): simplify header component structure

API-GATEWAY [/home/jane/work/projects/api-gateway]
----------------------------------------

commit d1e2f3...
Author: Jane Smith <jane.smith@example.com>
Date:   Wed Dec 3 11:32:00 2024 +0100

    feat: add rate limiting middleware for partner APIs
```

## Installation

```bash
# Clone the repository
git clone https://github.com/thomasklein/mgitlog
cd mgitlog

# Make the script executable
chmod +x mgitlog.sh

# (Optional) Make mgitlog globally accessible
sudo ln -s "$(pwd)/mgitlog.sh" /usr/local/bin/mgitlog
```

## Options & Environment Variables

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
  
  Environment Variables:
  MGITLOG_BEFORE_CMD        A command (or series of commands) to run *before* 'git log' in each repository.
                            For example:
                              MGITLOG_BEFORE_CMD="git pull --rebase"

  MGITLOG_AFTER_CMD         A command (or series of commands) to run *after* 'git log' output is printed for each repository.
                            For example:
                              MGITLOG_AFTER_CMD="echo 'Done with repo!'"

If these variables are unset or empty, no pre- or post-processing is done.
  ```

All other arguments are passed directly to git log. For example:

- `--author="Jane Doe"`
- `--since="2 weeks ago"`
- `--grep="JIRA-123"`
- `--before="2024-01-01"`
- Specify branches or other git log arguments as needed

## Tips & Tricks

1. **Per-Repo Hooks: Pre/Post Execution Steps Using `MGITLOG_BEFORE_CMD` and `MGITLOG_AFTER_CMD`**

Set `MGITLOG_BEFORE_CMD` to ensure your repos are up to date before logging:

```bash
export MGITLOG_BEFORE_CMD="git checkout main && git pull"
```

Use `MGITLOG_AFTER_CMD` to log which repos were processed:

```bash
export MGITLOG_AFTER_CMD="echo \"Processed \$(basename \$(pwd)) at \$(date)\" >> ~/repo_processing.log"
```

1. **Common Queries: Environment Variables or Aliases**

```bash
export MGITLOG_DEFAULT_ARGS='--since="1 week ago" --author="jane.smith@example.com"'
alias mgitlog-weekly='mgitlog --mroot ~/projects $MGITLOG_DEFAULT_ARGS'
```

1. **Pipe into standard Unix tools**

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

## JSON Output & `jq` Integration

Use `--pretty` formatting from `git log` to produce JSON-like output and pipe it into `jq` for complex filtering:

```bash
mgitlog --mroot ~/projects \
  --pretty=format:'{"commit":"%H","author":"%an <%ae>","date":"%ad","message":"%f"}' \
  | jq
```

Example for filtering by author using `jq`:

```bash
mgitlog --mroot ~/projects \
  --pretty=format:'{"commit":"%H","author":"%an","email":"%ae","date":"%ad","message":"%s"}' \
  | jq 'select(.author == "Jane Smith")'
```

[Contributing](CONTRIBUTING.md) | [Changelog](CHANGELOG.md) | [MIT](LICENSE)
