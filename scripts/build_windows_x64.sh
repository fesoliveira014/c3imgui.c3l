#!/usr/bin/env bash
# Build libdcimgui.a for windows-x64. Uses MinGW-w64 (`x86_64-w64-mingw32-g++`).
# Run under MSYS2 / Cygwin / WSL / on Linux with mingw-w64 installed.
#
# Backends bundled here in ADDITION to the cross-platform core: dx9, dx10, dx11,
# dx12, win32. glfw can be enabled by uncommenting the optional probe below if
# a Windows GLFW build is present.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/windows-x64"
BUILD="$REPO/build/windows-x64"
PLATFORM="windows-x64"

mkdir -p "$OUT_DIR" "$BUILD"

CXX="${CXX:-x86_64-w64-mingw32-g++}"
AR="${AR:-x86_64-w64-mingw32-ar}"
if ! command -v "$CXX" >/dev/null 2>&1; then
    echo "error: $CXX not found. Install MinGW-w64:"
    echo "  Debian/Ubuntu: apt install g++-mingw-w64-x86-64"
    echo "  MSYS2:         pacman -S mingw-w64-x86_64-toolchain"
    echo "Or set CXX=<your-mingw-c++>."
    exit 1
fi

CXXFLAGS=(
    -O2 -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -DUNICODE -D_UNICODE
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN"
)

source "$REPO/c3imgui.c3l/scripts/common/build_common.sh"

SOURCES=("${CORE_SOURCES[@]}")
# Windows-only backends — every dx* and win32. Their dcimgui_impl_*.cpp comes
# from M13's generate_backend_manifests step; manifests + .c3i are already in
# the tree.
for be in dx9 dx10 dx11 dx12 win32; do
    SOURCES+=("$IMGUI/backends/imgui_impl_$be.cpp")
    SOURCES+=("$GEN/backends/dcimgui_impl_$be.cpp")
done

ar_build_archive
# No layout probe on cross-build. If you run this script natively in MSYS2,
# set RUN_PROBE=1 to re-run sizes.json against the mingw view of the structs.

echo
echo "consumers must link these Windows SDK libs (already in manifest.json"
echo "for the windows-x64 target):"
echo "  -lSDL3 -lopengl32 -luser32 -lgdi32 -lshell32 -lkernel32"
echo "  -ldxgi -ld3d9 -ld3d10 -ld3d11 -ld3d12 -ld3dcompiler -ldwmapi -limm32"
echo "Plus libstdc++ via the MinGW runtime: -static-libstdc++ -static-libgcc"
