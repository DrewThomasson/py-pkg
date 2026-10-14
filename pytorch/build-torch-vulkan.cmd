@echo off
rem build-torch-vulkan.cmd - torch/torchaudio/torchcodec wheels with the PyTorch Vulkan backend for Windows x64 / arm64.
rem Runs from any command prompt: it loads the Visual Studio C++ environment for this machine itself (vswhere + vcvarsall).
rem Linux and macOS: build-torch-vulkan.sh. build-torch-vulkan.cmd --help for the options, --list for this machine.
setlocal EnableExtensions DisableDelayedExpansion
if not defined ROOT set "ROOT=%CD%\pytorch-vulkan"
if not defined TORCH set "TORCH=2.11.0"
if not defined AUDIO set "AUDIO=2.11.0"
if not defined CODEC set "CODEC=0.11.1"
if not defined SUFFIX set "SUFFIX=vulkan"
if not defined PYS set "PYS=3.12"
if not defined PKGS set "PKGS=torch torchaudio torchcodec"
if not defined JOBS set "JOBS=%NUMBER_OF_PROCESSORS%"
if not defined CLEAN set "CLEAN=0"
if not defined NO_BUNDLE set "NO_BUNDLE=0"
if not defined CODEC_FFMPEG set "CODEC_FFMPEG=auto"
if not defined INSTALL_VK set "INSTALL_VK=auto"
if not defined INSTALL_SDK set "INSTALL_SDK=1"
if not defined INSTALL_BT set "INSTALL_BT=0"
set "GPU_OK=unknown"
set "LIST=0"
:args
if "%~1"=="" goto :args_done
if /i "%~1"=="-l" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--list" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--clean" (set "CLEAN=1" & shift & goto :args)
if /i "%~1"=="--no-bundle" (set "NO_BUNDLE=1" & shift & goto :args)
if /i "%~1"=="--install-vulkan" (set "INSTALL_VK=1" & shift & goto :args)
if /i "%~1"=="--no-install-vulkan" (set "INSTALL_VK=0" & shift & goto :args)
if /i "%~1"=="--no-install-sdk" (set "INSTALL_SDK=0" & shift & goto :args)
if /i "%~1"=="--install-buildtools" (set "INSTALL_BT=1" & shift & goto :args)
if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?" goto :usage
if /i "%~1"=="--pkgs" (set "OPT=PKGS" & goto :value)
if /i "%~1"=="--torch" (set "OPT=TORCH" & goto :value)
if /i "%~1"=="--torchaudio" (set "OPT=AUDIO" & goto :value)
if /i "%~1"=="--torchcodec" (set "OPT=CODEC" & goto :value)
if /i "%~1"=="--py" (set "OPT=PYS" & goto :value)
if /i "%~1"=="--suffix" (set "OPT=SUFFIX" & goto :value)
if /i "%~1"=="--root" (set "OPT=ROOT" & goto :value)
if /i "%~1"=="--jobs" (set "OPT=JOBS" & goto :value)
if /i "%~1"=="--codec-ffmpeg" (set "OPT=CODEC_FFMPEG" & goto :value)
echo unknown option: %~1 - see --help
exit /b 1
:value
if "%~2"=="" (echo %~1 needs a value - see --help & exit /b 1)
set "%OPT%=%~2"
shift
shift
goto :args
:args_done
if /i not "%CODEC_FFMPEG%"=="auto" if /i not "%CODEC_FFMPEG%"=="s3" if /i not "%CODEC_FFMPEG%"=="local" (echo --codec-ffmpeg must be auto, s3 or local & exit /b 1)
for %%p in (%PKGS%) do if /i not "%%p"=="torch" if /i not "%%p"=="torchaudio" if /i not "%%p"=="torchcodec" (echo unknown package %%p - torch, torchaudio, torchcodec & exit /b 1)
set "HA=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HA=%PROCESSOR_ARCHITEW6432%"
set "HOSTA="
if /i "%HA%"=="AMD64" set "HOSTA=x64"
if /i "%HA%"=="ARM64" set "HOSTA=arm64"
if not defined HOSTA (echo unsupported machine %HA% & exit /b 1)
set "TARGET=windows-%HOSTA%-vulkan"
call :vs_env
call :find_sdk
call :missing
call :codec_mode
if not "%LIST%"=="1" goto :build
echo targets on this Windows-%HOSTA% machine:
if defined MISS (echo   %TARGET%   missing:%MISS:~0,-1% - see --help & exit /b 0)
set "NOTE="
call :want torchcodec && if "%CMODE%"=="skip" set "NOTE= - torchcodec skipped: no local FFmpeg"
if "%INSTALL_SDK%"=="1" if not exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" set "NOTE=%NOTE% - installs the Vulkan SDK first"
echo   %TARGET%   ready%NOTE%
call :install_on || exit /b 0
call :gpu_check
echo GPU: %GPU_NAME% - %GPU_NOTE%
exit /b 0
:build
if defined MISS (echo [vk-build] ERROR: %TARGET%: missing:%MISS:~0,-1% - see --help & exit /b 1)
if not exist "%ROOT%" mkdir "%ROOT%"
for %%r in ("%ROOT%") do set "ROOT=%%~fr"
if "%INSTALL_BT%"=="1" call :install_bt || exit /b 1
call :install_on || goto :sdk_only
call :vk_job || exit /b 1
goto :after_vk
:sdk_only
call :sdk_job || exit /b 1
:after_vk
call :find_loader
if "%NO_BUNDLE%"=="1" goto :loader_ok
if "%LOADER%"=="no" (echo [vk-build] ERROR: no vulkan-1.dll to bundle - install the Vulkan runtime, use --install-vulkan or --no-bundle & exit /b 1)
:loader_ok
where uv >nul 2>&1 && goto :have_uv
echo [vk-build] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [vk-build] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
set "SRC=%ROOT%\src-%TARGET%"
set "DIST=%ROOT%\dist\%TARGET%"
if not exist "%SRC%" mkdir "%SRC%"
if not exist "%DIST%" mkdir "%DIST%"
set "MAX_JOBS=%JOBS%"
set "CMAKE_BUILD_PARALLEL_LEVEL=%JOBS%"
set "CMAKE_GENERATOR=Ninja"
set "DISTUTILS_USE_SDK=1"
set "USE_CUDA=0"
set "USE_ROCM=0"
set "USE_XPU=0"
set "USE_MPS=0"
set "USE_CUDNN=0"
set "USE_NCCL=0"
set "ENABLE_CUDA=0"
set "PATH=%VULKAN_SDK%\Bin;%PATH%"
set "BASEPATH=%PATH%"
set "CLEANNOW=%CLEAN%"
set "BUILT="
echo [vk-build] %TARGET%: torch %TORCH%, torchaudio %AUDIO%, torchcodec %CODEC% +%SUFFIX%, python %PYS%, %JOBS% jobs, packages: %PKGS%
echo [vk-build] Vulkan SDK %VULKAN_SDK%, torchcodec FFmpeg: %CMODE%, bundled loader: %LOADER%
for %%v in (%PYS%) do (call :build_py %%v || exit /b 1)
echo [vk-build] built wheels:
for %%w in (%BUILT%) do echo [vk-build]   %%w
exit /b 0
rem ---------------------------------------------------------------- subroutines
:usage
echo Usage: build-torch-vulkan.cmd [options]
echo Builds torch, torchaudio and torchcodec wheels with the PyTorch Vulkan backend for this Windows machine
echo - windows-x64-vulkan or windows-arm64-vulkan. The torch wheel carries vulkan-1.dll, so it imports on machines
echo without a Vulkan runtime - Vulkan is then simply unavailable. Linux and macOS: build-torch-vulkan.sh.
echo Options                                                                                [env]
echo   -l, --list              what this machine can build now
echo   --pkgs "torch ..."      packages to build                                            [PKGS]    default: %PKGS%
echo   --torch VER             default: %TORCH%                                               [TORCH]
echo   --torchaudio VER        default: %AUDIO%                                               [AUDIO]
echo   --torchcodec VER        default: %CODEC%                                               [CODEC]
echo   --py "3.10 3.12"        Python versions from uv, one full torch build each            [PYS]     default: %PYS%
echo   --suffix TAG            local version tag, e.g. %TORCH%+%SUFFIX%                         [SUFFIX]  default: %SUFFIX%
echo   --root DIR              sources, venvs and wheels                                     [ROOT]    default: .\pytorch-vulkan
echo   --jobs N                parallel compile jobs, ~2 GB RAM each                         [JOBS]    default: %JOBS%
echo   --clean                 git clean the checkouts first - do it when changing versions  [CLEAN=1]
echo   --codec-ffmpeg MODE     torchcodec FFmpeg: auto, s3 - PyTorch's LGPL builds, x64 only, [CODEC_FFMPEG] default: auto
echo                           local - pkg-config, redistributable only if that FFmpeg is LGPL
echo                           auto = s3 on x64, local on arm64 if pkg-config finds it, else torchcodec is skipped
echo   --no-bundle             do not put vulkan-1.dll into the torch wheel                  [NO_BUNDLE=1]
echo   --install-vulkan        run the Vulkan install job on any host                        [INSTALL_VK=1]
echo   --no-install-vulkan     never run it                                                  [INSTALL_VK=0]  default: arm64 hosts
echo   --no-install-sdk        do not install the LunarG Vulkan SDK when it is missing        [INSTALL_SDK=0] default: installs it
echo   --install-buildtools    install Visual Studio 2022 Build Tools with C++ through winget [INSTALL_BT=1]  several GB, UAC
echo                           checks the GPU for a Vulkan driver, installs the LunarG SDK for this architecture into
echo                           %%LOCALAPPDATA%%\VulkanSDK when none is found - checksum-verified, copy-only, may show a UAC
echo                           prompt - and fetches LunarG's vulkan-1.dll for bundling when the system has none;
echo                           without a Vulkan driver the wheels still build and the op probe is skipped
echo   -h, --help
echo Output
echo   ROOT\dist\TARGET\PKG-VER+SUFFIX-cpXY-cpXY-win_amd64.whl or win_arm64.whl, sources in ROOT\src-TARGET
echo   Each build ends with a probe of the Vulkan ops TTS models use.
echo Needs
echo   Visual Studio 2022 or its Build Tools with the C++ workload for this machine - found with vswhere, no special
echo   prompt needed, or --install-buildtools; git; network access. The LunarG Vulkan SDK and uv are installed if missing
echo   windows-arm64-vulkan torchcodec: a shared LGPL FFmpeg with its .pc files on PKG_CONFIG_PATH, and pkg-config
echo   Vulkan on Windows arm64: Snapdragon X has a native Qualcomm driver; older Snapdragons need Microsoft's
echo   OpenCL, OpenGL, and Vulkan Compatibility Pack from the Microsoft Store
echo Examples
echo   build-torch-vulkan.cmd --list
echo   build-torch-vulkan.cmd
echo   build-torch-vulkan.cmd --py "3.10 3.12" --jobs 8
echo   build-torch-vulkan.cmd --pkgs "torchaudio torchcodec"
exit /b 0
:want
echo %PKGS% | findstr /i /r /c:"\<%~1\>" >nul
exit /b %ERRORLEVEL%
:local_ffmpeg
where pkg-config >nul 2>&1 || exit /b 1
pkg-config --exists libavutil libavcodec libavformat libavfilter libswscale libswresample || exit /b 1
exit /b 0
:codec_mode
if /i not "%CODEC_FFMPEG%"=="auto" (set "CMODE=%CODEC_FFMPEG%" & exit /b 0)
if "%HOSTA%"=="x64" (set "CMODE=s3" & exit /b 0)
set "CMODE=skip"
call :local_ffmpeg && set "CMODE=local"
exit /b 0
:missing
set "MISS="
if "%INSTALL_BT%"=="1" goto :miss_vs_done
where cl >nul 2>&1 || set "MISS=%MISS% Visual Studio 2022 C++ build tools for %HOSTA% - add --install-buildtools,"
if defined VSCMD_ARG_TGT_ARCH if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" set "MISS=%MISS% a %HOSTA% Visual Studio environment - this one targets %VSCMD_ARG_TGT_ARCH%,"
:miss_vs_done
where git >nul 2>&1 || set "MISS=%MISS% git,"
if not defined VULKAN_SDK goto :miss_nosdk
if not exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" goto :miss_nosdk
if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "MISS=%MISS% glslc.exe in %VULKAN_SDK%\Bin,"
if not exist "%VULKAN_SDK%\Lib\vulkan-1.lib" set "MISS=%MISS% vulkan-1.lib in %VULKAN_SDK%\Lib,"
goto :miss_loader
:miss_nosdk
if not "%INSTALL_SDK%"=="1" set "MISS=%MISS% the LunarG Vulkan SDK - VULKAN_SDK is not set, drop --no-install-sdk to install it,"
:miss_loader
if "%NO_BUNDLE%"=="1" goto :miss_codec
call :find_loader
if "%INSTALL_SDK%"=="1" goto :miss_codec
if "%LOADER%"=="no" set "MISS=%MISS% vulkan-1.dll to bundle - install the Vulkan runtime or use --no-bundle,"
:miss_codec
call :want torchcodec || exit /b 0
if /i "%CODEC_FFMPEG%"=="s3" if "%HOSTA%"=="arm64" set "MISS=%MISS% S3 FFmpeg for arm64 - PyTorch has none, use --codec-ffmpeg local,"
if /i not "%CODEC_FFMPEG%"=="local" exit /b 0
call :local_ffmpeg || set "MISS=%MISS% pkg-config + a shared FFmpeg on PKG_CONFIG_PATH,"
exit /b 0
:build_py
set "V=%~1"
set "TAG=cp%V:.=%"
set "VENV=%ROOT%\venv-%TARGET%-%V%"
echo [vk-build] --- python %V%
if exist "%VENV%" rmdir /s /q "%VENV%"
uv venv -q --seed --python %V% "%VENV%" || exit /b 1
set "PY=%VENV%\Scripts\python.exe"
set "PATH=%VENV%\Scripts;%BASEPATH%"
"%PY%" -m pip install -q cmake ninja setuptools wheel || exit /b 1
call :want torch && (call :sync_repo torch https://github.com/pytorch/pytorch.git %TORCH% || exit /b 1)
call :want torchaudio && (call :sync_repo torchaudio https://github.com/pytorch/audio.git %AUDIO% || exit /b 1)
call :want torchcodec && (call :sync_repo torchcodec https://github.com/pytorch/torchcodec.git %CODEC% || exit /b 1)
call :want torch && goto :bp_torch
call :install_existing_torch || exit /b 1
goto :bp_rest
:bp_torch
call :build_torch || exit /b 1
:bp_rest
call :want torchaudio && (call :build_torchaudio || exit /b 1)
call :want torchcodec && (call :build_torchcodec || exit /b 1)
if "%GPU_OK%"=="0" (echo [vk-build] op probe skipped: no Vulkan driver on this machine) else call :probe
set "CLEANNOW=1"
exit /b 0
:install_on
if "%INSTALL_VK%"=="1" exit /b 0
if "%INSTALL_VK%"=="0" exit /b 1
if "%HOSTA%"=="arm64" exit /b 0
exit /b 1
:find_sdk
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "%LOCALAPPDATA%\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%%d"
if defined VULKAN_SDK exit /b 0
for /f "delims=" %%d in ('dir /b /ad /o-n "C:\VulkanSDK" 2^>nul') do if not defined VULKAN_SDK set "VULKAN_SDK=C:\VulkanSDK\%%d"
exit /b 0
:find_loader
set "LOADER=no"
if defined VULKAN_SDK if exist "%VULKAN_SDK%\Bin\vulkan-1.dll" set "LOADER=%VULKAN_SDK%\Bin\vulkan-1.dll"
if "%LOADER%"=="no" if exist "%ROOT%\tools\vulkanrt-%HOSTA%\vulkan-1.dll" set "LOADER=%ROOT%\tools\vulkanrt-%HOSTA%\vulkan-1.dll"
if "%LOADER%"=="no" if exist "%SystemRoot%\System32\vulkan-1.dll" set "LOADER=%SystemRoot%\System32\vulkan-1.dll"
exit /b 0
:gpu_check
rem a Vulkan driver registers VulkanDriverName on its display adapter key, or an ICD under Khronos\Vulkan\Drivers
set "GPU_OK=0"
set "GPU_NAME=unknown GPU"
set "PS1=%TEMP%\vk_gpu_%RANDOM%.ps1"
> "%PS1%" echo($c='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
>>"%PS1%" echo($a=@(Get-ChildItem $c -ErrorAction SilentlyContinue ^| ForEach-Object {Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue} ^| Where-Object {$_.VulkanDriverName -or $_.VulkanDriverNameWow})
>>"%PS1%" echo($k=Get-ItemProperty 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers' -ErrorAction SilentlyContinue
>>"%PS1%" echo($n=(Get-CimInstance Win32_VideoController ^| Select-Object -First 1).Name
>>"%PS1%" echo(if($a.Count -gt 0 -or $k){$ok=1}else{$ok=0}
>>"%PS1%" echo(Write-Output "$ok;$n"
for /f "usebackq tokens=1* delims=;" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"`) do (set "GPU_OK=%%a" & set "GPU_NAME=%%b")
del /q "%PS1%" 2>nul
if not defined VULKAN_SDK goto :gc_note
if not exist "%VULKAN_SDK%\Bin\vulkaninfoSDK.exe" goto :gc_note
"%VULKAN_SDK%\Bin\vulkaninfoSDK.exe" --summary 2>nul | findstr /i "deviceName" | findstr /v /i "llvmpipe" >nul && set "GPU_OK=1"
:gc_note
set "GPU_NOTE=Vulkan driver installed"
if "%GPU_OK%"=="0" set "GPU_NOTE=no Vulkan driver - Snapdragon X: update the Qualcomm graphics driver; older Snapdragon: Microsoft's OpenCL, OpenGL, and Vulkan Compatibility Pack from the Store; other GPUs: the vendor driver"
exit /b 0
:vk_job
call :gpu_check
echo [vk-build] GPU: %GPU_NAME% - %GPU_NOTE%
if defined VULKAN_SDK if exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" goto :vj_sdk
call :sdk_job || exit /b 1
call :gpu_check
exit /b 0
:vj_sdk
call :sdk_job || exit /b 1
exit /b 0
:sdk_job
if defined VULKAN_SDK if exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" goto :sj_loader
if not "%INSTALL_SDK%"=="1" (echo [vk-build] ERROR: no Vulkan SDK - see --help & exit /b 1)
call :install_sdk || exit /b 1
:sj_loader
if "%NO_BUNDLE%"=="1" exit /b 0
call :find_loader
if not "%LOADER%"=="no" exit /b 0
call :get_vulkanrt || exit /b 1
exit /b 0
:vs_env
rem already in a Visual Studio environment for this architecture: keep it
if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" goto :vs_find
where cl >nul 2>&1 && exit /b 0
:vs_find
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" exit /b 0
set "VSCOMP=Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
if "%HOSTA%"=="arm64" set "VSCOMP=Microsoft.VisualStudio.Component.VC.Tools.ARM64"
set "VSPATH="
for /f "usebackq delims=" %%i in (`""%VSWHERE%" -latest -products * -requires %VSCOMP% -property installationPath"`) do set "VSPATH=%%i"
if not defined VSPATH exit /b 0
if not exist "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" exit /b 0
echo [vk-build] loading the Visual Studio C++ environment for %HOSTA% from %VSPATH%
call "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" %HOSTA% >nul
exit /b 0
:install_bt
where cl >nul 2>&1 && exit /b 0
set "VSCOMP=Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
if "%HOSTA%"=="arm64" set "VSCOMP=Microsoft.VisualStudio.Component.VC.Tools.ARM64"
echo [vk-build] installing Visual Studio 2022 Build Tools with the C++ workload - several GB, a UAC prompt may appear
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --silent --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add %VSCOMP% --includeRecommended"
call :vs_env
where cl >nul 2>&1 && exit /b 0
echo [vk-build] ERROR: the C++ build tools are still not usable - finish the Visual Studio install, then run this again
exit /b 1
:vk_version
set "VKPLAT=windows"
set "RTARCH=X64"
if "%HOSTA%"=="arm64" (set "VKPLAT=warm" & set "RTARCH=ARM64")
if defined VKVER exit /b 0
for /f "usebackq delims=" %%v in (`curl.exe -fsSL https://vulkan.lunarg.com/sdk/latest/%VKPLAT%.txt`) do set "VKVER=%%v"
if not defined VKVER (echo [vk-build] ERROR: cannot reach vulkan.lunarg.com & exit /b 1)
exit /b 0
:check_sha
set "SHAEXP="
for /f "usebackq tokens=1" %%s in (`curl.exe -fsSL %~2 2^>nul`) do if not defined SHAEXP set "SHAEXP=%%s"
if not defined SHAEXP goto :cs_none
if "%SHAEXP:~63,1%"=="" goto :cs_none
if not "%SHAEXP:~64,1%"=="" goto :cs_none
set "SHAGOT="
for /f "usebackq delims=" %%h in (`powershell -NoProfile -c "(Get-FileHash -Algorithm SHA256 -LiteralPath '%~1').Hash"`) do set "SHAGOT=%%h"
if /i "%SHAEXP%"=="%SHAGOT%" exit /b 0
echo [vk-build] ERROR: checksum mismatch for %~nx1
exit /b 1
:cs_none
echo [vk-build] WARNING: no published checksum for %~nx1, skipping verification
exit /b 0
:install_sdk
call :vk_version || exit /b 1
set "VKEXE=%TEMP%\vulkan_sdk_%VKPLAT%_%VKVER%.exe"
echo [vk-build] installing the LunarG Vulkan SDK %VKVER% for %VKPLAT% into %LOCALAPPDATA%\VulkanSDK\%VKVER%
curl.exe -fL -o "%VKEXE%" https://sdk.lunarg.com/sdk/download/%VKVER%/%VKPLAT%/vulkan_sdk.exe || exit /b 1
call :check_sha "%VKEXE%" https://sdk.lunarg.com/sdk/sha/%VKVER%/%VKPLAT%/vulkan_sdk.exe.txt || exit /b 1
"%VKEXE%" --root "%LOCALAPPDATA%\VulkanSDK\%VKVER%" --accept-licenses --default-answer --confirm-command install copy_only=1 || exit /b 1
del /q "%VKEXE%" 2>nul
set "VULKAN_SDK=%LOCALAPPDATA%\VulkanSDK\%VKVER%"
if not exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" (echo [vk-build] ERROR: the SDK install did not produce Include\vulkan\vulkan.h & exit /b 1)
exit /b 0
:get_vulkanrt
call :vk_version || exit /b 1
set "RTZIP=%TEMP%\VulkanRT-%RTARCH%-%VKVER%-Components.zip"
set "RTDIR=%TEMP%\vulkanrt-%RANDOM%"
echo [vk-build] fetching LunarG's Vulkan runtime %VKVER% for %RTARCH% to bundle vulkan-1.dll
curl.exe -fL -o "%RTZIP%" https://sdk.lunarg.com/sdk/download/%VKVER%/%VKPLAT%/VulkanRT-%RTARCH%-%VKVER%-Components.zip || exit /b 1
powershell -NoProfile -c "Expand-Archive -Force -LiteralPath '%RTZIP%' -DestinationPath '%RTDIR%'" || exit /b 1
set "RTDLL="
for /f "delims=" %%f in ('dir /s /b "%RTDIR%\vulkan-1.dll" 2^>nul') do if not defined RTDLL set "RTDLL=%%f"
for /f "delims=" %%f in ('dir /s /b "%RTDIR%\vulkan-1.dll" 2^>nul ^| findstr /i /c:"%RTARCH%"') do set "RTDLL=%%f"
if not defined RTDLL (echo [vk-build] ERROR: no vulkan-1.dll inside the runtime package & exit /b 1)
if not exist "%ROOT%\tools\vulkanrt-%HOSTA%" mkdir "%ROOT%\tools\vulkanrt-%HOSTA%"
copy /y "%RTDLL%" "%ROOT%\tools\vulkanrt-%HOSTA%\vulkan-1.dll" >nul || exit /b 1
rmdir /s /q "%RTDIR%"
del /q "%RTZIP%" 2>nul
exit /b 0
:sync_repo
set "RP=%SRC%\%~1"
if exist "%RP%\.git" goto :sr_have
git clone -c core.longpaths=true --recursive %~2 "%RP%" || exit /b 1
:sr_have
git -C "%RP%" -c core.longpaths=true fetch -q --tags --force origin || exit /b 1
git -C "%RP%" -c advice.detachedHead=false checkout -q v%~3 || exit /b 1
git -C "%RP%" -c core.longpaths=true submodule sync -q --recursive || exit /b 1
git -C "%RP%" -c core.longpaths=true submodule update -q --init --recursive || exit /b 1
if not "%CLEANNOW%"=="1" exit /b 0
git -C "%RP%" clean -q -xdf
git -C "%RP%" submodule foreach -q --recursive git clean -q -xdf
exit /b 0
:pip_wheel
del /q "%DIST%\%~1-*-%TAG%-*.whl" 2>nul
pushd "%SRC%\%~1"
"%PY%" -m pip wheel . --no-build-isolation --no-deps -v -w "%DIST%"
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b 1
set "WHL="
for %%f in ("%DIST%\%~1-*-%TAG%-*.whl") do set "WHL=%%~ff"
if not defined WHL (echo [vk-build] ERROR: no %~1 wheel was produced & exit /b 1)
echo %WHL% | findstr /c:"+%SUFFIX%-" >nul || echo [vk-build] WARNING: %~1 wheel does not carry +%SUFFIX% - the repo ignored the version variable
exit /b 0
:install_whl
"%PY%" -m pip install -q --force-reinstall --no-deps "%WHL%" || exit /b 1
exit /b 0
:install_existing_torch
set "WHL="
for %%f in ("%DIST%\torch-%TORCH%+%SUFFIX%-%TAG%-*.whl") do set "WHL=%%~ff"
if not defined WHL (echo [vk-build] ERROR: torch is not in --pkgs and no torch-%TORCH%+%SUFFIX% %TAG% wheel was built before & exit /b 1)
"%PY%" -m pip install -q "%WHL%" || exit /b 1
exit /b 0
:build_torch
if not exist "%SRC%\torch\aten\src\ATen\native\vulkan" (echo [vk-build] ERROR: torch %TORCH% has no aten\src\ATen\native\vulkan - pick an older --torch & exit /b 1)
if not exist "%SRC%\torch\requirements-build.txt" goto :bt_req
"%PY%" -m pip install -q -r "%SRC%\torch\requirements-build.txt" || exit /b 1
:bt_req
if not exist "%SRC%\torch\requirements.txt" goto :bt_env
"%PY%" -m pip install -q -r "%SRC%\torch\requirements.txt" || exit /b 1
:bt_env
setlocal
rem USE_VULKAN_WRAPPER is Android-only in torch: desktop builds always link the Vulkan loader, hence the bundling
set "USE_VULKAN=1"
set "USE_VULKAN_WRAPPER=0"
set "USE_VULKAN_SHADERC_RUNTIME=0"
set "USE_VULKAN_FP16_INFERENCE=0"
set "USE_VULKAN_RELAXED_PRECISION=0"
set "BUILD_TEST=0"
set "PYTORCH_BUILD_VERSION=%TORCH%+%SUFFIX%"
set "PYTORCH_BUILD_NUMBER=1"
call :pip_wheel torch || (endlocal & exit /b 1)
endlocal & set "WHL=%WHL%"
if "%NO_BUNDLE%"=="1" goto :bt_install
call :bundle || exit /b 1
:bt_install
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:bundle
set "TB=%DIST%\_bundle"
if exist "%TB%" rmdir /s /q "%TB%"
"%PY%" -m wheel unpack "%WHL%" -d "%TB%" >nul || exit /b 1
set "PKGDIR="
for /d %%d in ("%TB%\*") do set "PKGDIR=%%~fd"
copy /y "%LOADER%" "%PKGDIR%\torch\lib\vulkan-1.dll" >nul || exit /b 1
for %%f in ("%WHL%") do set "WHLNAME=%%~nxf"
del /q "%WHL%"
"%PY%" -m wheel pack "%PKGDIR%" -d "%DIST%" >nul || exit /b 1
rmdir /s /q "%TB%"
if not exist "%DIST%\%WHLNAME%" (echo [vk-build] ERROR: repacking %WHLNAME% failed & exit /b 1)
echo [vk-build] bundled vulkan-1.dll into %WHLNAME%
exit /b 0
:build_torchaudio
setlocal
set "USE_FFMPEG=0"
set "BUILD_SOX=0"
set "BUILD_VERSION=%AUDIO%+%SUFFIX%"
call :pip_wheel torchaudio || (endlocal & exit /b 1)
endlocal & set "WHL=%WHL%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:build_torchcodec
if "%CMODE%"=="skip" (echo [vk-build] skipping torchcodec: no prebuilt FFmpeg for %TARGET% and pkg-config finds no local one - see --help & exit /b 0)
"%PY%" -m pip install -q pybind11 || exit /b 1
setlocal
set "BUILD_VERSION=%CODEC%+%SUFFIX%"
if "%CMODE%"=="s3" set "BUILD_AGAINST_ALL_FFMPEG_FROM_S3=1"
if "%CMODE%"=="local" set "I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1"
if "%CMODE%"=="local" echo [vk-build] WARNING: torchcodec built against the local FFmpeg - only redistribute it if that FFmpeg is an LGPL build
call :pip_wheel torchcodec || (endlocal & exit /b 1)
endlocal & set "WHL=%WHL%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:probe
echo [vk-build] Vulkan op probe for python %V% - FAIL = op not implemented on the Vulkan backend:
set "PROBE=%TEMP%\vk_probe_%RANDOM%.py"
> "%PROBE%" echo(import torch,torch.nn.functional as F
>>"%PROBE%" echo(print('torch',torch.__version__,'vulkan_available',torch.is_vulkan_available())
>>"%PROBE%" echo(for mod in ['torchaudio','torchcodec']:
>>"%PROBE%" echo(    try:
>>"%PROBE%" echo(        m=__import__(mod)
>>"%PROBE%" echo(        print(mod,m.__version__)
>>"%PROBE%" echo(    except Exception as e:
>>"%PROBE%" echo(        print(mod,'not available:',str(e).splitlines()[0][:120])
>>"%PROBE%" echo(if torch.is_vulkan_available():
>>"%PROBE%" echo(    x=torch.randn(1,8,64)
>>"%PROBE%" echo(    tests=dict(
>>"%PROBE%" echo(        softmax=lambda:torch.softmax(x.vulkan(),-1).cpu(),
>>"%PROBE%" echo(        gelu=lambda:F.gelu(x.vulkan()).cpu(),
>>"%PROBE%" echo(        layer_norm=lambda:F.layer_norm(x.vulkan(),[64]).cpu(),
>>"%PROBE%" echo(        matmul=lambda:torch.matmul(torch.randn(64,64).vulkan(),torch.randn(64,64).vulkan()).cpu(),
>>"%PROBE%" echo(        conv1d=lambda:F.conv1d(x.vulkan(),torch.randn(8,8,3)).cpu(),
>>"%PROBE%" echo(        stft=lambda:torch.stft(torch.randn(16000).vulkan(),n_fft=1024,return_complex=True).cpu(),
>>"%PROBE%" echo(        multinomial=lambda:torch.multinomial(torch.rand(4,100).vulkan(),1).cpu(),
>>"%PROBE%" echo(    )
>>"%PROBE%" echo(    for name,fn in tests.items():
>>"%PROBE%" echo(        try:
>>"%PROBE%" echo(            fn()
>>"%PROBE%" echo(            print(f'  {name:12s} OK')
>>"%PROBE%" echo(        except Exception as e:
>>"%PROBE%" echo(            print(f'  {name:12s} FAIL',str(e).splitlines()[0][:120])
"%PY%" "%PROBE%"
del /q "%PROBE%" 2>nul
exit /b 0
