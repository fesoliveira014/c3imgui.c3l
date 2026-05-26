// Tiny C shims exposing a handful of ImGuiIO fields and font-atlas helpers
// without needing to bind the full 116-field ImGuiIO struct on the C3 side.
//
// Every symbol here is prefixed `c3imgui_` so it can't collide with dear_bindings
// or imgui itself. These get compiled into libdcimgui.a alongside the generated
// dcimgui wrappers.

#include <cstdlib>
#include <new>

#include "imgui.h"

extern "C" {

void c3imgui_io_set_display_size(float w, float h) {
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(w, h);
}

void c3imgui_io_set_delta_time(float dt) {
    ImGui::GetIO().DeltaTime = dt;
}

void c3imgui_io_set_config_flags(int flags) {
    ImGui::GetIO().ConfigFlags = flags;
}

int c3imgui_io_get_config_flags(void) {
    return ImGui::GetIO().ConfigFlags;
}

void c3imgui_io_set_backend_flags(int flags) {
    ImGui::GetIO().BackendFlags = flags;
}

int c3imgui_io_get_backend_flags(void) {
    return ImGui::GetIO().BackendFlags;
}

// Returns the current ImDrawData* — same as ImGui::GetDrawData(), exposed here
// for symmetry with the field accessors. (Already bound via @cname; this is a
// safety net if the public binding's signature drifts.)
void* c3imgui_io_get_fonts(void) {
    return ImGui::GetIO().Fonts;
}

// Build the default font atlas using the embedded ProggyClean font. Required
// before NewFrame in headless setups where no platform backend has done it.
bool c3imgui_fonts_build(void* atlas_ptr) {
    auto* atlas = static_cast<ImFontAtlas*>(atlas_ptr);
    // 1.92 changed font building; AddFontDefault then Build() is the simplest path.
    if (atlas->Sources.Size == 0) {
        atlas->AddFontDefault();
    }
    return atlas->Build();
}

// Number of draw lists in the current frame's draw data. Useful for tests
// (assert > 0 after EndFrame + Render).
int c3imgui_draw_data_cmd_list_count(void* draw_data) {
    if (draw_data == nullptr) return -1;
    return static_cast<ImDrawData*>(draw_data)->CmdListsCount;
}

int c3imgui_draw_data_total_vtx_count(void* draw_data) {
    if (draw_data == nullptr) return -1;
    return static_cast<ImDrawData*>(draw_data)->TotalVtxCount;
}

int c3imgui_draw_data_total_idx_count(void* draw_data) {
    if (draw_data == nullptr) return -1;
    return static_cast<ImDrawData*>(draw_data)->TotalIdxCount;
}

// True if the frame's draw data is valid (NewFrame has been called and Render
// has produced data). Use as a sanity gate before reading other fields.
bool c3imgui_draw_data_valid(void* draw_data) {
    if (draw_data == nullptr) return false;
    return static_cast<ImDrawData*>(draw_data)->Valid;
}

// IM_COL32(r,g,b,a) packs as (a<<24)|(b<<16)|(g<<8)|r on little-endian targets,
// matching the stb_truetype + OpenGL3 vertex format ImGui uses internally.
// Exposed here so C3 consumers don't have to reproduce the macro by hand.
unsigned int c3imgui_col32(unsigned char r, unsigned char g, unsigned char b, unsigned char a) {
    return IM_COL32(r, g, b, a);
}

// Build an ImTextureRef from a raw renderer texture id (e.g. a GL texture name).
// Saves callers from spelling the {_TexData, _TexID} struct literal — the field
// names start with underscore on the C++ side, which is awkward C3 syntax.
ImTextureRef c3imgui_texture_ref_from_id(ImU64 id) {
    return ImTextureRef((ImTextureID)id);
}

// ----------------------------------------------------------------------------
// Constructor / destructor shims for ImVector-bearing C++ classes that the
// dear_bindings JSON doesn't emit ctor/dtor wrappers for. These let C3 callers
// allocate + free instances without needing to declare the full struct layout
// (ImVector<T> isn't expressible on the C3 side).
//
// Pattern: c3imgui_<snake>_new() returns a heap-allocated instance; the matching
// c3imgui_<snake>_destroy(p) calls operator delete. Use them as:
//
//   imgui::TextFilter f = imgui::text_filter::new_();
//   defer imgui::text_filter::destroy(f);
//   imgui::text_filter::draw(f, "filter", 0.0);

// Use malloc + placement new instead of `new` so libstdc++'s operator new/delete
// don't need to be in the consumer's link line. The consumer already links
// libstdc++ for ImGui's internal vtables, but link order between libstdc++ and
// libdcimgui depends on how the consumer invokes the linker; this avoids the
// ordering footgun entirely.
#define C3IMGUI_LIFECYCLE(C3_NAME, CPP_TYPE) \
    void* c3imgui_##C3_NAME##_new(void) { \
        void* p = std::malloc(sizeof(CPP_TYPE)); \
        if (!p) return nullptr; \
        return new (p) CPP_TYPE(); \
    } \
    void c3imgui_##C3_NAME##_destroy(void* p) { \
        if (!p) return; \
        static_cast<CPP_TYPE*>(p)->~CPP_TYPE(); \
        std::free(p); \
    }

C3IMGUI_LIFECYCLE(text_filter, ImGuiTextFilter)
C3IMGUI_LIFECYCLE(text_buffer, ImGuiTextBuffer)
C3IMGUI_LIFECYCLE(selection_basic_storage, ImGuiSelectionBasicStorage)
C3IMGUI_LIFECYCLE(draw_list_splitter, ImDrawListSplitter)
C3IMGUI_LIFECYCLE(font_glyph_ranges_builder, ImFontGlyphRangesBuilder)
C3IMGUI_LIFECYCLE(font_config, ImFontConfig)

// ImFontConfig setters for the fields callers most commonly tweak. The full
// struct (~160 bytes, ~25 fields with one conditional based on
// IMGUI_DISABLE_OBSOLETE_FUNCTIONS) is too brittle to mirror in C3 directly;
// this thin set of setters keeps the binding boundary clean.
void c3imgui_font_config_set_merge_mode(void* p, bool v) {
    static_cast<ImFontConfig*>(p)->MergeMode = v;
}
void c3imgui_font_config_set_pixel_snap_h(void* p, bool v) {
    static_cast<ImFontConfig*>(p)->PixelSnapH = v;
}
void c3imgui_font_config_set_oversample(void* p, int h, int v) {
    static_cast<ImFontConfig*>(p)->OversampleH = (ImS8)h;
    static_cast<ImFontConfig*>(p)->OversampleV = (ImS8)v;
}
void c3imgui_font_config_set_size_pixels(void* p, float px) {
    static_cast<ImFontConfig*>(p)->SizePixels = px;
}
void c3imgui_font_config_set_glyph_offset(void* p, float x, float y) {
    static_cast<ImFontConfig*>(p)->GlyphOffset = ImVec2(x, y);
}
void c3imgui_font_config_set_glyph_min_advance_x(void* p, float v) {
    static_cast<ImFontConfig*>(p)->GlyphMinAdvanceX = v;
}
void c3imgui_font_config_set_glyph_max_advance_x(void* p, float v) {
    static_cast<ImFontConfig*>(p)->GlyphMaxAdvanceX = v;
}
void c3imgui_font_config_set_rasterizer_multiply(void* p, float v) {
    static_cast<ImFontConfig*>(p)->RasterizerMultiply = v;
}
void c3imgui_font_config_set_name(void* p, const char* name) {
    if (!name) return;
    auto* cfg = static_cast<ImFontConfig*>(p);
    size_t n = sizeof(cfg->Name);
    size_t i = 0;
    for (; i < n - 1 && name[i]; ++i) cfg->Name[i] = name[i];
    cfg->Name[i] = '\0';
}

// TextFilter wants an optional "default filter" string in its constructor (the
// pattern shown to the user). Bind a second variant that takes one.
void* c3imgui_text_filter_new_with_default(const char* default_filter) {
    void* p = std::malloc(sizeof(ImGuiTextFilter));
    if (!p) return nullptr;
    return new (p) ImGuiTextFilter(default_filter ? default_filter : "");
}

#undef C3IMGUI_LIFECYCLE

}  // extern "C"
