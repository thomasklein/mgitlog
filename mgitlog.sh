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
VERSION="1.0.0"

# Arrays to store multiple root directories and git arguments
declare -a root_dirs        # Stores paths to search for repositories
declare -a git_args=()      # Stores arguments to pass to git log
declare -a exclude_patterns=() # Patterns for repositories to exclude

# Control flags and settings
show_header="none"         # Header display mode: none, auto, always
git_args_string=""         # Concatenated git arguments as a single string
parallel_processes=0       # Number of parallel processes (0 = sequential)
max_depth=2               # Maximum directory depth for repository scanning

# Export git_args for subshell access
export git_args

#===============================================================================
# Helper Functions
#===============================================================================

# Display usage information and available options
show_help() {
    cat << EOF
Usage: $TOOL_NAME [options] [git log arguments] # Run 'git log' across multiple repositories

Options:
  --mroot DIR               Specify root directory. Defaults to current directory 
                              and checks direct subdirectories (can be used multiple times)
  --mheader [style]         Show repository headers. Optional style: 'auto' (default), 'always'
                              'auto' only shows headers when there are commits to display
  --mexclude PATTERN        Exclude repository path(s) from scanning (can be used multiple times)
                              Supports partial matches (e.g., 'test' excludes 'test-repo')
  --mparallelize [NUMBER]   Enable parallel processing with optional number of processes (default: 4)
  --mscandepth NUMBER       Maximum depth when scanning for repositories (default: 2)
  --help                    Show this help message
  --version                 Show version information
  
Environment Variables:
  MGITLOG_BEFORE_CMD        A command (or series of commands) to run *before* 'git log' in each repository.
                              For example:
                              MGITLOG_BEFORE_CMD="git pull --rebase" mgitlog

  MGITLOG_AFTER_CMD         A command (or series of commands) to run *after* 'git log' output is printed for each repository.
                              The result of the git log command is piped into the command.
                              For example:
                              MGITLOG_AFTER_CMD="echo 'Done with repo!'" mgitlog

If these variables are unset or empty, no pre- or post-processing is done.
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
    
    local output=""
    if [[ "$header_mode" == "always" ]] || [[ "$header_mode" == "auto" && -n "$content" ]]; then
        local repo_name
        repo_name=$(basename "$repo_path" | tr '[:lower:]' '[:upper:]')
        output+="\n$repo_name [$repo_path]\n"
        output+="----------------------------------------\n\n"
    fi
    [[ -n "$content" ]] && output+="$content\n\n"
    echo -e "$output"
}

# Process a single repository
# This function:
# 1. Runs pre-processing hook if defined
# 2. Executes git log with provided arguments
# 3. Formats the output
# 4. Runs post-processing hook if defined
#
# Args:
#   $1 - Path to repository
#   $2 - Show header flag
#   $3 - Git arguments string
process_repository() {
    local repo_path="$1"
    local show_header="$2"
    local git_args_str="$3"
    
    [[ -z "$repo_path" ]] && return
    
    # HOOK: Pre-processing (e.g., git pull, checkout branch)
    if [[ -n "${MGITLOG_BEFORE_CMD:-}" ]]; then
        execute_in_dir "$repo_path" "$MGITLOG_BEFORE_CMD" "Pre-processing command failed" || return
    fi
    
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
        
        # HOOK: Post-processing (e.g., logging, additional formatting)
        if [[ -n "${MGITLOG_AFTER_CMD:-}" && -n "$git_output" ]]; then
            echo -e "$git_output" | execute_in_dir "$repo_path" "$MGITLOG_AFTER_CMD" "Post-processing command failed"
        fi
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

    # If the directory itself is a git repo, return it (unless excluded)
    if [[ -d "$dir/.git" ]]; then
        is_excluded "$dir" || echo "$dir"
        return
    fi

    # Find all .git directories and output their parent paths
    # -L flag follows symlinks for more thorough scanning
    find -L "$dir" -maxdepth "$max_depth" -type d -name .git -prune 2>/dev/null | while read -r gitdir; do
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
                        root_dirs+=("$(eval echo "$2")")
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
    if pushd "${root_dirs[$i]}" >/dev/null 2>/dev/null; then
        root_dirs[$i]="$(pwd)"
        popd >/dev/null
    else
        echo "Error: Cannot access directory: ${root_dirs[$i]}" >&2
        exit 1
    fi
done

# Convert git_args array to string
[[ ${#git_args[@]} -gt 0 ]] && printf -v git_args_string '%q ' "${git_args[@]}"

# Process repositories in parallel or sequentially
for root_dir in "${root_dirs[@]}"; do
    if [ "$parallel_processes" -gt 0 ]; then
        find_git_repos "$root_dir" | xargs -P "$parallel_processes" -I {} bash -c "process_repository {} '$show_header' '$git_args_string'" || true
    else
        while IFS= read -r repo; do
            process_repository "$repo" "$show_header" "$git_args_string"
        done < <(find_git_repos "$root_dir")
    fi
done