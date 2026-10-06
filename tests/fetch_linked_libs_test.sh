#!/usr/bin/env bash
# Exercises fetch_linked_libs.sh against a file:// release directory.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(dirname "$here")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rel="$work/release"
mkdir -p "$rel"
for p in linux-x64 windows-x64; do
    mkdir -p "$work/src/$p/linked-libs/$p"
    echo "$p" > "$work/src/$p/linked-libs/$p/payload.bin"
    echo '{}' > "$work/src/$p/manifest.json"
    (cd "$work/src/$p" && zip -X -q -r "$rel/c3imgui-v9.9.9-$p.c3l" manifest.json linked-libs)
done
(cd "$rel" && sha256sum ./*.c3l | sed 's|\./||' > SHA256SUMS)

dst="$work/pkg"
mkdir -p "$dst"
cp "$pkg/fetch_linked_libs.sh" "$dst/"

C3IMGUI_RELEASE_URL="file://$rel" bash "$dst/fetch_linked_libs.sh" v9.9.9
[[ "$(cat "$dst/linked-libs/linux-x64/payload.bin")" == linux-x64 ]]
[[ "$(cat "$dst/linked-libs/windows-x64/payload.bin")" == windows-x64 ]]

echo corrupt >> "$rel/c3imgui-v9.9.9-linux-x64.c3l"
rm -rf "$dst/linked-libs"
if C3IMGUI_RELEASE_URL="file://$rel" bash "$dst/fetch_linked_libs.sh" v9.9.9 2>/dev/null; then
    echo "FAIL: corrupted archive accepted" >&2
    exit 1
fi
[[ ! -e "$dst/linked-libs" ]]

if (cd "$dst" && git init -q && bash ./fetch_linked_libs.sh 2>/dev/null); then
    echo "FAIL: untagged checkout without a tag argument accepted" >&2
    exit 1
fi

echo "fetch_linked_libs_test: ok"
