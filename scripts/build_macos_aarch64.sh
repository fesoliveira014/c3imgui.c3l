#!/usr/bin/env bash
# Build libdcimgui.a for macos-aarch64 (Apple Silicon). Must run on macOS.
# Identical to build_macos_x64.sh except for -arch arm64 and OUT_DIR.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/macos-aarch64"
BUILD="$REPO/build/macos-aarch64"
PLATFORM="macos-aarch64"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: this script must run on macOS (host is $(uname))."
    exit 1
fi

mkdir -p "$OUT_DIR" "$BUILD"

CXX="${CXX:-clang++}"
CXXFLAGS=(
    -O2 -fPIC -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -arch arm64
    -mmacosx-version-min=11.0
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN"
    -I/usr/local/include -I/opt/homebrew/include
)

source "$REPO/c3imgui.c3l/scripts/common/build_common.sh"

SOURCES=("${CORE_SOURCES[@]}")
for be in osx metal; do
    [[ -f "$IMGUI/backends/imgui_impl_$be.mm" ]] && SOURCES+=("$IMGUI/backends/imgui_impl_$be.mm")
    [[ -f "$GEN/backends/dcimgui_impl_$be.cpp" ]] && SOURCES+=("$GEN/backends/dcimgui_impl_$be.cpp")
done

ar_build_archive
RUN_PROBE=1 run_layout_probe

echo
echo "consumers must link (already in manifest.json for macos-aarch64):"
echo "  -lSDL3 plus -framework Cocoa -framework Metal -framework QuartzCore"
echo "  -framework GameController -framework IOKit"
