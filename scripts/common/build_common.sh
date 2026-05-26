# Shared build logic for libdcimgui.a across all targets.
# Sourced by build_<platform>.sh after the caller has defined: CXX, CXXFLAGS,
# OUT_DIR, BUILD, PLATFORM (informational), and any extra SOURCES to append.
# Provides: CORE_SOURCES, common_optional_linux_backends, ar_build_archive,
# run_layout_probe.
#
# Compile flags chosen so the archive has minimal C++ runtime requirements:
#   -fno-exceptions          : no exception machinery
#   -fno-rtti                : no typeid / dynamic_cast tables
#   -fno-threadsafe-statics  : no __cxa_guard_acquire/release for fn-local statics
#   -fPIC                    : position-independent (when applicable)

# Caller must set REPO, IMGUI, GEN before sourcing this file.
: "${REPO:?common: REPO must be set}"
: "${IMGUI:?common: IMGUI must be set}"
: "${GEN:?common: GEN must be set}"

# Core sources used on every platform: imgui core + dear_bindings C wrapper
# + cross-platform backends (sdl3, opengl3, opengl2, null) + sdl3 renderer/gpu.
declare -ag CORE_SOURCES=(
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

# Probe helpers — Linux-style filesystem layout. Override on platforms that
# need it (Windows/macOS callers don't probe — they just bundle everything).
have_header() { [[ -f /usr/include/$1 ]] || [[ -f /usr/local/include/$1 ]]; }
have_lib() {
    local libname=$1
    for d in /usr/lib /usr/local/lib /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu \
             /usr/lib/aarch64-linux-gnu /lib/aarch64-linux-gnu; do
        [[ -f "$d/lib${libname}.so" ]] && return 0
        [[ -f "$d/lib${libname}.so.0" ]] && return 0
        [[ -f "$d/lib${libname}.a"  ]] && return 0
    done
    return 1
}

# Append the standard set of Linux-style optional backends (glfw, vulkan, etc.)
# to SOURCES iff both their header and library are installed. Populates the
# global BUNDLED_LIBS array so the caller can echo which libs the consumer
# must `-l` against. SOURCES and BUNDLED_LIBS must exist in the caller.
common_optional_linux_backends() {
    local maybe_add
    maybe_add() {
        local header=$1; local lib=$2; local cpp=$3; local genc=$4
        if have_header "$header" && have_lib "$lib"; then
            echo "  (+) bundling backend ($header + lib$lib found)"
            SOURCES+=("$cpp" "$genc")
            BUNDLED_LIBS+=("$lib")
        else
            echo "  (-) skipping backend (need $header + lib$lib)"
        fi
    }
    maybe_add GLFW/glfw3.h        glfw       "$IMGUI/backends/imgui_impl_glfw.cpp"   "$GEN/backends/dcimgui_impl_glfw.cpp"
    maybe_add vulkan/vulkan.h     vulkan     "$IMGUI/backends/imgui_impl_vulkan.cpp" "$GEN/backends/dcimgui_impl_vulkan.cpp"
    maybe_add GL/freeglut.h       glut       "$IMGUI/backends/imgui_impl_glut.cpp"   "$GEN/backends/dcimgui_impl_glut.cpp"
    maybe_add allegro5/allegro.h  allegro    "$IMGUI/backends/imgui_impl_allegro5.cpp" "$GEN/backends/dcimgui_impl_allegro5.cpp"
    maybe_add SDL2/SDL.h          SDL2       "$IMGUI/backends/imgui_impl_sdl2.cpp"   "$GEN/backends/dcimgui_impl_sdl2.cpp"
    maybe_add SDL2/SDL.h          SDL2       "$IMGUI/backends/imgui_impl_sdlrenderer2.cpp" "$GEN/backends/dcimgui_impl_sdlrenderer2.cpp"
}

# Compile every entry in SOURCES into BUILD/<basename>.o then `ar` them into
# OUT_DIR/<libname>. Caller sets SOURCES, OUT_DIR, BUILD, CXX, CXXFLAGS, and
# optionally LIB_NAME (default libdcimgui.a) and AR (default ar). Uses
# `ar Drcs` for byte-deterministic output.
ar_build_archive() {
    local lib_name="${LIB_NAME:-libdcimgui.a}"
    local ar_cmd="${AR:-ar}"
    local objs=()
    for src in "${SOURCES[@]}"; do
        local ext="${src##*.}"
        local obj="$BUILD/$(basename "${src%.${ext}}").o"
        echo "  CXX $(basename "$src")"
        local extra=()
        if [[ "$ext" == "mm" || "$ext" == "m" ]]; then
            extra+=(-x objective-c++)
        fi
        "$CXX" "${CXXFLAGS[@]}" "${extra[@]}" -c "$src" -o "$obj"
        objs+=("$obj")
    done
    echo "  AR  $lib_name"
    rm -f "$OUT_DIR/$lib_name"
    "$ar_cmd" Drcs "$OUT_DIR/$lib_name" "${objs[@]}"
    echo "done: $OUT_DIR/$lib_name ($(du -h "$OUT_DIR/$lib_name" | cut -f1))"
}

# Build and run the layout probe so the translator can emit `$assert T::size`
# values matching the host's view of the imgui structs. Only meaningful on the
# native host (cross-builds can't execute the resulting binary), so callers
# guard with `[[ "${RUN_PROBE:-0}" == "1" ]]`.
run_layout_probe() {
    local probe_src="$REPO/c3imgui.c3l/scripts/c3imgui_probe.cpp"
    local probe_bin="$BUILD/c3imgui_probe"
    local sizes_json="$REPO/c3imgui.c3l/scripts/sizes.json"
    [[ -f "$probe_src" ]] || return 0
    echo "  CXX+LINK c3imgui_probe"
    "$CXX" "${CXXFLAGS[@]}" -o "$probe_bin" "$probe_src"
    echo "  RUN     c3imgui_probe -> sizes.json"
    "$probe_bin" > "$sizes_json"
}
