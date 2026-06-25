# c3imgui.c3l

Dear ImGui bindings for [C3](https://c3-lang.org). Three modules:

- `imgui` — core API (windows, widgets, drawing, fonts, tables, drag/drop, etc.)
- `imgui::sdl` — SDL3 platform backend
- `imgui::gl` — OpenGL3 render backend

(Bindings for the other Dear ImGui backends are generated too — see `backend/`.)

This repo is the **consumable package**: the generated `.c3i` plus a prebuilt
`linked-libs/linux-x64/libdcimgui.a` (the Dear ImGui C API + a few `c3imgui_*`
shims, compiled). A consumer needs nothing else on Linux.

## Use (git submodule)

```sh
git submodule add https://github.com/fesoliveira014/c3imgui.c3l lib/c3imgui.c3l
```

Then in `project.json`: `"dependency-search-paths": [ "lib" ]`, `"dependencies": [ "c3imgui" ]`.
The package's `manifest.json` links `dcimgui` + its transitive deps per platform; a consumer
also links `-lstdc++ -lSDL3 -lGL -lm` (see the manifest's per-target comments).

```c3
import imgui;
imgui::Context ctx = imgui::create_context(null);
defer imgui::destroy_context(ctx);
```

## Regenerating / rebuilding

The `.c3i` are **generated** (do not hand-edit) and `libdcimgui.a` is **built**, both by the
separate [`c3imgui-build`](https://github.com/fesoliveira014/c3imgui-build) repo, which pins
`ocornut/imgui` + `dearimgui/dear_bindings`. Regenerate there, commit/tag this package, then bump
the submodule in your project. The hand-maintained shims live in `c3imgui-build`'s
`scripts/imgui.json` (`extra`) ↔ `scripts/c3imgui_helpers.cpp`, not in the `.c3i`.
