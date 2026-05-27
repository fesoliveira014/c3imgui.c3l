# SDL3 header + static archive discovery for Windows builds.
# Sourced by build_windows_x64.sh and build_windows_x64_msvc.sh after REPO is
# defined. Caller may set any of these env vars to override discovery:
#   SDL3_INCLUDE   absolute path containing SDL3/SDL.h
#   SDL3_STATIC    absolute path to SDL3-static archive (SDL3.lib / libSDL3.a)
#   SDL_DIR        directory containing include/ and lib/ (legacy VC devel pack)
#   VCPKG_ROOT     vcpkg install root (we probe installed/*-windows-static/)

: "${REPO:?sdl3_discovery: REPO must be set before sourcing}"

# Expand a glob pattern via `compgen -G` so paths containing whitespace survive
# (plain `for d in $pat` word-splits on spaces). Echoes the first existing
# match, or nothing.
_first_glob() {
    local pat=$1 m
    while IFS= read -r m; do
        if [[ -n "$m" && -e "$m" ]]; then echo "$m"; return 0; fi
    done < <(compgen -G "$pat" 2>/dev/null || true)
    return 1
}

# Try every pattern argument in order; echo first match, return 0 on hit.
_first_match() {
    local pat hit
    for pat in "$@"; do
        hit=$(_first_glob "$pat") && [[ -n "$hit" ]] && { echo "$hit"; return 0; }
    done
    return 1
}

sdl3_find_include() {
    if [[ -n "${SDL3_INCLUDE:-}" ]]; then
        if [[ -f "$SDL3_INCLUDE/SDL3/SDL.h" ]]; then echo "$SDL3_INCLUDE"; return 0; fi
        echo "error: SDL3_INCLUDE=$SDL3_INCLUDE has no SDL3/SDL.h" >&2
        return 1
    fi

    if [[ -n "${SDL_DIR:-}" && -f "$SDL_DIR/include/SDL3/SDL.h" ]]; then
        echo "$SDL_DIR/include"; return 0
    fi

    # Build candidate root list — VCPKG_ROOT first, then common WSL locations.
    local roots=()
    [[ -n "${VCPKG_ROOT:-}" ]] && roots+=("$VCPKG_ROOT")
    roots+=(
        "/mnt/c/vcpkg"
        "/mnt/c/Users/*/source/repos/vcpkg"
        "/mnt/c/Users/*/vcpkg"
    )

    local root flavor base hit
    for root in "${roots[@]}"; do
        for flavor in x64-windows-static x64-windows-static-md x64-windows; do
            for base in installed/$flavor packages/sdl3_$flavor; do
                hit=$(_first_glob "$root/$base/include/SDL3/SDL.h") || continue
                [[ -n "$hit" ]] && { dirname "$(dirname "$hit")"; return 0; }
            done
        done
    done

    # Legacy SDL3 devel pack inside vendor/.
    hit=$(_first_glob "$REPO/vendor/sdl3-windows/SDL3-*/include/SDL3/SDL.h") || true
    if [[ -n "$hit" ]]; then dirname "$(dirname "$hit")"; return 0; fi

    # CPATH-style env vars.
    local IFS=:
    for d in ${CPATH:-} ${C_INCLUDE_PATH:-} ${CPLUS_INCLUDE_PATH:-}; do
        [[ -n "$d" && -f "$d/SDL3/SDL.h" ]] && { echo "$d"; return 0; }
    done

    return 1
}

# lib_name: "SDL3-static.lib" (MSVC ABI) or "libSDL3.a" (MinGW ABI).
sdl3_find_static_lib() {
    local want="${1:-SDL3-static.lib}"

    if [[ -n "${SDL3_STATIC:-}" ]]; then
        if [[ -f "$SDL3_STATIC" ]]; then echo "$SDL3_STATIC"; return 0; fi
        echo "error: SDL3_STATIC=$SDL3_STATIC does not exist" >&2
        return 1
    fi

    if [[ -n "${SDL_DIR:-}" ]]; then
        local p
        for p in "$SDL_DIR/lib/$want" "$SDL_DIR/lib/x64/$want"; do
            [[ -f "$p" ]] && { echo "$p"; return 0; }
        done
    fi

    local roots=()
    [[ -n "${VCPKG_ROOT:-}" ]] && roots+=("$VCPKG_ROOT")
    roots+=(
        "/mnt/c/vcpkg"
        "/mnt/c/Users/*/source/repos/vcpkg"
        "/mnt/c/Users/*/vcpkg"
    )

    local root flavor base hit
    for root in "${roots[@]}"; do
        for flavor in x64-windows-static x64-windows-static-md; do
            for base in installed/$flavor packages/sdl3_$flavor; do
                hit=$(_first_glob "$root/$base/lib/$want") || continue
                [[ -n "$hit" ]] && { echo "$hit"; return 0; }
            done
        done
    done

    return 1
}

sdl3_print_help() {
    cat >&2 <<EOF
error: SDL3 development files not found.
       Provide one of:
         SDL3_INCLUDE=<dir-with-SDL3/SDL.h>     header path
         SDL3_STATIC=<path-to-static-archive>   static archive (vcpkg's SDL3-static.lib)
         SDL_DIR=<SDL3-devel-VC-extracted>      legacy VC devel pack
         VCPKG_ROOT=<vcpkg-root>                use installed/x64-windows-static
       Or install vcpkg's sdl3:x64-windows-static and re-run.
EOF
}
