#!/usr/bin/env bash
# Run dear_bindings against vendored imgui to produce dcimgui.{h,cpp,json}
# and selected backend bindings. Output → c3imgui.c3l/generated/ (gitignored).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEAR_BINDINGS="$REPO_ROOT/vendor/dear_bindings"
IMGUI="$REPO_ROOT/vendor/imgui"
OUT="$REPO_ROOT/c3imgui.c3l/generated"
VENV="$DEAR_BINDINGS/.venv"

if [[ ! -d "$VENV" ]]; then
    echo "creating venv at $VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q -r "$DEAR_BINDINGS/requirements.txt"
fi

PY="$VENV/bin/python3"
DB="$DEAR_BINDINGS/dear_bindings.py"

mkdir -p "$OUT/backends"

echo "generating dcimgui from imgui.h"
"$PY" "$DB" -o "$OUT/dcimgui" "$IMGUI/imgui.h"

echo "generating dcimgui_internal from imgui_internal.h"
"$PY" "$DB" -o "$OUT/dcimgui_internal" --include "$IMGUI/imgui.h" "$IMGUI/imgui_internal.h"

# All ImGui backends
for backend in allegro5 android dx9 dx10 dx11 dx12 glfw glut metal null opengl2 opengl3 osx sdl2 sdl3 sdlgpu3 sdlrenderer2 sdlrenderer3 vulkan wgpu win32; do
    src="$IMGUI/backends/imgui_impl_$backend.h"
    [[ -f "$src" ]] || { echo "  SKIP: $backend (no header)"; continue; }
    echo "generating dcimgui_impl_$backend"
    "$PY" "$DB" --backend \
        --include "$IMGUI/imgui.h" \
        --imconfig-path "$IMGUI/imconfig.h" \
        -o "$OUT/backends/dcimgui_impl_$backend" \
        "$src" 2>&1 || echo "  WARN: backend $backend failed (likely needs platform SDK headers)"
done

echo "done: $OUT"
