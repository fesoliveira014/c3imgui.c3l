# windows-x64 linked libs

Not tracked in git. Run `../../fetch_linked_libs.sh` from a tagged checkout,
or `fetch_linked_libs.sh vX.Y.Z`, to download them from the matching GitHub
release. The file is built by this repository's release workflow on
`windows-2022` with MSVC against the static CRT (`/MT`). The manifest
declares `"wincrt": "static"` to match; a consumer built against the dynamic
CRT fails at link with `lld-link: error: /failifmismatch: mismatch detected
for 'RuntimeLibrary'`.

- `dcimgui.lib` - static archive with imgui core, the dear_bindings C wrapper,
  the `c3imgui_*` shims, and every backend `manifest.json` lists for
  windows-x64 (sdl3, opengl2/3, null, sdlrenderer3, sdlgpu3, vulkan, dx9-12,
  win32).

SDL3 is not part of this package; the `sdl3` library supplies it.
