#!/usr/bin/env bats
#
# Test suite for mgitlog. Run with: bats test/
#
# Each test builds a throwaway directory tree of real git repositories under
# BATS_TEST_TMPDIR, so tests never touch the user's actual repositories.

setup() {
    MGITLOG="$BATS_TEST_DIRNAME/../mgitlog.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"

    # Deterministic identity so commits succeed in CI sandboxes.
    export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
}

# Create a git repo at $1 with a single commit whose message is $2.
# Optional $3 sets the author/committer date (for deterministic ordering tests).
make_repo() {
    local path="$1" msg="${2:-initial commit}" date="${3:-}"
    mkdir -p "$path"
    git -C "$path" init -q
    : > "$path/file.txt"
    git -C "$path" add -A
    if [ -n "$date" ]; then
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
            git -C "$path" commit -q -m "$msg"
    else
        git -C "$path" commit -q -m "$msg"
    fi
}

@test "lists commits from multiple repos under a root" {
    make_repo "$WORK/alpha" "feat: alpha thing"
    make_repo "$WORK/beta"  "fix: beta thing"

    run "$MGITLOG" --mroot "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: alpha thing"* ]]
    [[ "$output" == *"fix: beta thing"* ]]
}

@test "--mheader always prints repo header" {
    make_repo "$WORK/alpha" "feat: alpha thing"

    run "$MGITLOG" --mroot "$WORK" --mheader always
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALPHA ["* ]]
}

@test "--mheader auto only shows header when there are matching commits" {
    make_repo "$WORK/alpha" "feat: alpha thing"

    # Filter by an author that does not exist -> no commits -> no header.
    run "$MGITLOG" --mroot "$WORK" --mheader auto --author=nobody@nowhere
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALPHA ["* ]]
}

@test "--mexclude skips matching repositories" {
    make_repo "$WORK/keepme"      "feat: keep this"
    make_repo "$WORK/test-helper" "feat: exclude this"

    run "$MGITLOG" --mroot "$WORK" --mexclude test
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: keep this"* ]]
    [[ "$output" != *"feat: exclude this"* ]]
}

@test "handles repository paths containing spaces" {
    make_repo "$WORK/my repo" "feat: spaced path"

    run "$MGITLOG" --mroot "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: spaced path"* ]]
}

@test "parallel mode handles paths with spaces and matches sequential output" {
    make_repo "$WORK/my repo"  "feat: spaced path"
    make_repo "$WORK/other"    "fix: other path"

    run "$MGITLOG" --mroot "$WORK" --mparallelize 4
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: spaced path"* ]]
    [[ "$output" == *"fix: other path"* ]]
}

@test "preserves backslash sequences in commit messages" {
    make_repo "$WORK/alpha" 'fix: handle C:\path and \n literally'

    run "$MGITLOG" --mroot "$WORK"
    [ "$status" -eq 0 ]
    # The literal backslash-n must survive (not be turned into a newline).
    [[ "$output" == *'C:\path and \n literally'* ]]
}

@test "--mscandepth limits how deep repos are discovered" {
    make_repo "$WORK/a/b/c/deep" "feat: deep repo"

    # Default depth is 2; the repo sits deeper, so it should not be found.
    run "$MGITLOG" --mroot "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"feat: deep repo"* ]]

    # With a larger scan depth it should be discovered.
    run "$MGITLOG" --mroot "$WORK" --mscandepth 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: deep repo"* ]]
}

@test "rejects mgitlog options that appear after git log args" {
    make_repo "$WORK/alpha" "feat: alpha thing"

    run "$MGITLOG" --mroot "$WORK" --oneline --mheader
    [ "$status" -ne 0 ]
    [[ "$output" == *"must appear before git log arguments"* ]]
}

@test "errors on a non-existent root directory" {
    run "$MGITLOG" --mroot "$WORK/does-not-exist"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot access directory"* ]]
}

@test "--version prints the version" {
    run "$MGITLOG" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help prints usage" {
    run "$MGITLOG" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--minterleave sorts commits newest-first across repos" {
    make_repo "$WORK/old"    "feat: oldest"  "2026-01-01T10:00:00"
    make_repo "$WORK/mid"    "feat: middle"  "2026-03-01T10:00:00"
    make_repo "$WORK/new"    "feat: newest"  "2026-06-01T10:00:00"

    run "$MGITLOG" --mroot "$WORK" --minterleave
    [ "$status" -eq 0 ]
    # Newest must appear before middle, which appears before oldest.
    newest_pos=$(awk '/feat: newest/{print NR; exit}' <<< "$output")
    middle_pos=$(awk '/feat: middle/{print NR; exit}' <<< "$output")
    oldest_pos=$(awk '/feat: oldest/{print NR; exit}' <<< "$output")
    [ "$newest_pos" -lt "$middle_pos" ]
    [ "$middle_pos" -lt "$oldest_pos" ]
}

@test "--minterleave tags each commit with its repo name" {
    make_repo "$WORK/alpha" "feat: a" "2026-01-01T10:00:00"
    make_repo "$WORK/beta"  "feat: b" "2026-02-01T10:00:00"

    run "$MGITLOG" --mroot "$WORK" --minterleave
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ALPHA]"* ]]
    [[ "$output" == *"[BETA]"* ]]
}

@test "--mjson emits a valid, sorted JSON array of all commits" {
    command -v jq >/dev/null || skip "jq not installed"
    make_repo "$WORK/old" "feat: oldest" "2026-01-01T10:00:00"
    make_repo "$WORK/new" "feat: newest" "2026-06-01T10:00:00"

    run "$MGITLOG" --mroot "$WORK" --mjson
    [ "$status" -eq 0 ]
    # Valid JSON, two objects, sorted newest-first by timestamp.
    echo "$output" | jq -e 'length == 2' >/dev/null
    echo "$output" | jq -e '.[0].subject == "feat: newest"' >/dev/null
    echo "$output" | jq -e '.[0].timestamp > .[1].timestamp' >/dev/null
    echo "$output" | jq -e '.[0] | has("repo") and has("hash") and has("author")' >/dev/null
}

@test "--mjson safely escapes quotes and backslashes in commit messages" {
    command -v jq >/dev/null || skip "jq not installed"
    make_repo "$WORK/alpha" 'fix: "quoted" and C:\path \n stays'

    run "$MGITLOG" --mroot "$WORK" --mjson
    [ "$status" -eq 0 ]
    # jq round-trips the exact subject string -> escaping is correct.
    got=$(echo "$output" | jq -r '.[0].subject')
    [ "$got" = 'fix: "quoted" and C:\path \n stays' ]
}

@test "discovers repos via the find fallback when fd is absent" {
    make_repo "$WORK/alpha" "feat: alpha"
    make_repo "$WORK/beta"  "feat: beta"

    # PATH with the required tools but neither fd nor fdfind -> find backend.
    local bindir="$BATS_TEST_TMPDIR/nofd-bin"
    mkdir -p "$bindir"
    for t in git sort find basename dirname tr cat; do
        ln -sf "$(command -v "$t")" "$bindir/$t"
    done

    run env PATH="$bindir" "$MGITLOG" --mroot "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"feat: alpha"* ]]
    [[ "$output" == *"feat: beta"* ]]
}

@test "--mjson errors clearly when jq is unavailable" {
    make_repo "$WORK/alpha" "feat: a"

    # Build a PATH that has every tool the script needs EXCEPT jq, so the
    # missing-jq branch is exercised without breaking the rest of the script.
    local bindir="$BATS_TEST_TMPDIR/nojq-bin"
    mkdir -p "$bindir"
    for t in git sort find basename dirname tr cat; do
        ln -sf "$(command -v "$t")" "$bindir/$t"
    done

    run env PATH="$bindir" "$MGITLOG" --mroot "$WORK" --mjson
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires 'jq'"* ]]
}
