@echo off
rem Build dcimgui.lib for windows-x64 using MSVC (cl.exe + lib.exe), natively
rem on Windows. Equivalent to build_windows_x64_msvc.sh but runs in cmd.exe
rem without WSL / wslpath. Bundles every cross-platform backend plus the
rem windows-only dx*/win32 backends, matching manifest.json windows-x64.
rem
rem imgui source / dear_bindings discovery (in order):
rem   1. C3IMGUI_SRC_REPO   root with vendor\imgui and c3imgui.c3l\generated
rem   2. %REPO%             script's two-up dir (classic upstream layout)
rem   3. %REPO%\..          one above that (handles c3vq/lib layout)
rem   4. C:\repos\c3imgui, %USERPROFILE%\source\repos\c3imgui,
rem      %USERPROFILE%\repos\c3imgui
rem
rem SDL3 header + static archive discovery (in order):
rem   1. SDL3_INCLUDE / SDL3_STATIC   explicit env overrides
rem   2. SDL_DIR                      legacy VC devel pack (SDL3-devel-<ver>)
rem   3. VCPKG_ROOT                   uses installed\x64-windows-static
rem   4. %USERPROFILE%\source\repos\vcpkg, C:\vcpkg, %USERPROFILE%\vcpkg
rem
rem Requirements:
rem   - Visual Studio 2022 with MSVC v143 (vcvars64.bat).
rem   - An upstream c3imgui checkout with `vendor\imgui` and a populated
rem     `c3imgui.c3l\generated\` (run scripts\generate.sh once in that repo).
rem   - vcpkg with sdl3:x64-windows-static installed, OR an SDL3 VC devel pack
rem     pointed to via SDL_DIR / SDL3_INCLUDE.
rem
rem OUT_DIR follows the script's own location: running this from
rem c3vq\lib\c3imgui.c3l\scripts writes the libs into c3vq's vendored
rem linked-libs\windows-x64\, even when sources came from an upstream
rem c3imgui repo elsewhere.

setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%..\.." >NUL
set "REPO=%CD%"
popd >NUL

set "OUT_DIR=%REPO%\c3imgui.c3l\linked-libs\windows-x64"
set "BUILD=%REPO%\build\windows-x64-msvc"
set "HELPERS=%REPO%\c3imgui.c3l\scripts\c3imgui_helpers.cpp"

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if not exist "%BUILD%"   mkdir "%BUILD%"

call :find_imgui_src
if errorlevel 1 (
    call :print_src_help
    exit /b 2
)
echo found imgui sources:     %IMGUI%
echo found dear_bindings out: %GEN%

call :find_sdl3_include
if errorlevel 1 (
    call :print_sdl3_help
    exit /b 2
)
echo found SDL3 headers:      %SDL3_INCLUDE_DIR%

call :find_sdl3_static_lib
if errorlevel 1 (
    echo warn: SDL3-static.lib not found via discovery; %OUT_DIR%\SDL3.lib won't be refreshed.
    set "SDL3_STATIC_LIB="
) else (
    echo found SDL3 static archive: !SDL3_STATIC_LIB!
)

if not defined VCVARS set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo error: vcvars64.bat not found at "%VCVARS%". Set VCVARS=^<path^> to override.
    exit /b 2
)

call "%VCVARS%" >NUL
if errorlevel 1 (
    echo vcvars64.bat failed
    exit /b 1
)

set "CFLAGS=/nologo /c /O2 /MD /EHs-c- /GR- /Zc:threadSafeInit- /std:c++17 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS"
set INCS=/I"%IMGUI%" /I"%IMGUI%\backends" /I"%GEN%" /I"%SDL3_INCLUDE_DIR%"

rem Wipe stale .obj from previous failed runs so lib *.obj is clean.
del /Q "%BUILD%\*.obj" >NUL 2>NUL

pushd "%BUILD%" >NUL

set "FAILED=0"

call :cl_one "%IMGUI%\imgui.cpp"
call :cl_one "%IMGUI%\imgui_draw.cpp"
call :cl_one "%IMGUI%\imgui_tables.cpp"
call :cl_one "%IMGUI%\imgui_widgets.cpp"
call :cl_one "%IMGUI%\imgui_demo.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_sdl3.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_opengl3.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_opengl2.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_null.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_sdlrenderer3.cpp"
call :cl_one "%IMGUI%\backends\imgui_impl_sdlgpu3.cpp"
call :cl_one "%GEN%\dcimgui.cpp"
call :cl_one "%GEN%\dcimgui_internal.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_sdl3.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_opengl3.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_opengl2.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_null.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_sdlrenderer3.cpp"
call :cl_one "%GEN%\backends\dcimgui_impl_sdlgpu3.cpp"
call :cl_one "%HELPERS%"

for %%B in (dx9 dx10 dx11 dx12 win32) do (
    call :cl_one "%IMGUI%\backends\imgui_impl_%%B.cpp"
    call :cl_one "%GEN%\backends\dcimgui_impl_%%B.cpp"
)

if not "%FAILED%"=="0" (
    echo build failed: %FAILED% source file^(s^) did not compile.
    popd >NUL
    exit /b 1
)

echo   LIB dcimgui.lib
lib /nologo /OUT:"%OUT_DIR%\dcimgui.lib" *.obj
if errorlevel 1 (
    echo LIB failed
    popd >NUL
    exit /b 1
)
popd >NUL

if defined SDL3_STATIC_LIB (
    copy /Y "!SDL3_STATIC_LIB!" "%OUT_DIR%\SDL3.lib" >NUL
    echo done: %OUT_DIR%\SDL3.lib  ^(copied from !SDL3_STATIC_LIB!^)
)

echo.
echo done: %OUT_DIR%\dcimgui.lib
echo.
echo consumers must link these Windows SDK libs (already in manifest.json
echo for the windows-x64 target):
echo   SDL3 opengl32 user32 gdi32 shell32 kernel32
echo   winmm ole32 oleaut32 version uuid advapi32 setupapi dinput8
echo   dxgi d3d9 d3d10 d3d11 d3d12 d3dcompiler dwmapi imm32
echo.
echo SDL3 is linked statically -- no SDL3.dll needed at runtime.
endlocal
exit /b 0

rem ===========================================================================

:cl_one
rem %~1 = absolute path to a .cpp file. Compiles to %BUILD%\<basename>.obj.
rem Increments FAILED on error but does not abort — caller checks FAILED.
set "SRC=%~1"
for %%F in ("%SRC%") do set "BASE=%%~nF"
echo   CL  %BASE%.cpp
cl %CFLAGS% %INCS% /Fo"%BUILD%\%BASE%.obj" "%SRC%"
if errorlevel 1 (
    echo CL FAILED on %BASE%
    set /a FAILED+=1
)
exit /b 0

:find_imgui_src
set "IMGUI="
set "GEN="
if defined C3IMGUI_SRC_REPO (
    call :probe_src "%C3IMGUI_SRC_REPO%"
    if defined IMGUI goto :find_imgui_src_check
    echo error: C3IMGUI_SRC_REPO=%C3IMGUI_SRC_REPO% has no vendor\imgui\imgui.cpp 1>&2
    exit /b 1
)
call :probe_src "%REPO%"
if defined IMGUI goto :find_imgui_src_check
call :probe_src "%REPO%\.."
if defined IMGUI goto :find_imgui_src_check
call :probe_src "C:\repos\c3imgui"
if defined IMGUI goto :find_imgui_src_check
call :probe_src "%USERPROFILE%\source\repos\c3imgui"
if defined IMGUI goto :find_imgui_src_check
call :probe_src "%USERPROFILE%\repos\c3imgui"
if defined IMGUI goto :find_imgui_src_check
exit /b 1

:find_imgui_src_check
if not exist "%GEN%\dcimgui.cpp" (
    echo error: imgui sources at %IMGUI% but dear_bindings output 1>&2
    echo        missing at %GEN%\dcimgui.cpp. 1>&2
    echo        Run c3imgui.c3l\scripts\generate.sh in that repo first. 1>&2
    exit /b 1
)
exit /b 0

:probe_src
if "%~1"=="" exit /b 0
if not exist "%~1\vendor\imgui\imgui.cpp" exit /b 0
set "IMGUI=%~1\vendor\imgui"
set "GEN=%~1\c3imgui.c3l\generated"
exit /b 0

:print_src_help
echo error: imgui sources not found.
echo        Need an upstream c3imgui checkout containing:
echo          vendor\imgui\           (Dear ImGui submodule)
echo          c3imgui.c3l\generated\  (dear_bindings .cpp output)
echo.
echo        Provide:
echo          C3IMGUI_SRC_REPO=^<path-to-c3imgui-repo^>
echo        Or clone c3imgui to one of: C:\repos\c3imgui,
echo        %%USERPROFILE%%\source\repos\c3imgui, %%USERPROFILE%%\repos\c3imgui.
echo.
echo        c3vq's vendored c3imgui.c3l only carries the C3 bindings + prebuilt
echo        linked-libs. To rebuild dcimgui.lib, point this script at the
echo        upstream c3imgui repo (sources stay there, output lands in
echo        whichever c3imgui.c3l\linked-libs\windows-x64 you ran from).
exit /b 0

:find_sdl3_include
set "SDL3_INCLUDE_DIR="
if defined SDL3_INCLUDE (
    if exist "%SDL3_INCLUDE%\SDL3\SDL.h" (
        set "SDL3_INCLUDE_DIR=%SDL3_INCLUDE%"
        exit /b 0
    )
    echo error: SDL3_INCLUDE=%SDL3_INCLUDE% has no SDL3\SDL.h 1>&2
    exit /b 1
)
if defined SDL_DIR (
    if exist "%SDL_DIR%\include\SDL3\SDL.h" (
        set "SDL3_INCLUDE_DIR=%SDL_DIR%\include"
        exit /b 0
    )
)
call :probe_vcpkg_include "%VCPKG_ROOT%"
if defined SDL3_INCLUDE_DIR exit /b 0
call :probe_vcpkg_include "%USERPROFILE%\source\repos\vcpkg"
if defined SDL3_INCLUDE_DIR exit /b 0
call :probe_vcpkg_include "%USERPROFILE%\vcpkg"
if defined SDL3_INCLUDE_DIR exit /b 0
call :probe_vcpkg_include "C:\vcpkg"
if defined SDL3_INCLUDE_DIR exit /b 0
exit /b 1

:probe_vcpkg_include
if "%~1"=="" exit /b 0
for %%T in (x64-windows-static-md x64-windows-static x64-windows) do (
    if exist "%~1\installed\%%T\include\SDL3\SDL.h" (
        set "SDL3_INCLUDE_DIR=%~1\installed\%%T\include"
        exit /b 0
    )
    if exist "%~1\packages\sdl3_%%T\include\SDL3\SDL.h" (
        set "SDL3_INCLUDE_DIR=%~1\packages\sdl3_%%T\include"
        exit /b 0
    )
)
exit /b 0

:find_sdl3_static_lib
set "SDL3_STATIC_LIB="
if defined SDL3_STATIC (
    if exist "%SDL3_STATIC%" (
        set "SDL3_STATIC_LIB=%SDL3_STATIC%"
        exit /b 0
    )
    echo error: SDL3_STATIC=%SDL3_STATIC% does not exist 1>&2
    exit /b 1
)
if defined SDL_DIR (
    if exist "%SDL_DIR%\lib\SDL3-static.lib" (
        set "SDL3_STATIC_LIB=%SDL_DIR%\lib\SDL3-static.lib"
        exit /b 0
    )
    if exist "%SDL_DIR%\lib\x64\SDL3-static.lib" (
        set "SDL3_STATIC_LIB=%SDL_DIR%\lib\x64\SDL3-static.lib"
        exit /b 0
    )
)
call :probe_vcpkg_static "%VCPKG_ROOT%"
if defined SDL3_STATIC_LIB exit /b 0
call :probe_vcpkg_static "%USERPROFILE%\source\repos\vcpkg"
if defined SDL3_STATIC_LIB exit /b 0
call :probe_vcpkg_static "%USERPROFILE%\vcpkg"
if defined SDL3_STATIC_LIB exit /b 0
call :probe_vcpkg_static "C:\vcpkg"
if defined SDL3_STATIC_LIB exit /b 0
exit /b 1

:probe_vcpkg_static
if "%~1"=="" exit /b 0
for %%T in (x64-windows-static-md x64-windows-static) do (
    if exist "%~1\installed\%%T\lib\SDL3-static.lib" (
        set "SDL3_STATIC_LIB=%~1\installed\%%T\lib\SDL3-static.lib"
        exit /b 0
    )
    if exist "%~1\packages\sdl3_%%T\lib\SDL3-static.lib" (
        set "SDL3_STATIC_LIB=%~1\packages\sdl3_%%T\lib\SDL3-static.lib"
        exit /b 0
    )
)
exit /b 0

:print_sdl3_help
echo error: SDL3 development files not found.
echo        Provide one of:
echo          SDL3_INCLUDE=^<dir-with-SDL3\SDL.h^>       header path
echo          SDL3_STATIC=^<path-to-static-archive^>     SDL3-static.lib
echo          SDL_DIR=^<SDL3-devel-VC-extracted^>        legacy VC devel pack
echo          VCPKG_ROOT=^<vcpkg-root^>                  use installed\x64-windows-static
echo        Or install vcpkg's sdl3:x64-windows-static and re-run.
exit /b 0
