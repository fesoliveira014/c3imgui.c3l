# c3imgui.c3l

Dear ImGui bindings for [C3](https://c3-lang.org). Three modules:

- `imgui` — core API (windows, widgets, drawing, fonts, tables, drag/drop, etc.)
- `imgui::sdl` — SDL3 platform backend
- `imgui::gl` — OpenGL3 render backend

(Bindings for the other Dear ImGui backends are generated too — see `backend/`.)

This repo is the **consumable package**: the generated `.c3i` plus, per release,
prebuilt `linked-libs/<platform>/` archives (the Dear ImGui C API + a few
`c3imgui_*` shims, compiled). The archives are release assets, not git content;
one script fetches them.

## Use

Download `c3imgui-v<version>-<platform>.c3l` from a release into your `lib/` directory, with
`sdl3-v<version>-<platform>.c3l` from the sdl3.c3l release and `vk` (the Vulkan backend imports it).
In `project.json`: `"dependency-search-paths": [ "lib" ]`, `"dependencies": [ "c3imgui", "sdl3", "vk" ]`.
The archive carries `dcimgui` only; SDL3 comes from the sdl3 library. A consumer also links
`-lstdc++ -lm` (see the manifest's per-target comments).

From a source checkout, `fetch_linked_libs.sh <tag>` downloads a release's platform archives and
extracts their `linked-libs/` into the checkout.

```c3
import imgui;
imgui::Context ctx = imgui::create_context(null);
defer imgui::destroy_context(ctx);
```

## Building

`.github/workflows/release.yml` builds the archives: `scripts/bootstrap.sh` fetches Dear ImGui and
dear_bindings (pinned), `scripts/generate.sh` writes the C API sources, and `CMakeLists.txt` builds
`libdcimgui.a` (Linux, clang) and `dcimgui.lib` (Windows, MSVC `/MT`) with SDL3 headers from the
upstream `release-3.4.16` tag. On a `v*` tag the workflow publishes
`c3imgui-v<version>-linux-x64.c3l`, `c3imgui-v<version>-windows-x64.c3l` and `SHA256SUMS`.

The `.c3i` bindings are generated from dear_bindings' JSON by the translator in the separate
[`c3imgui-build`](https://github.com/fesoliveira014/c3imgui-build) repository and committed here;
the hand-maintained shims live in `scripts/c3imgui_helpers.cpp`.
