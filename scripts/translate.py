#!/usr/bin/env python3
"""dcimgui.json -> C3 .c3i translator.

Reads a dear_bindings JSON, a manifest listing wanted symbols + naming rules,
and emits a C3 interface file following docs/bindings_guidelines.md +
docs/style.md (C3 0.8.0).

Manifest schema:
    module:         str   — emitted `module <name>;` line
    fn_prefix:      str   — C-side prefix stripped from fn names (default "ImGui_")
    type_prefixes:  list  — C-side prefixes stripped from type names (default ["ImGui","Im"])
    header:         str   — free-form comment block placed after module decl
    opaques:        list  — C-side struct names → `typedef Foo = inline void*;`
    typedefs:       list  — C-side typedef names → `alias Foo = <mapped>;`
                            Typedefs whose name overlaps a flag enum become bitstructs and the alias is skipped.
    structs:        list  — C-side struct names → full struct decl + `$assert T::size == N;`
                            (N pulled from sizes.json if present; else commented placeholder.)
    enums:          list  — C-side enum names. Flag enums (matching `*_Flags_` or marked as
                            flags by dear_bindings) emitted as bitstructs; closed enums emitted
                            as prefixed `const int` constants.
    functions:      list  — C-side function names → `extern fn ... @cname("...");`
    overrides:      dict  — C-name → C3-name (skips automatic naming for that symbol)
    external_types: dict  — C-name → "module::C3Name", e.g. {"ImDrawData": "imgui::DrawData"}.
                            When this C type appears, emit the fully-qualified C3 name and
                            add an import for the module.
    extra:          str   — raw C3 text appended at the end (for hand-written shims)
    sizes:          path  — optional path to a JSON map {C_struct_name: byte_size} used to
                            fill `$assert T::size == N;` for full structs.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

RESERVED = frozenset({
    # control + decl keywords
    "type", "self", "fn", "macro", "module", "import", "alias", "typedef",
    "struct", "union", "enum", "bitstruct", "interface", "any", "var",
    "const", "static", "extern", "inline", "asm", "defer", "if", "else",
    "while", "for", "foreach", "switch", "case", "default", "break",
    "continue", "return", "nextcase", "catch", "try", "null", "true", "false",
    # built-in type names
    "sz", "usz", "isz", "void", "bool", "char", "ichar", "short", "ushort",
    "int", "uint", "long", "ulong", "int128", "uint128", "float", "double",
    "float16", "float128", "iptr", "uptr",
})

PRIMITIVE_MAP = {
    "void": "void",
    "bool": "bool",
    "char": "char",
    "signed_char": "ichar",
    "signed char": "ichar",
    "unsigned_char": "char",
    "unsigned char": "char",
    "short": "short",
    "unsigned_short": "ushort",
    "unsigned short": "ushort",
    "int": "int",
    "unsigned_int": "uint",
    "unsigned int": "uint",
    "long": "long",
    "unsigned_long": "ulong",
    "unsigned long": "ulong",
    "long_long": "long",
    "long long": "long",
    "unsigned_long_long": "ulong",
    "unsigned long long": "ulong",
    "float": "float",
    "double": "double",
    "size_t": "usz",
    "ptrdiff_t": "isz",
    "int8_t": "ichar",
    "int16_t": "short",
    "int32_t": "int",
    "int64_t": "long",
    "uint8_t": "char",
    "uint16_t": "ushort",
    "uint32_t": "uint",
    "uint64_t": "ulong",
    "intptr_t": "isz",
    "uintptr_t": "usz",
    "ImU8": "char",
    "ImU16": "ushort",
    "ImU32": "uint",
    "ImU64": "ulong",
    "ImS8": "ichar",
    "ImS16": "short",
    "ImS32": "int",
    "ImS64": "long",
    "ImWchar": "uint",
    "ImWchar16": "ushort",
    "ImWchar32": "uint",
}


# ---------------- naming ----------------


def normalize_screaming(name: str) -> str:
    """C3 rejects all-uppercase type names. Map e.g. ALLEGRO_EVENT -> AllegroEvent,
    HWND -> Hwnd, _SDL_GameController -> SdlGameController. Names that already
    contain a lowercase character (or are short acronyms) pass through unchanged
    upstream — this only runs for opaque typedefs and SDK fallbacks."""
    stripped = name.lstrip('_')
    if not stripped:
        return name
    parts = [p for p in stripped.split('_') if p]
    if not parts:
        return name
    out = []
    for p in parts:
        if p.isupper():
            out.append(p[0] + p[1:].lower())
        else:
            out.append(p[0].upper() + p[1:])
    return ''.join(out)


def strip_type_prefix(name: str, prefixes: list[str]) -> str:
    for prefix in sorted(prefixes, key=len, reverse=True):
        if name.startswith(prefix) and len(name) > len(prefix) and name[len(prefix)].isupper():
            stripped = name[len(prefix):]
            if stripped.isupper() and 2 <= len(stripped) <= 4:
                return stripped[0] + stripped[1:].lower()
            if stripped.isupper() or stripped.startswith('_') or '_' in stripped and stripped.replace('_', '').isupper():
                return normalize_screaming(stripped)
            return stripped
    # Names that weren't stripped — if they are all-uppercase (SDK opaques like
    # HWND, LRESULT) or leading-underscore (e.g. _SDL_GameController), still need
    # normalization or C3 will reject them as type identifiers.
    if name.replace('_', '').isupper() or name.startswith('_'):
        return normalize_screaming(name)
    return name


def strip_im_prefix(c_name: str) -> str:
    """Strip leading 'ImGui' or 'Im' followed by uppercase. Longest match wins.

    Examples:
      ImGuiPlatformIO_SetPlatform_GetX -> PlatformIO_SetPlatform_GetX
      ImVector_Construct -> Vector_Construct
      ImColor_HSV -> Color_HSV
    """
    for p in ("ImGui", "Im"):
        if c_name.startswith(p) and len(c_name) > len(p) and c_name[len(p)].isupper():
            return c_name[len(p):]
    return c_name


def to_snake(name: str) -> str:
    """PascalCase -> snake_case, collapse multiple underscores to one."""
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s.lower()


def normalize_class_path(cls: str) -> str:
    """For original_class strings like `ImGuiTextFilter_ImGuiTextRange`
    (nested C++ inner-class flattened by dear_bindings), strip the Im/ImGui
    umbrella from each underscore-separated segment, snake-case each, then join
    with `::` so the result is a real nested sub-module path
    (`text_filter::text_range`).

    Segments that don't form a valid C3 identifier (e.g. numeric template
    args like `32` in `ImStableVector_ImFontBaked_32`) are merged into the
    previous segment with an underscore instead of becoming their own module."""
    parts = cls.split("_")
    cleaned: list[str] = []
    for p in parts:
        s = p
        for pre in ("ImGui", "Im"):
            if s.startswith(pre) and len(s) > len(pre) and s[len(pre)].isupper():
                s = s[len(pre):]
                break
        if not s:
            continue
        snake = to_snake(s)
        if not snake:
            continue
        # Numeric / leading-digit segments aren't valid C3 module names — fold
        # them back into the previous segment.
        if snake[0].isdigit():
            if cleaned:
                cleaned[-1] = cleaned[-1] + "_" + snake
            else:
                cleaned.append("_" + snake)
        else:
            cleaned.append(snake)
    return "::".join(cleaned)


def split_class(stripped: str) -> tuple[str, str] | None:
    """Greedy match leading PascalCase token up to first underscore.

    PlatformIO_SetPlatform_GetX -> (PlatformIO, SetPlatform_GetX)
    DrawList_AddLine            -> (DrawList,   AddLine)
    Color                       -> None (no underscore)
    """
    m = re.match(r"^([A-Z][A-Za-z0-9]+)_(.+)$", stripped)
    if m:
        return (m.group(1), m.group(2))
    return None


def c_fn_to_c3(c_name: str, fn_prefix) -> str:
    """fn_prefix may be a single string or a list of acceptable prefixes.
    The longest matching prefix wins so that e.g. cImGui_ImplNullPlatform_ takes
    precedence over cImGui_ImplNull_ when both are listed."""
    prefixes = [fn_prefix] if isinstance(fn_prefix, str) else list(fn_prefix)
    prefixes.sort(key=len, reverse=True)
    stripped = c_name
    for p in prefixes:
        if c_name.startswith(p):
            stripped = c_name[len(p):]
            break
    return to_snake(stripped)


def safe_ident(name: str) -> str:
    if name in RESERVED:
        return name + "_"
    return name


def is_flag_enum(enum: dict) -> bool:
    """Heuristic: ImGui flag enums end their C name with `_Flags_` (trailing underscore).

    dear_bindings also sometimes sets `is_flags_enum: true` on the JSON entry; trust that
    when present and fall back to the name pattern otherwise.
    """
    if enum.get("is_flags_enum"):
        return True
    name = enum["name"]
    return name.endswith("Flags_") or name.endswith("Flags")


def snake_screaming(name: str) -> str:
    """Convert PascalCase / camelCase to SCREAMING_SNAKE_CASE."""
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    return s.upper()


# ---------------- context ----------------


class Ctx:
    def __init__(self, manifest: dict, data: dict, sizes: dict[str, int]):
        self.fn_prefix = manifest.get("fn_prefix", "ImGui_")
        self.type_prefixes = manifest.get("type_prefixes", ["ImGui", "Im"])
        self.overrides = manifest.get("overrides", {})
        self.external_types = manifest.get("external_types", {})
        self.sizes = sizes
        # M15: sub-module split threshold. A Class with ≥ N fns becomes
        # `module <parent>::<class_snake>;`. 0 disables splitting.
        self.submodule_threshold = manifest.get("submodule_threshold", 0)
        self.nested_submodule_threshold = manifest.get("nested_submodule_threshold", 2)
        # Force-include / force-exclude Class names from sub-module promotion.
        self.submodule_include = set(manifest.get("submodule_include", []))
        self.submodule_exclude = set(manifest.get("submodule_exclude", []))
        # Path-rebased fn-name override applied by the submodule emitter.
        self._fn_name_override: dict[str, str] = {}
        self.opaque_types = {
            self.translate_type_name(c_name) for c_name in manifest.get("opaques", [])
        }
        # C-side typedef names that map to function pointers. emit_callback_alias
        # generates a `alias Name = fn ReturnType(Arg1, ...);` line instead of
        # the default `alias Name = int;`. map_type doesn't need special handling
        # because dear_bindings uses these typedef names verbatim in fn signatures.
        self.callback_typedefs: set[str] = set(manifest.get("callbacks", []))
        # Names of typedefs that should NOT be emitted as `alias = int` because they're
        # already covered by a bitstruct generated from the matching flag enum.
        self.bitstruct_typedef_names: set[str] = set()
        # Tracks which external_types modules have been referenced — drives `import` lines.
        self.used_imports: set[str] = set()
        # Type names that already have an explicit C3 declaration (typedef / opaque /
        # struct / bitstruct). Used by emit_enum_constants to decide whether to add
        # a fallback `alias = int` for the closed-enum type name.
        self.declared_type_names: set[str] = set()
        for c_name in manifest.get("opaques", []):
            self.declared_type_names.add(self.translate_type_name(c_name))
        for c_name in manifest.get("typedefs", []):
            self.declared_type_names.add(self.translate_type_name(c_name))
        for c_name in manifest.get("structs", []):
            self.declared_type_names.add(self.translate_type_name(c_name))

    def translate_type_name(self, c_name: str) -> str:
        # external_types short-circuits every other rule.
        if c_name in self.external_types:
            qualified = self.external_types[c_name]
            mod = qualified.rsplit("::", 1)[0] if "::" in qualified else None
            if mod:
                self.used_imports.add(mod)
            # The bare type name (after the last ::) is what shows in the file.
            return qualified
        if c_name in self.overrides:
            return self.overrides[c_name]
        return strip_type_prefix(c_name, self.type_prefixes)

    def translate_fn_name(self, c_name: str) -> str:
        if c_name in self.overrides:
            return self.overrides[c_name]
        if c_name in self._fn_name_override:
            return self._fn_name_override[c_name]
        return c_fn_to_c3(c_name, self.fn_prefix)


# ---------------- type mapping ----------------


def map_type(t: dict, ctx: Ctx) -> str:
    desc = t.get("description") or t
    kind = desc.get("kind")

    if kind == "Builtin":
        name = desc.get("builtin_type") or desc.get("name", "void")
        return PRIMITIVE_MAP.get(name, name)

    if kind == "Pointer":
        inner = desc["inner_type"]
        if inner.get("kind") == "Builtin" and inner.get("builtin_type") == "char":
            storages = inner.get("storage_classes") or []
            if "const" in storages:
                return "ZString"
        if inner.get("kind") == "User":
            inner_c_name = inner["name"]
            # External-types entries are always treated as `inline void*` opaques —
            # they are the cross-module handle types we share by convention. So
            # `Foo*` on the C side collapses to `Foo` on the C3 side without an
            # extra pointer level, just like local opaques.
            if inner_c_name in ctx.external_types:
                return ctx.translate_type_name(inner_c_name)
            c3_inner = ctx.translate_type_name(inner_c_name)
            if c3_inner in ctx.opaque_types:
                return c3_inner
        inner_str = map_type({"description": inner}, ctx)
        return f"{inner_str}*"

    if kind == "User":
        c_name = desc["name"]
        if c_name in PRIMITIVE_MAP:
            return PRIMITIVE_MAP[c_name]
        return ctx.translate_type_name(c_name)

    if kind == "Array":
        bounds = desc.get("bounds")
        inner = desc["inner_type"]
        inner_str = map_type({"description": inner}, ctx)
        # C3 doesn't accept `T[?]` as a bounds. When bounds is unknown
        # (decay-array param like `const char* items[]`), emit `T*` instead
        # — the C ABI treats them identically and consumers pass via `&arr[0]`.
        if bounds is None or bounds == "?" or bounds == "":
            return f"{inner_str}*"
        return f"{inner_str}[{bounds}]"

    if kind == "Function":
        return "void*"  # callbacks: bind as opaque, expand in M3

    return desc.get("declaration", "void*")


# ---------------- emitters ----------------


def emit_typedef_opaque(c_name: str, ctx: Ctx) -> str:
    name = ctx.translate_type_name(c_name)
    return f"typedef {name} = inline void*;"


def emit_callback_alias(typedef: dict, ctx: Ctx) -> str:
    """Emit a C3 fn-type alias for a function-pointer typedef.

    dear_bindings stores the function-pointer details under
    `type.type_details` with `flavour == "function_pointer"` and `return_type`
    and `arguments` arrays. We need both kinds because the legacy fallback
    `description.inner_type.inner_type.kind == "Function"` is harder to walk.
    """
    c_name = typedef["name"]
    c3_name = ctx.translate_type_name(c_name)
    details = typedef.get("type", {}).get("type_details", {})
    if details.get("flavour") != "function_pointer":
        # Fall back to plain alias if the typedef isn't actually a function pointer.
        c3_target = map_type(typedef["type"], ctx)
        return f"alias {c3_name} = {c3_target};"
    ret = map_type(details["return_type"], ctx)
    args = []
    for a in details.get("arguments", []):
        arg_t = map_type(a["type"], ctx)
        arg_n = safe_ident(a.get("name", "arg"))
        args.append(f"{arg_t} {arg_n}")
    arg_str = ", ".join(args)
    return f"alias {c3_name} = fn {ret}({arg_str});"


def emit_struct(struct: dict, ctx: Ctx) -> str:
    c_name = struct["name"]
    c3_name = ctx.translate_type_name(c_name)
    if not struct.get("fields"):
        return emit_typedef_opaque(c_name, ctx)

    lines = [f"struct {c3_name} {{"]
    for f in struct["fields"]:
        raw_name = f.get("name") or (f["names"][0]["name"] if f.get("names") else "_")
        # C3 0.8.0 rejects all-uppercase field names (e.g. `Id ID;` fails to parse).
        # Convert PascalCase / camelCase / ALL_CAPS to snake_case for fields.
        field_name = safe_ident(snake_screaming(raw_name).lower())
        field_type = map_type(f["type"], ctx)
        lines.append(f"    {field_type} {field_name};")
    lines.append("}")
    # Layout pin: prefer concrete size from probe; else mark TODO.
    if c_name in ctx.sizes:
        lines.append(f"$assert {c3_name}::size == {ctx.sizes[c_name]};")
    else:
        lines.append(f"// $assert {c3_name}::size == <run c3imgui_probe to fill>;")
    return "\n".join(lines)


def emit_bitstruct(enum: dict, ctx: Ctx) -> str:
    """Emit a flag enum as a C3 bitstruct + composite-value constants.

    Single-bit variants become bool fields. Composite values (multiple bits set,
    or non-power-of-2) become `const Foo NAME = (Foo){...};` declarations below.
    Zero and "_COUNT" markers are dropped.
    """
    c_name = enum["name"]
    type_name_c = c_name.rstrip("_")
    c3_type = ctx.translate_type_name(type_name_c)

    # Group variants into single-bit-positions vs composite values.
    single_bits: list[tuple[int, str, int]] = []  # (bit_index, c3_field_name, raw_value)
    composites: list[tuple[str, int]] = []        # (c3_const_name, raw_value)
    skip_names = {"_None", "_COUNT", "None", "COUNT"}

    for elt in enum["elements"]:
        v_name = elt["name"]
        value = elt.get("value")
        if value is None:
            continue
        # Variant name on the C3 side: strip enum prefix.
        if v_name.startswith(type_name_c + "_"):
            short = v_name[len(type_name_c) + 1:]
        else:
            short = v_name
        short = short.lstrip("_")
        # Skip sentinels.
        if short in skip_names:
            continue
        # Some flag enums tag obsolete members; dear_bindings annotates with names
        # ending in `_OBSOLETE` or in deprecated comments. Cheap filter:
        if "OBSOLETE" in short.upper() or "DEPRECATED" in short.upper():
            continue
        # Detect single-bit power of 2.
        if value > 0 and (value & (value - 1)) == 0:
            bit_index = value.bit_length() - 1
            raw = snake_screaming(short).lower()
            # safe_ident handles `float`, `int`, `bool` etc. as ImGui has flag
            # names like `ImGuiColorEditFlags_Float` -> raw `float` -> reserved.
            field_name = safe_ident(raw)
            single_bits.append((bit_index, field_name, value))
        else:
            # Composite (multiple bits) or zero (after filtering _None) or negative — emit as const.
            # Skip values that overflow signed 32-bit (ImGui's `_INVALID_MASK_`-style
            # sentinels use high-bit-set values that don't fit a `int`-backed bitstruct).
            if value > 2147483647 or value < -2147483648:
                continue
            composites.append((snake_screaming(short), value))

    # Bitstruct.
    lines = [f"bitstruct {c3_type} : int {{"]
    # Deduplicate by bit_index (multiple names for same bit can occur in obsolete
    # ImGui aliases). Keep the first (most descriptive) name.
    seen_bits: set[int] = set()
    for bit_index, field_name, _val in sorted(single_bits):
        if bit_index in seen_bits:
            continue
        seen_bits.add(bit_index)
        lines.append(f"    bool {field_name} : {bit_index};")
    lines.append("}")
    # Composites as `const` of the bitstruct type via int cast.
    flag_prefix = snake_screaming(c3_type)
    for c_const_name, value in composites:
        full_name = f"{flag_prefix}_{c_const_name}"
        lines.append(f"const {c3_type} {full_name} = ({c3_type}){value};")
    return "\n".join(lines)


def emit_enum_constants(enum: dict, ctx: Ctx) -> str:
    """Emit closed-enum values as `const int` constants, prefixed by the enum type name.

    Also auto-emits a `alias <C3Type> = int;` line when the enum's type name isn't
    already an explicit typedef in the manifest. This lets fn signatures referencing
    the enum-as-type-name (e.g. `SelectionRequestType type`) resolve without forcing
    the manifest author to list the type in `typedefs`.
    """
    c_name = enum["name"]
    type_prefix_to_strip = c_name.rstrip("_")
    c3_type_name = ctx.translate_type_name(type_prefix_to_strip)
    c3_prefix = snake_screaming(c3_type_name)

    lines = [f"// from {c_name}"]
    # Emit the type alias up-front if it wasn't already declared via a typedef.
    if c3_type_name not in ctx.declared_type_names:
        lines.append(f"alias {c3_type_name} = int;")
        ctx.declared_type_names.add(c3_type_name)
    for elt in enum["elements"]:
        v_name = elt["name"]
        value = elt.get("value")
        if value is None:
            continue
        if v_name.startswith(type_prefix_to_strip + "_"):
            short = v_name[len(type_prefix_to_strip) + 1:]
        else:
            short = v_name
        short = short.lstrip("_")
        if short in {"COUNT", "_COUNT"}:
            continue
        snake = snake_screaming(short)
        lines.append(f"const int {c3_prefix}_{snake} = {value};")
    return "\n".join(lines)


def emit_function(fn: dict, ctx: Ctx) -> str:
    c_name = fn["name"]
    c3_name = ctx.translate_fn_name(c_name)
    ret = map_type(fn["return_type"], ctx)

    args = []
    for a in fn.get("arguments", []):
        if a.get("is_varargs"):
            args.append("...")
            continue
        arg_t = map_type(a["type"], ctx)
        # C array parameters (`float v[3]`, `int items[4]`) decay to pointers
        # at the ABI boundary. C3 passes `float[3]` by value (12 bytes),
        # which doesn't match. Demote fixed-size array argument types to
        # pointer-to-element so the call site matches C's calling convention.
        desc = a["type"].get("description") or a["type"]
        if desc.get("kind") == "Array":
            inner = desc.get("inner_type", {})
            inner_str = map_type({"description": inner}, ctx)
            arg_t = f"{inner_str}*"
        arg_n = safe_ident(a["name"])
        args.append(f"{arg_t} {arg_n}")

    arg_str = ", ".join(args)
    return f'extern fn {ret} {c3_name}({arg_str}) @cname("{c_name}");'


# ---------------- driver ----------------


def classify_submodules(
    want_fns: list[str], fns_by_name: dict[str, dict], ctx: Ctx
) -> dict[str, list[str]]:
    """Return {class_name_or_None: [c_fn_names]}.

    Primary signal: dear_bindings' `original_class` JSON field. Any fn with
    that field set is a struct method and goes into the matching sub-module
    (threshold doesn't apply — even a one-method class earns its own sub-mod
    when M16 inline emission is the cost).

    Fallback (for fns where `original_class` is unset but the C name still
    follows `<Class>_<Method>` shape — e.g. `ImGuiPlatformIO_SetPlatform_*`):
    use the regex-based class split with ctx.submodule_threshold."""
    if ctx.submodule_threshold <= 0 and not any(
        (fns_by_name.get(c) or {}).get("original_class") for c in want_fns
    ):
        return {None: list(want_fns)}

    fn_prefixes = [ctx.fn_prefix] if isinstance(ctx.fn_prefix, str) else list(ctx.fn_prefix)
    fn_class: dict[str, str | None] = {}
    regex_counts: dict[str, int] = {}

    for c in want_fns:
        if c in ctx.overrides:
            fn_class[c] = None
            continue
        f = fns_by_name.get(c, {})
        oc = f.get("original_class")
        if oc and oc not in ctx.submodule_exclude:
            fn_class[c] = oc
            continue
        # Parent-module umbrella (e.g. `ImGui_`) stays in parent.
        if any(c.startswith(p) for p in fn_prefixes):
            fn_class[c] = None
            continue
        # Name-regex fallback for nested static-fn groups.
        stripped = strip_im_prefix(c)
        split = split_class(stripped)
        if split is None:
            fn_class[c] = None
            continue
        cls, _rest = split
        if cls in ctx.submodule_exclude:
            fn_class[c] = None
            continue
        regex_counts[cls] = regex_counts.get(cls, 0) + 1
        fn_class[c] = ("__regex__", cls)

    # Promote regex-classed fns only if they meet threshold.
    promoted_regex = {
        cls for cls, n in regex_counts.items()
        if n >= max(ctx.submodule_threshold, 2) or cls in ctx.submodule_include
    }

    buckets: dict[str | None, list[str]] = {None: []}
    for c, cls in fn_class.items():
        if isinstance(cls, tuple) and cls[0] == "__regex__":
            real_cls = cls[1]
            if real_cls in promoted_regex:
                buckets.setdefault(real_cls, []).append(c)
            else:
                buckets[None].append(c)
        elif cls is not None:
            buckets.setdefault(cls, []).append(c)
        else:
            buckets[None].append(c)
    return buckets


def fn_name_after_class_strip(c_name: str, class_prefix: str) -> str:
    """For sub-module emission: strip the C umbrella + class prefix, snake-case
    the remainder. class_prefix may itself carry Im/ImGui (the dear_bindings
    `original_class` string preserves it), so we strip on both sides."""
    stripped = strip_im_prefix(c_name)
    cls_stripped = strip_im_prefix(class_prefix)
    # The class may be a nested name like ImGuiTextFilter_ImGuiTextRange.
    # After outer strip we get TextFilter_ImGuiTextRange. The fn after strip
    # becomes TextFilter_ImGuiTextRange_empty. Strip "TextFilter_" first, then
    # the inner Im* from what's left, then the next segment.
    if stripped.startswith(cls_stripped + "_"):
        stripped = stripped[len(cls_stripped) + 1:]
    else:
        # Try strip each segment of cls_stripped, allowing inner Im/ImGui in c.
        for seg in cls_stripped.split("_"):
            for pre in ("ImGui", "Im"):
                if stripped.startswith(pre + seg + "_"):
                    stripped = stripped[len(pre) + len(seg) + 1:]
                    break
            else:
                if stripped.startswith(seg + "_"):
                    stripped = stripped[len(seg) + 1:]
    return to_snake(stripped)


def flat_name_with_class(c_name: str) -> str:
    """For tiny classes (< threshold): flatten to <class>_<method> in parent."""
    stripped = strip_im_prefix(c_name)
    return to_snake(stripped)


def emit_submodule_file(
    fns: list[dict],
    submodule_path: list[str],
    parent_module: str,
    out_dir: Path,
    ctx: Ctx,
    file_prefix: str,
    header: str | None,
) -> Path:
    """Write a sub-module .c3i. submodule_path like ['draw_list'] or
    ['platform_io', 'set_platform']. Module name = parent + :: + path.
    Filename = file_prefix + '_' + '_'.join(path) + '.c3i'."""
    module_name = "::".join([parent_module] + submodule_path)
    file_name = f"{file_prefix}_{'_'.join(submodule_path)}.c3i"
    out_path = out_dir / file_name

    used_imports_before = set(ctx.used_imports)
    out: list[str] = []
    out.append(f"module {module_name};")
    out.append("")
    imports_marker = len(out)
    out.append("")
    if header:
        out.append(header)
        out.append("")
    out.append("// functions")
    for f in fns:
        out.append(emit_function(f, ctx))

    new_imports = ctx.used_imports - used_imports_before
    # Always import the parent module so callbacks/types declared there resolve.
    new_imports.add(parent_module)
    if new_imports:
        out[imports_marker] = "\n".join(f"import {m};" for m in sorted(new_imports)) + "\n"
    else:
        out[imports_marker] = ""
    out_path.write_text("\n".join(out) + "\n")
    return out_path


def translate(json_path: Path, manifest: dict, out_path: Path, sizes: dict[str, int]) -> None:
    data = json.loads(json_path.read_text())
    ctx = Ctx(manifest, data, sizes)

    want_fns = manifest.get("functions", [])
    want_opaques = manifest.get("opaques", [])
    want_structs = manifest.get("structs", [])
    want_enums = manifest.get("enums", [])
    want_typedefs = manifest.get("typedefs", [])
    module_name = manifest["module"]
    header = (manifest.get("header") or "").rstrip("\n")
    extra = (manifest.get("extra") or "").rstrip("\n")

    structs_by_name = {s["name"]: s for s in data.get("structs", [])}
    fns_by_name = {f["name"]: f for f in data.get("functions", [])}
    enums_by_name = {e["name"]: e for e in data.get("enums", [])}
    typedefs_by_name = {t["name"]: t for t in data.get("typedefs", [])}

    # First pass: which typedefs are shadowed by a bitstruct?
    # The typedef and the enum share the C3 type name (e.g. ImGuiWindowFlags typedef +
    # ImGuiWindowFlags_ enum both translate to `WindowFlags`).
    for n in want_enums:
        e = enums_by_name.get(n)
        if e and is_flag_enum(e):
            typedef_c_name = e["name"].rstrip("_")
            ctx.bitstruct_typedef_names.add(typedef_c_name)

    out: list[str] = []
    out.append(f"module {module_name};")
    out.append("")

    # Reserve a slot for imports — filled in after we know which external types got used.
    imports_marker = len(out)
    out.append("")  # placeholder

    if header:
        out.append(header)
        out.append("")

    if want_opaques:
        out.append("// opaque handles")
        for n in want_opaques:
            out.append(emit_typedef_opaque(n, ctx))
        out.append("")

    if want_typedefs:
        emitted_any = False
        for n in want_typedefs:
            if n in ctx.bitstruct_typedef_names:
                continue  # bitstruct will cover this
            t = typedefs_by_name.get(n)
            if t is None:
                print(f"WARN: typedef '{n}' not in JSON", file=sys.stderr)
                continue
            if not emitted_any:
                out.append("// typedefs")
                emitted_any = True
            if n in ctx.callback_typedefs:
                out.append(emit_callback_alias(t, ctx))
            else:
                c3_target = map_type(t["type"], ctx)
                c3_name = ctx.translate_type_name(n)
                out.append(f"alias {c3_name} = {c3_target};")
        if emitted_any:
            out.append("")

    if want_structs:
        out.append("// structs")
        for n in want_structs:
            s = structs_by_name.get(n)
            if s is None:
                print(f"WARN: struct '{n}' not in JSON", file=sys.stderr)
                continue
            out.append(emit_struct(s, ctx))
            out.append("")

    if want_enums:
        out.append("// enums (flag enums → bitstructs; closed enums → const int)")
        for n in want_enums:
            e = enums_by_name.get(n)
            if e is None:
                print(f"WARN: enum '{n}' not in JSON", file=sys.stderr)
                continue
            if is_flag_enum(e):
                out.append(emit_bitstruct(e, ctx))
            else:
                out.append(emit_enum_constants(e, ctx))
            out.append("")

    # M16: partition fns into the parent module vs per-class sub-modules.
    # original_class-tagged fns go to dedicated sub-modules; regex-classified
    # fns split off when they hit the legacy threshold; everything else stays
    # in the parent. Sub-modules emit INLINE into the same .c3i file.
    buckets = classify_submodules(want_fns, fns_by_name, ctx)
    parent_fns = buckets.pop(None, [])

    # Parent module fns: for any fn that fell back to the parent because its
    # class was below threshold, retain the class prefix in the snake name so
    # we don't get bare `clear` clashing with a similarly-named fn from another
    # tiny class. Compute the override map for those.
    parent_class_counts: dict[str, int] = {}
    for c in parent_fns:
        if c in ctx.overrides:
            continue
        stripped = strip_im_prefix(c)
        split = split_class(stripped)
        if split is not None:
            cls, _ = split
            parent_class_counts[cls] = parent_class_counts.get(cls, 0) + 1
    # Any C name that was rewritten via Im-prefix strip AND didn't match the
    # manifest's `fn_prefix` — apply the flat `<class>_<method>` snake-case form
    # so the output looks like `vector_construct` not `im_vector__construct`.
    # Fns that matched fn_prefix go through c_fn_to_c3 normally (default path).
    fn_prefixes = [ctx.fn_prefix] if isinstance(ctx.fn_prefix, str) else list(ctx.fn_prefix)
    for c in parent_fns:
        if c in ctx.overrides:
            continue
        if any(c.startswith(p) for p in fn_prefixes):
            continue
        stripped = strip_im_prefix(c)
        if stripped != c:
            ctx._fn_name_override[c] = to_snake(stripped)

    out.append("// functions")
    skipped = []
    for n in parent_fns:
        f = fns_by_name.get(n)
        if f is None:
            skipped.append(n)
            continue
        out.append(emit_function(f, ctx))

    if extra:
        out.append("")
        out.append("// --- hand-written shims ---")
        out.append(extra)

    # M16: in-file sub-module blocks. After the parent's fns we re-declare
    # `module <parent>::<class>;` for each detected class and emit its fns.
    # C3's auto-import-by-shared-top-module means we don't need explicit
    # `import` statements for parent types here.
    submodule_counts = []
    for cls, cls_fns in sorted(buckets.items()):
        sub_snake = normalize_class_path(cls)
        nested_buckets = classify_nested(cls_fns, cls, ctx)
        leaf_fns = nested_buckets.pop(None, [])

        ctx._fn_name_override.clear()
        for c in leaf_fns:
            ctx._fn_name_override[c] = fn_name_after_class_strip(c, cls)
        leaf_objs = [fns_by_name[c] for c in leaf_fns if c in fns_by_name]
        if leaf_objs:
            out.append("")
            out.append(f"// ──── {module_name}::{sub_snake} ────  ({cls}_* methods)")
            out.append(f"module {module_name}::{sub_snake};")
            out.append("")
            for f in leaf_objs:
                out.append(emit_function(f, ctx))
            submodule_counts.append((f"{module_name}::{sub_snake}", len(leaf_objs)))

        for sub_cls, sub_fns in sorted(nested_buckets.items()):
            sub_sub_snake = to_snake(sub_cls)
            ctx._fn_name_override.clear()
            for c in sub_fns:
                stripped = strip_im_prefix(c)
                if stripped.startswith(cls + "_"):
                    stripped = stripped[len(cls) + 1:]
                if stripped.startswith(sub_cls + "_"):
                    stripped = stripped[len(sub_cls) + 1:]
                ctx._fn_name_override[c] = to_snake(stripped)
            sub_objs = [fns_by_name[c] for c in sub_fns if c in fns_by_name]
            if sub_objs:
                out.append("")
                out.append(f"// ──── {module_name}::{sub_snake}::{sub_sub_snake} ────")
                out.append(f"module {module_name}::{sub_snake}::{sub_sub_snake};")
                out.append("")
                for f in sub_objs:
                    out.append(emit_function(f, ctx))
                submodule_counts.append(
                    (f"{module_name}::{sub_snake}::{sub_sub_snake}", len(sub_objs))
                )

    if skipped:
        print(
            f"WARN: {len(skipped)} fn(s) not in JSON: {skipped[:5]}{'...' if len(skipped) > 5 else ''}",
            file=sys.stderr,
        )

    # Now fill the imports slot — only modules we actually referenced via external_types.
    if ctx.used_imports:
        import_lines = [f"import {m};" for m in sorted(ctx.used_imports)]
        out[imports_marker] = "\n".join(import_lines) + "\n"
    else:
        out[imports_marker] = ""

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(out) + "\n")
    n_bitstructs = sum(1 for n in want_enums if (e := enums_by_name.get(n)) and is_flag_enum(e))
    print(
        f"wrote {out_path}  (parent: {len(parent_fns)} fns, {len(want_opaques)} opaques, "
        f"{len(want_structs)} structs, {n_bitstructs} bitstructs, {len(want_enums) - n_bitstructs} const-enums; "
        f"{len(submodule_counts)} inline sub-modules)"
    )
    for mod, n in submodule_counts:
        print(f"  └─ {mod}  ({n} fns)")


def classify_nested(
    parent_cls_fns: list[str], parent_class: str, ctx: Ctx
) -> dict[str | None, list[str]]:
    """Inside a sub-module, detect nested `<Sub>_<Method>` partitions.

    Each parent-class fn has C-name `<Im or ImGui><parent_class>_<Rest>`. After
    stripping both, `<Rest>` may itself be `<Sub>_<Method>` and warrant a nested
    sub-module if the count is >= ctx.nested_submodule_threshold."""
    if ctx.nested_submodule_threshold <= 0:
        return {None: list(parent_cls_fns)}

    # `parent_class` arrives as either `ImGuiPlatformIO` (from dear_bindings
    # original_class field) or its Im-stripped form. Normalize both so the
    # prefix-strip below catches the actual class chunk in the C name.
    parent_stripped = strip_im_prefix(parent_class)
    counts: dict[str, int] = {}
    fn_sub: dict[str, str | None] = {}
    for c in parent_cls_fns:
        stripped = strip_im_prefix(c)
        if stripped.startswith(parent_stripped + "_"):
            rest = stripped[len(parent_stripped) + 1:]
        else:
            rest = stripped
        split = split_class(rest)
        if split is None:
            fn_sub[c] = None
            continue
        sub, _r = split
        counts[sub] = counts.get(sub, 0) + 1
        fn_sub[c] = sub

    promoted = {s for s, n in counts.items() if n >= ctx.nested_submodule_threshold}
    buckets: dict[str | None, list[str]] = {None: []}
    for c, sub in fn_sub.items():
        if sub in promoted:
            buckets.setdefault(sub, []).append(c)
        else:
            buckets[None].append(c)
    return buckets


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--json", required=True, type=Path)
    p.add_argument("--manifest", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    p.add_argument("--sizes", type=Path, default=None,
                   help="Optional JSON file mapping C struct names to byte sizes (produced by c3imgui_probe).")
    args = p.parse_args()

    manifest = json.loads(args.manifest.read_text())
    sizes: dict[str, int] = {}
    sizes_path = args.sizes
    # Manifest may also point at a sizes file.
    if sizes_path is None and "sizes" in manifest:
        sizes_path = Path(manifest["sizes"])
        if not sizes_path.is_absolute():
            sizes_path = args.manifest.parent / sizes_path
    if sizes_path and sizes_path.exists():
        sizes = json.loads(sizes_path.read_text())

    translate(args.json, manifest, args.out, sizes)


if __name__ == "__main__":
    main()
