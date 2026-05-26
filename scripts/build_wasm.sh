#!/usr/bin/env bash
# Build libdcimgui.a for wasm32. Requires Emscripten (`emcc`, `emar`).
#
# IMPORTANT: Emscripten ships ports only for SDL1 and SDL2 — NOT SDL3.
# The consumer must build SDL3 separately for wasm via SDL3's own Emscripten
# CMake recipe and link the resulting libSDL3.a alongside this archive.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/wasm32"
BUILD="$REPO/build/wasm32"
PLATFORM="wasm32"

mkdir -p "$OUT_DIR" "$BUILD"

CXX="${CXX:-em++}"
AR="${AR:-emar}"
if ! command -v "$CXX" >/dev/null 2>&1; then
    echo "error: $CXX not found. Install Emscripten:"
    echo "  git clone https://github.com/emscripten-core/emsdk.git"
    echo "  cd emsdk && ./emsdk install latest && ./emsdk activate latest"
    echo "  source ./emsdk_env.sh"
    exit 1
fi

CXXFLAGS=(
    -O2 -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -s USE_WEBGL2=1
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN"
)
# Consumer must pass `-I<path-to-sdl3-emscripten-build>/include` so this
# archive's sdl3 backend cpps can find SDL3 headers at compile time. Set
# WASM_SDL3_INC to that path.
if [[ -n "${WASM_SDL3_INC:-}" ]]; then
    CXXFLAGS+=(-I"$WASM_SDL3_INC")
fi

source "$REPO/c3imgui.c3l/scripts/common/build_common.sh"

# Wasm gets the cross-platform core only. No Apple/Windows backends; glfw could
# potentially be added (Emscripten provides a glfw port) but skipped here for
# minimal surface — re-add if a consumer needs it.
SOURCES=("${CORE_SOURCES[@]}")

ar_build_archive
# No layout probe — can't run wasm binary natively.

echo
echo "wasm build done. Consumer must:"
echo "  1. Build SDL3 for wasm separately (Emscripten doesn't ship a SDL3 port)."
echo "  2. Link this archive + libSDL3.a in their emcc command."
