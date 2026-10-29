@echo off
rem Build audio_analyzer GDExtension and deploy DLLs to addons\audio_analyzer\bin.
rem godot-cpp: CMake+Ninja (static lib). Extension: direct cl (same flow as build.bat).
rem NOTE: SCons is avoided on purpose - its MSVC spawn intermittently fails with
rem       WinError 2 ("system cannot find the file") on this machine.
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
set GDCPP=E:\build_tools\godot-cpp-4.5
set HERE=%~dp0
cd /d "%HERE%"

if not exist gdextension\bin mkdir gdextension\bin

rem ---- 1) godot-cpp static libs (cmake+ninja caches; rebuilds only on change) ----
for %%T in (template_debug template_release) do (
  if not exist "%GDCPP%\build_%%T" mkdir "%GDCPP%\build_%%T"
  cmake -G Ninja -S "%GDCPP%" -B "%GDCPP%\build_%%T" -DGODOTCPP_TARGET=%%T -DCMAKE_BUILD_TYPE=Release >nul || exit /b 1
  cmake --build "%GDCPP%\build_%%T" -j 8 || exit /b 1
)

rem ---- 2) extension DLLs ----
for %%T in (template_debug template_release) do (
  cl /nologo /O2 /utf-8 /EHsc /std:c++17 /LD ^
    /I "%GDCPP%\gen\include" /I "%GDCPP%\include" /I "%GDCPP%\gdextension" /I gdextension /I . /I third_party ^
    /D TYPED_METHOD_BIND /D WINDOWS_ENABLED /D NOMINMAX /D NDEBUG ^
    gdextension\src\register_types.cpp gdextension\src\audio_analyzer_gd.cpp analyzer_core.cpp  third_party\stb_vorbis.c ^
    /Fe:gdextension\bin\libaudio_analyzer.windows.%%T.x86_64.dll ^
    /Fo:gdextension\bin\ ^
    /link "%GDCPP%\build_%%T\bin\libgodot-cpp.windows.%%T.x86_64.lib" || exit /b 1
)

rem ---- 3) deploy ----
if not exist ..\addons\audio_analyzer\bin mkdir ..\addons\audio_analyzer\bin
copy /y gdextension\bin\*.dll ..\addons\audio_analyzer\bin\ >nul
echo Done: addons\audio_analyzer\bin\
