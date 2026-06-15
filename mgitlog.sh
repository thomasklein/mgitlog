#!/bin/bash
# mgitlog - Multi-repository Git Log Tool
# 
# This script enables running 'git log' across multiple Git repositories simultaneously.
# It supports parallel processing, repository filtering, and custom pre/post processing hooks.
#
# Author: Thomas Klein
# License: MIT

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

#===============================================================================
# Configuration and Global Variables
#===============================================================================
TOOL_NAME="mgitlog"
VERSION="1.2.0"

# Arrays to store multiple root directories and git arguments
declare -a root_dirs        # Stores paths to search for repositories
declare -a git_args=()      # Stores arguments to pass to git log
declare -a exclude_patterns=() # Patterns for repositories to exclude

# Control flags and settings
show_header="none"         # Header display mode: none, auto, always
git_args_string=""         # Concatenated git arguments as a single string
parallel_processes=0       # Number of parallel processes (0 = sequential)
max_depth=2               # Maximum directory depth for repository scanning
interleave_mode=false      # Interleave commits from all repos into one time-sorted stream
json_mode=false            # Emit a JSON array of commit objects instead of text
summary_mode=false         # Print a one-line-per-repo activity overview
stale_mode=false           # List repositories untouched for longer than a threshold
stale_threshold=""         # Duration string for --mstale (e.g. 30d, 2w, 6m)

# Control characters used to frame machine-readable git output.
# US (unit separator) between fields, NUL between records (via `git log -z`).
US=$'\x1f'

# Prefer 'fd' for repository discovery when available (much faster on large
# trees, and skips into hidden dirs cleanly). Debian/Ubuntu package it as
# 'fdfind'. Falls back to POSIX 'find' otherwise.
FD_BIN=""
if command -v fd >/dev/null 2>&1; then
    FD_BIN="fd"
elif command -v fdfind >/dev/null 2>&1; then
    FD_BIN="fdfind"
fi

# Export git_args for subshell access
export git_args

#===============================================================================
# Helper Functions
#===============================================================================

# Display usage information and available options
show_help() {
    cat << EOF
Usage: $TOOL_NAME [mgitlog options] [git log arguments]

Run 'git log' across multiple repositories. All mgitlog options (--m*) must come
BEFORE any git log arguments; everything else is passed straight through to git log.

By default each repository's log is printed in turn. --minterleave, --mjson,
--msummary and --mstale are alternative output modes (use one at a time).

Options:
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
  --mjson                   Emit a JSON array of commit objects (implies --minterleave
                              ordering; requires 'jq'). Ideal for piping into jq.
  --msummary                One line per repository: commit count, last activity,
                              and authors. Honors git log filters (e.g. --since).
  --mstale DURATION         List repositories whose last commit is older than
                              DURATION (e.g. 30d, 2w, 6m, 1y; bare number = days).
  --help                    Show this help message
  --version                 Show version information

Examples:
  # Per-repo logs from every repo under ~/projects, with headers
  $TOOL_NAME --mroot ~/projects --mheader

  # One unified timeline of your commits across all repos this week
  $TOOL_NAME --mroot ~/projects --minterleave --author="you@example.com" --since="1 week ago"

  # Activity overview: commits, last activity and authors per repo
  $TOOL_NAME --mroot ~/projects --msummary --since="1 month ago"

  # Repositories with no commit in the last 30 days
  $TOOL_NAME --mroot ~/projects --mstale 30d

  # Machine-readable JSON for scripting (requires jq)
  $TOOL_NAME --mroot ~/projects --mjson | jq '.[].subject'
EOF
}

# Execute a command in a specific directory with error handling
# Args:
#   $1 - Directory to execute in
#   $2 - Command to execute
#   $3 - Error message if command fails
execute_in_dir() {
    local dir="$1"
    local cmd="$2"
    local error_msg="${3:-Command failed}"
    
    (pushd "$dir" >/dev/null && eval "$cmd"; popd >/dev/null) || {
        echo "Warning: $error_msg in $dir" >&2
        return 1
    }
}

# Format repository output with optional headers
# Args:
#   $1 - Repository path
#   $2 - Git command output content
#   $3 - Whether to show repository headers
format_repo_output() {
    local repo_path="$1"
    local content="$2"
    local header_mode="$3"
    
    if [[ "$header_mode" == "always" ]] || [[ "$header_mode" == "auto" && -n "$content" ]]; then
        local repo_name
        repo_name=$(basename "$repo_path" | tr '[:lower:]' '[:upper:]')
        printf '\n%s [%s]\n' "$repo_name" "$repo_path"
        printf '%s\n\n' "----------------------------------------"
    fi
    # Use printf (not echo -e) so backslash sequences in commit text are preserved verbatim
    [[ -n "$content" ]] && printf '%s\n\n' "$content"
    printf '\n'
}

# Process a single repository: run git log and format the output.
# Args:
#   $1 - Path to repository
#   $2 - Show header flag
#   $3 - Git arguments string
process_repository() {
    local repo_path="$1"
    local show_header="$2"
    local git_args_str="$3"

    [[ -z "$repo_path" ]] && return

    # Execute git log with provided arguments
    local git_output=""
    if [[ -n "$git_args_str" ]]; then
        git_output=$(execute_in_dir "$repo_path" "git --no-pager log $git_args_str") || return
    else
        git_output=$(execute_in_dir "$repo_path" "git --no-pager log") || return
    fi

    # Always format output if header mode is 'always', otherwise only when we have git output
    if [[ "$show_header" == "always" ]] || [[ -n "$git_output" ]]; then
        format_repo_output "$repo_path" "$git_output" "$show_header"
    fi
}

# Check if a path matches any exclusion patterns
# Args:
#   $1 - Path to check
# Returns:
#   0 if path should be excluded, 1 otherwise
is_excluded() {
    local path="$1"
    
    if (( ${#exclude_patterns[@]} > 0 )); then
        for pattern in "${exclude_patterns[@]}"; do
            [[ "$path" == *"$pattern"* ]] && return 0  # Path matches exclusion pattern
        done
    fi
    return 1  # Path should not be excluded
}

# Find all Git repositories under a directory
# Uses find with optimization flags and respects max_depth setting
# Args:
#   $1 - Root directory to search
find_git_repos() {
    local dir="$1"
    [[ ! -d "$dir" ]] && { echo "Error: Directory does not exist: $dir" >&2; return 1; }

    # If the directory itself is a git repo, return it (unless excluded).
    # Use -e (not -d): linked worktrees and submodules use a .git *file*, not a dir.
    if [[ -e "$dir/.git" ]]; then
        is_excluded "$dir" || echo "$dir"
        return
    fi

    # Find all .git entries (dirs or worktree/submodule files) and output their
    # parent paths. Both backends follow symlinks and match the literal name
    # '.git'; depth is relative to "$dir" with identical semantics.
    {
        if [[ -n "$FD_BIN" ]]; then
            "$FD_BIN" --hidden --no-ignore --follow --absolute-path \
                --max-depth "$max_depth" '^\.git$' "$dir" 2>/dev/null
        else
            # -L follows symlinks for more thorough scanning
            find -L "$dir" -maxdepth "$max_depth" -name .git -prune 2>/dev/null
        fi
    } | while read -r gitdir; do
        local repo_path
        repo_path=$(dirname "$gitdir")
        is_excluded "$repo_path" || printf '%s\n' "$repo_path"
    done
}

# Export functions needed for parallel processing
export -f execute_in_dir
export -f format_repo_output
export -f process_repository
export -f is_excluded

#===============================================================================
# Interleaved / JSON Output
#===============================================================================

# Machine-readable git log format. Fields are US-separated; commits are
# NUL-separated by `git log -z`. The leading field is the committer Unix
# timestamp, used as the cross-repo sort key.
#   1:%ct  2:%H  3:%an  4:%ae  5:%aI  6:%cI  7:%s  8:%b
MACHINE_FMT='%ct%x1f%H%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%s%x1f%b'

# Emit one machine record per commit for a repo, with the repo path injected
# as a second field so downstream rendering knows where each commit came from.
# Output records stay NUL-separated.
# Args: $1 repo path, $2 git args string
emit_repo_records() {
    local repo="$1" git_args_str="$2"

    # Stream git's NUL-separated output directly into the loop. We must NOT
    # capture it with $(...), because command substitution strips NUL bytes
    # and would merge every commit of a repo into a single record.
    # Re-emit each record as: <ct> US <repo> US <rest...> NUL
    local rec ct rest
    while IFS= read -r -d '' rec || [[ -n "$rec" ]]; do
        [[ -z "$rec" ]] && continue
        ct=${rec%%"$US"*}
        rest=${rec#*"$US"}
        printf '%s%s%s%s%s\0' "$ct" "$US" "$repo" "$US" "$rest"
    done < <(execute_in_dir "$repo" \
        "git --no-pager log -z $git_args_str --pretty=format:'$MACHINE_FMT'" 2>/dev/null)
}

# Collect records from every repo under all roots into one NUL-delimited,
# newest-first stream on stdout. Collection is sequential so the merge is
# deterministic; per-repo git calls dominate cost, not the merge.
collect_all_records() {
    local root repo
    for root in "${root_dirs[@]}"; do
        while IFS= read -r repo; do
            emit_repo_records "$repo" "$git_args_string"
        done < <(find_git_repos "$root")
    done | sort -z -t "$US" -k1,1 -nr
}

# Render the collected stream as a unified, git-log-like text view.
render_interleaved_text() {
    local rec
    local ct repo hash an ae aI cI subject body repo_name
    while IFS= read -r -d '' rec || [[ -n "$rec" ]]; do
        [[ -z "$rec" ]] && continue
        # shellcheck disable=SC2034  # ct/aI are parsed for position but not shown in text view
        IFS="$US" read -r ct repo hash an ae aI cI subject body <<< "$rec"
        repo_name=$(basename "$repo" | tr '[:lower:]' '[:upper:]')
        printf 'commit %s  [%s]\n' "$hash" "$repo_name"
        printf 'Author: %s <%s>\n' "$an" "$ae"
        printf 'Date:   %s\n\n' "$cI"
        printf '    %s\n' "$subject"
        [[ -n "$body" ]] && printf '%s\n' "$body" | sed 's/^/    /'
        printf '\n'
    done
}

# Render the collected stream as a JSON array via a single jq invocation.
# jq does the escaping, so commit text with quotes/backslashes/newlines is safe.
render_json() {
    jq -Rs '
        split("\u0000")
        | map(select(length > 0))
        | map(split("\u001f"))
        | map({
            repo:        .[1],
            hash:        .[2],
            author:      { name: .[3], email: .[4] },
            author_date: .[5],
            commit_date: .[6],
            timestamp:   (.[0] | tonumber),
            subject:     .[7],
            body:        (.[8] // "")
          })
    '
}

#===============================================================================
# Activity Summary & Stale Detection
#===============================================================================

# Parse a duration like 30d, 2w, 6m, 1y (a bare number means days) into seconds.
# Prints the number of seconds on success; returns 1 on invalid input.
parse_duration() {
    local spec="$1" num unit
    [[ "$spec" =~ ^([0-9]+)([dwmy]?)$ ]] || return 1
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]:-d}"
    case "$unit" in
        d) printf '%s\n' "$((num * 86400))" ;;
        w) printf '%s\n' "$((num * 604800))" ;;
        m) printf '%s\n' "$((num * 2592000))" ;;   # 30-day month
        y) printf '%s\n' "$((num * 31536000))" ;;  # 365-day year
        *) return 1 ;;
    esac
}

# Emit one NUL-terminated, US-delimited summary record for a repo:
#   <last_ct> US <repo_name> US <count> US <last_relative> US <authors>
# Honors the user's git log arguments (e.g. --since, --author). At most three
# distinct authors are shown, with "+N" for the rest. last_ct is the sort key.
summarize_repo() {
    local repo="$1" git_args_str="$2"
    local count=0 last_ct=0 last_cr="" authors_seen="" distinct=0
    local ct cr an
    while IFS="$US" read -r ct cr an; do
        count=$((count + 1))
        if (( count == 1 )); then last_ct="$ct"; last_cr="$cr"; fi
        # Dedupe authors with a comma-delimited membership test (no assoc arrays in bash 3.2)
        case ",$authors_seen," in
            *",$an,"*) ;;
            *) authors_seen="${authors_seen:+$authors_seen,}$an"; distinct=$((distinct + 1)) ;;
        esac
    done < <(execute_in_dir "$repo" \
        "git --no-pager log $git_args_str --pretty=tformat:'%ct%x1f%cr%x1f%an'" 2>/dev/null)

    local repo_name authors
    repo_name=$(basename "$repo")
    if (( distinct == 0 )); then
        authors="-"
    else
        authors="$authors_seen"
        (( distinct > 3 )) && authors="$(printf '%s' "$authors_seen" | cut -d, -f1-3) +$((distinct - 3))"
        authors="${authors//,/, }"   # comma-only internally (for dedupe); space out for display
    fi
    (( count == 0 )) && last_cr="-"
    printf '%s%s%s%s%s%s%s%s%s\0' \
        "$last_ct" "$US" "$repo_name" "$US" "$count" "$US" "$last_cr" "$US" "$authors"
}

# Render collected summary records as an aligned table (no external deps so it
# works the same on macOS and Linux). Two passes: measure widths, then print.
render_summary() {
    local -a r_name r_count r_last r_auth
    local rec name count last auth
    local w_name=4 w_count=7 w_last=13   # widths of headers REPO / COMMITS / LAST ACTIVITY
    while IFS= read -r -d '' rec || [[ -n "$rec" ]]; do
        [[ -z "$rec" ]] && continue
        # shellcheck disable=SC2034  # first field is the sort key, consumed upstream
        local last_ct
        IFS="$US" read -r last_ct name count last auth <<< "$rec"
        r_name+=("$name"); r_count+=("$count"); r_last+=("$last"); r_auth+=("$auth")
        (( ${#name} > w_name )) && w_name=${#name}
        (( ${#count} > w_count )) && w_count=${#count}
        (( ${#last} > w_last )) && w_last=${#last}
    done
    printf '%-*s  %*s  %-*s  %s\n' \
        "$w_name" "REPO" "$w_count" "COMMITS" "$w_last" "LAST ACTIVITY" "AUTHORS"
    local i
    for i in "${!r_name[@]}"; do
        printf '%-*s  %*s  %-*s  %s\n' \
            "$w_name" "${r_name[$i]}" "$w_count" "${r_count[$i]}" \
            "$w_last" "${r_last[$i]}" "${r_auth[$i]}"
    done
}

# Emit a NUL-terminated record for a repo only if it is stale (last commit older
# than the cutoff, or no commits at all):
#   <last_ct> US <repo_name> US <last_relative> US <last_date>
# Repos with no commits sort first (key 0).
check_stale_repo() {
    local repo="$1" git_args_str="$2" cutoff="$3"
    local repo_name line ct cr cs
    repo_name=$(basename "$repo")
    line=$(execute_in_dir "$repo" \
        "git --no-pager log -1 $git_args_str --pretty=format:'%ct%x1f%cr%x1f%cs'" 2>/dev/null) || line=""
    if [[ -z "$line" ]]; then
        printf '%s%s%s%s%s%s%s\0' "0" "$US" "$repo_name" "$US" "no commits" "$US" "-"
        return
    fi
    IFS="$US" read -r ct cr cs <<< "$line"
    if (( ct < cutoff )); then
        printf '%s%s%s%s%s%s%s\0' "$ct" "$US" "$repo_name" "$US" "$cr" "$US" "$cs"
    fi
}

# Render collected stale records as an aligned table.
render_stale() {
    local -a s_name s_last s_date
    local rec name last date count=0
    local w_name=4 w_last=11   # widths of headers REPO / LAST COMMIT
    while IFS= read -r -d '' rec || [[ -n "$rec" ]]; do
        [[ -z "$rec" ]] && continue
        # shellcheck disable=SC2034  # first field is the sort key, consumed upstream
        local ct
        IFS="$US" read -r ct name last date <<< "$rec"
        s_name+=("$name"); s_last+=("$last"); s_date+=("$date"); count=$((count + 1))
        (( ${#name} > w_name )) && w_name=${#name}
        (( ${#last} > w_last )) && w_last=${#last}
    done
    if (( count == 0 )); then
        echo "No stale repositories."
        return
    fi
    printf '%-*s  %-*s  %s\n' "$w_name" "REPO" "$w_last" "LAST COMMIT" "DATE"
    local i
    for i in "${!s_name[@]}"; do
        printf '%-*s  %-*s  %s\n' \
            "$w_name" "${s_name[$i]}" "$w_last" "${s_last[$i]}" "${s_date[$i]}"
    done
}

#===============================================================================
# Argument Parsing
#===============================================================================

# Flag to indicate if we have started processing git log arguments
git_args_started=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            echo "$VERSION"
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
        --m*)
            if $git_args_started; then
                echo "Error: All mgitlog options (--m*) must appear before git log arguments" >&2
                show_help >&2
                exit 1
            fi
            case $1 in
                --mroot)
                    if [[ -n "${2:-}" ]]; then
                        # Expand a leading ~ without eval (avoids command injection)
                        mroot="$2"
                        # shellcheck disable=SC2088  # these are case patterns, not tilde expansion
                        case "$mroot" in
                            "~")    mroot="$HOME" ;;
                            "~/"*)  mroot="$HOME/${mroot#\~/}" ;;
                        esac
                        root_dirs+=("$mroot")
                        shift 2
                    else
                        echo "Error: --mroot requires a directory argument" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                --mheader)
                    if [[ "${2:-}" =~ ^(auto|always)$ ]]; then
                        show_header="$2"
                        shift 2
                    else
                        show_header="auto"
                        shift
                    fi
                    ;;
                --mexclude)
                    if [[ -n "${2:-}" ]]; then
                        exclude_patterns+=("$2")
                        shift 2
                    else
                        echo "Error: --mexclude requires a pattern argument" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                --mparallelize)
                    parallel_processes="${2:-4}"
                    if ! [[ "$parallel_processes" =~ ^[0-9]+$ ]]; then
                        parallel_processes=4
                        shift
                    else
                        shift 2
                    fi
                    ;;
                --mscandepth)
                    if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                        max_depth="$2"
                        shift 2
                    else
                        echo "Error: --mscandepth requires a numeric argument" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                --minterleave)
                    interleave_mode=true
                    shift
                    ;;
                --mjson)
                    json_mode=true
                    shift
                    ;;
                --msummary)
                    summary_mode=true
                    shift
                    ;;
                --mstale)
                    if [[ -n "${2:-}" ]]; then
                        stale_threshold="$2"
                        stale_mode=true
                        shift 2
                    else
                        echo "Error: --mstale requires a duration (e.g. 30d, 2w)" >&2
                        show_help >&2
                        exit 1
                    fi
                    ;;
                *)
                    echo "Error: Unknown mgitlog option: $1" >&2
                    show_help >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            git_args_started=true
            git_args+=("$1")
            shift
            ;;
    esac
done

#===============================================================================
# Main Execution
#===============================================================================

# Use current directory if no roots specified
[[ ${#root_dirs[@]} -eq 0 ]] && root_dirs+=("$(pwd)")

# Convert all paths to absolute paths
for i in "${!root_dirs[@]}"; do
    if pushd "${root_dirs[i]}" >/dev/null 2>/dev/null; then
        root_dirs[i]="$(pwd)"
        popd >/dev/null
    else
        echo "Error: Cannot access directory: ${root_dirs[i]}" >&2
        exit 1
    fi
done

# Convert git_args array to string
[[ ${#git_args[@]} -gt 0 ]] && printf -v git_args_string '%q ' "${git_args[@]}"

# --mjson implies the interleaved collection path; validate jq is available.
if [[ "$json_mode" == true ]]; then
    interleave_mode=true
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: --mjson requires 'jq' to be installed" >&2
        exit 1
    fi
fi

# Activity overview: one aggregated line per repo, most-recently-active first.
if [[ "$summary_mode" == true ]]; then
    for root_dir in "${root_dirs[@]}"; do
        while IFS= read -r repo; do
            summarize_repo "$repo" "$git_args_string"
        done < <(find_git_repos "$root_dir")
    done | sort -z -t "$US" -k1,1 -nr | render_summary
    exit 0
fi

# Stale detection: list repos whose last commit is older than the threshold.
if [[ "$stale_mode" == true ]]; then
    stale_seconds=$(parse_duration "$stale_threshold") || {
        echo "Error: invalid --mstale duration: '$stale_threshold' (try 30d, 2w, 6m, 1y)" >&2
        exit 1
    }
    cutoff=$(( $(date +%s) - stale_seconds ))
    for root_dir in "${root_dirs[@]}"; do
        while IFS= read -r repo; do
            check_stale_repo "$repo" "$git_args_string" "$cutoff"
        done < <(find_git_repos "$root_dir")
    done | sort -z -t "$US" -k1,1 -n | render_stale
    exit 0
fi

# Interleaved / JSON path: collect commits from every repo into one
# time-sorted stream, then render. This bypasses per-repo headers and hooks.
if [[ "$interleave_mode" == true ]]; then
    if [[ "$json_mode" == true ]]; then
        collect_all_records | render_json
    else
        collect_all_records | render_interleaved_text
    fi
    exit 0
fi

# Process repositories in parallel or sequentially
for root_dir in "${root_dirs[@]}"; do
    if [ "$parallel_processes" -gt 0 ]; then
        # Pass values as positional args ($1..$3), never interpolated into the
        # command string, so paths/args with spaces or shell metacharacters are safe.
        # shellcheck disable=SC2016  # single quotes are intentional: values come via positional args
        find_git_repos "$root_dir" | xargs -P "$parallel_processes" -I {} \
            bash -c 'process_repository "$1" "$2" "$3"' _ {} "$show_header" "$git_args_string" || true
    else
        while IFS= read -r repo; do
            process_repository "$repo" "$show_header" "$git_args_string"
        done < <(find_git_repos "$root_dir")
    fi
done