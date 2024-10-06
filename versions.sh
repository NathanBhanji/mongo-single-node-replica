#!/usr/bin/env bash
set -Eeuo pipefail

shell="$(
    wget -qO- 'https://downloads.mongodb.org/current.json' \
    | jq -r '
        [
            .versions[]

            # Filter out download objects we are not interested in (enterprise, rhel, etc)
            | del(.downloads[] | select(
                (
                    .edition == "base"
                    or .edition == "targeted"
                )
                and (
                    .target // ""
                    | (
                        test("^(" + ([
                            "debian[0-9]+", # debian10, debian11, etc
                            "ubuntu[0-9]{4}" # ubuntu2004, ubuntu1804, etc
                        ] | join("|")) + ")$")
                        and (
                            # Exclude old versions
                            test("^(" + ([
                                "debian[89].*",
                                "ubuntu1[0-9].*"
                            ] | join("|")) + ")$")
                            | not
                        )
                    )
                )
            | not))

            | {
                version: (
                    # Convert "4.4.x" into "4.4" and "4.9.x-rcY" into "4.9-rc"
                    (.version | split(".")[0:2] | join("."))
                    + if .release_candidate then "-rc" else "" end
                ),
                meta: .,
            }

            # Filter out EOL versions
            | select(.version as $v | [
                "3.0",
                "3.2",
                "3.4",
                "3.6",
                "4.0",
                "4.2",
                empty
            ] | index($v) | not)

            # Filter out rapid releases
            | select(
                (.version | split("[.-]"; "")) as $splitVersion
                | ($splitVersion[0] | tonumber? // 0) >= 5 and ($splitVersion[1] | tonumber? // 0) > 0
                | not
            )
        ]

        # Prefer the first entry in case of duplicates
        | unique_by(.version)

        # Convert data to a shell list and map
        | "allVersions=( " + (
            map(.version | ., if endswith("-rc") then rtrimstr("-rc") else . + "-rc" end)
            | unique
            | map(@sh)
            | join(" ")
        ) + " )\n"
        + "declare -A versionMeta\n" + (
            map(
                "versionMeta[" + (.version | @sh) + "]=" + (.meta | @json | @sh)
            ) | join("\n")
        ) + "\n"
    '
)"
eval "$shell"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
    versions=( "${allVersions[@]}" )
    json='{}'
else
    versions=( "${versions[@]%/}" )
    json="$(< versions.json)"
fi

for version in "${versions[@]}"; do
    export version

    if [ -z "${versionMeta["$version"]:+foo}" ]; then
        echo >&2 "warning: skipping/removing '$version' (does not appear to exist upstream)"
        json="$(jq <<<"$json" -c '.[env.version] = null')"
        continue
    fi
    _jq() { jq <<<"${versionMeta["$version"]}" "$@"; }

    # Display version information
    _jq -r 'env.version + ": " + .version'

    json="$(
        {
            jq <<<"$json" -c .
            _jq --slurpfile pgpKeys pgp-keys.json '{ (env.version): (
                $pgpKeys[0] as $pgp
                | (env.version | rtrimstr("-rc")) as $rcVersion
                | with_entries(select(.key as $key | [
                    "changes",
                    "date",
                    "githash",
                    "notes",
                    "version",
                    empty
                ] | index($key)))
                + {
                    pgp: [
                        if env.version != $rcVersion then
                            $pgp.dev
                        else empty end,

                        $pgp[$rcVersion],

                        empty
                    ],
                    targets: (
                        reduce (
                            .downloads[]
                            | select(.target | test("^windows") | not)
                        ) as $d ({}; $d.target as $t |
                            .[$t].arches |= (. + [
                                {
                                    "aarch64": "arm64v8",
                                    "arm64": "arm64v8",
                                    "s390x": "s390x",
                                    "x86_64": "amd64",
                                }[$d.arch] // ("unknown:" + $d.arch)
                            ] | sort)
                            | if $t | test("^(debian|ubuntu)") then
                                .[$t].image = (
                                    {
                                        "debian10": "debian:buster-slim",
                                        "debian11": "debian:bullseye-slim",
                                        "debian12": "debian:bookworm-slim",
                                        "debian13": "debian:trixie-slim",
                                        "debian14": "debian:forky-slim",
                                        "ubuntu1604": "ubuntu:xenial",
                                        "ubuntu1804": "ubuntu:bionic",
                                        "ubuntu2004": "ubuntu:focal",
                                        "ubuntu2204": "ubuntu:jammy",
                                        "ubuntu2404": "ubuntu:noble",
                                    }[$t] // "unknown"
                                )
                                | .[$t].suite = (
                                    .[$t].image
                                    | gsub("^.*:|-slim$"; "")
                                )
                            else . end
                        )
                    ),
                }
                | .linux = (
                    # Choose an appropriate Linux target
                    .targets
                    | to_entries
                    | [ .[] | select(.key | test("^(debian|ubuntu)")) ]
                    | sort_by([
                        (.value.arches | length),
                        (
                            .key
                            | if startswith("ubuntu") then
                                1
                            elif startswith("debian") then
                                2
                            else 0 end
                        ),
                        (.key | sub("^(debian|ubuntu)"; "") | tonumber? // 0),
                        .key
                    ])
                    | reverse[0].key
                )
                | .
            ) }'
        } | jq -cs add
    )"
done

jq <<<"$json" -S . > versions.json
