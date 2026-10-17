@echo off
rem build-zonos2.cmd - the e2a zonos2-server packages for Windows x64 (zonos2.cpp, Zyphra), built natively:
rem   windows-x64-cpu-avx2 / -cpu-sse42 / -vulkan with clang-cl, windows-x64-cuda12 / -cuda13 with MSVC + nvcc.
rem Each lands as zonos2-server-<target>.zip in the zonos2.cpp folder, named like e2a downloads it from the zonos2
rem release of py-pkg. Runs from any command prompt: it loads the Visual Studio C++ environment itself (vswhere +
rem vcvarsall). Linux and macOS: build-zonos2.sh. build-zonos2.cmd --help for the options, --list for this machine.
setlocal EnableExtensions DisableDelayedExpansion
if not defined TAG set "TAG=v0.5.2"
if not defined SRC set "SRC=%CD%\zonos2.cpp"
if not defined TOOLS set "TOOLS=%CD%\zonos2-tools"
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
if /i "%~1"=="--tag" (set "OPT=TAG" & goto :value)
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
set "HA=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HA=%PROCESSOR_ARCHITEW6432%"
if /i not "%HA%"=="AMD64" (echo build-zonos2.cmd builds the Windows x64 packages on a Windows x64 machine, this one is %HA% & exit /b 1)
for %%r in ("%SRC%") do set "SRC=%%~fr"
for %%r in ("%TOOLS%") do set "TOOLS=%%~fr"
call :vs_env
call :find_sdk
call :llvm_path
if "%LIST%"=="1" goto :list
goto :build
:usage
echo build-zonos2.cmd - the e2a zonos2-server packages for Windows x64, built natively on Windows x64.
echo Each target is packed as zonos2-server-^<target^>.zip in the zonos2.cpp folder.
echo.
echo Targets
echo   windows-x64-cpu-avx2   CPU, AVX2/FMA/F16C, clang-cl, static C runtime: system DLLs only, Windows 10+
echo   windows-x64-cpu-sse42  same, SSE4.2, for CPUs without AVX2
echo   windows-x64-vulkan     GPU via Vulkan (NVIDIA, AMD, Intel), CPU part SSE4.2, clang-cl, the LunarG SDK's glslc
echo                          and vulkan-1.lib; users need only their GPU driver, which brings vulkan-1.dll
echo   windows-x64-cuda12     GPU via CUDA 12 (Maxwell to Blackwell, driver 525+), CPU part SSE4.2, MSVC + nvcc;
echo                          CUDA runtime, cuBLAS and the VC++ runtime bundled next to the exe: driver only for users
echo   windows-x64-cuda13     GPU via CUDA 13 (Turing to Blackwell, driver 580+), same
echo No GPU is needed to build any of them.
echo.
echo Options                     [environment variable]   default
echo   -l, --list                what this machine can build now, nothing built
echo   --only "T1 T2"            build these targets only     [ONLY]      every target
echo   --tag vX.Y.Z              zonos2.cpp release to build  [TAG]       v0.5.2
echo   --src DIR                 zonos2.cpp tree, cloned if missing  [SRC]   .\zonos2.cpp
echo   --tools DIR               CUDA toolkits and build venv [TOOLS]     .\zonos2-tools
echo   --jobs N                  parallel compile jobs        [JOBS]      all cores
echo   --clean                   delete build-^<target^> after packing  [CLEAN=1]
echo   --cuda12 / --cuda13 VER   CUDA releases used           [CUDA12 / CUDA13]   12.8.1 / 13.0.2
echo   --archs12 / --archs13 "LIST"  CUDA architectures       [ARCHS12 / ARCHS13]
echo   --no-install              install nothing: no Vulkan SDK, no CUDA download  [INSTALL=0]
echo   --install-buildtools      install Visual Studio 2022 Build Tools with C++ and clang-cl through winget
echo   NVCC_ALLOW_UNSUPPORTED=1  let nvcc accept a Visual Studio newer than its CUDA release supports
echo.
echo Needs
echo   every target: git, curl and PowerShell (both part of Windows 10+), Visual Studio 2022 C++ build tools
echo   cpu and vulkan: the "C++ Clang tools for Windows" component of Visual Studio (clang-cl)
echo   vulkan: the LunarG Vulkan SDK, installed by this script when missing
echo   cuda12 / cuda13: the CUDA compiler, runtime and cuBLAS, downloaded by this script into --tools from NVIDIA's
echo     redistributable archives - checksums verified, no installer, no driver, no admin rights, about 3 GB each
echo   cmake and ninja come from a venv this script makes with uv, installed when missing
exit /b 0
:list
echo targets on this Windows x64 machine:
for %%t in (%ALL%) do call :list_one %%t
exit /b 0
:list_one
call :missing %1
set "NOTE=ready"
if defined MISS set "NOTE=missing:%MISS:~0,-1% - see --help"
call :install_note %1
echo   %1   %NOTE%%INOTE%
exit /b 0
:install_note
set "INOTE="
if defined MISS exit /b 0
if /i "%~1"=="windows-x64-vulkan" if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "INOTE= - installs the Vulkan SDK first"
if /i "%~1"=="windows-x64-cuda12" if not exist "%TOOLS%\cuda-%CUDA12%\bin\nvcc.exe" set "INOTE= - downloads CUDA %CUDA12% first"
if /i "%~1"=="windows-x64-cuda13" if not exist "%TOOLS%\cuda-%CUDA13%\bin\nvcc.exe" set "INOTE= - downloads CUDA %CUDA13% first"
exit /b 0
:missing
rem sets MISS to what target %1 lacks on this machine, each item comma-terminated; empty when it can be built
set "MISS="
where git >nul 2>&1 || set "MISS=%MISS% git,"
where curl >nul 2>&1 || set "MISS=%MISS% curl,"
where cl >nul 2>&1 || set "MISS=%MISS% Visual Studio C++ build tools,"
if /i "%~1"=="windows-x64-cuda12" goto :miss_cuda12
if /i "%~1"=="windows-x64-cuda13" goto :miss_cuda13
where clang-cl >nul 2>&1 || set "MISS=%MISS% clang-cl - C++ Clang tools for Windows,"
if /i not "%~1"=="windows-x64-vulkan" exit /b 0
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
for %%t in (%TARGETS%) do call :check_target %%t || exit /b 1
call :tools_env || exit /b 1
call :source || exit /b 1
for %%t in (%TARGETS%) do call :build_one %%t || exit /b 1
echo [zonos2] done: the zips are in %SRC%
exit /b 0
:check_target
set "KNOWN=0"
for %%a in (%ALL%) do if /i "%%a"=="%~1" set "KNOWN=1"
if "%KNOWN%"=="0" (echo [zonos2] ERROR: unknown target %~1 - see --list & exit /b 1)
call :missing %1
if defined MISS goto :ct_missing
exit /b 0
:ct_missing
echo [zonos2] ERROR: %~1: missing:%MISS:~0,-1% - see --help
exit /b 1
:tools_env
if not exist "%TOOLS%" mkdir "%TOOLS%"
where uv >nul 2>&1 && goto :have_uv
echo [zonos2] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [zonos2] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
if not exist "%TOOLS%\zbuild\Scripts\python.exe" uv venv -q "%TOOLS%\zbuild" || exit /b 1
uv pip install -q --python "%TOOLS%\zbuild\Scripts\python.exe" cmake ninja || exit /b 1
set "PATH=%TOOLS%\zbuild\Scripts;%PATH%"
exit /b 0
:source
if not exist "%SRC%\.git" git clone --depth 1 -b %TAG% --recurse-submodules --shallow-submodules https://github.com/Zyphra/zonos2.cpp "%SRC%" || exit /b 1
rem a tree cloned without --recurse-submodules, or copied, has an empty ggml folder: fetch the pinned ggml
if not exist "%SRC%\ggml\CMakeLists.txt" git -C "%SRC%" submodule update --init --recursive --depth 1
if not exist "%SRC%\ggml\CMakeLists.txt" goto :src_noggml
rem zonos2.cpp v0.5.2 only looks for a discrete GPU, but ggml reports integrated Vulkan GPUs (Intel / AMD laptops) as
rem IGPU, so those ran on CPU: take an integrated GPU when there is no discrete one - same patch as build-zonos2.sh
findstr /c:"DEVICE_TYPE_IGPU" "%SRC%\src\zonos2.cpp" >nul && exit /b 0
call :igpu_patch "%SRC%\src\zonos2.cpp" || exit /b 1
call :igpu_patch "%SRC%\src\dac.cpp" || exit /b 1
exit /b 0
:src_noggml
echo [zonos2] ERROR: %SRC%\ggml is empty and the submodule could not be fetched: remove %SRC% and run again
exit /b 1
:igpu_patch
powershell -NoProfile -c "$p='%~1';$s=[IO.File]::ReadAllText($p);$s=[regex]::Replace($s,'(?m)^( *)if \(use_gpu\) dev = ggml_backend_dev_by_type\(GGML_BACKEND_DEVICE_TYPE_GPU\);\r?\n',{param($m) $m.Value+$m.Groups[1].Value+'if (use_gpu && !dev) dev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);'+[char]10});$s=$s.Replace('m.is_gpu  = (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU);','m.is_gpu  = (ggml_backend_dev_type(dev) != GGML_BACKEND_DEVICE_TYPE_CPU);');[IO.File]::WriteAllText($p,$s)" || exit /b 1
exit /b 0
:build_one
set "T=%~1"
set "B=%SRC%\build-%T%"
set "D=%SRC%\zonos2-server-%T%"
set "CV="
echo === %T%
rem CPU and Vulkan: clang-cl, whose ggml CPU code is faster than MSVC's, with the static C runtime, so the zip needs
rem only system DLLs. CUDA: nvcc takes only MSVC's cl.exe as host compiler, with the DLL runtime, which is bundled.
rem The GPU builds keep their CPU part at SSE4.2: the GPU runs the model, and older CPUs stay in
set "COMMON=-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_AVX512=OFF -DGGML_CCACHE=OFF"
set "STATIC=-DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
set "SSE42=-DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF"
set "AVX2=-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON"
set "CLANG=-DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl %STATIC%"
if /i "%T%"=="windows-x64-cpu-avx2" set "FLAGS=%CLANG% %AVX2%"
if /i "%T%"=="windows-x64-cpu-sse42" set "FLAGS=%CLANG% %SSE42%"
if /i "%T%"=="windows-x64-vulkan" goto :bo_vulkan
if /i "%T%"=="windows-x64-cuda12" (set "CV=%CUDA12%" & set "CA=%ARCHS12%" & goto :bo_cuda)
if /i "%T%"=="windows-x64-cuda13" (set "CV=%CUDA13%" & set "CA=%ARCHS13%" & goto :bo_cuda)
goto :bo_cmake
:bo_vulkan
call :ensure_sdk || exit /b 1
set "FLAGS=%CLANG% %SSE42% -DGGML_VULKAN=ON"
goto :bo_cmake
:bo_cuda
call :ensure_cuda %CV% || exit /b 1
set "CUDADIR=%TOOLS%\cuda-%CV%"
set "CUDAF=%CUDADIR:\=/%"
set "NVF="
if "%NVCC_ALLOW_UNSUPPORTED%"=="1" set "NVF=-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
set "FLAGS=-DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl %SSE42% -DGGML_CUDA=ON -DGGML_CUDA_NCCL=OFF "-DCMAKE_CUDA_COMPILER=%CUDAF%/bin/nvcc.exe" "-DCUDAToolkit_ROOT=%CUDAF%" "-DCMAKE_CUDA_ARCHITECTURES=%CA%" %NVF%"
set "PATH=%CUDADIR%\bin;%PATH%"
:bo_cmake
cmake -S "%SRC%" -B "%B%" %COMMON% %FLAGS%
if errorlevel 1 goto :bo_fail
cmake --build "%B%" --target zonos2-server -j %JOBS%
if errorlevel 1 goto :bo_fail
if exist "%D%" rmdir /s /q "%D%"
mkdir "%D%"
copy /y "%B%\zonos2-server.exe" "%D%\" >nul || exit /b 1
if defined CV call :bundle_cuda || exit /b 1
call :pack || exit /b 1
if "%CLEAN%"=="1" rmdir /s /q "%B%"
exit /b 0
:bo_fail
echo [zonos2] ERROR: %T% failed to build, see above
if defined CV echo [zonos2]   if nvcc rejects this Visual Studio version: set NVCC_ALLOW_UNSUPPORTED=1, or use the Visual Studio 2022 release CUDA %CV% supports
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
echo [zonos2] ERROR: no cublasLt64 DLL under %CUDADIR%\bin
exit /b 1
:bc_nocrt
echo [zonos2] ERROR: no VC++ runtime under %VCToolsRedistDir%x64
exit /b 1
:pack
xcopy /e /i /q /y "%SRC%\emotion_directions" "%D%\emotion_directions" >nul || exit /b 1
xcopy /e /i /q /y "%SRC%\web" "%D%\web" >nul || exit /b 1
copy /y "%SRC%\ggml\LICENSE" "%D%\LICENSE-ggml" >nul || exit /b 1
> "%D%\NOTICE" echo zonos2.cpp %TAG% (Zyphra), redistributed with authorization
>> "%D%\NOTICE" echo cpp-httplib: Copyright (c) 2024 Yuji Hirose, MIT License
>> "%D%\NOTICE" echo nlohmann/json 3.11.3: Copyright (c) 2013-2023 Niels Lohmann, MIT License
>> "%D%\NOTICE" echo ggml: MIT License, see LICENSE-ggml
if defined CV echo cudart64, cublas64, cublasLt64: NVIDIA CUDA runtime and cuBLAS %CV%, redistributed under the NVIDIA CUDA Toolkit EULA>> "%D%\NOTICE"
if defined CV echo msvcp140, vcruntime140, concrt140: Microsoft Visual C++ runtime, redistributed under the Visual Studio license terms>> "%D%\NOTICE"
if exist "%D%.zip" del /q "%D%.zip"
powershell -NoProfile -c "Compress-Archive -LiteralPath '%D%' -DestinationPath '%D%.zip' -CompressionLevel Optimal" || exit /b 1
echo --- %T% DLLs the exe loads:
dumpbin /nologo /dependents "%D%\zonos2-server.exe" | findstr /i /r "\.dll"
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
echo [zonos2] ERROR: no LunarG Vulkan SDK - install it, or drop --no-install
exit /b 1
:find_sdk
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "%LOCALAPPDATA%\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%%d"
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "C:\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=C:\VulkanSDK\%%d"
exit /b 0
:install_sdk
set "VKVER="
for /f "usebackq delims=" %%v in (`curl.exe -fsSL https://vulkan.lunarg.com/sdk/latest/windows.txt`) do set "VKVER=%%v"
if not defined VKVER (echo [zonos2] ERROR: cannot reach vulkan.lunarg.com & exit /b 1)
set "VKEXE=%TEMP%\vulkan_sdk_%VKVER%.exe"
echo [zonos2] installing the LunarG Vulkan SDK %VKVER% into %LOCALAPPDATA%\VulkanSDK\%VKVER%
curl.exe -fL -o "%VKEXE%" https://sdk.lunarg.com/sdk/download/%VKVER%/windows/vulkan_sdk.exe || exit /b 1
call :check_sha "%VKEXE%" https://sdk.lunarg.com/sdk/sha/%VKVER%/windows/vulkan_sdk.exe.txt || exit /b 1
"%VKEXE%" --root "%LOCALAPPDATA%\VulkanSDK\%VKVER%" --accept-licenses --default-answer --confirm-command install copy_only=1 || exit /b 1
del /q "%VKEXE%" 2>nul
set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%VKVER%"
if not exist "%VULKAN_SDK%\Bin\glslc.exe" (echo [zonos2] ERROR: the SDK install did not produce Bin\glslc.exe & exit /b 1)
exit /b 0
:check_sha
set "SHAEXP="
for /f "usebackq tokens=1" %%s in (`curl.exe -fsSL %~2 2^>nul`) do if not defined SHAEXP set "SHAEXP=%%s"
if not defined SHAEXP goto :cs_none
set "SHAGOT="
for /f "usebackq delims=" %%h in (`powershell -NoProfile -c "(Get-FileHash -Algorithm SHA256 -LiteralPath '%~1').Hash"`) do set "SHAGOT=%%h"
if /i "%SHAEXP%"=="%SHAGOT%" exit /b 0
echo [zonos2] ERROR: checksum mismatch for %~nx1
exit /b 1
:cs_none
echo [zonos2] WARNING: no published checksum for %~nx1, skipping verification
exit /b 0
:ensure_cuda
rem CUDA %1 from NVIDIA's redistributable archives - redistrib_%1.json lists each component's zip and sha256: the
rem compiler (nvcc, plus crt and nvvm, separate since CUDA 13), the runtime, the CCCL headers and cuBLAS, merged into
rem one toolkit folder. No installer, no driver, no admin rights, several CUDA releases side by side
set "CUDADIR=%TOOLS%\cuda-%~1"
if exist "%CUDADIR%\bin\nvcc.exe" exit /b 0
if not "%INSTALL%"=="1" goto :ec_none
echo [zonos2] downloading the CUDA %~1 compiler, runtime and cuBLAS into %CUDADIR%, about 3 GB
powershell -NoProfile -ExecutionPolicy Bypass -c "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$v='%~1';$d='%CUDADIR%';$b='https://developer.download.nvidia.com/compute/cuda/redist/';$j=Invoke-RestMethod ($b+'redistrib_'+$v+'.json');New-Item -ItemType Directory -Force $d | Out-Null;foreach($c in @('cuda_nvcc','cuda_crt','libnvvm','cuda_cudart','cuda_cccl','libcublas')){$e=$j.$c.'windows-x86_64';if(-not $e){continue};$z=Join-Path $env:TEMP ([IO.Path]::GetFileName($e.relative_path));Write-Host ('[zonos2]   '+$c+' '+$j.$c.version);Invoke-WebRequest -UseBasicParsing ($b+$e.relative_path) -OutFile $z;if((Get-FileHash -Algorithm SHA256 $z).Hash -ne $e.sha256.ToUpper()){throw ('checksum mismatch: '+$c)};$t=Join-Path $env:TEMP ('zcuda'+[guid]::NewGuid().ToString('N'));Expand-Archive -LiteralPath $z -DestinationPath $t -Force;$r=(Get-ChildItem $t | Select-Object -First 1).FullName;robocopy $r $d /E /NFL /NDL /NJH /NJS /NP | Out-Null;if($LASTEXITCODE -ge 8){throw ('copy failed: '+$c)};Remove-Item $t -Recurse -Force;Remove-Item $z};exit 0" || exit /b 1
if not exist "%CUDADIR%\bin\nvcc.exe" goto :ec_nonvcc
exit /b 0
:ec_none
echo [zonos2] ERROR: no CUDA %~1 in %CUDADIR% - drop --no-install to download it
exit /b 1
:ec_nonvcc
echo [zonos2] ERROR: CUDA %~1 has no bin\nvcc.exe after the download - check that release on developer.download.nvidia.com/compute/cuda/redist
exit /b 1
:llvm_path
rem vcvarsall does not put Visual Studio's clang-cl on PATH
where clang-cl >nul 2>&1 && exit /b 0
if defined VCINSTALLDIR if exist "%VCINSTALLDIR%Tools\Llvm\x64\bin\clang-cl.exe" set "PATH=%VCINSTALLDIR%Tools\Llvm\x64\bin;%PATH%"
exit /b 0
:vs_env
rem already in a Visual Studio x64 environment: keep it
if /i not "%VSCMD_ARG_TGT_ARCH%"=="x64" goto :vs_find
where cl >nul 2>&1 && exit /b 0
:vs_find
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 0
rem run vswhere outside any ( ) block: its path holds "(x86)", whose ")" would end a for /f clause early
set "VSPATH="
set "VSOUT=%TEMP%\zonos2_vspath_%RANDOM%.txt"
"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%VSOUT%" 2>nul
set /p VSPATH=<"%VSOUT%"
del /q "%VSOUT%" 2>nul
if not defined VSPATH exit /b 0
if not exist "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" exit /b 0
echo [zonos2] loading the Visual Studio C++ environment from %VSPATH%
call "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
exit /b 0
:install_bt
where cl >nul 2>&1 && where clang-cl >nul 2>&1 && exit /b 0
echo [zonos2] installing Visual Studio 2022 Build Tools with C++ and clang-cl - several GB, a UAC prompt may appear
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset --includeRecommended"
call :vs_env
call :llvm_path
where cl >nul 2>&1 && where clang-cl >nul 2>&1 && exit /b 0
echo [zonos2] ERROR: the C++ build tools or clang-cl are still not usable - finish the Visual Studio install, then run this again
exit /b 1
