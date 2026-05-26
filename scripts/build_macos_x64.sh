#!/usr/bin/env bash
# Build libdcimgui.a for macos-x64. Must run on macOS (clang++ with Apple SDK).
# Bundles the core cross-platform backends + Apple-only osx and metal backends
# (Objective-C++). Run natively on an Intel Mac, or on Apple Silicon with
# `-arch x86_64` via the Rosetta SDK.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/macos-x64"
BUILD="$REPO/build/macos-x64"
PLATFORM="macos-x64"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: this script must run on macOS (host is $(uname))."
    exit 1
fi

mkdir -p "$OUT_DIR" "$BUILD"

CXX="${CXX:-clang++}"
CXXFLAGS=(
    -O2 -fPIC -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -arch x86_64
    -mmacosx-version-min=10.13
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN"
    -I/usr/local/include -I/opt/homebrew/include
)

source "$REPO/c3imgui.c3l/scripts/common/build_common.sh"

SOURCES=("${CORE_SOURCES[@]}")
# Apple-only backends. .mm files compile via the -x objective-c++ handling in
# ar_build_archive(). If the dcimgui_impl_*.cpp for metal/osx isn't in
# c3imgui.c3l/generated/backends, dear_bindings didn't emit them (can happen
# on non-Apple hosts) — skip those entries and only bundle the imgui-side .mm.
for be in osx metal; do
    [[ -f "$IMGUI/backends/imgui_impl_$be.mm" ]] && SOURCES+=("$IMGUI/backends/imgui_impl_$be.mm")
    [[ -f "$GEN/backends/dcimgui_impl_$be.cpp" ]] && SOURCES+=("$GEN/backends/dcimgui_impl_$be.cpp")
done

ar_build_archive
RUN_PROBE=1 run_layout_probe

echo
echo "consumers must link (already in manifest.json for macos-x64):"
echo "  -lSDL3 plus -framework Cocoa -framework Metal -framework QuartzCore"
echo "  -framework GameController -framework IOKit"
