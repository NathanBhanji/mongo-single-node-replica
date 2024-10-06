#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
    [8.0]='8 latest'
    [7.0]='7'
    [6.0]='6'
    [5.0]='5'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
    versions="$(jq -r 'to_entries | map(if .value then .key | @sh else empty end) | join(" ")' versions.json)"
    eval "set -- $versions"
fi

# Sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

# Get the most recent commit which modified any of "$@"
fileCommit() {
    git log -1 --format='format:%H' HEAD -- "$@"
}

# Get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
    local dir="$1"; shift
    (
        cd "$dir"
        fileCommit \
            Dockerfile \
            $(git show HEAD:./Dockerfile | awk '
                toupper($1) == "COPY" {
                    for (i = 2; i < NF; i++) {
                        print $i
                    }
                }
            ')
    )
}

# Get architectures of parent images
getArches() {
    local repo="$1"; shift
    local officialImagesBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}/"

    local parentRepoToArchesStr
    parentRepoToArchesStr="$(
        find . -name 'Dockerfile' -exec awk -v officialImagesBase="$officialImagesBase" '
                toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|.*\/.*)(:|$)/ {
                    printf "%s%s\n", officialImagesBase, $2
                }
            ' '{}' \; \
            | sort -u \
            | xargs -r bashbrew cat --format '["{{ .RepoName }}:{{ .TagName }}"]="{{ join " " .TagEntry.Architectures }}"'
    )"
    eval "declare -g -A parentRepoToArches=( $parentRepoToArchesStr )"
}
getArches 'mongo'

cat <<-EOH
# This file is generated via https://github.com/NathanBhanji/mongo-single-node-replica/blob/$(fileCommit "$self")/$self

Maintainers: Nathan Bhanji <nathanbhanji@flux-ltd.co.uk> (@NathanBhanji)
GitRepo: https://github.com/NathanBhanji/mongo-single-node-replica.git
EOH

# Function to join array elements with a separator
join() {
    local sep="$1"; shift
    local out; printf -v out "${sep//%/%%}%s" "$@"
    echo "${out#$sep}"
}

for version; do
    rcVersion="${version%-rc}"
    export version rcVersion

    if ! fullVersion="$(jq -er '.[env.version] | if . then .version else empty end' versions.json)"; then
        continue
    fi

    if [ "$rcVersion" != "$version" ] && [ -e "$rcVersion/Dockerfile" ]; then
        # Skip if release candidate is already GA
        rcFullVersion="$(jq -r '.[env.rcVersion].version' versions.json)"
        latestVersion="$({ echo "$fullVersion"; echo "$rcFullVersion"; } | sort -V | tail -1)"
        if [[ "$fullVersion" == "$rcFullVersion"* ]] || [ "$latestVersion" = "$rcFullVersion" ]; then
            continue
        fi
    fi

    versionAliases=(
        $fullVersion
        $version
        ${aliases[$version]:-}
    )

    # Remove Windows variants
    variants=('')
    # variants="$(jq -r '.[env.version].targets.windows.variants | [""] + map("windows/" + .) | map(@sh) | join(" ")' versions.json)"
    # eval "variants=( $variants )"

    for v in "${variants[@]}"; do
        dir="$version"
        commit="$(dirCommit "$dir")"

        variant="$(jq -r '.[env.version] | .targets[.linux].suite' versions.json)" # e.g., "bullseye"

        variantAliases=( "${versionAliases[@]/%/-$variant}" )
        variantAliases=( "${variantAliases[@]//latest-/}" )

        sharedTags=( "${versionAliases[@]}" )

        variantArches="$(jq -r '.[env.version] | .targets[.linux].arches | map(@sh) | join(" ")' versions.json)"
        eval "variantArches=( $variantArches )"

		echo
		echo "Tags: $(join ', ' "${variantAliases[@]}")"
		if [ "${#sharedTags[@]}" -gt 0 ]; then
			echo "SharedTags: $(join ', ' "${sharedTags[@]}")"
		fi
		cat <<-EOE
			Architectures: $(join ', ' "${variantArches[@]}")
			GitCommit: $commit
			Directory: $dir
		EOE
	done
done
