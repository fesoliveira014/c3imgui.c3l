#!/usr/bin/env bash
# Build libdcimgui.a for linux-x64. See scripts/common/build_common.sh for the
# shared compile-flag rationale and source-list definition.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMGUI="$REPO/vendor/imgui"
GEN="$REPO/c3imgui.c3l/generated"
OUT_DIR="$REPO/c3imgui.c3l/linked-libs/linux-x64"
BUILD="$REPO/build/linux-x64"
PLATFORM="linux-x64"

mkdir -p "$OUT_DIR" "$BUILD"

CXX="${CXX:-clang++}"
SDL_INC="${SDL_INC:-/usr/local/include}"
CXXFLAGS=(
    -O2 -fPIC -fno-exceptions -fno-rtti -fno-threadsafe-statics
    -I"$IMGUI" -I"$IMGUI/backends" -I"$GEN" -I"$SDL_INC"
)

source "$REPO/c3imgui.c3l/scripts/common/build_common.sh"

SOURCES=("${CORE_SOURCES[@]}")
BUNDLED_LIBS=()
common_optional_linux_backends

ar_build_archive
RUN_PROBE=1 run_layout_probe

echo
echo "consumers must also link: -lstdc++ -lSDL3 -lGL -lm"
if (( ${#BUNDLED_LIBS[@]} > 0 )); then
    echo "optional backends bundled — also link: $(printf -- '-l%s ' "${BUNDLED_LIBS[@]}")"
    echo "  → add those names to c3imgui.c3l/manifest.json linux-x64.linked-libraries"
fi
