#!/usr/bin/env bash
# Build libdcimgui.a for windows-x64. Uses MinGW-w64 (`x86_64-w64-mingw32-g++`).
# Run under MSYS2 / Cygwin / WSL / on Linux with mingw-w64 installed.
#
# Backends bundled here in ADDITION to the cross-platform core: dx9, dx10, dx11,
# dx12, win32. glfw can be enabled by uncommenting the optional probe below if
# a Windows GLFW build is present.
#
# NOTE: c3c on Windows defaults to lld-link MSVC, which CANNOT consume the
# MinGW `.a` produced here (Itanium vs MSVC C++ ABI mismatch + MinGW libstdc++
# symbols). Use build_windows_x64_msvc.sh / build_windows_x64.bat for c3c
# Windows builds. This script remains for MinGW-link consumers and CI sanity.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

source "$REPO/c3imgui.c3l/scripts/common/imgui_src_discovery.sh"
imgui_find_src || { imgui_print_src_help; exit 2; }
echo "found imgui sources:     $IMGUI"
echo "found dear_bindings out: $GEN"

source "$REPO/c3imgui.c3l/scripts/common/sdl3_discovery.sh"
SDL3_INCLUDE_DIR="$(sdl3_find_include)" || { sdl3_print_help; exit 2; }
echo "found SDL3 headers:      $SDL3_INCLUDE_DIR"

# -fpermissive is required for the DX12 backend's enum-flag OR-int conversions
# under recent g++; MSVC accepts them silently.
CXXFLAGS=(
    -O2 -fno-exceptions -fno-rtti -fno-threadsafe-statics -fpermissive
    -DUNICODE -D_UNICODE
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN" -I"$SDL3_INCLUDE_DIR"
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
