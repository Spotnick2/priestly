#!/usr/bin/env bash
# fetch_external.sh - Clone one of .pkgmeta's externals at the ref it pins,
# and prove the checkout IS that ref. CI runs it for both embedded libraries
# before the tests (they load them from $LIBGROUPBUFFS and $LIBGLASS); it also
# works locally from git bash.
#
# The url and the pin are read from .pkgmeta, the one place they are written,
# BY PATH (tests/pkgmeta.lua): with two externals, the first `tag:` in the
# file is not necessarily the one asked for. A `commit:` pin works as well as
# a `tag:` - Priestly pilots a library release on a commit before it is
# tagged.
#
# Usage (from the repo root):  bash tests/fetch_external.sh <external path> <dest>
#   e.g.  bash tests/fetch_external.sh Libs/LibGlass-1.0 "$RUNNER_TEMP/LibGlass"
#
# <dest> must not exist: the script never deletes anything (a default of a
# sibling checkout would have wiped the dev copy, uncommitted work included).
# Needs lua5.1 on PATH (or $LUA).
set -euo pipefail

path="${1:-}"
dest="${2:-}"
if [ -z "$path" ] || [ -z "$dest" ]; then
    echo "usage: bash tests/fetch_external.sh <external path> <dest>   (dest must not exist yet)" >&2
    exit 2
fi
if [ -e "$dest" ]; then
    echo "$dest already exists; refusing to touch it (pick a fresh path)" >&2
    exit 1
fi

lua="${LUA:-lua5.1}"
url=$("$lua" tests/pkgmeta.lua "$path" url)
kind=$("$lua" tests/pkgmeta.lua "$path" kind)
ref=$("$lua" tests/pkgmeta.lua "$path" ref)

echo "$path: $kind $ref from $url -> $dest"
# A full clone: a commit pin can't be fetched with --branch (the packager does
# the same for `commit:`).
git clone -q "$url" "$dest"
git -C "$dest" -c advice.detachedHead=false checkout -q "$ref"

# The pinned-ref check: HEAD must be the commit the pin names.
want=$(git -C "$dest" rev-parse --verify "$ref^{commit}")
head=$(git -C "$dest" rev-parse HEAD)
if [ "$head" != "$want" ]; then
    echo "$path checkout is at $head, but .pkgmeta pins $kind $ref ($want)" >&2
    exit 1
fi
echo "$path checkout at $head (pinned $kind $ref)"
