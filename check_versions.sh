#!/bin/bash

set -euo pipefail

# Function to get versions from libraryfile
get_versions() {
    grep "Directory:" "$1" | awk '{print $2}' | sort -u
}

# Function to check if we're in a git repository
is_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Function to get previous versions from git
get_previous_versions() {
    git show HEAD~1:libraryfile 2>/dev/null | grep "Directory:" | awk '{print $2}' | sort -u
}

# Function to find updated versions
find_updated_versions() {
    local versions="$1"
    local updated=""
    for version in $versions; do
        if [ -d "$version" ] && [ -n "$(git status -s "$version" 2>/dev/null)" ]; then
            updated="$updated $version"
        fi
    done
    echo "$updated"
}

# Function to trim whitespace from a string
trim_whitespace() {
    echo "$1" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Function to create a summary of changes
create_summary() {
    local summary=""
    [ -n "$1" ] && summary+="Updated: $(echo $1 | tr ' ' ',' | sed 's/,/, /g') "
    [ -n "$2" ] && summary+="Removed: $(echo $2 | tr ' ' ',' | sed 's/,/, /g') "
    [ -n "$3" ] && summary+="Added: $(echo $3 | tr ' ' ',' | sed 's/,/, /g') "
    echo "${summary% }" | sed 's/  */ /g'
}

# Main script execution
main() {
    # Check if libraryfile exists
    if [ ! -f "libraryfile" ]; then
        echo "Error: libraryfile not found" >&2
        exit 1
    fi

    # Get current versions
    current_versions=$(get_versions "libraryfile")

    # Extract previous versions if in a git repository
    previous_versions=""
    if is_git_repo; then
        previous_versions=$(get_previous_versions)
    fi

    # Find updated, added, and removed versions
    updated_versions=$(find_updated_versions "$current_versions")
    added_versions=$(comm -13 <(echo "$previous_versions") <(echo "$current_versions"))
    removed_versions=$(comm -23 <(echo "$previous_versions") <(echo "$current_versions"))

    # Prepare output
    updated_versions=$(trim_whitespace "$updated_versions")
    removed_versions=$(trim_whitespace "$removed_versions")
    added_versions=$(trim_whitespace "$added_versions")

    # Create summary
    summary=$(create_summary "$updated_versions" "$removed_versions" "$added_versions")

    # Output results
    echo "updated_versions=$updated_versions"
    echo "removed_versions=$removed_versions"
    echo "added_versions=$added_versions"
    echo "summary=$summary"

    # For GitHub Actions, if present
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        {
            echo "updated_versions=$updated_versions"
            echo "removed_versions=$removed_versions"
            echo "added_versions=$added_versions"
            echo "summary=$summary"
        } >> "$GITHUB_OUTPUT"
    fi
}

# Run the main function
main
