@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
cl /nologo /O2 /utf-8 /EHsc /std:c++17 /Fe:build\audio_analyzer.exe audio_analyzer.cpp analyzer_core.cpp
