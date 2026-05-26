// Probe: dumps sizeof() for each struct the translator binds as a full struct,
// so $assert T::size == N; in the generated .c3i can pin layout against the
// real C++ ABI. Output is JSON on stdout; build_linux_x64.sh redirects it to
// c3imgui.c3l/scripts/sizes.json.
//
// Add new types here when the manifest gains a full struct.

#include <cstddef>
#include <cstdio>

#include "imgui.h"

int main() {
    std::printf("{\n");
    // ImVec2 / ImVec4 are bound as C3 short-vector aliases (float[<2>] /
    // float[<4>]) so no $assert pin is needed — the C3 compiler enforces
    // their sizes match the C ABI by construction.
    std::printf("  \"ImGuiViewport\": %zu,\n", sizeof(ImGuiViewport));
    std::printf("  \"ImFontConfig\": %zu,\n", sizeof(ImFontConfig));
    std::printf("  \"ImGuiInputTextCallbackData\": %zu,\n", sizeof(ImGuiInputTextCallbackData));
    std::printf("  \"ImGuiSizeCallbackData\": %zu,\n", sizeof(ImGuiSizeCallbackData));
    std::printf("  \"ImGuiPayload\": %zu,\n", sizeof(ImGuiPayload));
    std::printf("  \"ImGuiListClipper\": %zu,\n", sizeof(ImGuiListClipper));
    std::printf("  \"ImTextureRef\": %zu,\n", sizeof(ImTextureRef));
    std::printf("  \"ImGuiTableSortSpecs\": %zu,\n", sizeof(ImGuiTableSortSpecs));
    std::printf("  \"ImGuiTableColumnSortSpecs\": %zu,\n", sizeof(ImGuiTableColumnSortSpecs));
    std::printf("  \"ImGuiSelectionRequest\": %zu,\n", sizeof(ImGuiSelectionRequest));
    std::printf("  \"ImColor\": %zu,\n", sizeof(ImColor));
    std::printf("  \"ImDrawCmd\": %zu,\n", sizeof(ImDrawCmd));
    std::printf("  \"ImFontAtlasRect\": %zu,\n", sizeof(ImFontAtlasRect));
    std::printf("  \"ImFontGlyph\": %zu,\n", sizeof(ImFontGlyph));
    std::printf("  \"ImGuiWindowClass\": %zu,\n", sizeof(ImGuiWindowClass));
    std::printf("  \"ImGuiSelectionExternalStorage\": %zu\n", sizeof(ImGuiSelectionExternalStorage));
    std::printf("}\n");
    return 0;
}
