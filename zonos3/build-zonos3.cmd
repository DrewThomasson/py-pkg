@echo off
rem build-zonos3.cmd - the e2a zonos3-server packages for Windows x64 and arm64 (zonos3.cpp, servers/ggml of Zyphra's
rem ZONOS3-Mini), built natively on each: windows-x64-cpu-avx2 / -cpu-sse42 / -vulkan and windows-arm64-cpu / -cpu-v82 /
rem -vulkan with clang-cl, windows-x64-cuda12 / -cuda13 with MSVC + nvcc, each with zyphra-textnorm (Rust, cargo for the
rem MSVC host) linked in.
rem Each lands as zonos3-server-<target>.zip in the ZONOS3-Mini folder, named like e2a downloads it from the zonos3
rem release of py-pkg. Runs from any command prompt: it loads the Visual Studio C++ environment itself (vswhere +
rem vcvarsall). Linux and macOS: build-zonos3.sh. build-zonos3.cmd --help for the options, --list for this machine.
setlocal EnableExtensions DisableDelayedExpansion
rem zonos3.cpp refuses GGUFs of another schema: e2a pins this commit and the Zyphra/ZONOS3-Mini weights revision
rem together (default_engine_settings['zonos3']['commit'] / ['revision'] in lib/conf_models.py), a new commit moves both
if not defined COMMIT set "COMMIT=96d9e0ec1e39083ed336ac78f24e3dbc93721c0f"
if not defined SRC set "SRC=%CD%\ZONOS3-Mini"
if not defined TOOLS set "TOOLS=%CD%\zonos3-tools"
if not defined JOBS set "JOBS=%NUMBER_OF_PROCESSORS%"
if not defined CLEAN set "CLEAN=0"
if not defined INSTALL set "INSTALL=1"
if not defined INSTALL_BT set "INSTALL_BT=0"
if not defined CUDA12 set "CUDA12=12.8.1"
if not defined CUDA13 set "CUDA13=13.0.2"
if not defined ARCHS12 set "ARCHS12=50-real;52-real;60-real;61-real;70-real;75-real;80-real;86-real;89-real;90-real;100-real;120"
if not defined ARCHS13 set "ARCHS13=75-real;80-real;86-real;89-real;90-real;100-real;120"
set "ALL=windows-x64-cpu-avx2 windows-x64-cpu-sse42 windows-x64-vulkan windows-x64-cuda12 windows-x64-cuda13"
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
if /i "%~1"=="--commit" (set "OPT=COMMIT" & goto :value)
if /i "%~1"=="--src" (set "OPT=SRC" & goto :value)
if /i "%~1"=="--tools" (set "OPT=TOOLS" & goto :value)
if /i "%~1"=="--jobs" (set "OPT=JOBS" & goto :value)
if /i "%~1"=="--cuda12" (set "OPT=CUDA12" & goto :value)
if /i "%~1"=="--cuda13" (set "OPT=CUDA13" & goto :value)
if /i "%~1"=="--archs12" (set "OPT=ARCHS12" & goto :value)
if /i "%~1"=="--archs13" (set "OPT=ARCHS13" & goto :value)
echo unknown option: %~1 - see --help
exit /b 1
:value
if "%~2"=="" (echo %~1 needs a value - see --help & exit /b 1)
set "%OPT%=%~2"
shift
shift
goto :args
:args_done
rem each machine builds its own packages, natively: x64 the CPU, Vulkan and CUDA ones, arm64 the CPU and Vulkan ones
rem (ggml's ARM code takes clang-cl only, while nvcc takes only MSVC's cl as host compiler)
set "HA=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HA=%PROCESSOR_ARCHITEW6432%"
set "HOSTA="
if /i "%HA%"=="AMD64" set "HOSTA=x64"
if /i "%HA%"=="ARM64" set "HOSTA=arm64"
if not defined HOSTA (echo build-zonos3.cmd builds the Windows packages on a Windows x64 or arm64 machine, this one is %HA% & exit /b 1)
rem this machine's triple (clang-cl's target, the Rust host, uv's wheels), its MSVC component and clang-cl folder in
rem Visual Studio, and its LunarG Vulkan SDK platform
set "TRIPLE=x86_64-pc-windows-msvc"
set "VSTOOLS=Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
set "LLVMDIR=x64"
set "VKPLAT=windows"
if "%HOSTA%"=="arm64" set "ALL=windows-arm64-cpu windows-arm64-cpu-v82 windows-arm64-vulkan"
if "%HOSTA%"=="arm64" set "TRIPLE=aarch64-pc-windows-msvc"
if "%HOSTA%"=="arm64" set "VSTOOLS=Microsoft.VisualStudio.Component.VC.Tools.ARM64"
if "%HOSTA%"=="arm64" set "LLVMDIR=ARM64"
if "%HOSTA%"=="arm64" set "VKPLAT=warm"
for %%r in ("%SRC%") do set "SRC=%%~fr"
for %%r in ("%TOOLS%") do set "TOOLS=%%~fr"
call :vs_env
call :find_sdk
call :llvm_path
if "%LIST%"=="1" goto :list
goto :build
:usage
echo build-zonos3.cmd - the e2a zonos3-server packages for Windows, built natively: the x64 ones on Windows x64, the
echo arm64 ones on Windows arm64. Each target is packed as zonos3-server-^<target^>.zip in the ZONOS3-Mini folder.
echo.
echo Targets on Windows x64
echo   windows-x64-cpu-avx2   CPU, AVX2/FMA/F16C, clang-cl, static C runtime: system DLLs only, Windows 10+
echo   windows-x64-cpu-sse42  same, SSE4.2, for CPUs without AVX2
echo   windows-x64-vulkan     GPU via Vulkan (NVIDIA, AMD, Intel), CPU part SSE4.2, clang-cl, the LunarG SDK's glslc
echo                          and vulkan-1.lib; users need only their GPU driver, which brings vulkan-1.dll
echo   windows-x64-cuda12     GPU via CUDA 12 (Maxwell to Blackwell, driver 525+), CPU part SSE4.2, MSVC + nvcc;
echo                          CUDA runtime, cuBLAS and the VC++ runtime bundled next to the exe: driver only for users
echo   windows-x64-cuda13     GPU via CUDA 13 (Turing to Blackwell, driver 580+), same
echo Targets on Windows arm64
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
echo   --commit SHA              ZONOS3-Mini commit to build, must match e2a's "commit"  [COMMIT]  96d9e0e...
echo   --src DIR                 ZONOS3-Mini tree, fetched if missing  [SRC]   .\ZONOS3-Mini
echo   --tools DIR               CUDA toolkits and build venv [TOOLS]     .\zonos3-tools
echo   --jobs N                  parallel compile jobs        [JOBS]      all cores
echo   --clean                   delete build-^<target^> after packing  [CLEAN=1]
echo   --cuda12 / --cuda13 VER   CUDA releases used           [CUDA12 / CUDA13]   12.8.1 / 13.0.2
echo   --archs12 / --archs13 "LIST"  CUDA architectures       [ARCHS12 / ARCHS13]
echo   --no-install              install nothing: no clang-cl, no Rust, no Vulkan SDK, no CUDA download  [INSTALL=0]
echo   --install-buildtools      no Visual Studio yet: install the 2022 Build Tools with C++ and clang-cl via winget
echo   NVCC_ALLOW_UNSUPPORTED=1  let nvcc accept a Visual Studio newer than its CUDA release supports
echo.
echo Needs
echo   every target: git, curl and PowerShell (both part of Windows 10+), Visual Studio 2022 C++ build tools for
echo     this machine: x64, or ARM64 on arm64
echo   every target: Rust (cargo) for zyphra-textnorm, installed by this script when missing: rustup's minimal
echo     profile for this machine's host (x86_64- or aarch64-pc-windows-msvc), in %%USERPROFILE%%\.cargo; a Rust
echo     whose default host is another one gets this machine's stable toolchain added
echo   cpu and vulkan: the "C++ Clang tools for Windows" component of Visual Studio, added by this script when
echo     missing through the Visual Studio Installer - one UAC prompt
echo   vulkan: the LunarG Vulkan SDK for this machine (x64 or arm64), installed by this script when missing
echo   cuda12 / cuda13: the CUDA compiler, runtime and cuBLAS, downloaded by this script into --tools from NVIDIA's
echo     redistributable archives - checksums verified, no installer, no driver, no admin rights, about 3 GB each
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
if /i not "%~1"=="windows-x64-cuda12" if /i not "%~1"=="windows-x64-cuda13" call :clang_ok || set "INOTE= - adds clang-cl to Visual Studio first"
if /i "%~1"=="windows-x64-vulkan" if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "INOTE=%INOTE% - installs the Vulkan SDK first"
if /i "%~1"=="windows-arm64-vulkan" if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "INOTE=%INOTE% - installs the Vulkan SDK first"
if /i "%~1"=="windows-x64-cuda12" if not exist "%TOOLS%\cuda-%CUDA12%\bin\nvcc.exe" set "INOTE= - downloads CUDA %CUDA12% first"
if /i "%~1"=="windows-x64-cuda13" if not exist "%TOOLS%\cuda-%CUDA13%\bin\nvcc.exe" set "INOTE= - downloads CUDA %CUDA13% first"
call :find_cargo || set "INOTE=%INOTE% - installs Rust first"
exit /b 0
:missing
rem sets MISS to what target %1 lacks on this machine, each item comma-terminated; empty when it can be built
set "MISS="
where git >nul 2>&1 || set "MISS=%MISS% git,"
where curl >nul 2>&1 || set "MISS=%MISS% curl,"
where cl >nul 2>&1 || set "MISS=%MISS% Visual Studio C++ build tools for %HOSTA%,"
if defined VSCMD_ARG_TGT_ARCH if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" set "MISS=%MISS% a %HOSTA% Visual Studio environment - this one targets %VSCMD_ARG_TGT_ARCH%,"
if "%INSTALL%"=="0" call :find_cargo || set "MISS=%MISS% Rust (cargo),"
if /i "%~1"=="windows-x64-cuda12" goto :miss_cuda12
if /i "%~1"=="windows-x64-cuda13" goto :miss_cuda13
call :clang_ok || call :can_add_clang || set "MISS=%MISS% clang-cl for %HOSTA% - C++ Clang tools for Windows,"
if /i not "%~1"=="windows-x64-vulkan" if /i not "%~1"=="windows-arm64-vulkan" exit /b 0
if "%INSTALL%"=="1" exit /b 0
if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "MISS=%MISS% LunarG Vulkan SDK,"
exit /b 0
:miss_cuda12
if "%INSTALL%"=="0" if not exist "%TOOLS%\cuda-%CUDA12%\bin\nvcc.exe" set "MISS=%MISS% CUDA %CUDA12% in %TOOLS%,"
exit /b 0
:miss_cuda13
if "%INSTALL%"=="0" if not exist "%TOOLS%\cuda-%CUDA13%\bin\nvcc.exe" set "MISS=%MISS% CUDA %CUDA13% in %TOOLS%,"
exit /b 0
:build
set "TARGETS=%ALL%"
if defined ONLY set "TARGETS=%ONLY%"
if "%INSTALL_BT%"=="1" call :install_bt || exit /b 1
set "NEEDCLANG=0"
for %%t in (%TARGETS%) do if /i not "%%t"=="windows-x64-cuda12" if /i not "%%t"=="windows-x64-cuda13" set "NEEDCLANG=1"
if "%NEEDCLANG%"=="1" call :ensure_clang || exit /b 1
for %%t in (%TARGETS%) do call :check_target %%t || exit /b 1
call :tools_env || exit /b 1
call :ensure_rust || exit /b 1
call :source || exit /b 1
for %%t in (%TARGETS%) do call :build_one %%t || exit /b 1
echo [zonos3] done: the zips are in %SRC%
exit /b 0
:check_target
set "KNOWN=0"
for %%a in (%ALL%) do if /i "%%a"=="%~1" set "KNOWN=1"
if "%KNOWN%"=="0" (echo [zonos3] ERROR: %~1 is not a target of this Windows %HOSTA% machine - see --list & exit /b 1)
call :missing %1
if defined MISS goto :ct_missing
exit /b 0
:ct_missing
echo [zonos3] ERROR: %~1: missing:%MISS:~0,-1% - see --help
exit /b 1
:tools_env
if not exist "%TOOLS%" mkdir "%TOOLS%"
where uv >nul 2>&1 && goto :have_uv
echo [zonos3] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [zonos3] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
if not exist "%TOOLS%\zbuild\Scripts\python.exe" uv venv -q "%TOOLS%\zbuild" || exit /b 1
rem this machine's cmake and ninja whatever the venv's Python is, and cmake's own binary ahead of its Python launcher:
rem on arm64 the venv may get an x64 Python, whose emulated cmake would see an AMD64 machine and set ggml up for x86
uv pip install -q --python "%TOOLS%\zbuild\Scripts\python.exe" --python-platform %TRIPLE% cmake ninja || exit /b 1
set "PATH=%TOOLS%\zbuild\Lib\site-packages\cmake\data\bin;%TOOLS%\zbuild\Scripts;%PATH%"
exit /b 0
:source
rem ZONOS3-Mini at COMMIT (no release tags: fetched by commit), with the two submodules zonos3.cpp builds from: ggml
rem (its CMake applies servers\ggml\patches\*.patch to that worktree at configure time) and zyphra-textnorm (Rust).
rem The whole tree is needed: the build embeds model\src\zonos3\registries\*.json and servers\api\openapi.json.
rem zonos3.cpp takes an integrated GPU itself: no source patch, unlike zonos2.cpp v0.5.2
if not exist "%SRC%\.git" git init -q "%SRC%" || exit /b 1
git -C "%SRC%" remote get-url origin >nul 2>&1 || git -C "%SRC%" remote add origin https://github.com/Zyphra/ZONOS3-Mini || exit /b 1
set "HEADNOW="
for /f "delims=" %%h in ('git -C "%SRC%" rev-parse HEAD 2^>nul') do set "HEADNOW=%%h"
if /i "%HEADNOW%"=="%COMMIT%" goto :src_subs
git -C "%SRC%" fetch -q --depth 1 origin %COMMIT% || exit /b 1
git -C "%SRC%" checkout -q --force FETCH_HEAD || exit /b 1
:src_subs
git -C "%SRC%" submodule update -q --init --depth 1 servers/ggml/ggml third_party/zyphra-textnorm
if not exist "%SRC%\servers\ggml\ggml\CMakeLists.txt" goto :src_nosub
if not exist "%SRC%\third_party\zyphra-textnorm\Cargo.toml" goto :src_nosub
exit /b 0
:src_nosub
echo [zonos3] ERROR: the ggml or zyphra-textnorm submodule of %SRC% is empty and could not be fetched: remove %SRC% and run again
exit /b 1
:build_one
set "T=%~1"
set "B=%SRC%\build-%T%"
set "D=%SRC%\zonos3-server-%T%"
set "CV="
echo === %T%
rem CPU and Vulkan: clang-cl, whose ggml CPU code is faster than MSVC's (and the only compiler ggml takes for ARM),
rem with the static C runtime, so the zip needs only system DLLs. CUDA: nvcc takes only MSVC's cl.exe as host compiler,
rem with the DLL runtime, which is bundled. The GPU builds keep their CPU part at SSE4.2 on x64, ARMv8.0 on arm64: the
rem GPU runs the model, and older CPUs stay in.
rem zyphra-textnorm follows each one's C runtime: +crt-static with clang-cl's static one (libcmt), Rust's default (the
rem DLL runtime) with nvcc's
set "CARGO_BUILD_JOBS=%JOBS%"
set "RUSTFLAGS=-C target-feature=+crt-static"
set "COMMON=-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_AVX512=OFF -DGGML_CCACHE=OFF"
set "STATIC=-DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
set "SSE42=-DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF"
set "AVX2=-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON"
set "ARMV80=-DGGML_CPU_ARM_ARCH=armv8-a"
set "ARMV82=-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16"
set "CLANG=-DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl %STATIC%"
if /i "%T%"=="windows-x64-cpu-avx2" set "FLAGS=%CLANG% %AVX2%"
if /i "%T%"=="windows-x64-cpu-sse42" set "FLAGS=%CLANG% %SSE42%"
if /i "%T%"=="windows-arm64-cpu" set "FLAGS=%CLANG% %ARMV80%"
if /i "%T%"=="windows-arm64-cpu-v82" set "FLAGS=%CLANG% %ARMV82%"
if /i "%T%"=="windows-x64-vulkan" (set "CPUF=%SSE42%" & goto :bo_vulkan)
if /i "%T%"=="windows-arm64-vulkan" (set "CPUF=%ARMV80%" & goto :bo_vulkan)
if /i "%T%"=="windows-x64-cuda12" (set "CV=%CUDA12%" & set "CA=%ARCHS12%" & goto :bo_cuda)
if /i "%T%"=="windows-x64-cuda13" (set "CV=%CUDA13%" & set "CA=%ARCHS13%" & goto :bo_cuda)
goto :bo_cmake
:bo_vulkan
call :ensure_sdk || exit /b 1
set "FLAGS=%CLANG% %CPUF% -DGGML_VULKAN=ON"
goto :bo_cmake
:bo_cuda
call :ensure_cuda %CV% || exit /b 1
set "RUSTFLAGS="
set "CUDADIR=%TOOLS%\cuda-%CV%"
set "CUDAF=%CUDADIR:\=/%"
set "NVF="
if "%NVCC_ALLOW_UNSUPPORTED%"=="1" set "NVF=-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
set "FLAGS=-DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl %SSE42% -DGGML_CUDA=ON -DGGML_CUDA_NCCL=OFF "-DCMAKE_CUDA_COMPILER=%CUDAF%/bin/nvcc.exe" "-DCUDAToolkit_ROOT=%CUDAF%" "-DCMAKE_CUDA_ARCHITECTURES=%CA%" %NVF%"
set "PATH=%CUDADIR%\bin;%PATH%"
:bo_cmake
cmake -S "%SRC%\servers\ggml" -B "%B%" %COMMON% %FLAGS%
if errorlevel 1 goto :bo_fail
cmake --build "%B%" --target zonos3-server -j %JOBS%
if errorlevel 1 goto :bo_fail
if exist "%D%" rmdir /s /q "%D%"
mkdir "%D%"
copy /y "%B%\zonos3-server.exe" "%D%\" >nul || exit /b 1
if defined CV call :bundle_cuda || exit /b 1
call :pack || exit /b 1
if "%CLEAN%"=="1" rmdir /s /q "%B%"
exit /b 0
:bo_fail
echo [zonos3] ERROR: %T% failed to build, see above
if defined CV echo [zonos3]   if nvcc rejects this Visual Studio version: set NVCC_ALLOW_UNSUPPORTED=1, or use the Visual Studio 2022 release CUDA %CV% supports
exit /b 1
:bundle_cuda
rem next to the exe, where Windows looks first: this toolkit's CUDA runtime and cuBLAS (CUDA 13 keeps them in
rem bin\x64, hence /r) and the VC++ runtime that nvcc's /MD build needs
for /r "%CUDADIR%\bin" %%f in (cudart64_*.dll cublas64_*.dll cublasLt64_*.dll) do copy /y "%%f" "%D%\" >nul
if not exist "%D%\cublasLt64_*.dll" goto :bc_nocublas
set "CRT="
for /d %%d in ("%VCToolsRedistDir%x64\Microsoft.VC*.CRT") do set "CRT=%%~fd"
if not defined CRT goto :bc_nocrt
copy /y "%CRT%\*.dll" "%D%\" >nul || exit /b 1
exit /b 0
:bc_nocublas
echo [zonos3] ERROR: no cublasLt64 DLL under %CUDADIR%\bin
exit /b 1
:bc_nocrt
echo [zonos3] ERROR: no VC++ runtime under %VCToolsRedistDir%x64
exit /b 1
:pack
copy /y "%SRC%\LICENSE" "%D%\LICENSE-zonos3" >nul || exit /b 1
copy /y "%SRC%\NOTICE" "%D%\NOTICE-zonos3" >nul || exit /b 1
copy /y "%SRC%\servers\ggml\ggml\LICENSE" "%D%\LICENSE-ggml" >nul || exit /b 1
copy /y "%SRC%\third_party\zyphra-textnorm\LICENSE" "%D%\LICENSE-zyphra-textnorm" >nul || exit /b 1
copy /y "%SRC%\third_party\zyphra-textnorm\NOTICE" "%D%\NOTICE-zyphra-textnorm" >nul || exit /b 1
mkdir "%D%\licenses"
copy /y "%SRC%\third_party\licenses\*" "%D%\licenses\" >nul || exit /b 1
copy /y "%SRC%\third_party\zyphra-textnorm\licenses\*" "%D%\licenses\" >nul || exit /b 1
copy /y "%SRC%\servers\ggml\vendor\lmdb\LICENSE" "%D%\licenses\lmdb-OpenLDAP-2.8.txt" >nul || exit /b 1
copy /y "%SRC%\servers\ggml\vendor\json-schema-validator\LICENSE" "%D%\licenses\json-schema-validator-MIT.txt" >nul || exit /b 1
> "%D%\NOTICE" echo zonos3.cpp: servers/ggml of Zyphra ZONOS3-Mini %COMMIT%, MIT License, see LICENSE-zonos3 and NOTICE-zonos3
>> "%D%\NOTICE" echo zyphra-textnorm (Zyphra): MIT License, see LICENSE-zyphra-textnorm and NOTICE-zyphra-textnorm
>> "%D%\NOTICE" echo Rust standard library: MIT OR Apache-2.0
>> "%D%\NOTICE" echo ggml: MIT License, see LICENSE-ggml
>> "%D%\NOTICE" echo cpp-httplib: Copyright (c) Yuji Hirose, MIT License
>> "%D%\NOTICE" echo nlohmann/json: Copyright (c) Niels Lohmann, MIT License
>> "%D%\NOTICE" echo json-schema-validator 2.3.0: Copyright (c) Patrick Boettcher, MIT License
>> "%D%\NOTICE" echo LMDB: OpenLDAP Public License 2.8
>> "%D%\NOTICE" echo pocketfft: Max-Planck-Society, BSD 3-Clause License
>> "%D%\NOTICE" echo the other third-party licenses: licenses\
if defined CV echo cudart64, cublas64, cublasLt64: NVIDIA CUDA runtime and cuBLAS %CV%, redistributed under the NVIDIA CUDA Toolkit EULA>> "%D%\NOTICE"
if defined CV echo msvcp140, vcruntime140, concrt140: Microsoft Visual C++ runtime, redistributed under the Visual Studio license terms>> "%D%\NOTICE"
if exist "%D%.zip" del /q "%D%.zip"
powershell -NoProfile -c "Compress-Archive -LiteralPath '%D%' -DestinationPath '%D%.zip' -CompressionLevel Optimal" || exit /b 1
echo --- %T% DLLs the exe loads:
dumpbin /nologo /dependents "%D%\zonos3-server.exe" | findstr /i /r "\.dll"
echo --- %T% zip SHA-256:
certutil -hashfile "%D%.zip" SHA256 | findstr /v /c:"hash" /c:"CertUtil"
exit /b 0
:find_cargo
rem cargo on PATH, else rustup's default place: put it on PATH; fails when there is none
where cargo >nul 2>&1 && exit /b 0
if not defined CARGO_HOME set "CARGO_HOME=%USERPROFILE%\.cargo"
if not exist "%CARGO_HOME%\bin\cargo.exe" exit /b 1
set "PATH=%CARGO_HOME%\bin;%PATH%"
exit /b 0
:ensure_rust
rem Rust for zyphra-textnorm, which zonos3.cpp's CMake builds with cargo for the host (pure Rust, std only): rustup's
rem minimal profile for this machine's MSVC host when missing, no PATH change outside this run
call :find_cargo && goto :er_host
if not "%INSTALL%"=="1" goto :er_none
set "RUSTUP=%TEMP%\rustup-init-%RANDOM%.exe"
echo [zonos3] installing Rust (rustup, minimal profile, %TRIPLE%) into %USERPROFILE%\.cargo
curl.exe -fsSL -o "%RUSTUP%" https://static.rust-lang.org/rustup/dist/%TRIPLE%/rustup-init.exe || exit /b 1
"%RUSTUP%" -y --profile minimal --default-host %TRIPLE% --default-toolchain stable --no-modify-path || exit /b 1
del /q "%RUSTUP%" 2>nul
call :find_cargo && exit /b 0
echo [zonos3] ERROR: cargo is still missing after the Rust install
exit /b 1
:er_none
echo [zonos3] ERROR: no Rust (cargo) - install it from https://rustup.rs, or drop --no-install
exit /b 1
:er_host
rem cargo builds for its own host (no --target), so a Rust whose default host is another one - an x64 Rust on an arm64
rem machine, a GNU one - gives a library the link refuses: run this machine's stable MSVC toolchain instead
rustc -vV 2>nul | findstr /b /c:"host: %TRIPLE%" >nul && exit /b 0
set "RUSTUP_TOOLCHAIN=stable-%TRIPLE%"
rustc -vV 2>nul | findstr /b /c:"host: %TRIPLE%" >nul && exit /b 0
where rustup >nul 2>&1 || goto :er_nohost
if not "%INSTALL%"=="1" goto :er_nohost
echo [zonos3] adding the Rust toolchain %RUSTUP_TOOLCHAIN% (minimal profile): the default one builds for another host
rustup toolchain install %RUSTUP_TOOLCHAIN% --profile minimal --no-self-update || exit /b 1
exit /b 0
:er_nohost
echo [zonos3] ERROR: this Rust builds for another host than %TRIPLE% - rustup toolchain install stable-%TRIPLE%, or drop --no-install
exit /b 1
:ensure_sdk
call :find_sdk
if exist "%VULKAN_SDK%\Bin\glslc.exe" if exist "%VULKAN_SDK%\Lib\vulkan-1.lib" goto :es_ok
if not "%INSTALL%"=="1" goto :es_none
call :install_sdk || exit /b 1
:es_ok
set "PATH=%VULKAN_SDK%\Bin;%PATH%"
exit /b 0
:es_none
echo [zonos3] ERROR: no LunarG Vulkan SDK - install it, or drop --no-install
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
if not defined VKVER (echo [zonos3] ERROR: cannot reach vulkan.lunarg.com & exit /b 1)
set "VKEXE=%TEMP%\vulkan_sdk_%VKPLAT%_%VKVER%.exe"
echo [zonos3] installing the LunarG Vulkan SDK %VKVER% for %HOSTA% into %LOCALAPPDATA%\VulkanSDK\%VKVER%
curl.exe -fL -o "%VKEXE%" https://sdk.lunarg.com/sdk/download/%VKVER%/%VKPLAT%/vulkan_sdk.exe || exit /b 1
call :check_sha "%VKEXE%" https://sdk.lunarg.com/sdk/sha/%VKVER%/%VKPLAT%/vulkan_sdk.exe.txt || exit /b 1
"%VKEXE%" --root "%LOCALAPPDATA%\VulkanSDK\%VKVER%" --accept-licenses --default-answer --confirm-command install copy_only=1 || exit /b 1
del /q "%VKEXE%" 2>nul
set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%VKVER%"
if not exist "%VULKAN_SDK%\Bin\glslc.exe" (echo [zonos3] ERROR: the SDK install did not produce Bin\glslc.exe & exit /b 1)
exit /b 0
:check_sha
set "SHAEXP="
for /f "usebackq tokens=1" %%s in (`curl.exe -fsSL %~2 2^>nul`) do if not defined SHAEXP set "SHAEXP=%%s"
if not defined SHAEXP goto :cs_none
set "SHAGOT="
for /f "usebackq delims=" %%h in (`powershell -NoProfile -c "(Get-FileHash -Algorithm SHA256 -LiteralPath '%~1').Hash"`) do set "SHAGOT=%%h"
if /i "%SHAEXP%"=="%SHAGOT%" exit /b 0
echo [zonos3] ERROR: checksum mismatch for %~nx1
exit /b 1
:cs_none
echo [zonos3] WARNING: no published checksum for %~nx1, skipping verification
exit /b 0
:ensure_cuda
rem CUDA %1 from NVIDIA's redistributable archives - redistrib_%1.json lists each component's zip and sha256: the
rem compiler (nvcc, plus crt and nvvm, separate since CUDA 13), the runtime, the CCCL headers and cuBLAS, merged into
rem one toolkit folder (CCCL is cuda_cccl up to CUDA 13.2, cccl from 13.3). No installer, no driver, no admin rights,
rem several CUDA releases side by side
set "CUDADIR=%TOOLS%\cuda-%~1"
if exist "%CUDADIR%\bin\nvcc.exe" exit /b 0
if not "%INSTALL%"=="1" goto :ec_none
echo [zonos3] downloading the CUDA %~1 compiler, runtime and cuBLAS into %CUDADIR%, about 3 GB
powershell -NoProfile -ExecutionPolicy Bypass -c "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$v='%~1';$d='%CUDADIR%';$b='https://developer.download.nvidia.com/compute/cuda/redist/';$j=Invoke-RestMethod ($b+'redistrib_'+$v+'.json');New-Item -ItemType Directory -Force $d | Out-Null;foreach($c in @('cuda_nvcc','cuda_crt','libnvvm','cuda_cudart','cuda_cccl','cccl','libcublas')){$e=$j.$c.'windows-x86_64';if(-not $e){continue};$z=Join-Path $env:TEMP ([IO.Path]::GetFileName($e.relative_path));Write-Host ('[zonos3]   '+$c+' '+$j.$c.version);Invoke-WebRequest -UseBasicParsing ($b+$e.relative_path) -OutFile $z;if((Get-FileHash -Algorithm SHA256 $z).Hash -ne $e.sha256.ToUpper()){throw ('checksum mismatch: '+$c)};$t=Join-Path $env:TEMP ('zcuda'+[guid]::NewGuid().ToString('N'));Expand-Archive -LiteralPath $z -DestinationPath $t -Force;$r=(Get-ChildItem $t | Select-Object -First 1).FullName;robocopy $r $d /E /NFL /NDL /NJH /NJS /NP | Out-Null;if($LASTEXITCODE -ge 8){throw ('copy failed: '+$c)};Remove-Item $t -Recurse -Force;Remove-Item $z};exit 0" || exit /b 1
if not exist "%CUDADIR%\bin\nvcc.exe" goto :ec_nonvcc
exit /b 0
:ec_none
echo [zonos3] ERROR: no CUDA %~1 in %CUDADIR% - drop --no-install to download it
exit /b 1
:ec_nonvcc
echo [zonos3] ERROR: CUDA %~1 has no bin\nvcc.exe after the download - check that release on developer.download.nvidia.com/compute/cuda/redist
exit /b 1
:llvm_path
rem vcvarsall does not put Visual Studio's clang-cl on PATH: put the one of this machine (Llvm\x64 or Llvm\ARM64) first,
rem unless PATH has a clang-cl compiling for this machine already (an x64 one on arm64 would build x64 code)
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
set "VSOUT=%TEMP%\zonos3_vspath_%RANDOM%.txt"
"%VSWHERE%" -latest -products * -requires %VSTOOLS% -property installationPath > "%VSOUT%" 2>nul
set /p VSPATH=<"%VSOUT%"
del /q "%VSOUT%" 2>nul
if not defined VSPATH exit /b 0
if not exist "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" exit /b 0
echo [zonos3] loading the Visual Studio C++ environment for %HOSTA% from %VSPATH%
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
rem the CPU and Vulkan targets need clang-cl: add the C++ Clang tools to the Visual Studio found here, with its own
rem installer (it asks for admin rights through UAC), then pick clang-cl up from that Visual Studio
call :clang_ok && exit /b 0
call :can_add_clang || exit /b 0
echo [zonos3] adding clang-cl (C++ Clang tools for Windows) to the Visual Studio in %VSPATH% - accept the UAC prompt, then
echo [zonos3] the Visual Studio Installer works in the background for a few minutes
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
echo [zonos3] ERROR: clang-cl for %HOSTA% is still missing after the Visual Studio modify - was the UAC prompt declined? Add "C++ Clang Compiler for Windows" in the Visual Studio Installer (VC\Tools\Llvm\%LLVMDIR%), or on x64 build only the CUDA targets
exit /b 1
:vs_modify
rem adds the components in VSCOMPS to the Visual Studio in VSPATH, elevated (one UAC prompt)
powershell -NoProfile -c "$q=[char]34;try{$p=Start-Process -FilePath '%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe' -ArgumentList ('modify --installPath '+$q+'%VSPATH%'+$q+' %VSCOMPS% --quiet --norestart') -Verb RunAs -Wait -PassThru}catch{Write-Host '[zonos3] the UAC prompt was declined';exit 1};if($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010){Write-Host ('[zonos3] the Visual Studio Installer exited with '+$p.ExitCode);exit 1};exit 0"
exit /b 0
:install_bt
where cl >nul 2>&1 && call :clang_ok && exit /b 0
set "VSCOMPS=--add Microsoft.VisualStudio.Workload.VCTools --add %VSTOOLS% --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset"
rem a Visual Studio already here (VSPATH, from vs_env): add the missing components to it with its own installer;
rem winget would only report the Build Tools as already installed
if not defined VSPATH if defined VSINSTALLDIR set "VSPATH=%VSINSTALLDIR:~0,-1%"
if not defined VSPATH goto :bt_winget
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\setup.exe" goto :bt_winget
echo [zonos3] adding C++ and clang-cl to the Visual Studio in %VSPATH% - a UAC prompt may appear
call :vs_modify
goto :bt_check
:bt_winget
echo [zonos3] installing Visual Studio 2022 Build Tools with C++ and clang-cl - several GB, a UAC prompt may appear
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add %VSTOOLS% --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset --includeRecommended"
:bt_check
call :vs_env
call :llvm_path
where cl >nul 2>&1 && call :clang_ok && exit /b 0
echo [zonos3] ERROR: the C++ build tools or clang-cl are still not usable - finish the Visual Studio install, then run this again
exit /b 1
