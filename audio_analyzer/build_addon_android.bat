@echo off
rem Build audio_analyzer GDExtension for Android arm64 (debug + release)
setlocal
if "%1"=="" (set NDK=E:\build_tools/android_sdk\ndk\28.2.13676358) else (set NDK=%1)
set GDCPP=E:\build_tools\godot-cpp-4.5
set HERE=%~dp0
cd /d "%HERE%"
if not exist "%NDK%\toolchains\llvm\prebuilt\windows-x86_64" (
  echo NDK not found at %NDK%
  exit /b 1
)
set TC=%NDK%\toolchains\llvm\prebuilt\windows-x86_64
set NINJA=E:\build_tools/android_sdk/cmake/3.22.1/bin/ninja.exe
set CXX=%TC%\bin\clang++.exe
rem ---- 1) godot-cpp android arm64 static libs (debug + release, cached) ----
for %%T in (template_debug template_release) do (
  if not exist "%GDCPP%\build_android_%%T" mkdir "%GDCPP%\build_android_%%T"
  cmake -G Ninja -DCMAKE_MAKE_PROGRAM="%NINJA%" -S "%GDCPP%" -B "%GDCPP%\build_android_%%T" -DGODOTCPP_TARGET=%%T -DGODOTCPP_PLATFORM=android -DGODOTCPP_ARCH=arm64 -DCMAKE_TOOLCHAIN_FILE=%NDK%\build\cmake\android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 -DCMAKE_BUILD_TYPE=Release || exit /b 1
  cmake --build "%GDCPP%\build_android_%%T" -j 2 || exit /b 1
)
rem ---- 2) extension .so ----
if not exist gdextension\bin mkdir gdextension\bin
set SRC=gdextension\src\register_types.cpp gdextension\src\audio_analyzer_gd.cpp analyzer_core.cpp third_party\stb_vorbis.c
set INC=-I"%GDCPP%\gen\include" -I"%GDCPP%\include" -I"%GDCPP%\gdextension" -Igdextension -I. -Ithird_party
set TARGET_FLAGS=--target=aarch64-none-linux-android21 --sysroot="%TC%\sysroot"
for %%T in (template_debug template_release) do (
  "%CXX%" %TARGET_FLAGS% -std=c++17 -O2 -fPIC -shared -D TYPED_METHOD_BIND -D NOMINMAX %INC% %SRC% -o gdextension\bin/libaudio_analyzer.android.%%T.arm64.so "%GDCPP%\build_android_%%T\bin\libgodot-cpp.android.%%T.arm64.a" -llog || exit /b 1
)
rem ---- 3) deploy ----
if not exist ../addons/audio_analyzer/bin mkdir ../addons/audio_analyzer/bin
copy /y gdextension\bin/libaudio_analyzer.android.template_debug.arm64.so ../addons/audio_analyzer/bin/ >nul
copy /y gdextension\bin/libaudio_analyzer.android.template_release.arm64.so ../addons/audio_analyzer/bin/ >nul
echo Done: android arm64 debug + release
