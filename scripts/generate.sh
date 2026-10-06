#!/usr/bin/env bash
# Run dear_bindings over the vendored Dear ImGui and write the C++ sources the
# archive compiles into generated/ (gitignored).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEAR_BINDINGS="$REPO/vendor/dear_bindings"
IMGUI="$REPO/vendor/imgui"
OUT="$REPO/generated"
VENV="$DEAR_BINDINGS/.venv"

if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q -r "$DEAR_BINDINGS/requirements.txt"
fi

PY="$VENV/bin/python3"
DB="$DEAR_BINDINGS/dear_bindings.py"

mkdir -p "$OUT/backends"

"$PY" "$DB" -o "$OUT/dcimgui" "$IMGUI/imgui.h"
"$PY" "$DB" -o "$OUT/dcimgui_internal" --include "$IMGUI/imgui.h" "$IMGUI/imgui_internal.h"

for backend in sdl3 opengl2 opengl3 null sdlrenderer3 sdlgpu3 vulkan dx9 dx10 dx11 dx12 win32; do
    "$PY" "$DB" --backend \
        --include "$IMGUI/imgui.h" \
        --imconfig-path "$IMGUI/imconfig.h" \
        -o "$OUT/backends/dcimgui_impl_$backend" \
        "$IMGUI/backends/imgui_impl_$backend.h"
done

cp "$IMGUI/LICENSE.txt" "$OUT/LICENSE.IMGUI.txt"
