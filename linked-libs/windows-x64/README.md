# windows-x64 linked libs

- `dcimgui.lib` — MSVC static archive containing imgui core + dear_bindings C
  wrapper + every backend referenced by `manifest.json` windows-x64. Build it
  with `c3imgui.c3l/scripts/build_windows_x64_msvc.sh` (cl.exe via WSL interop)
  or `build_windows_x64.sh` (MinGW-w64 cross from POSIX → outputs `.a`, which
  c3c's MSVC linker cannot consume; for the MSVC ABI use the `_msvc` script).
- `SDL3.lib` — import lib for SDL3.dll, copied verbatim from the official
  `SDL3-devel-<ver>-VC.zip` release. Bundled here so the c3c link line for
  `windows-x64` resolves the `SDL3` entry in `manifest.json` without the
  consumer needing to add `linker-search-paths`. The matching `SDL3.dll` is
  **not** bundled — it must be placed next to the executable at runtime
  (typically copied from `vendor/sdl3-windows/SDL3-<ver>/lib/x64/SDL3.dll`).

SDL3 is zlib-licensed; see https://www.libsdl.org/.
