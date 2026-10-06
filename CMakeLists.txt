# Builds the dcimgui static archive: Dear ImGui, the dear_bindings C API and the
# c3imgui helper shims, with the backends listed in manifest.json per platform.
# Inputs: IMGUI_DIR (vendor/imgui), GENERATED_DIR (scripts/generate.sh output),
# SDL3_INCLUDE_DIR, VULKAN_INCLUDE_DIR (empty when the compiler finds it).
cmake_minimum_required(VERSION 3.20)
if(WIN32)
    set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)
endif()
project(dcimgui C CXX)

set(IMGUI_DIR "${CMAKE_SOURCE_DIR}/vendor/imgui" CACHE PATH "")
set(GENERATED_DIR "${CMAKE_SOURCE_DIR}/generated" CACHE PATH "")
set(SDL3_INCLUDE_DIR "" CACHE PATH "")
set(VULKAN_INCLUDE_DIR "" CACHE PATH "")

set(backends sdl3 opengl3 opengl2 null sdlrenderer3 sdlgpu3 vulkan)
if(WIN32)
    list(APPEND backends dx9 dx10 dx11 dx12 win32)
endif()

set(sources
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${GENERATED_DIR}/dcimgui.cpp
    ${GENERATED_DIR}/dcimgui_internal.cpp
    ${CMAKE_SOURCE_DIR}/scripts/c3imgui_helpers.cpp)
foreach(backend IN LISTS backends)
    list(APPEND sources
        ${IMGUI_DIR}/backends/imgui_impl_${backend}.cpp
        ${GENERATED_DIR}/backends/dcimgui_impl_${backend}.cpp)
endforeach()

add_library(dcimgui STATIC ${sources})
target_include_directories(dcimgui PRIVATE
    ${IMGUI_DIR} ${IMGUI_DIR}/backends ${GENERATED_DIR} ${SDL3_INCLUDE_DIR})
if(VULKAN_INCLUDE_DIR)
    target_include_directories(dcimgui PRIVATE ${VULKAN_INCLUDE_DIR})
endif()
set_target_properties(dcimgui PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)

if(MSVC)
    # gs_stub.c supplies __report_gsfailure; it must not reference its own cookie.
    target_sources(dcimgui PRIVATE ${CMAKE_SOURCE_DIR}/scripts/gs_stub.c)
    set_source_files_properties(${CMAKE_SOURCE_DIR}/scripts/gs_stub.c PROPERTIES COMPILE_OPTIONS /GS-)
    target_compile_options(dcimgui PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:/EHs-c- /GR- /Zc:threadSafeInit->)
    target_compile_definitions(dcimgui PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(dcimgui PRIVATE -fPIC -fno-exceptions -fno-rtti -fno-threadsafe-statics)
endif()
