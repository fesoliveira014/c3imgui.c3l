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

## Use (git submodule)

```sh
git submodule add https://github.com/fesoliveira014/c3imgui.c3l lib/c3imgui.c3l
git -C lib/c3imgui.c3l checkout v0.1.1          # any released tag
bash lib/c3imgui.c3l/fetch_linked_libs.sh       # downloads linked-libs/ for that tag
```

`fetch_linked_libs.sh` needs `curl`, `tar`, and `sha256sum` or `shasum`; on Windows
run it from git-bash. Pass a tag explicitly (`fetch_linked_libs.sh v0.1.1`) when the
checkout is not on one. Tag `v0.1.0` predates this and still has the archives in git.

Then in `project.json`: `"dependency-search-paths": [ "lib" ]`, `"dependencies": [ "c3imgui" ]`.
The package's `manifest.json` links `dcimgui` + its transitive deps per platform; a consumer
also links `-lstdc++ -lSDL3 -lGL -lm` (see the manifest's per-target comments).

```c3
import imgui;
imgui::Context ctx = imgui::create_context(null);
defer imgui::destroy_context(ctx);
```

## Regenerating / rebuilding

The `.c3i` are **generated** (do not hand-edit) and the archives are **built**, both by the
separate [`c3imgui-build`](https://github.com/fesoliveira014/c3imgui-build) repo, which pins
`ocornut/imgui` + `dearimgui/dear_bindings`. Its CI builds the Linux and Windows archives on
every push and, on a `vX.Y.Z` tag, publishes them as the assets of this repo's `vX.Y.Z`
release. Regenerate there, commit here, then tag the build repo. The hand-maintained shims
live in `c3imgui-build`'s `scripts/imgui.json` (`extra`) and `scripts/c3imgui_helpers.cpp`,
not in the `.c3i`.
