@echo off
rem build-torch-vulkan.cmd - torch/torchaudio/torchcodec wheels with the PyTorch Vulkan backend for Windows x64 / arm64.
rem Run it from the Visual Studio "x64 Native Tools" or "ARM64 Native Tools" command prompt, on a machine of that architecture.
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
set "LIST=0"
:args
if "%~1"=="" goto :args_done
if /i "%~1"=="-l" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--list" (set "LIST=1" & shift & goto :args)
if /i "%~1"=="--clean" (set "CLEAN=1" & shift & goto :args)
if /i "%~1"=="--no-bundle" (set "NO_BUNDLE=1" & shift & goto :args)
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
call :missing
call :codec_mode
if not "%LIST%"=="1" goto :build
echo targets on this Windows-%HOSTA% machine:
if defined MISS (echo   %TARGET%   missing:%MISS:~0,-1% - see --help & exit /b 0)
set "NOTE="
call :want torchcodec && if "%CMODE%"=="skip" set "NOTE= - torchcodec skipped: no local FFmpeg"
echo   %TARGET%   ready%NOTE%
exit /b 0
:build
if defined MISS (echo [vk-build] ERROR: %TARGET%: missing:%MISS:~0,-1% - see --help & exit /b 1)
where uv >nul 2>&1 && goto :have_uv
echo [vk-build] installing uv
powershell -NoProfile -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex" || (echo [vk-build] ERROR: uv install failed & exit /b 1)
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
:have_uv
if not exist "%ROOT%" mkdir "%ROOT%"
for %%r in ("%ROOT%") do set "ROOT=%%~fr"
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
echo   -h, --help
echo Output
echo   ROOT\dist\TARGET\PKG-VER+SUFFIX-cpXY-cpXY-win_amd64.whl or win_arm64.whl, sources in ROOT\src-TARGET
echo   Each build ends with a probe of the Vulkan ops TTS models use.
echo Needs
echo   the Visual Studio "x64 Native Tools" or "ARM64 Native Tools" prompt matching this machine, git,
echo   the LunarG Vulkan SDK - VULKAN_SDK set by its installer, network access; uv is installed if missing
echo   windows-arm64-vulkan torchcodec: a shared LGPL FFmpeg with its .pc files on PKG_CONFIG_PATH, and pkg-config
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
if not defined VSCMD_ARG_TGT_ARCH set "MISS=%MISS% the Visual Studio Native Tools prompt,"
where cl >nul 2>&1 || set "MISS=%MISS% cl.exe - Visual Studio C++ tools,"
if defined VSCMD_ARG_TGT_ARCH if /i not "%VSCMD_ARG_TGT_ARCH%"=="%HOSTA%" set "MISS=%MISS% a %HOSTA% Native Tools prompt - this one targets %VSCMD_ARG_TGT_ARCH%,"
where git >nul 2>&1 || set "MISS=%MISS% git,"
set "LOADER=no"
if not defined VULKAN_SDK goto :miss_nosdk
if not exist "%VULKAN_SDK%\Include\vulkan\vulkan.h" set "MISS=%MISS% vulkan.h in %VULKAN_SDK%\Include,"
if not exist "%VULKAN_SDK%\Bin\glslc.exe" set "MISS=%MISS% glslc.exe in %VULKAN_SDK%\Bin,"
if not exist "%VULKAN_SDK%\Lib\vulkan-1.lib" set "MISS=%MISS% vulkan-1.lib in %VULKAN_SDK%\Lib,"
goto :miss_loader
:miss_nosdk
set "MISS=%MISS% the LunarG Vulkan SDK - VULKAN_SDK is not set,"
:miss_loader
if "%NO_BUNDLE%"=="1" goto :miss_codec
if defined VULKAN_SDK if exist "%VULKAN_SDK%\Bin\vulkan-1.dll" set "LOADER=%VULKAN_SDK%\Bin\vulkan-1.dll"
if "%LOADER%"=="no" if exist "%SystemRoot%\System32\vulkan-1.dll" set "LOADER=%SystemRoot%\System32\vulkan-1.dll"
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
call :probe
set "CLEANNOW=1"
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
call :install_whl || exit /b 1
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
