#!/usr/bin/env bash
# Build dcimgui.lib for windows-x64 using MSVC (cl.exe) via WSL interop.
# Mirrors build_windows_x64.sh but targets MSVC ABI / .lib naming so the
# archive can be linked by c3c's default Windows linker (lld-link MSVC).
#
# Requirements (on the host Windows side, invoked through cmd.exe):
#   - Visual Studio 2022 with MSVC v143 (cl.exe, lib.exe).
#   - vcvars64.bat reachable via the standard install path.
#   - SDL3 VC devel pack unpacked at vendor/sdl3-windows/SDL3-<ver>/.
#
# The MUST be run from a /mnt/c/... path so cmd.exe sees a drive-letter cwd
# (UNC paths from WSL native fs are rejected by cmd.exe).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/windows-x64"
BUILD="$REPO/build/windows-x64-msvc"
SDL_DIR="${SDL_DIR:-$REPO/vendor/sdl3-windows/SDL3-3.4.8}"

mkdir -p "$OUT_DIR" "$BUILD"

case "$REPO" in
    /mnt/?/*) ;;
    *) echo "error: REPO ($REPO) must live under /mnt/<drive>/ so cmd.exe can chdir into it." >&2
       exit 2 ;;
esac

if [[ ! -d "$SDL_DIR/include" ]]; then
    echo "error: SDL3 headers not found at $SDL_DIR/include" >&2
    echo "       Download SDL3-devel-<ver>-VC.zip from libsdl-org/SDL releases and" >&2
    echo "       unzip to vendor/sdl3-windows/ (or set SDL_DIR=...)." >&2
    exit 2
fi

VCVARS="${VCVARS:-C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat}"

# Mirror build_windows_x64.sh source list: cross-platform core + windows-only
# backends (dx9..12 + win32).
SOURCES=(
    "$IMGUI/imgui.cpp"
    "$IMGUI/imgui_draw.cpp"
    "$IMGUI/imgui_tables.cpp"
    "$IMGUI/imgui_widgets.cpp"
    "$IMGUI/imgui_demo.cpp"
    "$IMGUI/backends/imgui_impl_sdl3.cpp"
    "$IMGUI/backends/imgui_impl_opengl3.cpp"
    "$IMGUI/backends/imgui_impl_opengl2.cpp"
    "$IMGUI/backends/imgui_impl_null.cpp"
    "$IMGUI/backends/imgui_impl_sdlrenderer3.cpp"
    "$IMGUI/backends/imgui_impl_sdlgpu3.cpp"
    "$GEN/dcimgui.cpp"
    "$GEN/dcimgui_internal.cpp"
    "$GEN/backends/dcimgui_impl_sdl3.cpp"
    "$GEN/backends/dcimgui_impl_opengl3.cpp"
    "$GEN/backends/dcimgui_impl_opengl2.cpp"
    "$GEN/backends/dcimgui_impl_null.cpp"
    "$GEN/backends/dcimgui_impl_sdlrenderer3.cpp"
    "$GEN/backends/dcimgui_impl_sdlgpu3.cpp"
    "$REPO/c3imgui.c3l/scripts/c3imgui_helpers.cpp"
)
for be in dx9 dx10 dx11 dx12 win32; do
    SOURCES+=("$IMGUI/backends/imgui_impl_$be.cpp")
    SOURCES+=("$GEN/backends/dcimgui_impl_$be.cpp")
done

# Convert /mnt/c/foo -> C:\foo for MSVC tools.
to_win() { wslpath -w "$1"; }

INC_IMGUI="$(to_win "$IMGUI")"
INC_BACKENDS="$(to_win "$IMGUI/backends")"
INC_GEN="$(to_win "$GEN")"
INC_SDL="$(to_win "$SDL_DIR/include")"
BUILD_WIN="$(to_win "$BUILD")"
OUT_LIB_WIN="$(to_win "$OUT_DIR/dcimgui.lib")"
BAT_PATH="$BUILD/build_dcimgui.bat"

# CXX flags rationale mirrors build_common.sh:
#   /O2  /MD              : release, dynamic CRT (matches c3c --wincrt=dynamic)
#   /EHs-c-               : -fno-exceptions
#   /GR-                  : -fno-rtti
#   /Zc:threadSafeInit-   : -fno-threadsafe-statics
#   /DUNICODE /D_UNICODE  : Windows wide-char API
#   /std:c++17            : ImGui builds cleanly under C++17
{
    printf '@echo off\r\n'
    printf 'setlocal\r\n'
    printf 'call "%s" >NUL\r\n' "$VCVARS"
    printf 'if errorlevel 1 (echo vcvars64.bat failed & exit /b 1)\r\n'
    printf 'set CFLAGS=/nologo /c /O2 /MD /EHs-c- /GR- /Zc:threadSafeInit- /std:c++17 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS\r\n'
    printf 'set INCS=/I"%s" /I"%s" /I"%s" /I"%s"\r\n' \
        "$INC_IMGUI" "$INC_BACKENDS" "$INC_GEN" "$INC_SDL"
    printf 'pushd "%s"\r\n' "$BUILD_WIN"
    for src in "${SOURCES[@]}"; do
        src_win="$(to_win "$src")"
        base="$(basename "${src%.cpp}")"
        printf 'echo   CL  %s.cpp\r\n' "$base"
        printf 'cl %%CFLAGS%% %%INCS%% /Fo"%s.obj" "%s"\r\n' "$base" "$src_win"
        printf 'if errorlevel 1 (echo CL failed on %s & exit /b 1)\r\n' "$base"
    done
    printf 'echo   LIB dcimgui.lib\r\n'
    printf 'lib /nologo /OUT:"%s" *.obj\r\n' "$OUT_LIB_WIN"
    printf 'if errorlevel 1 (echo LIB failed & exit /b 1)\r\n'
    printf 'popd\r\n'
    printf 'endlocal\r\n'
} > "$BAT_PATH"

BAT_WIN="$(to_win "$BAT_PATH")"

# Run from a /mnt/<drive>/ cwd so cmd.exe accepts it.
cd "$REPO"
cmd.exe /c "$BAT_WIN"

echo
echo "done: $OUT_DIR/dcimgui.lib ($(du -h "$OUT_DIR/dcimgui.lib" | cut -f1))"
echo
echo "consumers must link these Windows SDK libs (already in manifest.json"
echo "for the windows-x64 target):"
echo "  SDL3 opengl32 user32 gdi32 shell32 kernel32"
echo "  dxgi d3d9 d3d10 d3d11 d3d12 d3dcompiler dwmapi imm32"
echo
echo "SDL3.dll must be copied next to the demo executable at runtime; it lives"
echo "in $SDL_DIR/lib/x64/SDL3.dll."
