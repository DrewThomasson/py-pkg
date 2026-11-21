# build-torch-vulkan

Builds **torch**, **torchaudio** and **torchcodec** wheels with PyTorch's Vulkan backend for Linux, macOS and Windows, on x86_64 and arm64/aarch64. On Windows, x64 and arm64, the `.cmd` also builds CPU-only and CUDA wheels (`--backend`).

| Script | Runs on | Builds |
|---|---|---|
| `build-torch-vulkan.sh` | Linux, macOS (bash 3.2+, so macOS's stock `/bin/bash` works) | Linux wheels in manylinux_2_28 Docker containers, macOS wheels natively |
| `build-torch-vulkan.cmd` | Windows 10/11, any command prompt | Windows wheels natively with MSVC: `vulkan`, `cpu` and `cuda` backends |

Both scripts take the same options, keep their state under one root folder, and end every build with an **op probe**. The probe runs the operations TTS models need on the Vulkan device and reports `OK`/`FAIL` for each.

## Before you start: what PyTorch's Vulkan backend can do

The Vulkan backend (`USE_VULKAN`) is PyTorch's old mobile backend. It is fp32, inference-only, no longer maintained, and was written for Android CNN inference. It has three limitations:

- **No automatic device selection.** You move tensors to it explicitly with `.vulkan()`. Code that doesn't do this keeps running on the CPU.
- **Narrow operator coverage, and no CPU fallback.** An unsupported op raises an exception. Ops such as `stft` and `multinomial` are missing, and so is most of the sampling stack TTS models use.
- **torchaudio and torchcodec have no Vulkan backend at all.** They are built against the Vulkan torch only so the binaries match.

The op probe at the end of each build shows what works on a given GPU. Treat these wheels as an experiment or for targeted use, not as a drop-in GPU backend.

## Targets

| Target | Host | How |
|---|---|---|
| `linux-x86_64-vulkan` | Linux x86_64 | manylinux_2_28 container |
| `linux-aarch64-vulkan` | Linux aarch64 | manylinux_2_28 container |
| `linux-aarch64-vulkan-qemu` | Linux x86_64 | manylinux_2_28 aarch64 container under QEMU, roughly 10–20× slower (a day or more); built only when named with `--only` |
| `macos-x86_64-vulkan` | Intel Mac | native, Vulkan through MoltenVK. PyTorch's last official Intel macOS wheel is 2.2.2, so this build is the only current torch there |
| `macos-arm64-vulkan` | Apple Silicon Mac | native, Vulkan through MoltenVK; MPS stays enabled too |
| `windows-x64-vulkan` | Windows x64 | native, MSVC |
| `windows-arm64-vulkan` | Windows on ARM | native, MSVC |
| `windows-x64-cpu`, `windows-arm64-cpu` | Windows x64 / on ARM | native, MSVC, CPU only (`--backend cpu`) |
| `windows-x64-cuda`, `windows-arm64-cuda` | Windows x64 / on ARM | native, MSVC + nvcc, CUDA and cuDNN bundled (`--backend cuda`); arm64 needs CUDA 13.4.1 or newer |

Builds are native only, with no cross-compiling. Torch's build compiles helper programs and runs them, and the wheel has to match the Python that builds it. QEMU emulation is the only exception.

`--list` shows which targets this machine can build and what's missing for the others. On Windows it lists all three backends.

## Quick start

### Linux

```
chmod +x build-torch-vulkan.sh
./build-torch-vulkan.sh --list
./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0
```

You need Docker and network access. Docker runs directly as root, or through `sudo` otherwise. Everything else is built inside the container. The Vulkan headers, loader and `glslc` are compiled once per architecture and cached.

### macOS

```
chmod +x build-torch-vulkan.sh
./build-torch-vulkan.sh --list
./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0
```

**Apple Silicon: run it from a native arm64 terminal.** The script stops when its shell runs under Rosetta, because the build would target x86_64 instead of arm64. Check with `uname -m`: it must print `arm64`. If it prints `x86_64`, open Terminal's Get Info in Finder (Applications → Utilities → Terminal) and untick "Open using Rosetta", or start a native shell with `arch -arm64 /bin/zsh`. Homebrew must be the native one in `/opt/homebrew` too.

You need the Xcode Command Line Tools (`xcode-select --install`), git and curl. When none is found in `~/VulkanSDK`, the script installs the LunarG Vulkan SDK there, checksum-verified. The SDK brings MoltenVK, the loader and `glslc`.

- **Intel Mac:** torchcodec needs a local FFmpeg it supports. With Homebrew present, the script installs one itself (see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg)); `--no-install-ffmpeg` turns that off.
- **Optional:** `brew install libomp` gives torch multi-threaded CPU ops.

### Windows

```
build-torch-vulkan.cmd --list
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0
```

Any command prompt works. The script finds Visual Studio 2022, or its Build Tools, with `vswhere` and loads the C++ environment for this machine itself. If they aren't installed, add `--install-buildtools`, which installs them through winget; it needs several GB and shows a UAC prompt. The LunarG Vulkan SDK is installed into `%LOCALAPPDATA%\VulkanSDK` when missing.

Keep the tree short, because torch's sources and build paths go past Windows' 260-character limit:

```
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --root=D:\ptv
```

Also enable long paths once, from an admin prompt. The script warns when they're off.

```
reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f
```

Other backends, one or several per run, each a full torch build with its own `src-<target>` and `dist\<target>` folders:

```
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --backend="vulkan cpu"
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --backend=cuda
```

See [Windows on ARM](#windows-on-arm) and [The CUDA backend](#the-cuda-backend-windows).

## Options

The two scripts share every option, except those marked `.sh` only or `.cmd` only. Each option can also be set with the environment variable in brackets. Options taking a value accept both `--option=VALUE` and `--option VALUE`.

**torch and torchcodec have no built-in version: name them on every run.** `--torch` is always required, because torchaudio and torchcodec build against that torch wheel. `--torchcodec` is required whenever torchcodec is in `--pkgs`. `--list` and `--help` need neither.

| Option | Env | Default | Meaning |
|---|---|---|---|
| `-l`, `--list` | | | Show what this machine can build now, and the GPU status where the install job is on (Windows: also the NVIDIA GPU, if any) |
| `--only "T1 T2"` | `ONLY` | all ready targets | Build only these targets (`.sh` only) |
| `--backend "vulkan cpu"` | `BACKENDS` | `vulkan` | Backends to build: `vulkan`, `cpu`, `cuda`; each one is a full torch build (`.cmd` only) |
| `--pkgs "torch ..."` | `PKGS` | `torch torchaudio torchcodec` | Packages to build |
| `--torch=VER` | `TORCH` | required | torch version to build (git tag `v<VER>`), e.g. `2.14.1`; the Vulkan backend is still in the tree in 2.15.0 |
| `--torchaudio=VER` | `AUDIO` | `2.11.0` | torchaudio version; 2.11.0 is the last release and, being built on torch's stable ABI, works with every torch from 2.11 on |
| `--torchcodec=VER` | `CODEC` | required with torchcodec | torchcodec version to build, e.g. `0.17.0`; 0.12 and later work with every torch from 2.11 on |
| `--py "3.11 3.12"` | `PYS` | `3.12` | Python versions; each one is a full torch build. Windows on ARM: 3.11 or newer |
| `--suffix TAG` | `SUFFIX` | the backend | Local version tag: `2.14.1+vulkan`; the `.cmd` defaults to `vulkan`, `cpu`, or `cu<major><minor>` for CUDA (`cu134`) |
| `--root DIR` | `ROOT` | `./pytorch-vulkan` | Sources, tools, venvs and wheels |
| `--jobs N` | `JOBS` | CPU threads, capped by RAM | Parallel compile jobs: about 2 GB of RAM each; on Windows (RAM − 8 GB kept for linking) ÷ 3 GB per MSVC job |
| `--clean` | `CLEAN=1` | | Reset and `git clean` the checkouts first |
| `--force` | `FORCE=1` | | Rebuild a package even when its wheel for this version, suffix and Python is already in `dist/`. By default such a package is skipped entirely, with no sync and no build, and its wheel is installed into the build venv for the packages after it |
| `--codec-ffmpeg MODE` | `CODEC_FFMPEG` | `auto` | Where torchcodec's FFmpeg comes from, see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg) |
| `--no-bundle` | `NO_BUNDLE=1` | | Don't put the Vulkan loader (macOS: plus MoltenVK) into the torch wheel |
| `--no-install-sdk` | `INSTALL_SDK=0` | installs it | Don't install the LunarG SDK when it's missing (macOS, Windows) |
| `--no-install-ffmpeg` | `INSTALL_FFMPEG=0` | installs it | macOS: don't install a Homebrew `ffmpeg@N` keg for the torchcodec build. Windows: don't fetch an FFmpeg for torchcodec, neither to build against on arm64 nor to run with |
| `--cuda X.Y.Z` | `CUDA_VER` | `13.4.3` | CUDA release for `cuda`, from NVIDIA's redistributable archives; Windows on ARM needs 13.4.1 or newer (`.cmd` only) |
| `--cudnn VER` | `CUDNN_VER` | `9.28.1` | cuDNN release for `cuda`, `0` for none (`.cmd` only) |
| `--cuda-arch "LIST"` | `CUDA_ARCH` | `auto` | `TORCH_CUDA_ARCH_LIST`, e.g. `"8.6;12.0"`, quoted. `auto`: the compute capabilities of this machine's NVIDIA GPUs, else `7.5;8.0;8.6;9.0;10.0;12.0` like the official CUDA 13 wheels (`.cmd` only) |
| `--apl VER` | `APL_VER` | `24.10` | Arm Performance Libraries for BLAS and LAPACK on Windows on ARM, `0` for none (`.cmd` only) |
| `--install-vulkan` | `INSTALL_VK=1` | arm64 hosts only | Run the [Vulkan install job](#vulkan-install-job) on any host |
| `--no-install-vulkan` | `INSTALL_VK=0` | | Never run it |
| `--macos-min X.Y` | `MACOS_MIN` | `11.0` | Oldest macOS the wheels run on (`.sh` only) |
| `--keep-images` | `KEEP_IMAGES=1` | removed | Keep the Docker images this run pulled (`.sh` only) |
| `--install-buildtools` | `INSTALL_BT=1` | | Install Visual Studio 2022 Build Tools with C++ through winget (`.cmd` only) |
| `-h`, `--help` | | | Full help |

### Examples

```
./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --py="3.10 3.12" --jobs=8
./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --only=linux-aarch64-vulkan-qemu --jobs=16
./build-torch-vulkan.sh --torch=2.14.1 --pkgs=torch                                   # torch only
./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --pkgs="torchaudio torchcodec"   # reuse the torch wheel in dist/
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --root=D:\ptv --jobs=12
build-torch-vulkan.cmd --torch=2.14.1 --torchcodec=0.17.0 --root=D:\ptv --backend="vulkan cpu cuda"
```

## What a run does

1. **Checks the host.**
   - **Linux:** Docker, plus QEMU for the `-qemu` target.
   - **macOS:** Xcode Command Line Tools and the SDK. It refuses to run under Rosetta.
   - **Windows:** Visual Studio, matched to this machine's architecture, git, and per backend the SDK (`vulkan`) or a CUDA release NVIDIA ships for this architecture (`cuda`: 13.4.1 or newer on arm64).
   - **Selection:** ready targets build. Targets with something missing are skipped, with the reason. A target named with `--only` that can't build stops the run.
2. **Prepares the toolchain.**
   - **Linux:** inside each container it builds the Vulkan headers, loader and `glslc` once per architecture into `<root>/tools/<arch>`.
   - **macOS and Windows:** it uses the LunarG SDK, installing it if missing.
   - **Windows `cuda`:** it downloads CUDA and cuDNN into `<root>\tools` (see [The CUDA backend](#the-cuda-backend-windows)).
   - **Windows on ARM:** it unpacks Arm Performance Libraries into `<root>\tools` (see [Windows on ARM](#windows-on-arm)).
   - **Python:** uv provides it, installed if missing. On Linux it comes from the manylinux image's `/opt/python`.
3. **Syncs the sources.** It clones or updates pytorch, audio and torchcodec in `<root>/src-<target>` and checks out the `v<version>` tags with all submodules. On Windows, git's long-path support is switched on for every repository.
4. **Builds torch** with `USE_VULKAN=1`, CUDA/ROCm/XPU off, and the version set to `<ver>+<suffix>`; on Windows `cpu` leaves Vulkan off too, and `cuda` turns CUDA on. For `vulkan` it first checks that the torch tag still contains the Vulkan backend. On x86_64 it installs pip's `mkl-static` and `mkl-include` first, so torch uses MKL for BLAS and FFT like the official wheels; without it, torch falls back to Eigen's BLAS and its CPU matrix multiplies are much slower. Apple Silicon uses Accelerate, Windows on ARM Arm Performance Libraries, which also bring LAPACK. The probe prints which one a wheel uses (`cpu blas: ...`).
5. **Bundles the Vulkan loader** into the torch wheel (see [Vulkan loader bundling](#vulkan-loader-bundling)); Windows `cuda` bundles cuDNN and the CUDA DLLs instead. On Linux the wheels are then retagged `manylinux_2_28_<arch>`.
6. **Builds torchaudio, then torchcodec,** against the new torch, then installs each wheel into the build venv.
7. **Runs the op probe** for each Python version.
8. **Runs the Vulkan install job** where enabled (see [Vulkan install job](#vulkan-install-job)). On Linux this ends with a second probe on the host's own GPU.

Checkouts and build trees are kept, so a rerun after a failure picks up where it stopped. Packages whose wheel is already in `dist/` are skipped. A torch build tree from another torch version, or for Windows `cuda` another CUDA release, is detected (`build/.vk_tag`) and started over automatically.

## Output

```
<root>/
  dist/<target>/
    torch-2.14.1+vulkan-cp312-cp312-manylinux_2_28_x86_64.whl    (Linux)
    torch-2.14.1+vulkan-cp312-cp312-macosx_11_0_arm64.whl        (macOS)
    torch-2.14.1+vulkan-cp312-cp312-win_amd64.whl                (Windows x64)
    torch-2.14.1+vulkan-cp312-cp312-win_arm64.whl                (Windows on ARM)
    torchaudio-2.11.0+vulkan-...whl
    torchcodec-0.17.0+vulkan-...whl
  src-<target>/{torch,torchaudio,torchcodec}    git checkouts and build trees
  venv-<target>-<python>/                       build venv, with the fresh wheels installed
  tools/<arch>/                                 Linux: Vulkan headers + loader, glslc
  tools/vulkanrt-<arch>/                        Windows: vulkan-1.dll fetched for bundling, if needed
  tools/ffmpeg-<arch>/                          Windows: the FFmpeg torchcodec runs with, and on arm64 builds against
  tools/apl-<ver>/                              Windows on ARM: Arm Performance Libraries
  tools/cuda-<ver>-<arch>/, tools/cudnn-...     Windows cuda: the CUDA toolkit and cuDNN
```

The Windows `cpu` and `cuda` backends land beside it in `dist\windows-<arch>-cpu` and `dist\windows-<arch>-cuda`, as `torch-2.14.1+cpu-...` and `torch-2.14.1+cu134-...`.

Install the wheels with `pip install torch-2.14.1+vulkan-...whl torchaudio-...whl torchcodec-...whl`.

## Windows on ARM

`build-torch-vulkan.cmd` builds all three backends natively on a Windows on ARM machine, with Visual Studio's ARM64 MSVC. PyTorch itself publishes CPU-only `win_arm64` torch wheels (download.pytorch.org, Python 3.11–3.13), but no torchaudio or torchcodec for Windows on ARM and no CUDA build. This script builds all three packages, for every backend.

- **Python 3.11 or newer.** Wheels must be built by a native arm64 Python: an emulated x64 one would produce `win_amd64` wheels around arm64 code. The script asks uv for `cpython-<ver>-windows-aarch64-none` and checks every build venv's platform; uv has those builds from 3.11 on.
- **BLAS and LAPACK** come from Arm Performance Libraries 24.10 (`--apl`), the release PyTorch's own `win_arm64` wheels use. Arm's MSI is unpacked into `<root>\tools\apl-<ver>` with an administrative install (`msiexec /a`): files only, no admin rights, nothing registered. torch links `armpl_lp64.dll` and carries it in `torch\lib`. Without it torch falls back to Eigen's slow BLAS and has no LAPACK, so no `torch.linalg`; `--apl 0` builds that way on purpose.
- **torchcodec** builds against BtbN's LGPL `winarm64` FFmpeg (`btbn`, see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg)), unless `pkg-config` finds a local FFmpeg. The wheel then needs that FFmpeg major at runtime; the probe uses the fetched build.
- **Vulkan** compiles for arm64 like for x64: the backend has no x86-specific code, and the LunarG `warm` SDK brings `glslc` and the loader. Whether it runs depends on the driver. Snapdragon X has a native Qualcomm Vulkan driver; older Snapdragons only get Vulkan through Microsoft's *OpenCL, OpenGL, and Vulkan Compatibility Pack*, which translates to Direct3D 12 and may lack what PyTorch's Vulkan backend needs. The probe tells. Where it falls short, use `--backend cpu`.
- **CUDA** needs CUDA 13.4.1 or newer, the first release NVIDIA ships for Windows on ARM; see the next section.

## The CUDA backend (Windows)

`--backend cuda` builds torch with CUDA and cuDNN on Windows x64 and Windows on ARM.

- **Toolkit.** CUDA (`--cuda`, default 13.4.3) comes from NVIDIA's redistributable archives: the compiler, runtime, CCCL headers, cuBLAS, cuFFT, cuRAND, cuSOLVER, cuSPARSE, nvJitLink, NVRTC, NVTX, CUPTI and NVML headers, each checked against the sha256 in `redistrib_<ver>.json` and merged into `<root>\tools\cuda-<ver>-<arch>`, about 2 GB. cuDNN (`--cudnn`, default 9.28.1) goes into its own folder, without its static libraries, about 1 GB. No installer, no driver, no admin rights; several CUDA releases can sit side by side.
- **arm64 folder names.** NVIDIA's Windows on ARM CUDA keeps its libraries in `lib\arm64` and DLLs in `bin\arm64`. torch's own CMake modules, its install step and `torch.utils.cpp_extension` (torchaudio's build) only know `lib\x64` and `bin\x64`, so the downloaded toolkit gets `lib\x64` and `bin\x64` junctions to them.
- **Architectures.** `--cuda-arch auto` builds for the NVIDIA GPUs of the build machine (`nvidia-smi`). Without one it takes PyTorch's CUDA 13 list, `7.5;8.0;8.6;9.0;10.0;12.0`; each architecture adds hours. `12.0` code also runs on 12.1 GPUs.
- **Bundled.** torch's install step puts the CUDA DLLs into `torch\lib`; the script adds cuDNN and every toolkit DLL a `torch\lib` DLL imports that is still missing (CUPTI's, for one). Users need only the NVIDIA driver.
- **torchaudio** is built with its CUDA kernels. **torchcodec** stays CPU-only (`ENABLE_CUDA=0`): NVDEC decoding would need an FFmpeg built with CUDA.
- **Left out:** NCCL (none on Windows), MAGMA, cuSPARSELt, cuDSS. `USE_*` variables you set reach torch's CMake, e.g. `set USE_FLASH_ATTENTION=0` drops the longest and most memory-hungry part of the build.
- **Visual Studio.** nvcc refuses a Visual Studio newer than its CUDA release supports; `set NVCC_ALLOW_UNSUPPORTED=1` passes `-allow-unsupported-compiler` to every nvcc run.

Building needs no GPU. On Windows on ARM this is a build PyTorch itself doesn't make, so the first runs will tell how far torch's CUDA code goes with ARM64 MSVC as nvcc's host compiler.

## Vulkan loader bundling

On desktop systems torch links the Vulkan loader directly; only Android builds load it at runtime. A plain build would therefore fail to `import torch` on any machine without a loader. The scripts put a loader into the torch wheel instead:

| OS | Bundled into `torch/lib` | How it is found |
|---|---|---|
| Linux | `libvulkan.so.1`, built in the container against glibc 2.28 | `$ORIGIN` added to RUNPATH where missing |
| macOS | `libvulkan.1.dylib`, `libMoltenVK.dylib`, `MoltenVK_icd.json` | dylibs relinked to `@rpath`, re-signed ad hoc; a small hook in `torch/__init__.py` points `VK_DRIVER_FILES` at the bundled MoltenVK unless you set it yourself |
| Windows | `vulkan-1.dll`, from the SDK, LunarG's runtime package or System32 | torch loads every DLL in `torch\lib` at import |

With the loader bundled, `import torch` works everywhere. `torch.is_vulkan_available()` is `True` only where a GPU driver provides Vulkan. Use `--no-bundle` to rely on the system loader instead.

## torchcodec and torch versions

Up to 0.11, each torchcodec release worked with exactly one torch release (0.11 ↔ 2.11, 0.10 ↔ 2.10, ...). Since 0.12, torchcodec uses PyTorch's stable ABI from torch 2.11 on: one torchcodec build works with torch 2.11 and every later release. Consequences:

- **The `+vulkan` torch wheels can use the official torchcodec from PyPI** (0.17: Linux x86_64/aarch64, macOS 14+ arm64, Windows x64). Building torchcodec yourself is only needed where PyPI has no wheel: Intel Macs, Windows on ARM, and macOS arm64 older than 14.
- **A torchcodec built here is not tied to the Vulkan torch.** It carries the `+vulkan` suffix only because it comes out of the same run.
- **torch older than 2.11** (e.g. Jetson builds of 2.3 / 2.8 / 2.9) still needs the torchcodec of its own era: 0.9.x for 2.9, 0.7 for 2.8, none for 2.3.
- **Image decoders:** 0.12+ also builds image decoders, each requiring its library (libjpeg, libpng, libwebp, libavif, libheif, ...). The scripts build audio/video only (`TORCHCODEC_BUILD_IMAGE=0`); set `TORCHCODEC_BUILD_IMAGE=1` with those libraries installed to include them.

## torchcodec and FFmpeg

torchcodec links against FFmpeg at build time. `--codec-ffmpeg` picks the source:

| Mode | What it does |
|---|---|
| `s3` | PyTorch's prebuilt LGPL FFmpeg builds, every major the torchcodec version supports (4–9 for 0.17), like the official wheels. These exist for Linux x86_64/aarch64, macOS arm64 and Windows x64 only |
| `btbn` | BtbN's LGPL shared build (FFmpeg 9.0, else 8.1, the newest the torchcodec checkout accepts), fetched into `<root>\tools\ffmpeg-<arch>`; it ships MSVC import libraries and `.pc` files relative to their own folder, so torchcodec builds against it through pip's `pkgconf`. Windows x64 and arm64 (`.cmd` only) |
| `local` | The FFmpeg that `pkg-config` finds. The wheel is only redistributable if that FFmpeg is an LGPL build (no `--enable-gpl` / `--enable-nonfree`) |
| `auto` | `s3` where it exists, else `local` if found; on Windows on ARM then `btbn`; elsewhere torchcodec is skipped with a note |

`s3` builds a `libtorchcodec_core<N>` for every FFmpeg major, `btbn` and `local` only for the major they build against, which is then the one torchcodec needs at runtime.

In `local` mode the script accepts only the FFmpeg majors the torchcodec checkout lists (4–9 for 0.17, 4–8 for 0.11). If the default FFmpeg is newer, it tries Homebrew's keg-only `ffmpeg@N` kegs and uses the newest supported one.

So on an Intel Mac, `auto` needs a local FFmpeg, and on Windows on ARM it fetches one:

- **Intel Mac:** installed automatically when none fits. The script reads the FFmpeg majors torchcodec lists and installs Homebrew's keg-only `ffmpeg@N` from the newest down, checking each one's `libavcodec`. A keg torchcodec rejects is removed again, and a keg that was already installed is never touched. With torchcodec 0.17, Homebrew's plain `ffmpeg` (FFmpeg 9, `libavcodec` 63) is accepted directly, so nothing is installed; with 0.11 it lands on `ffmpeg@8`. The wheel links that FFmpeg by absolute path, so users need the same Homebrew FFmpeg at runtime
- **Windows on ARM:** a shared FFmpeg that `pkg-config` finds, else BtbN's LGPL `winarm64` build (`btbn`); `--no-install-ffmpeg` without a local one skips torchcodec

### FFmpeg at runtime

The build-time FFmpeg is not shipped in the wheel. Wherever the torchcodec wheel is used, it needs an FFmpeg of a major it supports: `libavcodec` 58 to 63, i.e. FFmpeg 4 to 9, for 0.17 (58 to 62, FFmpeg 4 to 8, for 0.11).

| OS | How torchcodec finds it | What the scripts do for the probe |
|---|---|---|
| Windows | the folder of the first `ffmpeg.exe` on `PATH` must hold the shared DLLs (`avcodec-NN.dll`, ...) | use the `ffmpeg.exe` on `PATH` if it fits; else fetch BtbN's LGPL shared build (9.0, 8.1; x64 and arm64), else Gyan.dev's versioned shared build (8.0.1 down to 7.1; x64, GPL), into `<root>\tools\ffmpeg-<arch>`, and put it on `PATH`. Each candidate is checked by its `avcodec-NN.dll`; `--no-install-ffmpeg` turns this off. A `btbn` torchcodec takes the BtbN build it was built against, ahead of `PATH`. Fetched builds are never bundled |
| macOS | the Homebrew keg it was built against, by absolute path (`/usr/local/opt/ffmpeg@8/lib` on Intel) | the keg installed for the build stays installed; users need the same `brew install ffmpeg@8` |
| Linux | the system's shared FFmpeg (`libavcodec.so.58` to `.62`) | nothing; install your distribution's FFmpeg libraries |

BtbN's rolling `latest` release only keeps its two newest release branches (today 8.1 and 9.0), so the Gyan.dev fallback covers the day 8.x drops out of it.

## Vulkan install job

Building needs only the SDK; the GPU never comes into it. The install job covers the runtime side instead. It's on by default on arm64/aarch64 hosts; use `--install-vulkan` or `--no-install-vulkan` to change that.

**Linux.** The job identifies the GPU from its kernel driver:

| GPU | Vulkan driver | Packages installed |
|---|---|---|
| NVIDIA Jetson (L4T) | ships with JetPack | loader + `vulkaninfo` |
| Raspberry Pi 4/5 (`v3d`) | Mesa V3DV | loader + `vulkaninfo` + Mesa |
| Arm Mali (`panfrost`, `panthor`) | Mesa PanVK, needs a recent Mesa | loader + `vulkaninfo` + Mesa |
| Qualcomm Adreno (`msm`) | Mesa Turnip | loader + `vulkaninfo` + Mesa |
| AMD (`amdgpu`) | Mesa RADV | loader + `vulkaninfo` + Mesa |
| NVIDIA (`nouveau`) | Mesa NVK, Turing or newer, Mesa 24.1+ | loader + `vulkaninfo` + Mesa |
| NVIDIA (proprietary) | ships with the driver | loader + `vulkaninfo` |
| Intel (`i915`, `xe`) | Mesa ANV | loader + `vulkaninfo` + Mesa |
| Pi 3 (`vc4`), Mali-400 (`lima`), Vivante (`etnaviv`), none | no Vulkan driver exists | nothing; the host probe is skipped |

Packages come from apt, dnf or pacman, through `sudo` when not root. `vulkaninfo` then confirms that a real device is listed, not the llvmpipe software fallback. After the container build, the new wheels are installed into a host venv and probed on the actual GPU.

**macOS.** The job reports whether the GPU supports Metal, which MoltenVK needs. Every Apple Silicon Mac does.

**Windows.** The job looks for a Vulkan driver in the registry, then confirms with the SDK's `vulkaninfoSDK`. Without a driver the wheels still build, the probe shows `vulkan_available False`, and the job prints a hint:

- **Snapdragon X:** update the Qualcomm graphics driver.
- **Older Snapdragons:** install Microsoft's *OpenCL, OpenGL, and Vulkan Compatibility Pack* from the Microsoft Store.
- **Other GPUs:** install the vendor driver.

## The op probe

Each build ends with:

```
torch 2.14.1+vulkan vulkan_available True
torchaudio 2.11.0+vulkan
torchcodec 0.17.0+vulkan
  softmax      OK
  gelu         OK
  layer_norm   OK
  matmul       OK
  conv1d       OK
  stft         FAIL ...
  multinomial  FAIL ...
```

These lines show the expected format, not results from a real run. The first `FAIL` among the ops a model uses tells you whether that model can run on Vulkan at all. `vulkan_available False` means no usable Vulkan device on that machine, and the op lines are then skipped.

On Windows `cpu` and `cuda` the probe runs the same ops on `cpu` / `cuda`, plus `linalg_inv`, which needs LAPACK; `cuda` prints `cuda_available`, the device, its compute capability and the cuDNN version first. The `cpu blas:` line also says whether the wheel has LAPACK.

## Upstream workarounds applied automatically

Each one is applied only where needed. Where a source file is patched, it is restored after the build, so the checkouts stay clean.

| Problem | Where | Workaround |
|---|---|---|
| Submodule files longer than 260 characters | Windows | `git -c core.longpaths=true` before `clone`, so it also reaches the submodules; saved in every repository's config |
| `vswhere` path contains `(x86)` | Windows | run outside any `( )` block, read back through a temp file |
| `M_SQRT2` / `M_2_SQRTPI` undeclared in `vulkan/ops/Clamp.cpp` | Windows (MSVC) | `#define _USE_MATH_DEFINES` added as line 1 for the build |
| `find_package(pybind11)` can't see pip's pybind11 | all | `pybind11_ROOT` and `CMAKE_PREFIX_PATH` set from `python -m pybind11 --cmakedir` |
| A rerun of torchcodec still uses the Python / FFmpeg of a failed run (CMake and `pkg_check_modules` cache them) | all | torchcodec's build directory is removed before each build; it configures fresh in seconds |
| CMake picks another Python (e.g. Homebrew's framework 3.14) instead of the build venv's | all | `VIRTUAL_ENV` exported for the build venv; CMake's FindPython checks it first |
| `Unsupported libavcodec version` (FFmpeg newer than torchcodec supports) | `local` mode | supported majors read from the checkout; Homebrew `ffmpeg@N` kegs tried |
| torchcodec linked the build machine's `libpython` by absolute path | macOS | `Development.Module` plus `-undefined dynamic_lookup`: Python symbols come from the running interpreter |
| torch built from source has no BLAS library and falls back to Eigen's (`USE_MKL=OFF, USE_EIGEN_FOR_BLAS=ON`) | x86_64 | pip's `mkl-static`/`mkl-include` installed into the build venv, its prefix on `CMAKE_PREFIX_PATH` (`<venv>\Library` on Windows); Linux links MKL's GNU-OpenMP threading like torch, Windows and macOS the sequential MKL so no Intel OpenMP runtime is needed. The first build with MKL reconfigures and recompiles much of ATen |
| torch dylibs keep an rpath into the Vulkan SDK, so the SDK's loader shadows the bundled one | macOS | rpaths into `$VULKAN_SDK` are deleted during bundling, then the dylibs are re-signed |
| `Python3_LIBRARY` NOTFOUND: manylinux Pythons ship no `libpython`, on purpose | Linux | torchcodec's `find_package(Python3 ... Development ...)` switched to `Development.Module` for the build (0.17 itself already avoids linking libpython through `pybind11::module`) |
| torchcodec 0.12+ builds with scikit-build-core and requires its image-decoder libraries | all | `scikit-build-core` installed into the build venv; `TORCHCODEC_BUILD_IMAGE=0` by default |
| torchcodec refuses to build against a local FFmpeg | `local` mode | `I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1`, with the LGPL warning printed |
| Linking `torch_cpu` runs out of memory next to parallel compiles | all | links run one at a time (CMake job pool `vk_link=1`); a tree configured before this is reconfigured once, and compiled objects are kept |
| torch 2.14 builds with scikit-build-core, which no longer reads `CMAKE_FRESH` | Windows | a reconfigure (link pool, switching to MKL / APL) removes `build\CMakeCache.txt` as well as setting `CMAKE_FRESH=1` for older torch |
| uv may give an emulated x64 Python on Windows on ARM, whose wheels come out `win_amd64` around arm64 code | Windows arm64 | uv is asked for `cpython-<ver>-windows-aarch64-none`, and every build venv's `sysconfig.get_platform()` must match the machine |
| torch's `requirements.txt` lists `lintrunner`, which has no `win_arm64` wheel and needs Rust to build | Windows | installed without it; it is a linter, not a build dependency |
| No BLAS or LAPACK on Windows on ARM: Eigen's slow BLAS, no `torch.linalg` | Windows arm64 | Arm Performance Libraries, as in PyTorch's own `win_arm64` wheels: `BLAS=APL`, `ARMPL_DIR`; Arm's MSI unpacked with `msiexec /a`, no admin rights; torch's FindAPL puts `armpl_lp64.dll` into `torch\lib` |
| PyTorch has no S3 FFmpeg for Windows on ARM, so torchcodec was skipped | Windows arm64 | `btbn`: BtbN's LGPL `winarm64` shared build, MSVC import libraries and relocatable `.pc` files, pip's `pkgconf` as `pkg-config` |
| torch's FindCUDAToolkit, its install step and `cpp_extension` know only `lib\x64` / `bin\x64`; the Windows arm64 CUDA has `lib\arm64` / `bin\arm64` | Windows arm64 `cuda` | `lib\x64` and `bin\x64` junctions to them in the downloaded toolkit, copies where junctions fail |
| torch's install step takes cuDNN DLLs from the toolkit's `bin\` only, CUPTI's from `extras\CUPTI` only; the redistributable archives have neither | Windows `cuda` | cuDNN's DLLs copied into `torch\lib`, then every DLL a `torch\lib` DLL imports that the toolkit has (`dumpbin /dependents`, twice) |
| LunarG's latest SDK (1.4.363.1) has no runtime components zip, and the x64 zip's `x86\vulkan-1.dll` could be picked | Windows | the newest release `files.json` lists one for; the DLL is taken from the `X64\` folder, or the ARM64 zip's top level |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `missing: ...` from `--list` or at start | Install what it names; `--help` lists each requirement |
| Compiler killed partway through the torch build | Lower `--jobs`; budget about 2 GB of RAM per job |
| Windows: `C1002 compiler is out of heap space`, `C1356 unable to find mspdbcore.dll` or `LNK1102 out of memory` | All three mean MSVC ran out of memory. The default `--jobs` keeps 8 GB free for linking `torch_cpu.dll`, links run one at a time, and a failed torch build resumes once with 1 job. If it still fails, the commit limit (RAM + pagefile) is too small: set the pagefile to *System managed size* (System Properties → Advanced → Performance → Virtual memory) and reboot; the script warns when the pagefile adds under 8 GB |
| `Filename too long`, or odd file-not-found errors on Windows | Enable long paths (see [Windows](#windows)) and use a short `--root`, e.g. `D:\ptv` |
| `torch X has no aten/src/ATen/native/vulkan` | That torch version no longer contains the Vulkan backend; use an older `--torch` |
| Build broke after changing versions | Rerun with `--clean` |
| `cpu blas: Eigen (slow)` in the probe | The wheel was built without MKL (an older build, or MKL not installable); rebuild torch with the current script |
| `vulkan_available False` in the probe | No Vulkan driver on that machine; run `--list` on arm64 hosts to see the GPU status |
| torchcodec skipped | No prebuilt FFmpeg for this target; install a local one (see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg)), or on Windows drop `--no-install-ffmpeg` |
| Windows: `the build venv's Python ... is win-amd64, not win-arm64` | uv found no native arm64 Python of that version: use 3.11 or newer, or install python.org's ARM64 build |
| Windows `cuda`: nvcc rejects the Visual Studio version | `set NVCC_ALLOW_UNSUPPORTED=1`, or the Visual Studio 2022 release that CUDA supports |
| Windows `cuda`: `C1002`, `LNK1102` or a killed `nvcc` in flash attention | `--jobs` lower, or `set USE_FLASH_ATTENTION=0` (every `USE_*` variable reaches torch's CMake) |
| `torchcodec not available: Could not load libtorchcodec` | No runtime FFmpeg of a supported major where it's used (see [FFmpeg at runtime](#ffmpeg-at-runtime)); the probe prints the full list of tried versions |

## Status

| Platform | State |
|---|---|
| Linux x86_64 | Builds end to end: torch, torchaudio, torchcodec, manylinux_2_28 |
| Windows x64 | Builds end to end on an 11 GB machine with a 32 GB pagefile: torch, torchaudio, torchcodec |
| macOS x86_64 | Builds end to end: torch, torchaudio, torchcodec 0.17 |
| Linux aarch64, QEMU, macOS arm64, Windows arm64 | Written to the same pattern; first real runs pending |
| Windows `cpu` and `cuda` backends, x64 and arm64 | Written from PyTorch's own Windows builds and NVIDIA's archives; first real runs pending |

Untested parts:

- **macOS:** the unattended SDK installer run, and relinking and re-signing the bundled dylibs.
- **Windows:** the PowerShell GPU check.
- **Windows on ARM:** `msiexec /a` of Arm's MSI, torchcodec through BtbN's FFmpeg and `pkgconf`, and the Vulkan backend on Qualcomm's driver.
- **Windows `cuda`:** the whole backend; on arm64 also torch's CUDA build itself, which PyTorch does not build for Windows on ARM.
- **Intel Mac:** relinking and re-signing the bundled dylibs (torch itself builds).
