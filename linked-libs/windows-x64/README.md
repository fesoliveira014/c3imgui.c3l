# windows-x64 linked libs

Not tracked in git. Run `../../fetch_linked_libs.sh` from a tagged checkout,
or `fetch_linked_libs.sh vX.Y.Z`, to download them from the matching GitHub
release. Both files are built by the `c3imgui-build` repo's CI on
`windows-latest` with MSVC.

- `dcimgui.lib` - static archive with imgui core, the dear_bindings C wrapper,
  the `c3imgui_*` shims, and every backend `manifest.json` lists for
  windows-x64 (sdl3, opengl2/3, null, sdlrenderer3, sdlgpu3, vulkan, dx9-12,
  win32).
- `SDL3.lib` - the SDL3 **static** archive (`SDL3-static.lib` renamed), built
  from the SDL3 release the build repo pins. It is bundled so
  `c3c build windows-x64` resolves the `SDL3` entry in `manifest.json`
  without consumer-side `linker-search-paths`, and no SDL3.dll is needed at
  runtime. The winmm/version/ole32/oleaut32/advapi32/setupapi/uuid/dinput8
  entries in `manifest.json` exist because SDL3-static needs them.

SDL3 is zlib-licensed; see https://www.libsdl.org/.
