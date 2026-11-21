@echo off
rem build-torch-vulkan.cmd - torch/torchaudio/torchcodec wheels for Windows x64 / arm64: with the PyTorch Vulkan backend,
rem CPU only, or with CUDA (on arm64 NVIDIA's Windows arm64 CUDA, 13.4.1 and newer) - --backend picks them.
rem Runs from any command prompt: it loads the Visual Studio C++ environment for this machine itself (vswhere + vcvarsall).
rem Linux and macOS: build-torch-vulkan.sh. build-torch-vulkan.cmd --help for the options, --list for this machine.
setlocal EnableExtensions DisableDelayedExpansion
if not defined ROOT set "ROOT=%CD%\pytorch-vulkan"
if not defined AUDIO set "AUDIO=2.11.0"
if defined SUFFIX set "SUFFIX_USER=1"
if not defined BACKENDS set "BACKENDS=vulkan"
if not defined PYS set "PYS=3.12"
if not defined PKGS set "PKGS=torch torchaudio torchcodec"
if defined JOBS set "JOBS_USER=1"
if not defined JOBS set "JOBS=%NUMBER_OF_PROCESSORS%"
if not defined CLEAN set "CLEAN=0"
if not defined NO_BUNDLE set "NO_BUNDLE=0"
if not defined CODEC_FFMPEG set "CODEC_FFMPEG=auto"
if not defined INSTALL_VK set "INSTALL_VK=auto"
if not defined INSTALL_SDK set "INSTALL_SDK=1"
if not defined INSTALL_BT set "INSTALL_BT=0"
if not defined INSTALL_FFMPEG set "INSTALL_FFMPEG=1"
if not defined CUDA_VER set "CUDA_VER=13.4.3"
if not defined CUDNN_VER set "CUDNN_VER=9.28.1"
if not defined CUDA_ARCH set "CUDA_ARCH=auto"
if not defined APL_VER set "APL_VER=24.10"
if not defined FORCE set "FORCE=0"
set "GPU_OK=unknown"
set "LIST=0"
:args
if "%~1"=="" goto :args_done
if /i "%~1"=="-l" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--list" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--clean" (set "CLEAN=1" & shift & goto :args)
if /i "%~1"=="--force" (set "FORCE=1" & shift & goto :args)
if /i "%~1"=="--no-bundle" (set "NO_BUNDLE=1" & shift & goto :args)
if /i "%~1"=="--install-vulkan" (set "INSTALL_VK=1" & shift & goto :args)
if /i "%~1"=="--no-install-vulkan" (set "INSTALL_VK=0" & shift & goto :args)
if /i "%~1"=="--no-install-sdk" (set "INSTALL_SDK=0" & shift & goto :args)
if /i "%~1"=="--no-install-ffmpeg" (set "INSTALL_FFMPEG=0" & shift & goto :args)
if /i "%~1"=="--install-buildtools" (set "INSTALL_BT=1" & shift & goto :args)
if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?" goto :usage
if /i "%~1"=="--backend" (set "OPT=BACKENDS" & goto :value)
if /i "%~1"=="--pkgs" (set "OPT=PKGS" & goto :value)
if /i "%~1"=="--torch" (set "OPT=TORCH" & goto :value)
if /i "%~1"=="--torchaudio" (set "OPT=AUDIO" & goto :value)
if /i "%~1"=="--torchcodec" (set "OPT=CODEC" & goto :value)
if /i "%~1"=="--py" (set "OPT=PYS" & goto :value)
if /i "%~1"=="--suffix" (set "OPT=SUFFIX" & set "SUFFIX_USER=1" & goto :value)
if /i "%~1"=="--root" (set "OPT=ROOT" & goto :value)
if /i "%~1"=="--jobs" (set "OPT=JOBS" & set "JOBS_USER=1" & goto :value)
if /i "%~1"=="--codec-ffmpeg" (set "OPT=CODEC_FFMPEG" & goto :value)
if /i "%~1"=="--cuda" (set "OPT=CUDA_VER" & goto :value)
if /i "%~1"=="--cudnn" (set "OPT=CUDNN_VER" & goto :value)
if /i "%~1"=="--cuda-arch" (set "OPT=CUDA_ARCH" & goto :value)
if /i "%~1"=="--apl" (set "OPT=APL_VER" & goto :value)
echo unknown option: %~1 - see --help
exit /b 1
:value
if "%~2"=="" (echo %~1 needs a value - see --help & exit /b 1)
set "%OPT%=%~2"
shift
shift
goto :args
:args_done
if /i not "%CODEC_FFMPEG%"=="auto" if /i not "%CODEC_FFMPEG%"=="s3" if /i not "%CODEC_FFMPEG%"=="local" if /i not "%CODEC_FFMPEG%"=="btbn" (echo --codec-ffmpeg must be auto, s3, btbn or local & exit /b 1)
for %%p in (%PKGS%) do if /i not "%%p"=="torch" if /i not "%%p"=="torchaudio" if /i not "%%p"=="torchcodec" (echo unknown package %%p - torch, torchaudio, torchcodec & exit /b 1)
for %%b in (%BACKENDS%) do if /i not "%%b"=="vulkan" if /i not "%%b"=="cpu" if /i not "%%b"=="cuda" (echo unknown backend %%b - vulkan, cpu, cuda & exit /b 1)
set "HA=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "HA=%PROCESSOR_ARCHITEW6432%"
set "HOSTA="
if /i "%HA%"=="AMD64" set "HOSTA=x64"
if /i "%HA%"=="ARM64" set "HOSTA=arm64"
if not defined HOSTA (echo unsupported machine %HA% & exit /b 1)
rem arm64 wheels need a native arm64 Python: uv has those from 3.11 on, an x64 one would run emulated and build x64 wheels
if "%HOSTA%"=="arm64" for %%v in (%PYS%) do for %%o in (3.8 3.9 3.10) do if "%%v"=="%%o" (echo windows-arm64 builds need Python 3.11 or newer - uv has no native arm64 Python %%v & exit /b 1)
call :vs_env
call :find_sdk
call :cuda_ver
call :common_missing
call :codec_mode
if not "%LIST%"=="1" goto :build
echo targets on this Windows-%HOSTA% machine:
for %%b in (vulkan cpu cuda) do call :list_one %%b
call :install_on || goto :list_nvidia
call :gpu_check
echo GPU: %GPU_NAME% - %GPU_NOTE%
:list_nvidia
call :nv_gpu
if defined NV_GPU echo NVIDIA GPU: %NV_GPU%
exit /b 0
:build
rem torch's version is needed on every build - torchaudio and torchcodec build against that torch wheel - and
rem torchcodec's only when it is built; --list needs neither
if not defined TORCH (echo [vk-build] ERROR: --torch=VER is required, e.g. --torch=2.14.1 - see --help & exit /b 1)
call :want torchcodec && if not defined CODEC (echo [vk-build] ERROR: --torchcodec=VER is required when torchcodec is built, e.g. --torchcodec=0.17.0, or leave it out of --pkgs & exit /b 1)
call :longpath_check
call :size_jobs
set "MISSANY=0"
for %%b in (%BACKENDS%) do call :miss_stop %%b
if "%MISSANY%"=="1" exit /b 1
if not exist "%ROOT%" mkdir "%ROOT%"
for %%r in ("%ROOT%") do set "ROOT=%%~fr"
if "%INSTALL_BT%"=="1" call :install_bt || exit /b 1
where uv >nul 2>&1 && goto :have_uv
echo [vk-build] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [vk-build] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
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
set "BUILT="
for %%b in (%BACKENDS%) do (call :build_backend %%b || exit /b 1)
echo [vk-build] built wheels:
for %%w in (%BUILT%) do echo [vk-build]   %%w
exit /b 0
rem ---------------------------------------------------------------- subroutines
:usage
echo Usage: build-torch-vulkan.cmd --torch=VER --torchcodec=VER [options]
echo Builds torch, torchaudio and torchcodec wheels for this Windows machine, x64 or arm64, with one or more backends:
echo   vulkan  windows-ARCH-vulkan: the PyTorch Vulkan backend. The torch wheel carries vulkan-1.dll, so it imports on
echo           machines without a Vulkan runtime - Vulkan is then simply unavailable
echo   cpu     windows-ARCH-cpu: CPU only
echo   cuda    windows-ARCH-cuda: CUDA and cuDNN, downloaded into ROOT\tools and bundled into the torch wheel, so users
echo           need only the NVIDIA driver. arm64: NVIDIA's Windows arm64 CUDA, which starts at 13.4.1
echo Each backend is a full torch build of its own, with the CPU BLAS and LAPACK of the official wheels: MKL on x64, Arm
echo Performance Libraries on arm64. Linux and macOS: build-torch-vulkan.sh.
echo Versions - no built-in default for torch and torchcodec: name them on every run           [env]
echo   --torch=VER             torch to build, e.g. 2.14.1 - the Vulkan backend is still in the tree in 2.15.0  [TORCH]
echo   --torchcodec=VER        torchcodec to build, e.g. 0.17.0 - 0.12+ works with every torch 2.11+           [CODEC]
echo                           only required when torchcodec is in --pkgs
echo   --torchaudio=VER        default: %AUDIO%, the last release - stable ABI, any torch 2.11+              [AUDIO]
echo Options taking a value accept both --option=VALUE and --option VALUE
echo Options                                                                                [env]
echo   -l, --list              what this machine can build now, for every backend
echo   --backend "vulkan cpu"  backends to build: vulkan, cpu, cuda                        [BACKENDS] default: %BACKENDS%
echo   --pkgs "torch ..."      packages to build                                            [PKGS]    default: %PKGS%
echo   --py "3.11 3.12"        Python versions from uv, one full torch build each            [PYS]     default: %PYS%
echo                           arm64: 3.11 or newer - native arm64 Pythons, checked before the build
echo   --suffix TAG            local version tag, e.g. 2.14.1+vulkan                         [SUFFIX]  default: the backend,
echo                           vulkan, cpu, or cuXY for CUDA X.Y - cu134 for the default CUDA
echo   --root DIR              sources, venvs and wheels                                     [ROOT]    default: .\pytorch-vulkan
echo   --jobs N                parallel compile jobs, ~3 GB RAM each with MSVC              [JOBS]    default: CPU threads, capped by RAM
echo                           RAM minus 8 GB for linking, divided by 3 GB; a failed torch build resumes once with 1 job
echo   --clean                 git clean the checkouts first - do it when changing versions  [CLEAN=1]
echo   --force                 rebuild packages whose wheel is already in dist               [FORCE=1]
echo                           default: a package whose wheel for this version and Python is in dist is skipped
echo   --codec-ffmpeg MODE     torchcodec FFmpeg: auto, s3 - PyTorch's LGPL builds, x64 only, [CODEC_FFMPEG] default: auto
echo                           btbn - BtbN's LGPL shared build, fetched into ROOT\tools, x64 and arm64,
echo                           local - pkg-config, redistributable only if that FFmpeg is LGPL
echo                           auto = s3 on x64; on arm64 local if pkg-config finds one, else btbn
echo                           s3 builds for every FFmpeg major torchcodec supports, btbn and local for theirs only
echo   --no-bundle             do not put vulkan-1.dll into the vulkan torch wheel            [NO_BUNDLE=1]
echo   --install-vulkan        run the Vulkan install job on any host                        [INSTALL_VK=1]
echo   --no-install-vulkan     never run it                                                  [INSTALL_VK=0]  default: arm64 hosts
echo                           checks the GPU for a Vulkan driver; without one the wheels still build and the probe
echo                           shows vulkan_available False, with a hint on which driver to install
echo   --no-install-sdk        do not install the LunarG Vulkan SDK when it is missing        [INSTALL_SDK=0] default: installs it
echo                           latest SDK for this architecture into %%LOCALAPPDATA%%\VulkanSDK, checksum-verified,
echo                           copy-only, may show a UAC prompt; also fetches LunarG's vulkan-1.dll to bundle if needed
echo   --install-buildtools    install Visual Studio 2022 Build Tools with C++ through winget [INSTALL_BT=1]  several GB, UAC
echo   --no-install-ffmpeg     fetch no FFmpeg for torchcodec                                [INSTALL_FFMPEG=0] default: fetches it
echo                           auto on arm64 then needs a local one. At run time torchcodec loads FFmpeg from the first
echo                           ffmpeg.exe on PATH - a shared build, FFmpeg 4 to 9; without one: BtbN's LGPL shared build,
echo                           else Gyan.dev's x64 build, into ROOT\tools
echo CUDA backend                                                                           [env]
echo   --cuda X.Y.Z            CUDA release, from NVIDIA's redistributable archives, about 2 GB [CUDA_VER] default: %CUDA_VER%
echo                           into ROOT\tools, checksum-verified - no installer, no admin rights; arm64: 13.4.1 or newer
echo   --cudnn VER             cuDNN release, about 1 GB, 0 for none                        [CUDNN_VER] default: %CUDNN_VER%
echo   --cuda-arch "LIST"      CUDA architectures, e.g. "8.6;12.0" - quote the list           [CUDA_ARCH] default: auto
echo                           auto = this machine's NVIDIA GPUs from nvidia-smi, else 7.5 8.0 8.6 9.0 10.0 12.0 like
echo                           the official CUDA 13 wheels - each architecture adds hours to the build
echo   NVCC_ALLOW_UNSUPPORTED=1  let nvcc accept a Visual Studio newer than its CUDA release supports
echo   USE_FLASH_ATTENTION=0   like every USE_* variable, reaches torch's CMake: flash attention is the longest and most
echo                           memory-hungry part of a CUDA build
echo arm64 BLAS                                                                             [env]
echo   --apl VER               Arm Performance Libraries for BLAS and LAPACK, 0 for none     [APL_VER] default: %APL_VER%
echo                           the release PyTorch's own win_arm64 wheels use; unpacked from Arm's MSI without admin
echo                           rights into ROOT\tools, armpl_lp64.dll goes into torch\lib; without it torch has Eigen's
echo                           slow BLAS and no LAPACK
echo   -h, --help
echo Output
echo   ROOT\dist\TARGET\PKG-VER+SUFFIX-cpXY-cpXY-win_amd64.whl or win_arm64.whl, sources in ROOT\src-TARGET
echo   Each build ends with a probe of the ops TTS models use, on the backend's device.
echo Needs
echo   Visual Studio 2022 or its Build Tools with the C++ workload for this machine - found with vswhere, no special
echo   prompt needed, or --install-buildtools; git; network access. uv, and the backend's SDKs, are installed if missing
echo   Windows arm64: PyTorch's own win_arm64 wheels are CPU-only torch, no torchaudio or torchcodec - this builds all three
echo   Vulkan on Windows arm64: Snapdragon X has a native Qualcomm driver; older Snapdragons need Microsoft's
echo   OpenCL, OpenGL, and Vulkan Compatibility Pack from the Microsoft Store
echo   CUDA: building needs no GPU; running needs an NVIDIA GPU and driver - on arm64 NVIDIA's Windows on Arm GPUs
echo Examples
echo   build-torch-vulkan.cmd --list
echo   build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0
echo   build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --backend="vulkan cpu"
echo   build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --backend=cuda --cuda-arch="12.0"
echo   build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --py="3.11 3.12" --jobs=8
echo   build-torch-vulkan.cmd --torch=2.14.1 --pkgs=torch
echo   build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --pkgs="torchaudio torchcodec"
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
call :local_ffmpeg && (set "CMODE=local" & exit /b 0)
if "%INSTALL_FFMPEG%"=="1" set "CMODE=btbn"
exit /b 0
:cuda_ver
rem CU_NUM (130403 for 13.4.3), CU_MAJ and CU_TAG (cu134) from --cuda X.Y.Z; CU_NUM stays 0 for anything else
set "CU_MAJ="
set "CU_MIN="
set "CU_PAT="
set "CU_NUM=0"
set "CU_TAG=cuda"
for /f "tokens=1-3 delims=." %%a in ("%CUDA_VER%") do (set "CU_MAJ=%%a" & set "CU_MIN=%%b" & set "CU_PAT=%%c")
if not defined CU_PAT exit /b 0
set /a "CU_NUM=CU_MAJ*10000+CU_MIN*100+CU_PAT" 2>nul
set "CU_TAG=cu%CU_MAJ%%CU_MIN%"
exit /b 0
:common_missing
rem MISS0 = what every backend lacks on this machine
set "MISS0="
if "%INSTALL_BT%"=="1" goto :cm_git
where cl >nul 2>&1 || set "MISS0=%MISS0% Visual Studio 2022 C++ build tools for %HOSTA% - add --install-buildtools,"
if defined VSCMD_ARG_TGT_ARCH if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" set "MISS0=%MISS0% a %HOSTA% Visual Studio environment - this one targets %VSCMD_ARG_TGT_ARCH%,"
:cm_git
where git >nul 2>&1 || set "MISS0=%MISS0% git,"
exit /b 0
:missing
rem %1 backend: MISS = what windows-HOSTA-%1 lacks on this machine, empty when it can build
set "MISS=%MISS0%"
if /i "%~1"=="vulkan" goto :miss_vk
if /i "%~1"=="cuda" goto :miss_cuda
goto :miss_codec
:miss_vk
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
goto :miss_codec
:miss_cuda
if not "%CU_NUM%"=="0" goto :miss_cuda_arch
set "MISS=%MISS% a full CUDA release for --cuda, e.g. 13.4.3,"
goto :miss_codec
:miss_cuda_arch
if "%HOSTA%"=="arm64" if %CU_NUM% LSS 130401 set "MISS=%MISS% CUDA 13.4.1 or newer for --cuda - NVIDIA's Windows arm64 CUDA starts there,"
:miss_codec
call :want torchcodec || exit /b 0
if /i "%CODEC_FFMPEG%"=="s3" if "%HOSTA%"=="arm64" set "MISS=%MISS% S3 FFmpeg for arm64 - PyTorch has none, use --codec-ffmpeg btbn or local,"
if /i not "%CODEC_FFMPEG%"=="local" exit /b 0
call :local_ffmpeg || set "MISS=%MISS% pkg-config + a shared FFmpeg on PKG_CONFIG_PATH,"
exit /b 0
:miss_stop
call :missing %~1
if not defined MISS exit /b 0
echo [vk-build] ERROR: windows-%HOSTA%-%~1: missing:%MISS:~0,-1% - see --help
set "MISSANY=1"
exit /b 0
:list_one
rem %1 backend: its --list line
call :missing %~1
if defined MISS (echo   windows-%HOSTA%-%~1   missing:%MISS:~0,-1% - see --help & exit /b 0)
set "NOTE="
call :want torchcodec && if "%CMODE%"=="skip" set "NOTE= - torchcodec skipped: no FFmpeg for it, see --help"
call :want torchcodec && if "%CMODE%"=="btbn" if not exist "%ROOT%\tools\ffmpeg-%HOSTA%\lib\pkgconfig\libavcodec.pc" set "NOTE= - fetches BtbN's LGPL FFmpeg for torchcodec"
if "%HOSTA%"=="arm64" if not "%APL_VER%"=="0" if not exist "%ROOT%\tools\apl-%APL_VER%" set "NOTE=%NOTE% - fetches Arm Performance Libraries %APL_VER%"
if /i "%~1"=="vulkan" if "%INSTALL_SDK%"=="1" if not exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" set "NOTE=%NOTE% - installs the Vulkan SDK first"
if /i "%~1"=="cuda" if not exist "%ROOT%\tools\cuda-%CUDA_VER%-%HOSTA%\.vk_complete" set "NOTE=%NOTE% - downloads CUDA %CUDA_VER%, about 2 GB"
if /i "%~1"=="cuda" if not "%CUDNN_VER%"=="0" if not exist "%ROOT%\tools\cudnn-%CUDNN_VER%-cuda%CU_MAJ%-%HOSTA%\.vk_complete" set "NOTE=%NOTE% - downloads cuDNN %CUDNN_VER%, about 1 GB"
echo   windows-%HOSTA%-%~1   ready%NOTE%
exit /b 0
:build_backend
rem %1 backend: every Python of --py for windows-HOSTA-%1, with its own checkouts, venvs and dist folder; what the
rem backend sets up (PATH, CUDA variables) ends with it
setlocal
rem lower case whatever --backend spelled: BK names the folders and is the probe's torch device
for %%n in (vulkan cpu cuda) do if /i "%~1"=="%%n" set "BK=%%n"
set "TARGET=windows-%HOSTA%-%BK%"
if defined SUFFIX_USER goto :bb_suffix
set "SUFFIX=%BK%"
if /i "%BK%"=="cuda" set "SUFFIX=%CU_TAG%"
:bb_suffix
set "SRC=%ROOT%\src-%TARGET%"
set "DIST=%ROOT%\dist\%TARGET%"
if not exist "%SRC%" mkdir "%SRC%"
if not exist "%DIST%" mkdir "%DIST%"
set "BNOTE="
set "BLASNOTE=MKL"
if /i "%BK%"=="vulkan" call :prep_vulkan || exit /b 1
if /i "%BK%"=="cuda" call :prep_cuda || exit /b 1
if "%HOSTA%"=="arm64" call :prep_apl
set "BASEPATH=%PATH%"
set "CLEANNOW=%CLEAN%"
echo [vk-build] %TARGET%: torch %TORCH%, torchaudio %AUDIO%, torchcodec %CODEC% +%SUFFIX%, python %PYS%, %JOBS% jobs, packages: %PKGS%
echo [vk-build] %BNOTE%torchcodec FFmpeg: %CMODE%, CPU BLAS: %BLASNOTE%
for %%v in (%PYS%) do (call :build_py %%v || exit /b 1)
endlocal & set "BUILT=%BUILT%"
exit /b 0
:prep_vulkan
call :install_on || goto :pv_sdk
call :vk_job || exit /b 1
goto :pv_loader
:pv_sdk
call :sdk_job || exit /b 1
:pv_loader
call :find_loader
if "%NO_BUNDLE%"=="1" goto :pv_path
if "%LOADER%"=="no" (echo [vk-build] ERROR: no vulkan-1.dll to bundle - install the Vulkan runtime, use --install-vulkan or --no-bundle & exit /b 1)
:pv_path
set "PATH=%VULKAN_SDK%\Bin;%PATH%"
set "BNOTE=Vulkan SDK %VULKAN_SDK%, bundled loader: %LOADER%, "
exit /b 0
:prep_cuda
rem CUDA from NVIDIA's redistributable archives in ROOT\tools, cuDNN in its own folder beside it
call :ensure_cuda || exit /b 1
call :ensure_cudnn || exit /b 1
set "CUDA_PATH=%CUDADIR%"
set "CUDA_HOME=%CUDADIR%"
set "CUDAToolkit_ROOT=%CUDADIR%"
rem CMake takes no backslashes in the CUDA compiler's path
set "CUDACXX=%CUDADIR:\=/%/bin/nvcc.exe"
set "PATH=%CUDADIR%\bin;%PATH%"
call :cuda_arch
set "TORCH_CUDA_ARCH_LIST=%CARCH%"
rem nvcc refuses a Visual Studio newer than its release knows; NVCC_APPEND_FLAGS reaches every nvcc run, CMake's own too
if "%NVCC_ALLOW_UNSUPPORTED%"=="1" set "NVCC_APPEND_FLAGS=-allow-unsupported-compiler"
set "BNOTE=CUDA %CUDA_VER%, cuDNN %CUDNN_VER%, CUDA architectures %CARCH% - %CARCH_FROM%, "
exit /b 0
:ensure_cuda
rem CUDA %CUDA_VER% from NVIDIA's redistributable archives - redistrib_X.Y.Z.json lists each component's zip and sha256 -
rem merged into one toolkit folder: the compiler (nvcc, crt, nvvm), the runtime, the CCCL headers (cuda_cccl up to CUDA
rem 13.2, cccl from 13.3) and the libraries torch links. No installer, no driver, no admin rights
set "CUPLAT=windows-x86_64"
set "CPD=x64"
if "%HOSTA%"=="arm64" (set "CUPLAT=windows-arm64" & set "CPD=arm64")
set "CUDADIR=%ROOT%\tools\cuda-%CUDA_VER%-%HOSTA%"
if exist "%CUDADIR%\.vk_complete" exit /b 0
if exist "%CUDADIR%" rmdir /s /q "%CUDADIR%"
echo [vk-build] downloading CUDA %CUDA_VER% for %CUPLAT% into %CUDADIR%: compiler, runtime and the libraries torch links, about 2 GB
powershell -NoProfile -ExecutionPolicy Bypass -c "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$v='%CUDA_VER%';$p='%CUPLAT%';$d='%CUDADIR%';$b='https://developer.download.nvidia.com/compute/cuda/redist/';$j=Invoke-RestMethod ($b+'redistrib_'+$v+'.json');New-Item -ItemType Directory -Force $d | Out-Null;foreach($c in @('cuda_nvcc','cuda_crt','libnvvm','cuda_cudart','cuda_cccl','cccl','cuda_nvrtc','cuda_nvtx','cuda_cupti','cuda_profiler_api','cuda_nvml_dev','libcublas','libcufft','libcurand','libcusolver','libcusparse','libnvjitlink')){$e=$j.$c.$p;if(-not $e){continue};$z=Join-Path $env:TEMP ([IO.Path]::GetFileName($e.relative_path));Write-Host ('[vk-build]   '+$c+' '+$j.$c.version);Invoke-WebRequest -UseBasicParsing ($b+$e.relative_path) -OutFile $z;if((Get-FileHash -Algorithm SHA256 $z).Hash -ne $e.sha256.ToUpper()){throw ('checksum mismatch: '+$c)};$t=Join-Path $env:TEMP ('vkcuda'+[guid]::NewGuid().ToString('N'));Expand-Archive -LiteralPath $z -DestinationPath $t -Force;$r=(Get-ChildItem $t | Select-Object -First 1).FullName;robocopy $r $d /E /NFL /NDL /NJH /NJS /NP | Out-Null;if($LASTEXITCODE -ge 8){throw ('copy failed: '+$c)};Remove-Item $t -Recurse -Force;Remove-Item $z};exit 0" || exit /b 1
if not exist "%CUDADIR%\bin\nvcc.exe" (echo [vk-build] ERROR: CUDA %CUDA_VER% has no bin\nvcc.exe for %CUPLAT% - check that release on developer.download.nvidia.com/compute/cuda/redist & exit /b 1)
if not "%HOSTA%"=="arm64" goto :ecu_done
rem torch's own FindCUDAToolkit, its install step and torch.utils.cpp_extension know only CUDA's x64 folder names: the
rem arm64 toolkit's lib\arm64 and bin\arm64 get lib\x64 and bin\x64 junctions to them, copies where junctions fail
for %%d in (lib bin) do if not exist "%CUDADIR%\%%d\x64" mklink /J "%CUDADIR%\%%d\x64" "%CUDADIR%\%%d\arm64" >nul 2>&1 || xcopy /e /i /q /y "%CUDADIR%\%%d\arm64" "%CUDADIR%\%%d\x64" >nul
:ecu_done
type nul > "%CUDADIR%\.vk_complete"
exit /b 0
:ensure_cudnn
rem cuDNN %CUDNN_VER% for this CUDA major from NVIDIA's cudnn redistrib JSON, sha256-checked; its static libraries, most
rem of the archive, are left out. torch finds it through CUDNN_INCLUDE_DIR and CUDNN_LIB_DIR, its installed CMake
rem config (torchcodec's build) through CUDNN_LIBRARY
set "CUDNNDIR="
if "%CUDNN_VER%"=="0" exit /b 0
set "CUDNNDIR=%ROOT%\tools\cudnn-%CUDNN_VER%-cuda%CU_MAJ%-%HOSTA%"
if exist "%CUDNNDIR%\.vk_complete" goto :ecd_env
if exist "%CUDNNDIR%" rmdir /s /q "%CUDNNDIR%"
echo [vk-build] downloading cuDNN %CUDNN_VER% for CUDA %CU_MAJ% on %CUPLAT% into %CUDNNDIR%, about 1 GB
powershell -NoProfile -ExecutionPolicy Bypass -c "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$b='https://developer.download.nvidia.com/compute/cudnn/redist/';$j=Invoke-RestMethod ($b+'redistrib_%CUDNN_VER%.json');$e=$j.cudnn.'%CUPLAT%'.'cuda%CU_MAJ%';if(-not $e.relative_path){throw 'no cuDNN %CUDNN_VER% for CUDA %CU_MAJ% on %CUPLAT%'};$z=Join-Path $env:TEMP ([IO.Path]::GetFileName($e.relative_path));Invoke-WebRequest -UseBasicParsing ($b+$e.relative_path) -OutFile $z;if((Get-FileHash -Algorithm SHA256 $z).Hash -ne $e.sha256.ToUpper()){throw 'checksum mismatch: cuDNN'};$d='%CUDNNDIR%';Add-Type -AssemblyName System.IO.Compression.FileSystem;$a=[IO.Compression.ZipFile]::OpenRead($z);foreach($x in $a.Entries){$n=$x.FullName;if($n.EndsWith('/') -or $n -like '*_static*'){continue};$o=Join-Path $d $n.Substring($n.IndexOf('/')+1);New-Item -ItemType Directory -Force (Split-Path $o) | Out-Null;[IO.Compression.ZipFileExtensions]::ExtractToFile($x,$o,$true)};$a.Dispose();Remove-Item $z;exit 0" || exit /b 1
if not exist "%CUDNNDIR%\include\cudnn.h" (echo [vk-build] ERROR: the cuDNN %CUDNN_VER% download has no include\cudnn.h & exit /b 1)
type nul > "%CUDNNDIR%\.vk_complete"
:ecd_env
set "CUDNN_INCLUDE_DIR=%CUDNNDIR%\include"
set "CUDNN_LIB_DIR=%CUDNNDIR%\lib\%CPD%"
if not exist "%CUDNN_LIB_DIR%\cudnn.lib" set "CUDNN_LIB_DIR=%CUDNNDIR%\lib"
set "CUDNN_LIBRARY=%CUDNN_LIB_DIR%"
exit /b 0
:cuda_arch
rem CARCH = TORCH_CUDA_ARCH_LIST: --cuda-arch, else the compute capabilities of this machine's NVIDIA GPUs, else the list
rem of PyTorch's own CUDA 13 wheels
set "CARCH=%CUDA_ARCH%"
set "CARCH_FROM=--cuda-arch"
if /i not "%CUDA_ARCH%"=="auto" exit /b 0
set "CARCH="
set "NVOUT=%TEMP%\vk_nvsmi_%RANDOM%.txt"
nvidia-smi --query-gpu=compute_cap --format=csv,noheader > "%NVOUT%" 2>nul
for /f "usebackq tokens=1" %%c in ("%NVOUT%") do call :arch_add %%c
del /q "%NVOUT%" 2>nul
set "CARCH_FROM=this machine's GPU"
if defined CARCH exit /b 0
set "CARCH=7.5;8.0;8.6;9.0;10.0;12.0"
set "CARCH_FROM=no NVIDIA GPU here, the list of PyTorch's CUDA 13 wheels"
exit /b 0
:arch_add
rem %1 a compute capability like 12.1, added once; nvidia-smi's error text is not one
echo %~1| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*$" >nul || exit /b 0
echo ;%CARCH%; | findstr /c:";%~1;" >nul && exit /b 0
if defined CARCH (set "CARCH=%CARCH%;%~1") else set "CARCH=%~1"
exit /b 0
:nv_gpu
set "NV_GPU="
where nvidia-smi >nul 2>&1 || exit /b 0
set "NVOUT=%TEMP%\vk_nvsmi_%RANDOM%.txt"
nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader > "%NVOUT%" 2>nul
for /f "usebackq tokens=1-3 delims=," %%a in ("%NVOUT%") do if not defined NV_GPU set "NV_GPU=%%a - compute capability%%b, driver%%c"
del /q "%NVOUT%" 2>nul
exit /b 0
:prep_apl
rem arm64: BLAS and LAPACK from Arm Performance Libraries, as in PyTorch's own win_arm64 wheels: BLAS=APL, and torch's
rem FindAPL copies armpl_lp64.dll into torch\lib. Without them torch falls back to Eigen's slow BLAS and has no LAPACK, so
rem no torch.linalg. Arm's MSI is unpacked with an administrative install (msiexec /a): files only, no admin rights,
rem nothing registered
set "ARMPL_DIR="
set "BLASNOTE=Eigen, no LAPACK"
if "%APL_VER%"=="0" exit /b 0
set "APLROOT=%ROOT%\tools\apl-%APL_VER%"
call :find_apl
if defined ARMPL_DIR goto :pa_ok
set "APLMSI=%TEMP%\arm-performance-libraries_%APL_VER%_Windows.msi"
set "APLLOG=%TEMP%\vk_apl_%APL_VER%_msi.log"
echo [vk-build] fetching Arm Performance Libraries %APL_VER% for torch's arm64 BLAS and LAPACK into %APLROOT%
curl.exe -fL -o "%APLMSI%" https://developer.arm.com/-/cdn-downloads/permalink/Arm-Performance-Libraries/Version_%APL_VER%/arm-performance-libraries_%APL_VER%_Windows.msi || goto :pa_fail
if exist "%APLROOT%" rmdir /s /q "%APLROOT%"
start "" /wait msiexec /a "%APLMSI%" /qn TARGETDIR="%APLROOT%" /l* "%APLLOG%"
del /q "%APLMSI%" 2>nul
call :find_apl
if defined ARMPL_DIR goto :pa_ok
:pa_fail
echo [vk-build] WARNING: no Arm Performance Libraries %APL_VER% - torch keeps Eigen's slower BLAS and has no LAPACK; msiexec's log: %APLLOG%
exit /b 0
:pa_ok
rem armpl_lp64.dll on PATH: torch's CMake runs a BLAS check program linked against it
set "PATH=%ARMPL_DIR%\bin;%PATH%"
set "BLASNOTE=Arm Performance Libraries %APL_VER%, %ARMPL_DIR%"
exit /b 0
:find_apl
rem ARMPL_DIR = the folder of include\armpl.h, lib\armpl_lp64.dll.lib and bin\armpl_lp64.dll under APLROOT - the MSI
rem lays them out as PFiles64\Arm Performance Libraries\armpl_VER
set "APLH="
for /f "delims=" %%f in ('dir /s /b "%APLROOT%\armpl.h" 2^>nul') do if not defined APLH set "APLH=%%~dpf"
if not defined APLH exit /b 0
for %%i in ("%APLH%..") do set "ARMPL_DIR=%%~fi"
if not exist "%ARMPL_DIR%\lib\armpl_lp64.dll.lib" set "ARMPL_DIR="
if defined ARMPL_DIR if not exist "%ARMPL_DIR%\bin\armpl_lp64.dll" set "ARMPL_DIR="
exit /b 0
:build_py
set "V=%~1"
set "TAG=cp%V:.=%"
set "VENV=%ROOT%\venv-%TARGET%-%V%"
echo [vk-build] --- %TARGET% python %V%
if exist "%VENV%" rmdir /s /q "%VENV%"
rem arm64: ask uv for its native arm64 build by name - a plain version may get an emulated x64 Python, whose wheels would
rem be win_amd64 while cl builds arm64 code
set "UVPY=%V%"
if "%HOSTA%"=="arm64" set "UVPY=cpython-%V%-windows-aarch64-none"
uv venv -q --seed --python %UVPY% "%VENV%" || exit /b 1
set "PY=%VENV%\Scripts\python.exe"
set "PYPLAT="
set "PPOUT=%TEMP%\vk_pyplat_%RANDOM%.txt"
"%PY%" -c "import sysconfig;print(sysconfig.get_platform())" > "%PPOUT%" 2>nul
set /p PYPLAT=<"%PPOUT%"
del /q "%PPOUT%" 2>nul
set "WANTPLAT=win-amd64"
if "%HOSTA%"=="arm64" set "WANTPLAT=win-arm64"
if /i "%PYPLAT%"=="%WANTPLAT%" goto :bp_plat_ok
echo [vk-build] ERROR: the build venv's Python %V% is %PYPLAT%, not %WANTPLAT% like this machine - its wheels would not match
exit /b 1
:bp_plat_ok
set "PATH=%VENV%\Scripts;%BASEPATH%"
rem CMake's FindPython checks VIRTUAL_ENV before registry-installed Pythons
set "VIRTUAL_ENV=%VENV%"
"%PY%" -m pip install -q cmake ninja setuptools wheel || exit /b 1
rem a package whose wheel for this version, suffix and Python is already in dist is skipped: no sync, no build
call :built_whl torch %TORCH%
set "TW=%BW%"
call :built_whl torchaudio %AUDIO%
set "AW=%BW%"
call :built_whl torchcodec %CODEC%
set "CW=%BW%"
call :want torch && if not defined TW (call :sync_repo torch https://github.com/pytorch/pytorch.git %TORCH% || exit /b 1)
call :want torchaudio && if not defined AW (call :sync_repo torchaudio https://github.com/pytorch/audio.git %AUDIO% || exit /b 1)
call :want torchcodec && if not defined CW (call :sync_repo torchcodec https://github.com/pytorch/torchcodec.git %CODEC% || exit /b 1)
call :want torch || goto :bp_notorch
if defined TW goto :bp_torch_skip
call :build_torch || exit /b 1
goto :bp_audio
:bp_torch_skip
echo [vk-build] torch %TORCH%+%SUFFIX% %TAG% already built, skipped: %TW%
set "WHL=%TW%"
"%PY%" -m pip install -q "%WHL%" || exit /b 1
set "BUILT=%BUILT% %WHL%"
goto :bp_audio
:bp_notorch
call :install_existing_torch || exit /b 1
:bp_audio
call :want torchaudio || goto :bp_codec
if defined AW goto :bp_audio_skip
call :build_torchaudio || exit /b 1
goto :bp_codec
:bp_audio_skip
echo [vk-build] torchaudio %AUDIO%+%SUFFIX% %TAG% already built, skipped: %AW%
set "WHL=%AW%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
:bp_codec
call :want torchcodec || goto :bp_done
if defined CW goto :bp_codec_skip
call :build_torchcodec || exit /b 1
goto :bp_ffmpeg
:bp_codec_skip
echo [vk-build] torchcodec %CODEC%+%SUFFIX% %TAG% already built, skipped: %CW%
set "WHL=%CW%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
:bp_ffmpeg
call :runtime_ffmpeg
:bp_done
call :probe
set "CLEANNOW=1"
exit /b 0
:longpath_check
reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2>nul | findstr /i "0x1" >nul && exit /b 0
echo [vk-build] WARNING: Windows long paths are off. git copes on its own, but the compiler, CMake and Python may still
echo [vk-build]          hit the 260-character limit deep inside the torch build. Either enable them once, as admin:
echo [vk-build]            reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f
echo [vk-build]          or keep the tree short, e.g. --root D:\ptv
exit /b 0
:size_jobs
rem MSVC needs ~3 GB per torch compile job, and linking torch_cpu.dll needs several GB on its own while compiles go on;
rem too little ends in C1002 / C1356 / LNK1102. Jobs = (RAM - 8 GB for the link) / 3 GB
set "RAM_GB="
set "CL_GB="
for /f "usebackq tokens=1,2 delims=;" %%a in (`powershell -NoProfile -c "'{0};{1}' -f [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB), [math]::Floor((Get-CimInstance Win32_OperatingSystem).TotalVirtualMemorySize/1MB)"`) do (set "RAM_GB=%%a" & set "CL_GB=%%b")
if not defined RAM_GB exit /b 0
set /a "MJ=(RAM_GB-8)/3"
if %MJ% LSS 1 set "MJ=1"
set /a "PF_GB=CL_GB-RAM_GB"
if %PF_GB% LSS 8 echo [vk-build] WARNING: Windows can commit only %CL_GB% GB - RAM %RAM_GB% GB plus a %PF_GB% GB pagefile. Linking torch_cpu.dll may fail with LNK1102:
if %PF_GB% LSS 8 echo [vk-build]          set the pagefile to "System managed size" - System Properties, Advanced, Performance, Virtual memory - and reboot
if defined JOBS_USER goto :sj_user
if %MJ% LSS %JOBS% set "JOBS=%MJ%"
echo [vk-build] %JOBS% parallel jobs for %NUMBER_OF_PROCESSORS% CPU threads and %RAM_GB% GB RAM - 8 GB kept for linking, about 3 GB per MSVC job; --jobs overrides
exit /b 0
:sj_user
if %JOBS% GTR %MJ% echo [vk-build] WARNING: --jobs %JOBS% is more than the %MJ% that %RAM_GB% GB RAM supports with room for linking - if cl.exe or link.exe run out of memory, use --jobs %MJ%
exit /b 0
:runtime_ffmpeg
rem torchcodec loads FFmpeg at run time from the folder of the first ffmpeg.exe on PATH, which must be a shared build
rem of a major this torchcodec supports; otherwise fetch one into ROOT\tools: BtbN's LGPL shared builds first (x64 and
rem arm64), then Gyan.dev's versioned shared builds (x64, GPL). Every candidate is checked by its avcodec-NN.dll.
rem A torchcodec built against BtbN's FFmpeg (btbn) takes exactly that one, ahead of any ffmpeg.exe on PATH
if not "%CMODE%"=="btbn" goto :rf_where
call :ffmpeg_btbn || exit /b 0
goto :rf_path
:rf_where
set "FFCMAKE=%SRC%\torchcodec\src\torchcodec\share\cmake\TorchCodec\ffmpeg_versions.cmake"
set "FFDIR=%ROOT%\tools\ffmpeg-%HOSTA%"
set "FFBIN="
for /f "delims=" %%f in ('where ffmpeg 2^>nul') do if not defined FFBIN set "FFBIN=%%~dpf"
if not defined FFBIN goto :rf_local
call :ff_ok "%FFBIN%" || goto :rf_local
echo [vk-build] torchcodec runtime FFmpeg: %FFBIN%
exit /b 0
:rf_local
if not exist "%FFDIR%\bin\ffmpeg.exe" goto :rf_fetch
call :ff_ok "%FFDIR%\bin\" && goto :rf_path
:rf_fetch
if not "%INSTALL_FFMPEG%"=="1" (echo [vk-build] no torchcodec-compatible shared FFmpeg on PATH - torchcodec will not load, see --help & exit /b 0)
set "FFARCH=win64"
if "%HOSTA%"=="arm64" set "FFARCH=winarm64"
for %%b in (9.0 8.1 8.0 7.1) do call :ff_try btbn %%b && goto :rf_path
if "%HOSTA%"=="arm64" goto :rf_none
for %%b in (9.0 8.0.1 8.0 7.1.1 7.1) do call :ff_try gyan %%b && goto :rf_path
:rf_none
echo [vk-build] WARNING: could not fetch a torchcodec-compatible FFmpeg - torchcodec will not load until one is on PATH
exit /b 0
:rf_path
set "PATH=%FFDIR%\bin;%PATH%"
echo [vk-build] torchcodec runtime FFmpeg: %FFDIR%\bin - put this folder on PATH wherever these wheels are used
exit /b 0
:ffmpeg_btbn
rem BtbN's LGPL shared build in ROOT\tools\ffmpeg-ARCH, the newest one this torchcodec accepts: MSVC import libraries
rem (avcodec.lib, ...) and .pc files relative to their own folder, so torchcodec builds against it through pip's pkgconf,
rem and loads the same DLLs at run time
set "FFCMAKE=%SRC%\torchcodec\src\torchcodec\share\cmake\TorchCodec\ffmpeg_versions.cmake"
set "FFDIR=%ROOT%\tools\ffmpeg-%HOSTA%"
if not exist "%FFDIR%\lib\pkgconfig\libavcodec.pc" goto :fb_fetch
call :ff_ok "%FFDIR%\bin\" && exit /b 0
:fb_fetch
set "FFARCH=win64"
if "%HOSTA%"=="arm64" set "FFARCH=winarm64"
for %%b in (9.0 8.1 8.0 7.1) do call :ff_try btbn %%b && exit /b 0
echo [vk-build] ERROR: could not fetch a BtbN LGPL shared FFmpeg that torchcodec %CODEC% accepts
exit /b 1
:ff_try
rem %1 = btbn or gyan, %2 = FFmpeg version
if "%~1"=="btbn" (set "FFNAME=ffmpeg-n%~2-latest-%FFARCH%-lgpl-shared-%~2") else set "FFNAME=ffmpeg-%~2-full_build-shared"
set "FFURL=https://github.com/GyanD/codexffmpeg/releases/download/%~2/ffmpeg-%~2-full_build-shared.zip"
if "%~1"=="btbn" set "FFURL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/%FFNAME%.zip"
set "FFTMP=%ROOT%\tools\_ffmpeg_dl"
set "FFZIP=%ROOT%\tools\_ffmpeg_dl.zip"
if not exist "%ROOT%\tools" mkdir "%ROOT%\tools"
if exist "%FFTMP%" rmdir /s /q "%FFTMP%"
curl.exe -fsL -o "%FFZIP%" %FFURL% || exit /b 1
powershell -NoProfile -c "Expand-Archive -Force -LiteralPath '%FFZIP%' -DestinationPath '%FFTMP%'" || exit /b 1
del /q "%FFZIP%" 2>nul
call :ff_ok "%FFTMP%\%FFNAME%\bin\" || goto :ff_reject
if exist "%FFDIR%" rmdir /s /q "%FFDIR%"
move "%FFTMP%\%FFNAME%" "%FFDIR%" >nul || exit /b 1
rmdir /s /q "%FFTMP%"
if "%~1"=="btbn" (echo [vk-build] fetched FFmpeg %~2 LGPL shared build from BtbN/FFmpeg-Builds for torchcodec) else echo [vk-build] fetched FFmpeg %~2 shared build from Gyan.dev for torchcodec - GPL, used at run time only, not bundled
exit /b 0
:ff_reject
echo [vk-build] FFmpeg %~2 has avcodec-%FFAVC%, which torchcodec %CODEC% does not accept - trying an older one
rmdir /s /q "%FFTMP%"
exit /b 1
:ff_ok
rem ok when the folder (with a trailing backslash) holds avcodec-NN.dll and torchcodec maps libavcodec NN
set "FFAVC="
for %%d in ("%~1avcodec-*.dll") do set "FFAVC=%%~nd"
if not defined FFAVC exit /b 1
set "FFAVC=%FFAVC:avcodec-=%"
if exist "%FFCMAKE%" goto :fo_cmake
if %FFAVC% LSS 58 exit /b 1
if %FFAVC% GTR 63 exit /b 1
exit /b 0
:fo_cmake
findstr /c:"STREQUAL \"%FFAVC%\"" "%FFCMAKE%" >nul
exit /b %ERRORLEVEL%
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
rem run vswhere outside any ( ) block: its path holds "(x86)", whose ")" would end a for /f clause early
set "VSPATH="
set "VSOUT=%TEMP%\vk_vspath_%RANDOM%.txt"
"%VSWHERE%" -latest -products * -requires %VSCOMP% -property installationPath > "%VSOUT%" 2>nul
set /p VSPATH=<"%VSOUT%"
del /q "%VSOUT%" 2>nul
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
rem LunarG ships the runtime components zip with some SDK releases only (1.4.363.0 has one, 1.4.363.1 does not): the
rem latest SDK's first, else the newest release of this platform that files.json lists one for
set "RTVER=%VKVER%"
set "RTZIP=%TEMP%\VulkanRT-%RTARCH%-%RTVER%-Components.zip"
curl.exe -fsL -o "%RTZIP%" https://sdk.lunarg.com/sdk/download/%RTVER%/%VKPLAT%/VulkanRT-%RTARCH%-%RTVER%-Components.zip && goto :gr_unzip
set "RTVER="
for /f "usebackq delims=" %%v in (`powershell -NoProfile -c "$p=(Invoke-RestMethod https://vulkan.lunarg.com/sdk/files.json).'%VKPLAT%';$v=$p.PSObject.Properties.Name.Where({$p.$_.files.file_name -like 'VulkanRT-*-Components.zip'});if($v.Count){$a=[version[]]$v;[array]::Sort($a);[string]$a[-1]}"`) do set "RTVER=%%v"
if not defined RTVER (echo [vk-build] ERROR: vulkan.lunarg.com lists no Vulkan runtime components package for %VKPLAT% & exit /b 1)
set "RTZIP=%TEMP%\VulkanRT-%RTARCH%-%RTVER%-Components.zip"
curl.exe -fL -o "%RTZIP%" https://sdk.lunarg.com/sdk/download/%RTVER%/%VKPLAT%/VulkanRT-%RTARCH%-%RTVER%-Components.zip || exit /b 1
:gr_unzip
echo [vk-build] fetched LunarG's Vulkan runtime %RTVER% for %RTARCH% to bundle vulkan-1.dll
set "RTDIR=%TEMP%\vulkanrt-%RANDOM%"
powershell -NoProfile -c "Expand-Archive -Force -LiteralPath '%RTZIP%' -DestinationPath '%RTDIR%'" || exit /b 1
rem the x64 zip keeps x64\ and x86\ folders, the ARM64 zip its one vulkan-1.dll at the top
set "RTDLL="
for /d %%d in ("%RTDIR%\*") do if exist "%%~fd\%RTARCH%\vulkan-1.dll" set "RTDLL=%%~fd\%RTARCH%\vulkan-1.dll"
if not defined RTDLL for /d %%d in ("%RTDIR%\*") do if exist "%%~fd\vulkan-1.dll" set "RTDLL=%%~fd\vulkan-1.dll"
if not defined RTDLL (echo [vk-build] ERROR: no %RTARCH% vulkan-1.dll inside the runtime package & exit /b 1)
if not exist "%ROOT%\tools\vulkanrt-%HOSTA%" mkdir "%ROOT%\tools\vulkanrt-%HOSTA%"
copy /y "%RTDLL%" "%ROOT%\tools\vulkanrt-%HOSTA%\vulkan-1.dll" >nul || exit /b 1
rmdir /s /q "%RTDIR%"
del /q "%RTZIP%" 2>nul
exit /b 0
:sync_repo
set "RP=%SRC%\%~1"
if exist "%RP%\.git" goto :sr_have
rem "git -c" before the subcommand reaches the submodule clones too ("clone -c" would only reach the top repo)
git -c core.longpaths=true clone --recursive %~2 "%RP%"
if not exist "%RP%\.git" exit /b 1
:sr_have
git -C "%RP%" config core.longpaths true
git -C "%RP%" -c core.longpaths=true fetch -q --tags --force origin || exit /b 1
rem builds rewrite tracked files (torchcodec 0.11 and older write BUILD_VERSION into version.txt): restore them,
rem or switching to another tag is refused
git -C "%RP%" diff --quiet -- version.txt 2>nul || git -C "%RP%" checkout -q -- version.txt
if not "%CLEANNOW%"=="1" goto :sr_checkout
git -C "%RP%" reset -q --hard
git -C "%RP%" clean -q -xdf
git -C "%RP%" -c core.longpaths=true submodule foreach -q --recursive "git reset -q --hard && git clean -q -xdf"
:sr_checkout
git -C "%RP%" -c advice.detachedHead=false checkout -q v%~3 && goto :sr_sub
echo [vk-build] ERROR: %~1: cannot switch to v%~3 - local changes in %RP%, see git status there; rerun with --clean to reset it
exit /b 1
:sr_sub
git -C "%RP%" -c core.longpaths=true submodule sync -q --recursive || exit /b 1
git -C "%RP%" -c core.longpaths=true submodule update -q --init --recursive --force || exit /b 1
git -C "%RP%" -c core.longpaths=true submodule foreach -q --recursive git config core.longpaths true
exit /b 0
:pip_wheel
rem %1 package, %2 version: only that version's wheel is replaced, other versions in dist are kept
del /q "%DIST%\%~1-%~2+*-%TAG%-*.whl" "%DIST%\%~1-%~2-%TAG%-*.whl" 2>nul
pushd "%SRC%\%~1"
"%PY%" -m pip wheel . --no-build-isolation --no-deps -v -w "%DIST%"
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b 1
set "WHL="
for %%f in ("%DIST%\%~1-%~2+*-%TAG%-*.whl" "%DIST%\%~1-%~2-%TAG%-*.whl") do set "WHL=%%~ff"
if not defined WHL (echo [vk-build] ERROR: no %~1 wheel was produced & exit /b 1)
echo %WHL% | findstr /c:"+%SUFFIX%-" >nul || echo [vk-build] WARNING: %~1 wheel does not carry +%SUFFIX% - the repo ignored the version variable
exit /b 0
:built_whl
rem %1 package, %2 version: BW = the wheel already in dist for this version, suffix and Python; empty if none or --force
set "BW="
if "%FORCE%"=="1" exit /b 0
for %%f in ("%DIST%\%~1-%~2+%SUFFIX%-%TAG%-*.whl") do set "BW=%%~ff"
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
rem a build tree from another torch version or CUDA release (or from before this marker existed) is started over once
set "BT_WANT=%TORCH%"
if /i "%BK%"=="cuda" set "BT_WANT=%TORCH% CUDA %CUDA_VER%"
if not exist "%SRC%\torch\build" goto :bt_tree_ok
set "BT_TAG="
if exist "%SRC%\torch\build\.vk_tag" set /p BT_TAG=<"%SRC%\torch\build\.vk_tag"
if "%BT_TAG%"=="%BT_WANT%" goto :bt_tree_ok
echo [vk-build] torch: build tree is not from %BT_WANT% - removing it, full build
rmdir /s /q "%SRC%\torch\build"
:bt_tree_ok
if /i not "%BK%"=="vulkan" goto :bt_vk_ok
if not exist "%SRC%\torch\aten\src\ATen\native\vulkan" (echo [vk-build] ERROR: torch %TORCH% has no aten\src\ATen\native\vulkan - pick an older --torch & exit /b 1)
:bt_vk_ok
if not exist "%SRC%\torch\requirements-build.txt" goto :bt_req
"%PY%" -m pip install -q -r "%SRC%\torch\requirements-build.txt" || exit /b 1
:bt_req
if not exist "%SRC%\torch\requirements.txt" goto :bt_env
rem the development requirements without lintrunner, a linter with no win_arm64 wheel that would need Rust to build;
rem requirements-build.txt, which they include, is installed above
set "REQ=%TEMP%\vk_requirements_%RANDOM%.txt"
findstr /v /i /r /c:"^lintrunner" /c:"^-r " "%SRC%\torch\requirements.txt" > "%REQ%"
"%PY%" -m pip install -q -r "%REQ%"
set "RC=%ERRORLEVEL%"
del /q "%REQ%" 2>nul
if not "%RC%"=="0" exit /b 1
:bt_env
rem a CPU BLAS like the official wheels: without one torch falls back to Eigen's BLAS, much slower matmuls, and has no
rem LAPACK. x64: pip's mkl-static, linked in statically and sequential, so no Intel OpenMP runtime (libiomp5md.dll) is
rem needed at import. arm64: Arm Performance Libraries, see prep_apl. Turning one on changes torch's config: reconfigure
rem once, recorded by a marker file
set "BLASON="
if "%HOSTA%"=="arm64" goto :bt_apl
"%PY%" -m pip install -q mkl-static mkl-include && set "BLASON=MKL"
if not defined BLASON echo [vk-build] WARNING: MKL not installable here, torch keeps Eigen's slower BLAS
goto :bt_blas_done
:bt_apl
if defined ARMPL_DIR set "BLASON=APL"
:bt_blas_done
rem torch's Vulkan Clamp.cpp uses M_SQRT2/M_2_SQRTPI, which MSVC's cmath only defines after _USE_MATH_DEFINES;
rem upstream never builds Vulkan on Windows, so add the define on line 1 for this build and restore the file after
set "CLAMPG=aten/src/ATen/native/vulkan/ops/Clamp.cpp"
set "CLAMP=%SRC%\torch\aten\src\ATen\native\vulkan\ops\Clamp.cpp"
if /i not "%BK%"=="vulkan" goto :bt_math_ok
git -C "%SRC%\torch" checkout -q -- %CLAMPG%
findstr /c:"_USE_MATH_DEFINES" "%CLAMP%" >nul && goto :bt_math_ok
findstr /r /c:"M_SQRT2" /c:"M_2_SQRTPI" "%CLAMP%" >nul || goto :bt_math_ok
> "%CLAMP%.new" echo #define _USE_MATH_DEFINES
type "%CLAMP%" >> "%CLAMP%.new"
move /y "%CLAMP%.new" "%CLAMP%" >nul || exit /b 1
echo [vk-build] torch: added _USE_MATH_DEFINES to vulkan\ops\Clamp.cpp for MSVC
:bt_math_ok
setlocal
set "BT_FRESH="
if /i not "%BK%"=="vulkan" goto :bt_novk
rem USE_VULKAN_WRAPPER is Android-only in torch: desktop builds always link the Vulkan loader, hence the bundling
set "USE_VULKAN=1"
set "USE_VULKAN_WRAPPER=0"
set "USE_VULKAN_SHADERC_RUNTIME=0"
set "USE_VULKAN_FP16_INFERENCE=0"
set "USE_VULKAN_RELAXED_PRECISION=0"
goto :bt_backend_done
:bt_novk
set "USE_VULKAN=0"
if /i not "%BK%"=="cuda" goto :bt_backend_done
rem CUDA without what Windows or these archives lack - NCCL, MAGMA, cuSPARSELt, cuDSS - and with compressed fatbins
rem like the official wheels
set "USE_CUDA=1"
set "USE_CUDNN=0"
if defined CUDNNDIR set "USE_CUDNN=1"
set "USE_MAGMA=0"
set "USE_CUSPARSELT=0"
set "USE_CUDSS=0"
if not defined TORCH_NVCC_FLAGS set "TORCH_NVCC_FLAGS=-Xfatbin -compress-all"
:bt_backend_done
set "BUILD_TEST=0"
rem link one library at a time: linking torch_cpu.dll alone takes many GB, next to the parallel compiles
set "CMAKE_JOB_POOLS=vk_link=1"
set "CMAKE_JOB_POOL_LINK=vk_link"
if not defined BLASON goto :bt_blas_env_done
if "%BLASON%"=="APL" set "BLAS=APL"
if not "%BLASON%"=="MKL" goto :bt_blas_mark
rem pip's MKL wheels install into VENV\Library\lib and VENV\Library\include
set "CMAKE_PREFIX_PATH=%VENV%\Library;%VENV%"
set "MKL_THREADING=SEQ"
:bt_blas_mark
if not exist "%SRC%\torch\build\CMakeCache.txt" goto :bt_blas_env_done
if exist "%SRC%\torch\build\.vk_%BLASON%" goto :bt_blas_env_done
set "BT_FRESH=1"
echo [vk-build] torch: reconfiguring once to build with %BLASON% - this recompiles a large part of ATen
:bt_blas_env_done
if not exist "%SRC%\torch\build\CMakeCache.txt" goto :bt_fresh_ok
findstr /c:"CMAKE_JOB_POOL_LINK" "%SRC%\torch\build\CMakeCache.txt" >nul && goto :bt_fresh_ok
rem the existing build tree was configured without the link pool: reconfigure once, objects are kept
set "BT_FRESH=1"
echo [vk-build] torch: reconfiguring the existing build once to serialize links - compiled objects are kept
:bt_fresh_ok
rem a fresh configure: CMAKE_FRESH for torch's setup.py builds, up to 2.13, and no CMakeCache.txt for its scikit-build-core
rem builds from 2.14 on, which no longer read CMAKE_FRESH; ninja keeps the objects whose commands did not change
if not defined BT_FRESH goto :bt_version
set "CMAKE_FRESH=1"
del /q "%SRC%\torch\build\CMakeCache.txt" 2>nul
:bt_version
set "PYTORCH_BUILD_VERSION=%TORCH%+%SUFFIX%"
set "PYTORCH_BUILD_NUMBER=1"
call :pip_wheel torch %TORCH% && goto :bt_built
if "%JOBS%"=="1" (endlocal & exit /b 1)
rem out of memory is the usual cause at this size: resume with a single job so the remaining links get the whole machine
echo [vk-build] torch build failed with %JOBS% jobs - resuming once with 1 job; finished objects are kept, Ctrl+C to stop
set "MAX_JOBS=1"
set "CMAKE_BUILD_PARALLEL_LEVEL=1"
set "CMAKE_FRESH="
call :pip_wheel torch %TORCH% || (endlocal & exit /b 1)
:bt_built
endlocal & set "WHL=%WHL%"
if defined BLASON type nul > "%SRC%\torch\build\.vk_%BLASON%"
> "%SRC%\torch\build\.vk_tag" echo %BT_WANT%
git -C "%SRC%\torch" checkout -q -- %CLAMPG%
call :bundle || exit /b 1
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:bundle
rem DLLs the torch wheel needs that the build leaves out: vulkan-1.dll (vulkan, unless --no-bundle), MSVC's LLVM OpenMP
rem runtime when torch_cpu.dll links it, and for cuda cuDNN plus the toolkit DLLs torch's install step misses
set "TB=%DIST%\_bundle"
if exist "%TB%" rmdir /s /q "%TB%"
"%PY%" -m wheel unpack "%WHL%" -d "%TB%" >nul || exit /b 1
set "PKGDIR="
for /d %%d in ("%TB%\*") do set "PKGDIR=%%~fd"
set "TL=%PKGDIR%\torch\lib"
set "BADD="
if /i not "%BK%"=="vulkan" goto :bundle_omp
if "%NO_BUNDLE%"=="1" goto :bundle_omp
copy /y "%LOADER%" "%TL%\vulkan-1.dll" >nul || exit /b 1
set "BADD= vulkan-1.dll"
:bundle_omp
rem torch_cpu.dll can link MSVC's LLVM OpenMP runtime (libomp140), which no VC++ redistributable installs on a
rem user's machine: torch then fails at import ("Error loading shm.dll or one of its dependencies"). Carry it like
rem vulkan-1.dll, from this toolset's redistributable folder (vcvarsall's VCToolsRedistDir), when torch_cpu.dll
rem needs it. No ( ) block around the toolset path: it holds "(x86)"
set "OMPDLL=libomp140.x86_64.dll"
if "%HOSTA%"=="arm64" set "OMPDLL=libomp140.aarch64.dll"
where dumpbin >nul 2>&1 || goto :bundle_omp_find
dumpbin /dependents "%TL%\torch_cpu.dll" | findstr /i /c:"%OMPDLL%" >nul || goto :bundle_omp_done
:bundle_omp_find
set "OMPSRC="
for /d %%d in ("%VCToolsRedistDir%%HOSTA%\Microsoft.VC*.OpenMP.LLVM") do if exist "%%~fd\%OMPDLL%" set "OMPSRC=%%~fd\%OMPDLL%"
if defined OMPSRC goto :bundle_omp_copy
echo [vk-build] ERROR: torch_cpu.dll needs %OMPDLL%, not found in the toolset's redistributable folder %VCToolsRedistDir%%HOSTA%
exit /b 1
:bundle_omp_copy
copy /y "%OMPSRC%" "%TL%\%OMPDLL%" >nul || exit /b 1
set "BADD=%BADD% %OMPDLL%"
:bundle_omp_done
if /i "%BK%"=="cuda" call :bundle_cuda || exit /b 1
if defined BADD goto :bundle_pack
rmdir /s /q "%TB%"
exit /b 0
:bundle_pack
for %%f in ("%WHL%") do set "WHLNAME=%%~nxf"
del /q "%WHL%"
"%PY%" -m wheel pack "%PKGDIR%" -d "%DIST%" >nul || exit /b 1
rmdir /s /q "%TB%"
if not exist "%DIST%\%WHLNAME%" (echo [vk-build] ERROR: repacking %WHLNAME% failed & exit /b 1)
echo [vk-build] bundled%BADD% into %WHLNAME%
exit /b 0
:bundle_cuda
rem cuDNN: torch's install step takes cudnn*.dll from the toolkit's bin\ only, this one has its own folder; all of them,
rem cudnn64_9.dll loads its sub-libraries at run time
if not defined CUDNNDIR goto :bcu_deps
for %%f in ("%CUDNNDIR%\bin\%CPD%\cudnn*.dll" "%CUDNNDIR%\bin\cudnn*.dll") do copy /y "%%~ff" "%TL%\%%~nxf" >nul
if exist "%TL%\cudnn64_*.dll" goto :bcu_cudnn_ok
echo [vk-build] ERROR: no cudnn64_*.dll in %CUDNNDIR%\bin - remove that folder to fetch cuDNN again
exit /b 1
:bcu_cudnn_ok
set "BADD=%BADD% cuDNN"
:bcu_deps
rem then every DLL that a DLL in torch\lib imports, that is not there and that the toolkit has: CUPTI's cupti64 for the
rem profiler, which the redistributable archives keep in lib\x64 / lib\arm64 where torch's install step does not look,
rem and whatever else that step left out; twice, for what those DLLs import in turn
where dumpbin >nul 2>&1 || (echo [vk-build] WARNING: no dumpbin - CUDA DLLs that torch's install step left out are not bundled & exit /b 0)
call :bundle_deps || exit /b 1
call :bundle_deps || exit /b 1
exit /b 0
:bundle_deps
set "DEPS=%TEMP%\vk_deps_%RANDOM%.txt"
type nul > "%DEPS%"
for %%d in ("%TL%\*.dll") do dumpbin /nologo /dependents "%%~fd" >> "%DEPS%"
for /f "usebackq tokens=1" %%n in (`findstr /r /i /c:"^    [^ ]*\.dll" "%DEPS%"`) do call :bundle_dep %%n || exit /b 1
del /q "%DEPS%" 2>nul
exit /b 0
:bundle_dep
if exist "%TL%\%~1" exit /b 0
set "DSRC="
for %%s in ("%CUDADIR%\bin\%CPD%" "%CUDADIR%\bin" "%CUDADIR%\lib\%CPD%") do if not defined DSRC if exist "%%~s\%~1" set "DSRC=%%~s\%~1"
if not defined DSRC exit /b 0
copy /y "%DSRC%" "%TL%\%~1" >nul || exit /b 1
set "BADD=%BADD% %~1"
exit /b 0
:build_torchaudio
setlocal
set "USE_FFMPEG=0"
set "BUILD_SOX=0"
rem cuda: torchaudio's CUDA kernels (lfilter, RNN-T, forced alignment, CTC decoder) through torch.utils.cpp_extension
if /i "%BK%"=="cuda" set "USE_CUDA=1"
set "BUILD_VERSION=%AUDIO%+%SUFFIX%"
call :pip_wheel torchaudio %AUDIO% || (endlocal & exit /b 1)
endlocal & set "WHL=%WHL%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:build_torchcodec
if "%CMODE%"=="skip" (echo [vk-build] skipping torchcodec: no prebuilt FFmpeg for %TARGET%, no local one through pkg-config, and --no-install-ffmpeg - see --help & exit /b 0)
rem torchcodec >= 0.12 builds with scikit-build-core (no build isolation here, so it must be in the venv); btbn also
rem needs a pkg-config, pip's pkgconf
"%PY%" -m pip install -q pybind11 scikit-build-core || exit /b 1
if not "%CMODE%"=="btbn" goto :tc_fresh
call :ffmpeg_btbn || exit /b 1
"%PY%" -m pip install -q pkgconf || exit /b 1
:tc_fresh
rem torchcodec builds in minutes: always configure fresh, a cached CMake keeps the Python and the FFmpeg it found first
if exist "%SRC%\torchcodec\build" rmdir /s /q "%SRC%\torchcodec\build"
setlocal
set "BUILD_VERSION=%CODEC%+%SUFFIX%"
rem torchcodec >= 0.12 also builds image decoders, each one required; audio/video only unless TORCHCODEC_BUILD_IMAGE=1
if not defined TORCHCODEC_BUILD_IMAGE set "TORCHCODEC_BUILD_IMAGE=0"
rem torchcodec's CMake does find_package(pybind11), which never looks inside a pip-installed pybind11
set "pybind11_ROOT="
set "PBOUT=%TEMP%\vk_pybind11_%RANDOM%.txt"
"%PY%" -m pybind11 --cmakedir > "%PBOUT%" 2>nul
set /p pybind11_ROOT=<"%PBOUT%"
del /q "%PBOUT%" 2>nul
if not defined pybind11_ROOT (echo [vk-build] ERROR: pybind11 is not usable in the build venv & endlocal & exit /b 1)
if not defined CMAKE_PREFIX_PATH set "CMAKE_PREFIX_PATH=%pybind11_ROOT%"
if /i not "%CMAKE_PREFIX_PATH%"=="%pybind11_ROOT%" set "CMAKE_PREFIX_PATH=%pybind11_ROOT%;%CMAKE_PREFIX_PATH%"
if "%CMODE%"=="s3" set "BUILD_AGAINST_ALL_FFMPEG_FROM_S3=1"
if "%CMODE%"=="local" set "I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1"
if "%CMODE%"=="local" echo [vk-build] WARNING: torchcodec built against the local FFmpeg - only redistribute it if that FFmpeg is an LGPL build
if not "%CMODE%"=="btbn" goto :tc_build
rem BtbN's LGPL build: its .pc files point at their own folder; torchcodec builds for its FFmpeg major only
set "PKG_CONFIG_PATH=%FFDIR%\lib\pkgconfig"
set "I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1"
echo [vk-build] torchcodec builds against BtbN's LGPL FFmpeg in %FFDIR%, avcodec-%FFAVC% - it needs that major at run time
:tc_build
call :pip_wheel torchcodec %CODEC% || (endlocal & exit /b 1)
endlocal & set "WHL=%WHL%"
call :install_whl || exit /b 1
set "BUILT=%BUILT% %WHL%"
exit /b 0
:probe
rem the ops TTS models use, on the backend's device; vulkan_available / cuda_available False skips them
echo [vk-build] op probe for %TARGET% python %V% - FAIL = op not implemented on the %BK% backend:
set "PROBE=%TEMP%\vk_probe_%RANDOM%.py"
> "%PROBE%" echo(import torch,torch.nn.functional as F
>>"%PROBE%" echo(dev='%BK%'
>>"%PROBE%" echo(ok=torch.is_vulkan_available() if dev=='vulkan' else torch.cuda.is_available() if dev=='cuda' else True
>>"%PROBE%" echo(print('torch',torch.__version__,*([dev+'_available',ok] if dev!='cpu' else []))
>>"%PROBE%" echo(if dev=='cuda' and ok:print('cuda device:',torch.cuda.get_device_name(0),'capability',torch.cuda.get_device_capability(0),'cudnn',torch.backends.cudnn.version())
>>"%PROBE%" echo(cfg=torch.__config__.show()
>>"%PROBE%" echo(blas='MKL' if 'USE_MKL=ON' in cfg else 'APL' if 'blas_info=apl' in cfg.lower() else 'Accelerate' if 'accelerate' in cfg.lower() else 'OpenBLAS' if 'openblas' in cfg.lower() else 'Eigen (slow)' if 'USE_EIGEN_FOR_BLAS=ON' in cfg else 'unknown'
>>"%PROBE%" echo(print('cpu blas:',blas,'- LAPACK' if getattr(torch._C,'has_lapack',False) else '- no LAPACK')
>>"%PROBE%" echo(for mod in ['torchaudio','torchcodec']:
>>"%PROBE%" echo(    try:
>>"%PROBE%" echo(        m=__import__(mod)
>>"%PROBE%" echo(        print(mod,m.__version__)
>>"%PROBE%" echo(    except Exception as e:
>>"%PROBE%" echo(        print(mod,'not available:')
>>"%PROBE%" echo(        for l in str(e).splitlines()[:12]:print('   ',l[:160])
>>"%PROBE%" echo(if ok:
>>"%PROBE%" echo(    x=torch.randn(1,8,64)
>>"%PROBE%" echo(    w=torch.randn(8,8,3) if dev=='vulkan' else torch.randn(8,8,3,device=dev)
>>"%PROBE%" echo(    tests=dict(
>>"%PROBE%" echo(        softmax=lambda:torch.softmax(x.to(dev),-1).cpu(),
>>"%PROBE%" echo(        gelu=lambda:F.gelu(x.to(dev)).cpu(),
>>"%PROBE%" echo(        layer_norm=lambda:F.layer_norm(x.to(dev),[64]).cpu(),
>>"%PROBE%" echo(        matmul=lambda:torch.matmul(torch.randn(64,64).to(dev),torch.randn(64,64).to(dev)).cpu(),
>>"%PROBE%" echo(        conv1d=lambda:F.conv1d(x.to(dev),w).cpu(),
>>"%PROBE%" echo(        stft=lambda:torch.stft(torch.randn(16000).to(dev),n_fft=1024,return_complex=True).cpu(),
>>"%PROBE%" echo(        multinomial=lambda:torch.multinomial(torch.rand(4,100).to(dev),1).cpu(),
>>"%PROBE%" echo(    )
>>"%PROBE%" echo(    if dev!='vulkan':tests['linalg_inv']=lambda:torch.linalg.inv((torch.randn(8,8)+8*torch.eye(8)).to(dev)).cpu()
>>"%PROBE%" echo(    for name,fn in tests.items():
>>"%PROBE%" echo(        try:
>>"%PROBE%" echo(            fn()
>>"%PROBE%" echo(            print(f'  {name:12s} OK')
>>"%PROBE%" echo(        except Exception as e:
>>"%PROBE%" echo(            print(f'  {name:12s} FAIL',str(e).splitlines()[0][:120])
"%PY%" "%PROBE%"
del /q "%PROBE%" 2>nul
exit /b 0
