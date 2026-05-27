#!/usr/bin/env python3
"""Generate per-backend manifests for all dcimgui_impl_*.json files."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GEN = ROOT / "c3imgui.c3l" / "generated" / "backends"
SCRIPTS = ROOT / "c3imgui.c3l" / "scripts"

# Existing public dcimgui types (for external_types bridge)
pub = json.loads((ROOT / "c3imgui.c3l/generated/dcimgui.json").read_text())
pub_struct_names = {s['name'] for s in pub['structs']}
pub_typedef_names = {t['name'] for t in pub['typedefs']}
pub_enum_names = {e['name'].rstrip('_') for e in pub['enums']}
pub_types = pub_struct_names | pub_typedef_names | pub_enum_names

# Backends already covered by hand-written manifests (skip)
SKIP = {"sdl3", "opengl3"}

# C3 module-name overrides for backends whose raw name collides with a reserved word.
MODULE_NAME = {
    "null": "null_backend",  # `null` is reserved in C3
}

# Backend → C-side prefix mapping for fns. Most use ImGui_Impl<X>_ where X is the CamelCase form.
# dear_bindings translates these to cImGui_Impl<X>_.
PREFIX_MAP = {
    "allegro5":     "Allegro5",
    "android":      "Android",
    "dx9":          "DX9",
    "dx10":         "DX10",
    "dx11":         "DX11",
    "dx12":         "DX12",
    "glfw":         "Glfw",
    "glut":         "GLUT",
    "metal":        "Metal",
    "null":         "Null",
    "opengl2":      "OpenGL2",
    "opengl3":      "OpenGL3",
    "osx":          "OSX",
    "sdl2":         "SDL2",
    "sdl3":         "SDL3",
    "sdlgpu3":      "SDLGPU3",
    "sdlrenderer2": "SDLRenderer2",
    "sdlrenderer3": "SDLRenderer3",
    "vulkan":       "Vulkan",
    "wgpu":         "WGPU",
    "win32":        "Win32",
}


def strip_prefix(name: str) -> str:
    for prefix in ("ImGui", "Im"):
        if name.startswith(prefix) and len(name) > len(prefix) and name[len(prefix)].isupper():
            stripped = name[len(prefix):]
            if stripped.isupper() and 2 <= len(stripped) <= 4:
                return stripped[0] + stripped[1:].lower()
            return stripped
    return name


def acceptable_type_name(name: str) -> bool:
    if not name: return False
    if name.startswith('__'): return False
    if name.startswith('stbrp'): return False
    if name == 'FILE': return False
    return True


def has_valist(f):
    for a in f.get('arguments', []):
        if 'va_list' in a.get('type', {}).get('declaration', ''):
            return True
    return False


# C primitives + types the translator already maps. Don't add as opaques.
KNOWN_PRIMITIVES = {
    'void', 'bool', 'char', 'short', 'int', 'long', 'float', 'double',
    'int8_t', 'int16_t', 'int32_t', 'int64_t',
    'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t',
    'size_t', 'ptrdiff_t', 'intptr_t', 'uintptr_t',
    'wchar_t', 'unsigned char', 'unsigned short', 'unsigned int', 'unsigned long',
    'signed char', 'long long', 'unsigned long long', 'FILE',
}


def walk_type_names(desc, out):
    if not isinstance(desc, dict): return
    kind = desc.get('kind')
    if kind == 'User':
        name = desc.get('name')
        if name: out.add(name)
    elif kind == 'Pointer':
        walk_type_names(desc.get('inner_type', {}), out)
    elif kind == 'Array':
        walk_type_names(desc.get('inner_type', {}), out)
    elif kind == 'Function':
        for a in desc.get('arguments', []):
            walk_type_names(a.get('type', {}).get('description', a.get('type', {})), out)
        rt = desc.get('return_type', {})
        walk_type_names(rt.get('description', rt), out)


def collect_referenced_types(d):
    out = set()
    for f in d.get('functions', []):
        for a in f.get('arguments', []):
            t = a.get('type', {})
            walk_type_names(t.get('description', t), out)
        rt = f.get('return_type', {})
        walk_type_names(rt.get('description', rt), out)
    for s in d.get('structs', []):
        for fld in s.get('fields', []):
            t = fld.get('type', {})
            walk_type_names(t.get('description', t), out)
    return out


def gen_manifest(backend: str):
    json_path = GEN / f"dcimgui_impl_{backend}.json"
    if not json_path.exists():
        print(f"  SKIP {backend} (no JSON)")
        return
    d = json.loads(json_path.read_text())
    camel = PREFIX_MAP.get(backend, backend.capitalize())
    base_fn_prefix = f"cImGui_Impl{camel}_"
    base_type_prefix = f"ImGui_Impl{camel}_"

    # Some backends (notably "null") expose multiple sub-prefixes like
    # cImGui_ImplNullPlatform_ and cImGui_ImplNullRender_ alongside the base
    # cImGui_ImplNull_. Detect them so the translator can strip the longest match.
    # The base_fn_prefix has a trailing underscore; strip it to allow further
    # PascalCase suffixes before the first underscore that separates the leaf name.
    fn_names = [f['name'] for f in d.get('functions', [])]
    import re as _re
    bare = base_fn_prefix.rstrip('_')      # e.g. cImGui_ImplNull
    sub_prefixes = set()
    pat = _re.compile(rf"^({_re.escape(bare)}([A-Z][A-Za-z0-9]*)?_)")
    for fn in fn_names:
        m = pat.match(fn)
        if m and m.group(1) != base_fn_prefix:
            sub_prefixes.add(m.group(1))
    if sub_prefixes:
        fn_prefix = sorted([base_fn_prefix] + list(sub_prefixes), key=len, reverse=True)
    else:
        fn_prefix = base_fn_prefix

    # Detect type sub-prefixes like ImGui_ImplVulkanH_ (helper namespace) by
    # scanning struct names. Same logic as fn prefix.
    bare_t = base_type_prefix.rstrip('_')   # e.g. ImGui_ImplVulkan
    pat_t = _re.compile(rf"^({_re.escape(bare_t)}([A-Z][A-Za-z0-9]*)?_)")
    type_sub_prefixes = set()
    for n in d.get('structs', []) + d.get('typedefs', []) + d.get('enums', []):
        m = pat_t.match(n['name'])
        if m and m.group(1) != base_type_prefix:
            type_sub_prefixes.add(m.group(1))
    type_prefix_list = sorted([base_type_prefix] + list(type_sub_prefixes), key=len, reverse=True)

    # Collect types from struct + typedef
    backend_struct_names = [s['name'] for s in d.get('structs', [])]
    backend_typedef_names = [t['name'] for t in d.get('typedefs', [])]

    # External-type bridge to imgui:: for shared types. Bridge BOTH declared
    # (struct/typedef redeclarations) AND referenced (used in fn args but not
    # declared in backend JSON) — otherwise Viewport*/TextureData* fn args
    # render as bare unresolved identifiers.
    refs_for_extern = collect_referenced_types(d)
    external_types = {}
    for n in sorted(set(backend_struct_names + backend_typedef_names) | refs_for_extern):
        if n in pub_types:
            external_types[n] = f"imgui::{strip_prefix(n)}"

    # Backend-specific opaques (incl. SDK types if any)
    backend_only_opaques = [n for n in backend_struct_names if n not in pub_types and acceptable_type_name(n)]

    # SDK opaque types: referenced in fn signatures but never declared anywhere.
    # Bind them as inline void* so consumers can pass real SDK pointers via cast.
    refs = collect_referenced_types(d)
    declared = set(backend_struct_names) | set(backend_typedef_names) | pub_types
    declared |= {e['name'] for e in d.get('enums', [])}
    declared |= {e['name'].rstrip('_') for e in d.get('enums', [])}
    sdk_opaques = []
    for n in sorted(refs - declared):
        if not acceptable_type_name(n): continue
        if n in KNOWN_PRIMITIVES: continue
        sdk_opaques.append(n)
    backend_only_opaques = sorted(set(backend_only_opaques) | set(sdk_opaques))

    # Callback typedefs; promote self-referential forward-decl typedefs to opaques.
    callbacks = []
    plain_typedefs = []
    forward_decl_opaques = []
    for t in d.get('typedefs', []):
        if t['name'] in pub_types: continue
        if not acceptable_type_name(t['name']): continue
        td = t.get('type', {}).get('description', t.get('type', {}))
        if t.get('type', {}).get('type_details', {}).get('flavour') == 'function_pointer':
            callbacks.append(t['name'])
        elif td.get('kind') == 'User' and td.get('name') == t['name']:
            # Forward declaration: `typedef SDL_Event SDL_Event;` — bind opaque.
            forward_decl_opaques.append(t['name'])
        else:
            plain_typedefs.append(t['name'])
    backend_only_opaques = sorted(set(backend_only_opaques) | set(forward_decl_opaques))

    # Enums
    enums = [e['name'] for e in d.get('enums', []) if acceptable_type_name(e['name'].rstrip('_'))]

    # Functions (skip va_list)
    fns = [f['name'] for f in d.get('functions', []) if not has_valist(f)]

    module_name = MODULE_NAME.get(backend, backend)
    manifest = {
        "module": f"imgui::backend::{module_name}",
        "fn_prefix": fn_prefix,
        "type_prefixes": type_prefix_list + ["ImGui", "Im"],
        "header": f"// Backend binding: imgui_impl_{backend}.h. Generated from dear_bindings.",
        "opaques": sorted(backend_only_opaques),
        "typedefs": sorted(plain_typedefs),
        "callbacks": sorted(callbacks),
        "external_types": external_types,
        "enums": enums,
        "structs": [],
        "functions": sorted(fns),
    }
    out = SCRIPTS / f"imgui_{backend}.json"
    out.write_text(json.dumps(manifest, indent=2))
    print(f"  wrote {out.name}: {len(fns)} fns, {len(backend_only_opaques)} opaques")


def main():
    backends = sorted(p.stem.replace("dcimgui_impl_", "") for p in GEN.glob("dcimgui_impl_*.json")
                      if not p.stem.endswith("_imconfig") and not p.stem.endswith("_imgui"))
    for be in backends:
        if be in SKIP:
            print(f"  SKIP {be} (already bound by hand-written manifest)")
            continue
        gen_manifest(be)


if __name__ == "__main__":
    main()
