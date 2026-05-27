# imgui source / dear_bindings discovery for Windows + cross builds.
# Sourced by build_windows_x64*.sh after REPO is defined. Returns:
#   IMGUI            absolute path to vendor/imgui (contains imgui.cpp)
#   GEN              absolute path to dear_bindings .cpp output
#                    (the c3imgui.c3l/generated/ dir)
#
# Discovery order:
#   1. $C3IMGUI_SRC_REPO  root containing vendor/imgui and c3imgui.c3l/generated
#   2. $REPO              script's two-up dir (classic upstream layout)
#   3. $REPO/..           one above (handles c3vq-style lib/c3imgui.c3l layout)
#   4. /mnt/c/repos/c3imgui  /  $HOME/source/repos/c3imgui  /  $HOME/repos/c3imgui

: "${REPO:?imgui_src_discovery: REPO must be set before sourcing}"

# Returns 0 only when BOTH vendor/imgui/imgui.cpp AND
# c3imgui.c3l/generated/dcimgui.cpp exist under $1.
_imgui_probe_src() {
    local root=$1
    [[ -n "$root" && -f "$root/vendor/imgui/imgui.cpp" ]] || return 1
    [[ -f "$root/c3imgui.c3l/generated/dcimgui.cpp" ]]    || return 1
    IMGUI="$root/vendor/imgui"
    GEN="$root/c3imgui.c3l/generated"
    return 0
}

imgui_find_src() {
    IMGUI=""
    GEN=""
    if [[ -n "${C3IMGUI_SRC_REPO:-}" ]]; then
        if _imgui_probe_src "$C3IMGUI_SRC_REPO"; then return 0; fi
        echo "error: C3IMGUI_SRC_REPO=$C3IMGUI_SRC_REPO must contain BOTH" >&2
        echo "       vendor/imgui/imgui.cpp AND c3imgui.c3l/generated/dcimgui.cpp" >&2
        echo "       (run c3imgui.c3l/scripts/generate.sh in that repo to make the latter)." >&2
        return 1
    fi
    local candidate
    for candidate in \
        "$REPO" \
        "$REPO/.." \
        "/mnt/c/repos/c3imgui" \
        "$HOME/source/repos/c3imgui" \
        "$HOME/repos/c3imgui"
    do
        if _imgui_probe_src "$candidate"; then return 0; fi
    done
    return 1
}

imgui_print_src_help() {
    cat >&2 <<EOF
error: imgui sources not found.
       This script needs an upstream c3imgui checkout containing:
         vendor/imgui/           (Dear ImGui submodule)
         c3imgui.c3l/generated/  (dear_bindings .cpp output)

       Provide one of:
         C3IMGUI_SRC_REPO=<path-to-c3imgui-repo>
       Or clone c3imgui to one of:
         /mnt/c/repos/c3imgui, \$HOME/source/repos/c3imgui, \$HOME/repos/c3imgui

       c3vq's vendored c3imgui.c3l carries only C3 bindings + prebuilt
       linked-libs. To rebuild dcimgui.lib point this at an upstream repo.
EOF
}
