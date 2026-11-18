@echo off
rem build-audiocpp.cmd - the e2a audiocpp-server packages for Windows arm64 (audio.cpp, 0xShug0), which audio.cpp's own
rem releases leave out (they ship Windows x64 only): windows-arm64-cpu / -cpu-v82 / -vulkan, built natively on Windows
rem arm64 with Visual Studio's ARM64 clang-cl. Each lands as audiocpp-server-<target>.zip in the audio.cpp folder, named
rem like e2a downloads it from the audiocpp release of py-pkg. Runs from any command prompt: it loads the Visual Studio
rem C++ environment itself (vswhere + vcvarsall). Linux and macOS: build-audiocpp.sh. build-audiocpp.cmd --help for the
rem options, --list for this machine.
setlocal EnableExtensions DisableDelayedExpansion
rem the audio.cpp release, = e2a's audiocpp_version (lib/conf_models.py), the same default as build-audiocpp.sh
if not defined TAG set "TAG=v0.9.5"
if not defined SRC set "SRC=%CD%\audio.cpp"
if not defined TOOLS set "TOOLS=%CD%\audiocpp-tools"
if not defined JOBS set "JOBS=%NUMBER_OF_PROCESSORS%"
if not defined MODELS set "MODELS=e2a"
if not defined CLEAN set "CLEAN=0"
if not defined INSTALL set "INSTALL=1"
if not defined INSTALL_BT set "INSTALL_BT=0"
set "ALL=windows-arm64-cpu windows-arm64-cpu-v82 windows-arm64-vulkan"
set "LIST=0"
set "ONLY="
:args
if "%~1"=="" goto :args_done
if /i "%~1"=="-l" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--list" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--clean" (set "CLEAN=1" & shift & goto :args)
if /i "%~1"=="--no-install" (set "INSTALL=0" & shift & goto :args)
if /i "%~1"=="--install-buildtools" (set "INSTALL_BT=1" & shift & goto :args)
if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?" goto :usage
if /i "%~1"=="--only" (set "OPT=ONLY" & goto :value)
if /i "%~1"=="--tag" (set "OPT=TAG" & goto :value)
if /i "%~1"=="--src" (set "OPT=SRC" & goto :value)
if /i "%~1"=="--tools" (set "OPT=TOOLS" & goto :value)
if /i "%~1"=="--jobs" (set "OPT=JOBS" & goto :value)
if /i "%~1"=="--models" (set "OPT=MODELS" & goto :value)
echo unknown option: %~1 - see --help
exit /b 1
:value
if "%~2"=="" (echo %~1 needs a value - see --help & exit /b 1)
set "%OPT%=%~2"
shift
shift
goto :args
:args_done
rem Windows arm64 only: audio.cpp's own releases cover Windows x64 (CPU, Vulkan, CUDA 12.4 / 13.3). ggml's ARM code takes
rem clang-cl only (MSVC's cl is refused), so no arm64 CUDA either: nvcc takes only cl as host compiler
set "HA=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HA=%PROCESSOR_ARCHITEW6432%"
if /i "%HA%"=="AMD64" (echo build-audiocpp.cmd builds the Windows arm64 packages, on a Windows arm64 machine - Windows x64 has audio.cpp's own packages & exit /b 1)
if /i not "%HA%"=="ARM64" (echo build-audiocpp.cmd builds the Windows arm64 packages on a Windows arm64 machine, this one is %HA% & exit /b 1)
rem this machine's triple (clang-cl's target, uv's wheels), its MSVC component and clang-cl folder in Visual Studio,
rem and its LunarG Vulkan SDK platform
set "HOSTA=arm64"
set "TRIPLE=aarch64-pc-windows-msvc"
set "VSTOOLS=Microsoft.VisualStudio.Component.VC.Tools.ARM64"
set "LLVMDIR=ARM64"
set "VKPLAT=warm"
set "VER=%TAG%"
if /i "%TAG:~0,1%"=="v" set "VER=%TAG:~1%"
rem the model families compiled in, as in build-audiocpp.sh: e2a's engines (TTS_ENGINES), its reference ASR (qwen3_asr)
rem and its voice conversion (seed_vc); their dependencies (miocodec, qwen3_forced_aligner) are linked by audio.cpp itself.
rem moss holds moss_tts_local and moss_tts_nano
set "E2A_MODELS=breeze_tts,chatterbox,confucius4_tts,cosyvoice3,dots_tts,dramabox,fish_audio,firered_audio,fireredtts3,higgs_audio_tts,index_tts2,irodori_tts,kokoro_tts,kugelaudio,magpie_tts,maya1,miotts,moss,neutts,pocket_tts,qwen3_tts,supertonic,vibevoice,voxcpm2,voxtral_tts,seed_vc,qwen3_asr"
set "MODEL_FLAGS=-DAUDIOCPP_MODEL_SET=custom "-DAUDIOCPP_MODELS=%MODELS: =%""
if /i "%MODELS%"=="e2a" set "MODEL_FLAGS=-DAUDIOCPP_MODEL_SET=custom "-DAUDIOCPP_MODELS=%E2A_MODELS%""
if /i "%MODELS%"=="full" set "MODEL_FLAGS=-DAUDIOCPP_MODEL_SET=full"
for %%r in ("%SRC%") do set "SRC=%%~fr"
for %%r in ("%TOOLS%") do set "TOOLS=%%~fr"
call :vs_env
call :find_sdk
call :llvm_path
if "%LIST%"=="1" goto :list
goto :build
:usage
echo build-audiocpp.cmd - the e2a audiocpp-server packages for Windows arm64, built natively on Windows arm64: audio.cpp's
echo own releases cover Windows x64 only (CPU, Vulkan, CUDA 12.4 / 13.3). Each target is packed as
echo audiocpp-server-^<target^>.zip in the audio.cpp folder.
echo.
echo Targets
echo   windows-arm64-cpu      CPU, ARMv8.0, clang-cl, static C runtime: system DLLs only, Windows 10+
echo   windows-arm64-cpu-v82  same, ARMv8.2 + dotprod + fp16 (Snapdragon 850 and newer: 7c, 8cx, X)
echo   windows-arm64-vulkan   GPU via Vulkan (Qualcomm Adreno), CPU part ARMv8.0, clang-cl, the LunarG arm64 SDK's
echo                          glslc and vulkan-1.lib; users need only their GPU driver (Snapdragon X), or on older
echo                          Snapdragons Microsoft's OpenCL, OpenGL, and Vulkan Compatibility Pack
echo No GPU is needed to build any of them.
echo.
echo Options                     [environment variable]   default
echo   -l, --list                what this machine can build now, nothing built
echo   --only "T1 T2"            build these targets only     [ONLY]      every target
echo   --tag vX.Y.Z              audio.cpp release to build, = e2a's audiocpp_version  [TAG]   v0.9.5
echo   --src DIR                 audio.cpp tree, cloned if missing, else moved to --tag (local changes dropped)
echo                                                          [SRC]       .\audio.cpp
echo   --tools DIR               build venv                   [TOOLS]     .\audiocpp-tools
echo   --jobs N                  parallel compile jobs        [JOBS]      all cores
echo   --models e2a^|full^|"m1,m2"  model families compiled in [MODELS]    e2a: the families e2a's engines, ASR and
echo                             Seed-VC use, about half the build; full = every family; a list goes in quotes
echo   --clean                   delete build-^<target^> after packing  [CLEAN=1]
echo   --no-install              install nothing: no clang-cl, no Vulkan SDK  [INSTALL=0]
echo   --install-buildtools      no Visual Studio yet: install the 2022 Build Tools with C++ and clang-cl via winget
echo.
echo Needs
echo   git, curl and PowerShell (both part of Windows 10+), Visual Studio 2022 C++ build tools for ARM64
echo   the "C++ Clang tools for Windows" component of Visual Studio (its ARM64 clang-cl), added by this script when
echo     missing through the Visual Studio Installer - one UAC prompt
echo   vulkan: the LunarG Vulkan SDK for arm64, installed by this script when missing
echo   cmake and ninja come from a venv this script makes with uv, installed when missing
exit /b 0
:list
echo targets on this Windows %HOSTA% machine:
for %%t in (%ALL%) do call :list_one %%t
exit /b 0
:list_one
call :missing %1
set "NOTE=ready"
if defined MISS set "NOTE=missing:%MISS:~0,-1% - see --help"
call :install_note %1
set "NAME=%~1                         "
echo   %NAME:~0,24% %NOTE%%INOTE%
exit /b 0
:install_note
set "INOTE="
if defined MISS exit /b 0
call :clang_ok || set "INOTE= - adds clang-cl to Visual Studio first"
if /i "%~1"=="windows-arm64-vulkan" if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "INOTE=%INOTE% - installs the Vulkan SDK first"
exit /b 0
:missing
rem sets MISS to what target %1 lacks on this machine, each item comma-terminated; empty when it can be built
set "MISS="
where git >nul 2>&1 || set "MISS=%MISS% git,"
where curl >nul 2>&1 || set "MISS=%MISS% curl,"
where cl >nul 2>&1 || set "MISS=%MISS% Visual Studio C++ build tools for %HOSTA%,"
if defined VSCMD_ARG_TGT_ARCH if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" set "MISS=%MISS% a %HOSTA% Visual Studio environment - this one targets %VSCMD_ARG_TGT_ARCH%,"
call :clang_ok || call :can_add_clang || set "MISS=%MISS% clang-cl for %HOSTA% - C++ Clang tools for Windows,"
if /i not "%~1"=="windows-arm64-vulkan" exit /b 0
if "%INSTALL%"=="1" exit /b 0
if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "MISS=%MISS% LunarG Vulkan SDK,"
exit /b 0
:build
set "TARGETS=%ALL%"
if defined ONLY set "TARGETS=%ONLY%"
if "%INSTALL_BT%"=="1" call :install_bt || exit /b 1
call :ensure_clang || exit /b 1
for %%t in (%TARGETS%) do call :check_target %%t || exit /b 1
call :tools_env || exit /b 1
call :source || exit /b 1
for %%t in (%TARGETS%) do call :build_one %%t || exit /b 1
echo [audiocpp] done: the zips are in %SRC%
exit /b 0
:check_target
set "KNOWN=0"
for %%a in (%ALL%) do if /i "%%a"=="%~1" set "KNOWN=1"
if "%KNOWN%"=="0" (echo [audiocpp] ERROR: %~1 is not a target of this Windows %HOSTA% machine - see --list & exit /b 1)
call :missing %1
if defined MISS goto :ct_missing
exit /b 0
:ct_missing
echo [audiocpp] ERROR: %~1: missing:%MISS:~0,-1% - see --help
exit /b 1
:tools_env
if not exist "%TOOLS%" mkdir "%TOOLS%"
where uv >nul 2>&1 && goto :have_uv
echo [audiocpp] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [audiocpp] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
if not exist "%TOOLS%\abuild\Scripts\python.exe" uv venv -q "%TOOLS%\abuild" || exit /b 1
rem this machine's cmake and ninja whatever the venv's Python is, and cmake's own binary ahead of its Python launcher:
rem the venv may get an x64 Python, whose emulated cmake would see an AMD64 machine and set ggml up for x86
uv pip install -q --python "%TOOLS%\abuild\Scripts\python.exe" --python-platform %TRIPLE% cmake ninja || exit /b 1
set "PATH=%TOOLS%\abuild\Lib\site-packages\cmake\data\bin;%TOOLS%\abuild\Scripts;%PATH%"
exit /b 0
:source
rem audio.cpp at TAG: cloned, or an existing tree moved to TAG (a tree of an earlier run would stay at its release, and
rem the package carry another audio.cpp than its version says). No submodule: the only one
rem (external\audio.cpp-server-frontends) is the optional web frontends, off by default. No to_chars patch, unlike
rem build-audiocpp.sh (libc++ before macOS 13.3, GCC before 11): clang-cl builds against MSVC's STL, which has it
if not exist "%SRC%\.git" git clone --depth 1 -b %TAG% https://github.com/0xShug0/audio.cpp "%SRC%" || exit /b 1
set "HEADNOW="
set "TAGNOW="
for /f "delims=" %%h in ('git -C "%SRC%" rev-parse HEAD 2^>nul') do set "HEADNOW=%%h"
for /f "delims=" %%h in ('git -C "%SRC%" rev-list -n 1 %TAG% 2^>nul') do set "TAGNOW=%%h"
if defined TAGNOW if /i "%HEADNOW%"=="%TAGNOW%" goto :src_tree
echo [audiocpp] moving %SRC% to audio.cpp %TAG%
git -C "%SRC%" fetch -q --depth 1 origin tag %TAG% || exit /b 1
git -C "%SRC%" checkout -q --force %TAG% || exit /b 1
:src_tree
if not exist "%SRC%\CMakeLists.txt" goto :src_bad
if not exist "%SRC%\external\ggml\CMakeLists.txt" goto :src_bad
rem audio.cpp's ggml builds ggml_vld1q_u32 (ARM NEON) the MSVC way under clang-cl too, which fills the vector wrongly
rem ({a, c, 0, 0} instead of {a, b, c, d}) in the IQ3 / IQ1_M kernels, silently: ggml's later fix, MSVC proper only
call :neon_patch "%SRC%\external\ggml\src\ggml-cpu\ggml-cpu-impl.h" || exit /b 1
exit /b 0
:src_bad
echo [audiocpp] ERROR: %SRC% is not an audio.cpp source tree: remove it and run again
exit /b 1
:neon_patch
findstr /c:"#if defined(_MSC_VER) && !defined(__clang__)" "%~1" >nul && exit /b 0
powershell -NoProfile -c "$p='%~1';$s=[IO.File]::ReadAllText($p);$s=[regex]::Replace($s,'#ifdef _MSC_VER(\r?\n#define ggml_vld1q_u32)','#if defined(_MSC_VER) && !defined(__clang__)$1');[IO.File]::WriteAllText($p,$s)" || exit /b 1
exit /b 0
:build_one
set "T=%~1"
set "B=%SRC%\build-%T%"
set "D=%SRC%\audiocpp-server-%T%"
echo === %T%
rem clang-cl, the only compiler ggml takes for ARM, with the static C runtime, so the zip needs only system DLLs. As in
rem build-audiocpp.sh: no OpenMP (ggml's own thread pool), no model manager (e2a downloads the models: no OpenSSL). The
rem Vulkan build keeps its CPU part at ARMv8.0: the GPU runs the model, and older CPUs stay in.
rem Warnings off (/w through CFLAGS / CXXFLAGS, which CMake puts first): audio.cpp adds -Wall for Clang, which clang-cl
rem reads as /Wall, every warning there is (-Weverything), over the whole tree; its -pedantic-errors clang-cl ignores
set "CFLAGS=/w"
set "CXXFLAGS=/w"
set "COMMON=-G Ninja -DCMAKE_BUILD_TYPE=Release -DENGINE_ENABLE_NATIVE_CPU=OFF -DENGINE_ENABLE_OPENMP=OFF -DGGML_OPENMP=OFF -DENGINE_ENABLE_CUDA=OFF -DENGINE_ENABLE_METAL=OFF -DENGINE_ENABLE_LLAMAFILE=ON -DENGINE_BUILD_TESTS=OFF -DAUDIOCPP_DEPLOYMENT_BUILD=ON -DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF -DAUDIOCPP_VERSION=%VER% %MODEL_FLAGS%"
set "CLANG=-DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
set "ARMV80=-DGGML_CPU_ARM_ARCH=armv8-a"
set "ARMV82=-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16"
if /i "%T%"=="windows-arm64-cpu" set "FLAGS=%CLANG% %ARMV80% -DENGINE_ENABLE_VULKAN=OFF"
if /i "%T%"=="windows-arm64-cpu-v82" set "FLAGS=%CLANG% %ARMV82% -DENGINE_ENABLE_VULKAN=OFF"
if /i "%T%"=="windows-arm64-vulkan" goto :bo_vulkan
goto :bo_cmake
:bo_vulkan
call :ensure_sdk || exit /b 1
set "FLAGS=%CLANG% %ARMV80% -DENGINE_ENABLE_VULKAN=ON"
:bo_cmake
cmake -S "%SRC%" -B "%B%" %COMMON% %FLAGS%
if errorlevel 1 goto :bo_fail
cmake --build "%B%" --target audiocpp_server -j %JOBS%
if errorlevel 1 goto :bo_fail
if exist "%D%" rmdir /s /q "%D%"
mkdir "%D%"
copy /y "%B%\bin\audiocpp_server.exe" "%D%\" >nul || exit /b 1
call :pack || exit /b 1
if "%CLEAN%"=="1" rmdir /s /q "%B%"
exit /b 0
:bo_fail
echo [audiocpp] ERROR: %T% failed to build, see above
exit /b 1
:pack
rem model_specs\ next to the server, as in audio.cpp's own packages (e2a starts it from that folder); the specs are also
rem compiled in (AUDIOCPP_DEPLOYMENT_BUILD)
xcopy /e /i /q /y "%SRC%\model_specs" "%D%\model_specs" >nul || exit /b 1
copy /y "%SRC%\LICENSE" "%D%\LICENSE" >nul || exit /b 1
copy /y "%SRC%\external\ggml\LICENSE" "%D%\LICENSE-ggml" >nul || exit /b 1
> "%D%\NOTICE" echo audio.cpp %TAG% (0xShug0 / ShugoAI LLC), Apache License 2.0, see LICENSE
>> "%D%\NOTICE" echo ggml: MIT License, see LICENSE-ggml
>> "%D%\NOTICE" echo cpp-httplib (Yuji Hirose), cJSON (Dave Gamble), libyaml (Kirill Simonov, Ingy dot Net), utf8proc: MIT License
>> "%D%\NOTICE" echo sentencepiece (Google): Apache License 2.0
if exist "%D%.zip" del /q "%D%.zip"
powershell -NoProfile -c "Compress-Archive -LiteralPath '%D%' -DestinationPath '%D%.zip' -CompressionLevel Optimal" || exit /b 1
echo --- %T% DLLs the exe loads:
dumpbin /nologo /dependents "%D%\audiocpp_server.exe" | findstr /i /r "\.dll"
echo --- %T% zip SHA-256:
certutil -hashfile "%D%.zip" SHA256 | findstr /v /c:"hash" /c:"CertUtil"
exit /b 0
:ensure_sdk
call :find_sdk
if exist "%VULKAN_SDK%\Bin\glslc.exe" if exist "%VULKAN_SDK%\Lib\vulkan-1.lib" goto :es_ok
if not "%INSTALL%"=="1" goto :es_none
call :install_sdk || exit /b 1
:es_ok
set "PATH=%VULKAN_SDK%\Bin;%PATH%"
exit /b 0
:es_none
echo [audiocpp] ERROR: no LunarG Vulkan SDK - install it, or drop --no-install
exit /b 1
:find_sdk
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "%LOCALAPPDATA%\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%%d"
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "C:\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=C:\VulkanSDK\%%d"
exit /b 0
:install_sdk
set "VKVER="
rem the SDK of this machine's architecture: LunarG's "windows" platform is x64, "warm" is arm64
for /f "usebackq delims=" %%v in (`curl.exe -fsSL https://vulkan.lunarg.com/sdk/latest/%VKPLAT%.txt`) do set "VKVER=%%v"
if not defined VKVER (echo [audiocpp] ERROR: cannot reach vulkan.lunarg.com & exit /b 1)
set "VKEXE=%TEMP%\vulkan_sdk_%VKPLAT%_%VKVER%.exe"
echo [audiocpp] installing the LunarG Vulkan SDK %VKVER% for %HOSTA% into %LOCALAPPDATA%\VulkanSDK\%VKVER%
curl.exe -fL -o "%VKEXE%" https://sdk.lunarg.com/sdk/download/%VKVER%/%VKPLAT%/vulkan_sdk.exe || exit /b 1
call :check_sha "%VKEXE%" https://sdk.lunarg.com/sdk/sha/%VKVER%/%VKPLAT%/vulkan_sdk.exe.txt || exit /b 1
"%VKEXE%" --root "%LOCALAPPDATA%\VulkanSDK\%VKVER%" --accept-licenses --default-answer --confirm-command install copy_only=1 || exit /b 1
del /q "%VKEXE%" 2>nul
set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%VKVER%"
if not exist "%VULKAN_SDK%\Bin\glslc.exe" (echo [audiocpp] ERROR: the SDK install did not produce Bin\glslc.exe & exit /b 1)
exit /b 0
:check_sha
set "SHAEXP="
for /f "usebackq tokens=1" %%s in (`curl.exe -fsSL %~2 2^>nul`) do if not defined SHAEXP set "SHAEXP=%%s"
if not defined SHAEXP goto :cs_none
set "SHAGOT="
for /f "usebackq delims=" %%h in (`powershell -NoProfile -c "(Get-FileHash -Algorithm SHA256 -LiteralPath '%~1').Hash"`) do set "SHAGOT=%%h"
if /i "%SHAEXP%"=="%SHAGOT%" exit /b 0
echo [audiocpp] ERROR: checksum mismatch for %~nx1
exit /b 1
:cs_none
echo [audiocpp] WARNING: no published checksum for %~nx1, skipping verification
exit /b 0
:llvm_path
rem vcvarsall does not put Visual Studio's clang-cl on PATH: put the one of this machine (Llvm\ARM64) first, unless PATH
rem has a clang-cl compiling for this machine already (an x64 one would build x64 code)
call :clang_ok && exit /b 0
if defined VCINSTALLDIR if exist "%VCINSTALLDIR%Tools\Llvm\%LLVMDIR%\bin\clang-cl.exe" set "PATH=%VCINSTALLDIR%Tools\Llvm\%LLVMDIR%\bin;%PATH%"
exit /b 0
:clang_ok
rem the clang-cl on PATH compiles for this machine by default
clang-cl --version 2>nul | findstr /b /c:"Target: %TRIPLE%" >nul
exit /b %ERRORLEVEL%
:vs_env
rem already in a Visual Studio environment for this machine: keep it
if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" goto :vs_find
where cl >nul 2>&1 && exit /b 0
:vs_find
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 0
rem run vswhere outside any ( ) block: its path holds "(x86)", whose ")" would end a for /f clause early
set "VSPATH="
set "VSOUT=%TEMP%\audiocpp_vspath_%RANDOM%.txt"
"%VSWHERE%" -latest -products * -requires %VSTOOLS% -property installationPath > "%VSOUT%" 2>nul
set /p VSPATH=<"%VSOUT%"
del /q "%VSOUT%" 2>nul
if not defined VSPATH exit /b 0
if not exist "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" exit /b 0
echo [audiocpp] loading the Visual Studio C++ environment for %HOSTA% from %VSPATH%
call "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" %HOSTA% >nul
exit /b 0
:can_add_clang
rem clang-cl can be added: installing is allowed and this Visual Studio has its installer
if not "%INSTALL%"=="1" exit /b 1
if not defined VSPATH if defined VSINSTALLDIR set "VSPATH=%VSINSTALLDIR:~0,-1%"
if not defined VSPATH exit /b 1
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe" exit /b 1
exit /b 0
:ensure_clang
rem every target needs clang-cl: add the C++ Clang tools to the Visual Studio found here, with its own installer (it
rem asks for admin rights through UAC), then pick clang-cl up from that Visual Studio
call :clang_ok && exit /b 0
call :can_add_clang || exit /b 0
echo [audiocpp] adding clang-cl (C++ Clang tools for Windows) to the Visual Studio in %VSPATH% - accept the UAC prompt, then
echo [audiocpp] the Visual Studio Installer works in the background for a few minutes
rem a quiet modify must run elevated from the start (setup.exe exits 5007 otherwise): start it elevated through
rem PowerShell and wait for it and the processes it starts (Start-Process -Wait; setup.exe has no --wait, only the
rem vs_buildtools bootstrapper does). 0 and 3010 (reboot advised, not needed for the compiler) are success
set "VSCOMPS=--add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset"
call :vs_modify
call :llvm_path
call :clang_ok && exit /b 0
rem no ( ) block here: VSPATH holds "(x86)"
if not exist "%VSPATH%\VC\Tools\Llvm\%LLVMDIR%\bin\clang-cl.exe" goto :ec_noclang
set "PATH=%VSPATH%\VC\Tools\Llvm\%LLVMDIR%\bin;%PATH%"
exit /b 0
:ec_noclang
echo [audiocpp] ERROR: clang-cl for %HOSTA% is still missing after the Visual Studio modify - was the UAC prompt declined? Add "C++ Clang Compiler for Windows" in the Visual Studio Installer (VC\Tools\Llvm\%LLVMDIR%)
exit /b 1
:vs_modify
rem adds the components in VSCOMPS to the Visual Studio in VSPATH, elevated (one UAC prompt)
powershell -NoProfile -c "$q=[char]34;try{$p=Start-Process -FilePath '%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe' -ArgumentList ('modify --installPath '+$q+'%VSPATH%'+$q+' %VSCOMPS% --quiet --norestart') -Verb RunAs -Wait -PassThru}catch{Write-Host '[audiocpp] the UAC prompt was declined';exit 1};if($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010){Write-Host ('[audiocpp] the Visual Studio Installer exited with '+$p.ExitCode);exit 1};exit 0"
exit /b 0
:install_bt
where cl >nul 2>&1 && call :clang_ok && exit /b 0
set "VSCOMPS=--add Microsoft.VisualStudio.Workload.VCTools --add %VSTOOLS% --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset"
rem a Visual Studio already here (VSPATH, from vs_env): add the missing components to it with its own installer;
rem winget would only report the Build Tools as already installed
if not defined VSPATH if defined VSINSTALLDIR set "VSPATH=%VSINSTALLDIR:~0,-1%"
if not defined VSPATH goto :bt_winget
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe" goto :bt_winget
echo [audiocpp] adding C++ and clang-cl to the Visual Studio in %VSPATH% - a UAC prompt may appear
call :vs_modify
goto :bt_check
:bt_winget
echo [audiocpp] installing Visual Studio 2022 Build Tools with C++ and clang-cl - several GB, a UAC prompt may appear
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add %VSTOOLS% --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset --includeRecommended"
:bt_check
call :vs_env
call :llvm_path
where cl >nul 2>&1 && call :clang_ok && exit /b 0
echo [audiocpp] ERROR: the C++ build tools or clang-cl are still not usable - finish the Visual Studio install, then run this again
exit /b 1
