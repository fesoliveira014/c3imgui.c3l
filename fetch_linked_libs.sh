#!/usr/bin/env bash
# Download the prebuilt linked-libs for a release of this package.
#
# Usage: fetch_linked_libs.sh [tag]
#
# The tag defaults to the exact tag this checkout is on. Assets come from the
# GitHub release of that tag; C3IMGUI_RELEASE_URL overrides the base URL (any
# scheme curl accepts, file:// included). Needs curl, tar, and sha256sum or
# shasum.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/fesoliveira014/c3imgui.c3l"
PLATFORMS=(linux-x64 windows-x64)

tag="${1:-}"
if [[ -z "$tag" ]]; then
    tag="$(git -C "$PKG" describe --tags --exact-match 2>/dev/null)" || {
        echo "error: this checkout is not on a tag; pass one: $0 vX.Y.Z" >&2
        exit 2
    }
fi
base="${C3IMGUI_RELEASE_URL:-$REPO_URL/releases/download/$tag}"

sha256_check() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$1" >/dev/null
    else
        shasum -a 256 -c "$1" >/dev/null
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
    local name=$1
    echo "  GET $base/$name"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$name" "$base/$name"; then
        echo "error: could not download $base/$name" >&2
        echo "       (no release for $tag, or the asset is missing)" >&2
        exit 1
    fi
}

fetch SHA256SUMS
for p in "${PLATFORMS[@]}"; do
    fetch "$p.tar.gz"
done

if ! (cd "$tmp" && sha256_check SHA256SUMS); then
    echo "error: checksum mismatch for $tag assets" >&2
    exit 1
fi

for p in "${PLATFORMS[@]}"; do
    tar -xzf "$tmp/$p.tar.gz" -C "$PKG"
done
echo "linked-libs for $tag installed under $PKG/linked-libs"
