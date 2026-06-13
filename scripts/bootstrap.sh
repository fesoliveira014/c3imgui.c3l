#!/usr/bin/env bash
# Fetch the build-time dependencies c3imgui.c3l needs into lib/vendor/.
#
# The committed .c3i bindings + the prebuilt linked-libs are all a *consumer*
# needs. These two upstream checkouts are only required to (re)build
# libdcimgui.a from source (build_<platform>.sh) or to regenerate the C API
# (generate.sh). lib/vendor/ is gitignored — this is local-only dev state.
#
#   vendor/imgui/          ocornut/imgui          (Dear ImGui C++ source)
#   vendor/dear_bindings/  dearimgui/dear_bindings (C-API generator)
#
# Pins are docking-branch to match the committed bindings (DockNodeFlags,
# multi-viewport, ImTextureRef/ImFontBaked — the 1.92.x dynamic-font rework).
# Override any pin via env, e.g. IMGUI_REF=v1.92.7-docking bash bootstrap.sh.
set -euo pipefail

# REPO is the c3imgui package's parent (lib/), matching build_*.sh / generate.sh,
# which resolve IMGUI as "$REPO/vendor/imgui".
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR="$REPO/vendor"

IMGUI_URL="${IMGUI_URL:-https://github.com/ocornut/imgui.git}"
IMGUI_REF="${IMGUI_REF:-v1.92.8-docking}"
DEAR_BINDINGS_URL="${DEAR_BINDINGS_URL:-https://github.com/dearimgui/dear_bindings.git}"
# Pinned to a commit (not a moving branch) for reproducibility. Bump deliberately.
DEAR_BINDINGS_REF="${DEAR_BINDINGS_REF:-c9ff64913915df41c0f4beef485b98a1c685eda5}"

mkdir -p "$VENDOR"

# Clone (or fast-forward to) a specific ref. Shallow when the ref is a tag/sha
# we can fetch directly; falls back to a full clone + checkout otherwise.
fetch_dep() {
    local name="$1" url="$2" ref="$3"
    local dst="$VENDOR/$name"

    if [[ -d "$dst/.git" ]]; then
        echo "==> $name: updating existing checkout to $ref"
        git -C "$dst" fetch --tags --depth 1 origin "$ref" 2>/dev/null \
            || git -C "$dst" fetch --tags origin
        git -C "$dst" checkout --quiet --force "$ref"
    else
        echo "==> $name: cloning $url @ $ref"
        # Try a shallow single-ref clone first; full clone is the fallback for
        # refs that can't be fetched shallowly on some git/host combinations.
        if git clone --quiet --depth 1 --branch "$ref" "$url" "$dst" 2>/dev/null; then
            :
        else
            git clone --quiet "$url" "$dst"
            git -C "$dst" checkout --quiet --force "$ref"
        fi
    fi
    echo "    $name @ $(git -C "$dst" rev-parse --short HEAD)"
}

fetch_dep imgui         "$IMGUI_URL"         "$IMGUI_REF"
fetch_dep dear_bindings "$DEAR_BINDINGS_URL" "$DEAR_BINDINGS_REF"

echo
echo "vendor ready at $VENDOR"
echo "next:"
echo "  bash $REPO/c3imgui.c3l/scripts/generate.sh         # regenerate the C API"
echo "  bash $REPO/c3imgui.c3l/scripts/build_linux_x64.sh  # build libdcimgui.a"
