# windows-x64 linked libs

- `dcimgui.lib` — MSVC static archive containing imgui core + dear_bindings C
  wrapper + every backend referenced by `manifest.json` windows-x64. Build it
  with one of:
  - `c3imgui.c3l/scripts/build_windows_x64_msvc.sh` (WSL, cl.exe via cmd.exe
    interop — repo must live under `/mnt/<drive>/`).
  - `c3imgui.c3l/scripts/build_windows_x64.bat` (native Windows shell,
    no WSL required).

  `build_windows_x64.sh` (MinGW-w64 cross from POSIX) outputs `.a`, which
  lld-link MSVC — c3c's default Windows linker — cannot consume. Use the
  MSVC paths above for c3c.

- `SDL3.lib` — **static** SDL3 archive (`SDL3-static.lib` from vcpkg's
  `sdl3:x64-windows-static`, renamed). Bundled here so `c3c build windows-x64`
  resolves the `SDL3` entry in `manifest.json` without any consumer-side
  `linker-search-paths`. **No SDL3.dll** ships next to the exe at runtime
  because SDL3 is fully statically linked.

  The MSVC build scripts (`build_windows_x64_msvc.{sh,bat}`) refresh this
  file by copying whichever `SDL3-static.lib` they discover. Discovery
  priority: `SDL3_STATIC` env, then `SDL_DIR/lib`, then `VCPKG_ROOT`, then a
  short list of common vcpkg checkout locations. See
  `c3imgui.c3l/scripts/common/sdl3_discovery.sh` (POSIX) and the `.bat`
  script's `:find_sdl3_static_lib` block (native Windows).

  To switch back to the SDL3.dll import lib, replace this file with the
  `SDL3.lib` from `SDL3-devel-<ver>-VC.zip` and remove the
  winmm/version/ole32/oleaut32/advapi32/setupapi/uuid/dinput8 entries from
  `manifest.json`'s windows-x64 `linked-libraries` (they exist solely because
  SDL3-static needs them).

SDL3 is zlib-licensed; see https://www.libsdl.org/.
