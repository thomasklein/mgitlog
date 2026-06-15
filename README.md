# mgitlog (Multi git log)

[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](https://github.com/thomasklein/mgitlog/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Run `git log` across multiple repositories.

> **Note**: Compatible with Unix-like systems (Linux, macOS). Windows is supported over WSL.

## Table of Contents

- [Overview](#overview)
- [Example Usage](#example-usage)
- [Installation](#installation)
- [Options](#options)
- [Tips & Tricks](#tips--tricks)
- [Activity Overview & Stale Repos](#activity-overview--stale-repos)
- [Interleaved Cross-Repo View](#interleaved-cross-repo-view)
- [JSON Output & `jq` Integration](#json-output--jq-integration)

## Overview

`mgitlog` is a wrapper around `git log`, allowing you to run it over multiple repositories at once.
You can specify one or more "root" directories, and `mgitlog` will find and list logs from all discovered
Git repositories. This tool is especially helpful for engineers who work across many projects.

You can pipe its output into standard Unix tools like `grep`, `awk`, `sed`,
or use interactive tools like `fzf` to quickly locate, filter,
and analyze commit data (examples below).
You can also leverage all the usual `git log` arguments to narrow results by author, date range,
commit message patterns, and more.

## Example Usage

```bash
$ mgitlog --mroot ~/projects --mheader \
  --author=jane.smith@example.com --since "1 month ago"

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

## Options

```bash
  --mroot DIR               Specify root directory. Defaults to current directory 
                              and checks direct subdirectories (can be used multiple times)
  --mheader [style]         Show repository headers. Optional style: 'auto' (default), 'always'
                              'auto' only shows headers when there are commits to display
  --mexclude PATTERN        Exclude repository path(s) from scanning (can be used multiple times)
                              Supports partial matches (e.g., 'test' excludes 'test-repo')
  --mparallelize [NUMBER]   Enable parallel processing with optional number of processes (default: 4)
  --mscandepth NUMBER       Maximum depth when scanning for repositories (default: 2)
  --minterleave             Interleave commits from all repositories into one
                              chronological list, newest-first by commit date
  --mjson                   Emit a JSON array of commit objects (requires 'jq')
  --msummary                One line per repository: commit count, last activity, authors
  --mstale DURATION         List repositories whose last commit is older than DURATION
                              (e.g. 30d, 2w, 6m, 1y; a bare number means days)
  --help                    Show this help message
  --version                 Show version information
```

> **Tip:** if [`fd`](https://github.com/sharkdp/fd) is installed it is used for
> repository discovery (faster on large trees); otherwise `mgitlog` falls back to
> `find`. No configuration needed.

All mgitlog options (`--m*`) must come **before** any git log arguments;
everything after is passed directly to git log. For example:

- `--author="Jane Doe"`
- `--since="2 weeks ago"`
- `--grep="JIRA-123"`
- `--before="2024-01-01"`
- Specify branches or other git log arguments as needed

> `--minterleave`, `--mjson`, `--msummary` and `--mstale` are alternative output
> modes — use one at a time. Without any of them, each repo's log prints in turn.

## Tips & Tricks

1. **A timeline of what you did everywhere this week**

    `--minterleave` is the quickest way to see your cross-project activity in
    chronological order:

    ```bash
    mgitlog --mroot ~/projects --minterleave \
      --author="$(git config user.email)" --since="1 week ago"
    ```

2. **Common Queries: Environment Variables or Aliases**

    ```bash
    export MGITLOG_DEFAULT_ARGS='--since="1 month ago" --author="jane.smith@example.com"'
    alias mgitlog-weekly='mgitlog --mroot ~/projects $MGITLOG_DEFAULT_ARGS'
    ```

3. **Pipe into standard Unix tools**

    ```bash
    # Page through results
    mgitlog --mroot ~/projects | less

    # Extract just commit hashes (if output is in standard git log format)
    mgitlog --mroot ~/projects --color=never --since="1 month ago" | awk '/^commit/ {print $2}'

    # Use fzf for interactive filtering
    mgitlog --mroot ~/projects --color=never --since="1 month ago" | fzf
    ```

4. **Collect and analyze commit logs:**

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

## Activity Overview & Stale Repos

When you work across many repositories, the first questions are usually "where
have I been active?" and "what's gone quiet?" — not the full commit log. These
two modes answer that without relying on any commit-message conventions.

`--msummary` collapses each repo to a single line — commit count, last activity,
and authors — sorted most-recently-active first. It honors git log filters, so
you can scope it to a window or an author:

```bash
$ mgitlog --mroot ~/work --since="1 month ago" --msummary

REPO      COMMITS  LAST ACTIVITY  AUTHORS
api             12  2 days ago     jane, tom
frontend         8  15 hours ago   jane
checkout         3  3 weeks ago    tom
payments         0  -              -
```

`--mstale DURATION` lists only the repositories whose last commit is older than
the given age (`30d`, `2w`, `6m`, `1y`, or a bare number of days). Repos with no
commits are reported too — handy for spotting abandoned or forgotten services:

```bash
$ mgitlog --mroot ~/work --mstale 30d

REPO      LAST COMMIT  DATE
payments  no commits   -
checkout  6 weeks ago  2026-05-02
```

## Interleaved Cross-Repo View

`--minterleave` interleaves commits from every discovered repository into one
chronological list, newest-first by commit date — so you see what happened across
all your projects in order, with each commit tagged by repo:

```bash
$ mgitlog --mroot ~/projects --minterleave --since="1 week ago"

commit a1b2c3...  [API-GATEWAY]
Author: Jane Smith <jane.smith@example.com>
Date:   2026-06-12T16:10:53+02:00

    feat: add rate limiting middleware

commit d4e5f6...  [FRONTEND-SERVICE]
Author: Jane Smith <jane.smith@example.com>
Date:   2026-06-11T09:45:12+02:00

    fix: correct login form validation
```

## JSON Output & `jq` Integration

`--mjson` emits a JSON array of commit objects, globally sorted newest-first.
Unlike a hand-rolled `--pretty` format string, this escapes commit text correctly
(quotes, backslashes, and newlines in messages are preserved), so it's safe to
pipe straight into `jq`. Requires [`jq`](https://jqlang.github.io/jq/).

Each object has the shape:

```json
{
  "repo": "/home/jane/projects/api-gateway",
  "hash": "a1b2c3...",
  "author": { "name": "Jane Smith", "email": "jane.smith@example.com" },
  "author_date": "2026-06-12T16:10:53+02:00",
  "commit_date": "2026-06-12T16:10:53+02:00",
  "timestamp": 1749737453,
  "subject": "feat: add rate limiting middleware",
  "body": ""
}
```

Examples:

```bash
# Commits by a given author, newest first
mgitlog --mroot ~/projects --mjson --since="1 month ago" \
  | jq '.[] | select(.author.email == "jane.smith@example.com") | .subject'

# Count commits per repo
mgitlog --mroot ~/projects --mjson \
  | jq -r '.[].repo' | sort | uniq -c | sort -nr
```

You can still build JSON manually with `git log`'s `--pretty` if you prefer (note
this does not escape special characters in commit messages):

```bash
mgitlog --mroot ~/projects \
  --pretty=format:'{"commit":"%H","author":"%an","date":"%ad","message":"%s"}'
```

[Contributing](CONTRIBUTING.md) | [Changelog](CHANGELOG.md) | [MIT](LICENSE)
