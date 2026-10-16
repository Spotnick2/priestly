#!/usr/bin/env bash
# release_files.sh - Write what a tag publishes next to its zip: the release
# notes (the tag's CHANGELOG.md section) and release.json, the manifest addon
# managers read to pick the right zip for a client (#103). CI's `release` and
# `wago` jobs use both; `check` runs it on every pull request, so a broken
# changelog heading or TOC field fails there instead of at tag time.
#
# Why not the packager's own release.json: it writes one only inside its
# GitHub upload, which also creates (or PATCHes) the GitHub Release with the
# whole CHANGELOG.md as its body - what the `release` job exists to avoid.
# The schema is the packager's (release.sh upload_github, v2.6.1):
#   {"releases":[{"name","version","filename","nolib","metadata":[{"flavor","interface"}]}]}
#
# Everything is read from the PACKAGED TOC, the file players get - not the
# repository copy.
#
# Usage (from the repo root):  bash tests/release_files.sh <tag> <zip> <out dir>
#   e.g.  bash tests/release_files.sh v2.0.16 .release/Priestly-v2.0.16-forever.zip "$RUNNER_TEMP/out"
# A pre-release tag (v2.0.16-alpha1) uses its own changelog section if there
# is one, else the section of the version it is a trial of.
# Needs jq and unzip.
set -euo pipefail

tag="${1:-}"
zip="${2:-}"
out="${3:-}"
if [ -z "$tag" ] || [ -z "$zip" ] || [ -z "$out" ]; then
    echo "usage: bash tests/release_files.sh <tag> <zip> <out dir>" >&2
    exit 2
fi
test -f "$zip" || { echo "no zip at $zip" >&2; exit 1; }
mkdir -p "$out"

# The heading is "## v2.0.15 - 2026-10-11": the tag, then a space or nothing.
# The blank lines around the section are dropped.
section() {
    tr -d '\r' < CHANGELOG.md |
        awk -v h="## $1" '$0 == h || index($0, h " ") == 1 { on = 1; next } on && /^## / { exit } on' |
        sed -e '/[^[:space:]]/,$!d' | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}
section "$tag" > "$out/notes.md"
grep -q '[^[:space:]]' "$out/notes.md" || section "${tag%%-*}" > "$out/notes.md"
grep -q '[^[:space:]]' "$out/notes.md" ||
    { echo "CHANGELOG.md has no '## $tag' or '## ${tag%%-*}' section" >&2; exit 1; }

toc=$(unzip -p "$zip" Priestly/Priestly.toc | tr -d '\r')
field() { printf '%s\n' "$toc" | sed -n "s/^## $1: *//p" | head -1; }

# |cffRRGGBB...|r colour codes stripped, as the packager does for "name".
title=$(field Title | sed -E 's/\|c[0-9A-Fa-f]{8}//g; s/\|r//g')
test -n "$title" || { echo "the packaged TOC has no Title" >&2; exit 1; }

# One metadata entry per interface. Only Forever is mapped: a number from any
# other client fails here rather than being published under a guessed flavor.
interfaces=$(field Interface | tr ',' '\n' | tr -d ' ')
test -n "$interfaces" || { echo "the packaged TOC has no Interface" >&2; exit 1; }
for i in $interfaces; do
    case "$i" in
        16[0-9][0-9][0-9]) ;;
        *) echo "interface $i is not Forever (16xxx); add its flavor here first" >&2; exit 1 ;;
    esac
done

jq -c -n \
    --arg name "$title" \
    --arg version "$tag" \
    --arg filename "$(basename "$zip")" \
    --argjson interfaces "$(printf '%s\n' $interfaces | jq -s .)" \
    '{releases: [{name: $name, version: $version, filename: $filename, nolib: false,
                  metadata: [$interfaces[] | {flavor: "forever", interface: .}]}]}' \
    > "$out/release.json"

echo "notes: $(wc -l < "$out/notes.md") lines"
cat "$out/release.json"
