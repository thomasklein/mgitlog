#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Multi Git Log - Lists commits from specified authors across multiple repositories
# -----------------------------------------------------------------------------

VERSION="1.1.0"

USAGE="Usage: $(basename "$0") [OPTIONS]

Options:
    -r, --repo PATH         Specify repository path(s) to scan. Multiple paths allowed.
                                Default: scans all Git repositories in current directory.
    -e, --exclude PATH      Exclude repository path(s) from scanning.
                                Supports partial matches (e.g., 'test' excludes 'test-repo').
    -d, --date RANGE        Specify commit date range to filter:
                                - YYYY-MM-DD            (specific date)
                                - today, yesterday      (common ranges)
                                - week                  (current week, Mon-Sun)
                                - lastweek             (last week, Mon-Sun)
                                - YYYY-MM-DD..          (from date until today)
                                - YYYY-MM-DD..YYYY-MM-DD (custom date range)
    --log STRING            Override default --shortstat output with custom git log options
                                Example: '--oneline --name-only'
    --json                  Output results in JSON format for parsing
                                Note: Overrides any --log options if specified
    --files                 Show detailed file changes for each commit
                                Note: Shows additions and deletions per file
    --help                  Display this help message
    --version               Show version information"

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

error() {
    echo "Error: $1" >&2
    if [[ "$2" == "show_usage" ]]; then
        echo >&2
        echo "$USAGE" >&2
    fi
    exit 1
}

get_date_range() {
    local today=$(date +%Y-%m-%d)

    case "$1" in
        today)  echo "$today $today" ;;
        week)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                local this_monday=$(date -v-monday +%Y-%m-%d)
                local this_sunday=$(date -v+0d -v-monday -v+6d +%Y-%m-%d)
            else
                local this_monday=$(date -d "monday this week" +%Y-%m-%d)
                local this_sunday=$(date -d "monday this week + 6 days" +%Y-%m-%d)
            fi
            echo "$this_monday $this_sunday"
            ;;
        lastweek)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                local last_monday=$(date -v-monday -v-1w +%Y-%m-%d)
                local last_sunday=$(date -v-monday -v+6d -v-1w +%Y-%m-%d)
            else
                local last_monday=$(date -d "monday last week" +%Y-%m-%d)
                local last_sunday=$(date -d "monday last week + 6 days" +%Y-%m-%d)
            fi
            echo "$last_monday $last_sunday"
            ;;
        yesterday)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                local yesterday=$(date -v-1d +%Y-%m-%d)
            else
                local yesterday=$(date -d "yesterday" +%Y-%m-%d)
            fi
            echo "$yesterday $yesterday"
            ;;
        range)
            # $2 is from_date, $3 is to_date (or empty for today)
            local to_date=${3:-$today}
            echo "$2 $to_date"
            ;;
        *)      echo "$1 $1" ;;
    esac
}

validate_date() {
    local date=$1
    if [[ ! $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        error "Invalid date format: $date (expected YYYY-MM-DD)"
    fi

    # Validate date components - remove leading zeros for comparison
    local year=${date:0:4}
    local month=$((10#${date:5:2}))  # Force base 10 interpretation
    local day=$((10#${date:8:2}))    # Force base 10 interpretation

    if [[ $month -lt 1 || $month -gt 12 ]]; then
        error "Invalid month in date: $date"
    fi

    # Simple day validation (could be more sophisticated)
    if [[ $day -lt 1 || $day -gt 31 ]]; then
        error "Invalid day in date: $date"
    fi
}

format_date_range() {
    local start_date=$1
    local end_date=$2

    if [[ "$OSTYPE" == "darwin"* ]]; then
        start_fmt=$(date -j -f "%Y-%m-%d" "$start_date" "+%b %d" 2>/dev/null)
        end_fmt=$(date -j -f "%Y-%m-%d" "$end_date" "+%b %d" 2>/dev/null)
        year_fmt=$(date -j -f "%Y-%m-%d" "$end_date" "+%Y" 2>/dev/null)
    else
        start_fmt=$(date -d "$start_date" "+%b %d" 2>/dev/null)
        end_fmt=$(date -d "$end_date" "+%b %d" 2>/dev/null)
        year_fmt=$(date -d "$end_date" "+%Y" 2>/dev/null)
    fi

    if [[ "$start_date" == "$end_date" ]]; then
        echo "Git logs for $start_fmt, $year_fmt"
    else
        echo "Git logs $start_fmt - $end_fmt, $year_fmt"
    fi
}

print_base_directories() {
    local -a dirs=("$@")
    if [[ ${#dirs[@]} -eq 1 ]]; then
        printf "Base directory: %s" "${dirs[0]}"
    else
        printf "Base directories: %s" "${dirs[0]}"
        for ((i=1; i<${#dirs[@]}; i++)); do
            printf ", %s" "${dirs[$i]}"
        done
    fi
    echo
}

process_repository() {
    local dir=$1 start_date=$2 end_date=$3 authors=$4 log_options=$5 files_option=$6

    [ ! -d "$dir/.git" ] && return 1

    cd "$dir" || return 1

    # Build author arguments for git log
    local author_args=""
    IFS='|' read -ra author_array <<< "$authors"
    for author in "${author_array[@]}"; do
        author_args+=" --author=$author"
    done

    # Default to --shortstat if no custom log options provided
    local stat_option="--shortstat"
    [[ -n "$log_options" ]] && stat_option="$log_options"

    local has_commits=false
    local repo_name=$(basename "$dir" | tr '[:lower:]' '[:upper:]')

    if [[ "$files_option" == "true" ]]; then
        # Get commits with file details
        local commits=$(git log --all --format="%H" \
            --after="$start_date 00:00:00" \
            --before="$end_date 23:59:59" \
            $author_args 2>/dev/null)
        
        if [[ -n "$commits" ]]; then
            has_commits=true
            echo "$repo_name [$dir]"
            echo "━━━━━━━━━━━━━━━━━━━━"
            echo

            while IFS= read -r commit_hash; do
                # Print commit header with body - disable pager with --no-pager
                git --no-pager -c color.ui=always log -1 --pretty=format:"%C(yellow)commit %H%Creset%n%an <%ae>%n%ad%n%n    %s%n%n" "$commit_hash"
                # Format commit body with proper indentation
                git --no-pager log -1 --pretty=format:"%b" "$commit_hash" | sed 's/^/    /'
                echo

                # Get the summary line (total changes)
                local summary
                summary=$(git show --format="" --shortstat "$commit_hash")
                echo "$summary"

                # Get and print file changes
                git show --format="" --numstat "$commit_hash" | while read -r additions deletions file; do
                    # Skip empty lines
                    [[ -z "$additions" || -z "$file" ]] && continue
                    
                    # Handle binary files
                    if [[ "$additions" == "-" ]]; then
                        printf "   %s (binary)\n" "$file"
                    else
                        printf "   %s (\033[32m+%s\033[0m \033[31m-%s\033[0m)\n" "$file" "$additions" "$deletions"
                    fi
                done
                echo
            done <<< "$commits"
        fi
    else
        # Original behavior for normal output
        local commits
        commits=$(git -c color.ui=always log --all \
            $stat_option \
            --find-renames \
            --after="$start_date 00:00:00" \
            --before="$end_date 23:59:59" \
            $author_args 2>/dev/null)

        if [[ -n "$commits" ]]; then
            has_commits=true
            echo "$repo_name [$dir]"
            echo "━━━━━━━━━━━━━━━━━━━━"
            echo
            echo "$commits"
            echo
        fi
    fi

    [[ "$has_commits" == "true" ]] && return 0 || return 1
}

generate_json_output() {
    local start_date=$1
    local end_date=$2
    local authors=$3
    local first_repo=true
    
    # Start JSON structure
    echo "{"
    echo "  \"date_range\": \"$start_date..$end_date\","
    
    # Add authors array
    echo "  \"authors\": ["
    IFS='|' read -ra author_array <<< "$authors"
    local first_author=true
    for author in "${author_array[@]}"; do
        if ! $first_author; then echo "," ; fi
        echo "    \"$author\""
        first_author=false
    done
    echo "  ],"
    
    echo "  \"repositories\": ["
    
    return 0
}

process_repository_json() {
    local dir=$1 start_date=$2 end_date=$3 authors=$4 first_repo=$5 files_option=$6
    
    [ ! -d "$dir/.git" ] && return 1
    
    cd "$dir" || return 1
    
    # Build author arguments
    local author_args=""
    IFS='|' read -ra author_array <<< "$authors"
    for author in "${author_array[@]}"; do
        author_args+=" --author=$author"
    done
    
    # Get commit data with stats
    local commits=""
    while IFS= read -r line; do
        if [[ $line =~ ^commit ]]; then
            # Start of a new commit
            [[ -n "$commits" ]] && commits="${commits},"
            hash="${line#commit }"
            hash="${hash## }" # Remove leading spaces
            
            # Get commit details with proper indentation
            local details
            details=$(git show -s --format='        {
          "commit": "%H",
          "author": "%an",
          "author_email": "%ae",
          "author_date": "%ad",
          "subject": "%s",
          "body": "'"$(git show -s --format=%b "$hash" | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g')"'"' "$hash")
            commits+="$details"
            
            # Only include file changes if --files option is set
            if [[ "$files_option" == "true" ]]; then
                # Get changed files with stats using --numstat
                local files_output
                files_output=$(git show --format="" --numstat "$hash")
                
                commits+=',
          "changes": {'
                
                local first_file=true
                while IFS=$'\t' read -r additions deletions file; do
                    # Skip empty lines
                    [[ -z "$additions" || -z "$file" ]] && continue
                    
                    if ! $first_file; then
                        commits+=","
                    fi
                    first_file=false
                    
                    # Handle binary files
                    if [[ "$additions" == "-" ]]; then
                        additions="0"
                        deletions="0"
                    fi
                    
                    # Escape quotes in filenames
                    file="${file//\"/\\\"}"
                    
                    commits+="
            \"$file\": {
              \"additions\": $additions,
              \"deletions\": $deletions
            }"
                done <<< "$files_output"
                
                commits+="
          }"
            fi
            
            commits+="
        }"
        fi
    done < <(git log --all \
        --find-renames \
        --after="$start_date 00:00:00" \
        --before="$end_date 23:59:59" \
        $author_args 2>/dev/null)
    
    [ -z "$commits" ] && return 1
    
    # Output repository entry with proper indentation
    if ! $first_repo; then echo "    ," ; fi
    echo "    {"
    echo "      \"repository\": \"$dir\","
    echo "      \"commits\": ["
    echo "$commits"
    echo "      ]"
    echo "    }"
    
    return 0
}

# -----------------------------------------------------------------------------
# Main Function
# -----------------------------------------------------------------------------

main() {
    local -a dirs=() excludes=() 
    local -a authors=()
    local date_spec=""
    local log_options=""
    local json_output=false
    local files_option=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo)
                [[ -z "$2" ]] && error "Repository path required" "show_usage"
                dirs+=("$2")
                shift 2
                ;;
            -e|--exclude)
                [[ -z "$2" ]] && error "Exclude path required" "show_usage"
                excludes+=("$2")
                shift 2
                ;;
            --log)
                [[ -z "$2" ]] && error "Log options required" "show_usage"
                log_options="$2"
                shift 2
                ;;
            -d|--date)
                [[ -z "$2" ]] && error "Date range required" "show_usage"
                date_spec="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            --files)
                files_option=true
                shift
                ;;
            --help)
                echo "$USAGE"
                exit 0
                ;;
            --version)
                echo "$VERSION"
                exit 0
                ;;
            *)
                error "Unknown option: $1" "show_usage"
                ;;
        esac
    done

    # Set defaults
    [[ ${#dirs[@]} -eq 0 ]] && dirs+=("$(pwd)")
    [[ ${#authors[@]} -eq 0 ]] && authors+=("$(git config user.email)")

    # Parse date specification
    local start_date end_date
    if [[ -z "$date_spec" ]]; then
        read -r start_date end_date < <(get_date_range "today")
    elif [[ "$date_spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        read -r start_date end_date < <(get_date_range "$date_spec")
    elif [[ "$date_spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.\.[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        local from_date="${date_spec%..*}"
        local to_date="${date_spec#*..}"
        read -r start_date end_date < <(get_date_range "range" "$from_date" "$to_date")
    elif [[ "$date_spec" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.\.$ ]]; then
        local from_date="${date_spec%..*}"
        read -r start_date end_date < <(get_date_range "range" "$from_date")
    elif [[ "$date_spec" =~ ^(today|yesterday|week|lastweek)$ ]]; then
        read -r start_date end_date < <(get_date_range "$date_spec")
    else
        error "Invalid date format: $date_spec" "show_usage"
    fi

    # Print date range header only if not in JSON mode
    if ! $json_output; then
        echo
        echo "$(format_date_range "$start_date" "$end_date")"
        echo "Author(-s): $(IFS=', '; echo "${authors[*]}")"
        echo
    fi

    if $json_output; then
        generate_json_output "$start_date" "$end_date" "$(IFS='|'; echo "${authors[*]}")"
        local first_repo=true
        for dir in "${dirs[@]}"; do
            while IFS= read -r -d '' repo; do
                # Skip excluded paths
                local skip=false
                if [[ ${#excludes[@]} -gt 0 ]]; then
                    for exclude in "${excludes[@]}"; do
                        if [[ "$repo" == *"$exclude"* ]]; then
                            skip=true
                            break
                        fi
                    done
                fi
                $skip && continue

                if process_repository_json "$repo" "$start_date" "$end_date" \
                    "$(IFS='|'; echo "${authors[*]}")" "$first_repo" "$files_option"; then
                    found_commits=true
                    first_repo=false
                fi
            done < <(find "$dir" -maxdepth 1 -type d ! -name ".*" ! -name "node_modules" -print0)
        done
        # Close JSON structure
        echo "  ]"
        echo "}"
    else
        # Process repositories
        local found_commits=false
        local last_repo_had_commits=false
        for dir in "${dirs[@]}"; do
            while IFS= read -r -d '' repo; do
                # Skip excluded paths
                local skip=false
                if [[ ${#excludes[@]} -gt 0 ]]; then
                    for exclude in "${excludes[@]}"; do
                        if [[ "$repo" == *"$exclude"* ]]; then
                            skip=true
                            break
                        fi
                    done
                fi
                $skip && continue

                # Add newlines only if the previous repository had commits
                if $last_repo_had_commits; then
                    echo
                    echo
                fi

                if process_repository "$repo" "$start_date" "$end_date" \
                    "$(IFS='|'; echo "${authors[*]}")" "$log_options" "$files_option"; then
                    found_commits=true
                    last_repo_had_commits=true
                else
                    last_repo_had_commits=false
                fi
            done < <(find "$dir" -maxdepth 1 -type d ! -name ".*" ! -name "node_modules" -print0)
        done

        $found_commits || echo "No commits found."
    fi
}

main "$@"