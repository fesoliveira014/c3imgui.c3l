@echo off
rem Build dcimgui.lib for windows-x64 using MSVC (cl.exe).
rem Native cmd.exe sibling of build_windows_x64_msvc.sh (WSL).
rem
rem Requirements:
rem   - Visual Studio 2022 with MSVC v143 (cl.exe, lib.exe).
rem   - SDL3 VC devel pack unpacked at vendor\sdl3-windows\SDL3-<ver>\.
rem
rem Usage:
rem   c3imgui.c3l\scripts\build_windows_x64.bat
rem Optional env:
rem   VCVARS=<path to vcvars64.bat>
rem   SDL_DIR=<path to SDL3-<ver> root>  (default: vendor\sdl3-windows\SDL3-3.4.8)

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%i in ("%SCRIPT_DIR%..\..") do set "REPO=%%~fi"
set "IMGUI=%REPO%\vendor\imgui"
set "GEN=%REPO%\c3imgui.c3l\generated"
set "OUT_DIR=%REPO%\c3imgui.c3l\linked-libs\windows-x64"
set "BUILD=%REPO%\build\windows-x64-msvc"
if not defined SDL_DIR set "SDL_DIR=%REPO%\vendor\sdl3-windows\SDL3-3.4.8"
if not defined VCVARS set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

if not exist "%SDL_DIR%\include" (
    echo error: SDL3 headers not found at %SDL_DIR%\include
    echo        Download SDL3-devel-^<ver^>-VC.zip from libsdl-org/SDL releases and
    echo        unzip to vendor\sdl3-windows\ (or set SDL_DIR=...^).
    exit /b 2
)
if not exist "%GEN%\dcimgui.cpp" (
    echo error: dcimgui sources not found at %GEN%
    echo        Run c3imgui.c3l\scripts\generate.sh first (needs Python + WSL/MSYS^).
    exit /b 2
)
if not exist "%VCVARS%" (
    echo error: vcvars64.bat not found at %VCVARS%
    echo        Set VCVARS=^<path^> if MSVC is installed elsewhere.
    exit /b 2
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if not exist "%BUILD%" mkdir "%BUILD%"

call "%VCVARS%" >NUL
if errorlevel 1 (echo vcvars64.bat failed & exit /b 1)

rem CXX flags rationale mirrors build_common.sh:
rem   /O2 /MD             : release, dynamic CRT (matches c3c --wincrt=dynamic)
rem   /EHs-c-             : -fno-exceptions
rem   /GR-                : -fno-rtti
rem   /Zc:threadSafeInit- : -fno-threadsafe-statics
rem   /DUNICODE /D_UNICODE: Windows wide-char API
rem   /std:c++17          : ImGui builds cleanly under C++17
set "CFLAGS=/nologo /c /O2 /MD /EHs-c- /GR- /Zc:threadSafeInit- /std:c++17 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS"
set "INCS=/I"%IMGUI%" /I"%IMGUI%\backends" /I"%GEN%" /I"%SDL_DIR%\include""

pushd "%BUILD%"

rem Cross-platform core: imgui + dear_bindings + cross-platform backends.
set "CORE=imgui imgui_draw imgui_tables imgui_widgets imgui_demo"
for %%s in (%CORE%) do (
    echo   CL  %%s.cpp
    cl %CFLAGS% %INCS% /Fo"%%s.obj" "%IMGUI%\%%s.cpp"
    if errorlevel 1 (echo CL failed on %%s & popd & exit /b 1)
)

set "BACKENDS=imgui_impl_sdl3 imgui_impl_opengl3 imgui_impl_opengl2 imgui_impl_null imgui_impl_sdlrenderer3 imgui_impl_sdlgpu3"
for %%s in (%BACKENDS%) do (
    echo   CL  %%s.cpp
    cl %CFLAGS% %INCS% /Fo"%%s.obj" "%IMGUI%\backends\%%s.cpp"
    if errorlevel 1 (echo CL failed on %%s & popd & exit /b 1)
)

set "DCBASE=dcimgui dcimgui_internal"
for %%s in (%DCBASE%) do (
    echo   CL  %%s.cpp
    cl %CFLAGS% %INCS% /Fo"%%s.obj" "%GEN%\%%s.cpp"
    if errorlevel 1 (echo CL failed on %%s & popd & exit /b 1)
)

set "DCBACKENDS=dcimgui_impl_sdl3 dcimgui_impl_opengl3 dcimgui_impl_opengl2 dcimgui_impl_null dcimgui_impl_sdlrenderer3 dcimgui_impl_sdlgpu3"
for %%s in (%DCBACKENDS%) do (
    echo   CL  %%s.cpp
    cl %CFLAGS% %INCS% /Fo"%%s.obj" "%GEN%\backends\%%s.cpp"
    if errorlevel 1 (echo CL failed on %%s & popd & exit /b 1)
)

echo   CL  c3imgui_helpers.cpp
cl %CFLAGS% %INCS% /Fo"c3imgui_helpers.obj" "%REPO%\c3imgui.c3l\scripts\c3imgui_helpers.cpp"
if errorlevel 1 (echo CL failed on c3imgui_helpers & popd & exit /b 1)

rem Windows-only backends: dx9, dx10, dx11, dx12, win32.
set "WINBE=dx9 dx10 dx11 dx12 win32"
for %%b in (%WINBE%) do (
    echo   CL  imgui_impl_%%b.cpp
    cl %CFLAGS% %INCS% /Fo"imgui_impl_%%b.obj" "%IMGUI%\backends\imgui_impl_%%b.cpp"
    if errorlevel 1 (echo CL failed on imgui_impl_%%b & popd & exit /b 1)
    echo   CL  dcimgui_impl_%%b.cpp
    cl %CFLAGS% %INCS% /Fo"dcimgui_impl_%%b.obj" "%GEN%\backends\dcimgui_impl_%%b.cpp"
    if errorlevel 1 (echo CL failed on dcimgui_impl_%%b & popd & exit /b 1)
)

echo   LIB dcimgui.lib
lib /nologo /OUT:"%OUT_DIR%\dcimgui.lib" *.obj
if errorlevel 1 (echo LIB failed & popd & exit /b 1)

popd

echo.
echo done: %OUT_DIR%\dcimgui.lib
echo.
echo consumers must link these Windows SDK libs (already in manifest.json
echo for the windows-x64 target):
echo   SDL3 opengl32 user32 gdi32 shell32 kernel32
echo   dxgi d3d9 d3d10 d3d11 d3d12 d3dcompiler dwmapi imm32
echo.
echo SDL3.dll must be copied next to the demo executable at runtime; it lives
echo in %SDL_DIR%\lib\x64\SDL3.dll.

endlocal
