#!/usr/bin/env bash
# Fetch the build-time dependencies into vendor/ (gitignored): Dear ImGui and
# the dear_bindings C API generator. Override a pin with IMGUI_REF or
# DEAR_BINDINGS_REF.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor"

IMGUI_URL="${IMGUI_URL:-https://github.com/ocornut/imgui.git}"
IMGUI_REF="${IMGUI_REF:-v1.92.8-docking}"
DEAR_BINDINGS_URL="${DEAR_BINDINGS_URL:-https://github.com/dearimgui/dear_bindings.git}"
DEAR_BINDINGS_REF="${DEAR_BINDINGS_REF:-c9ff64913915df41c0f4beef485b98a1c685eda5}"

mkdir -p "$VENDOR"

fetch_dep() {
    local name="$1" url="$2" ref="$3"
    local dst="$VENDOR/$name"
    if [[ -d "$dst/.git" ]]; then
        git -C "$dst" fetch --tags --depth 1 origin "$ref" 2>/dev/null || git -C "$dst" fetch --tags origin
        git -C "$dst" checkout --quiet --force "$ref"
    elif ! git clone --quiet --depth 1 --branch "$ref" "$url" "$dst" 2>/dev/null; then
        git clone --quiet "$url" "$dst"
        git -C "$dst" checkout --quiet --force "$ref"
    fi
    echo "$name @ $(git -C "$dst" rev-parse --short HEAD)"
}

fetch_dep imgui "$IMGUI_URL" "$IMGUI_REF"
fetch_dep dear_bindings "$DEAR_BINDINGS_URL" "$DEAR_BINDINGS_REF"
