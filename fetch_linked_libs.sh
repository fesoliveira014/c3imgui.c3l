#!/usr/bin/env bash
# Download the prebuilt linked-libs for a release of this package.
#
# Usage: fetch_linked_libs.sh [tag]
#
# The tag defaults to the exact tag this checkout is on. Each platform's
# c3imgui-v<version>-<platform>.c3l comes from the GitHub release of that tag;
# its linked-libs/ directory is extracted into this package. C3IMGUI_RELEASE_URL
# overrides the base URL (any scheme curl accepts, file:// included). Needs curl,
# unzip, and sha256sum or shasum.
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

artifact() {
    echo "c3imgui-$1-$2.c3l"
}

fetch SHA256SUMS
for p in "${PLATFORMS[@]}"; do
    fetch "$(artifact "$tag" "$p")"
done

# SHA256SUMS covers every release file; check only the ones fetched here.
(
    cd "$tmp"
    for p in "${PLATFORMS[@]}"; do
        grep -F -- " $(artifact "$tag" "$p")" SHA256SUMS
    done > fetched.sums
)
if ! (cd "$tmp" && sha256_check fetched.sums); then
    echo "error: checksum mismatch for $tag assets" >&2
    exit 1
fi

for p in "${PLATFORMS[@]}"; do
    unzip -q -o "$tmp/$(artifact "$tag" "$p")" 'linked-libs/*' -d "$PKG"
done
echo "linked-libs for $tag installed under $PKG/linked-libs"
