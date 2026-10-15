# build-torch-vulkan

Builds **torch**, **torchaudio** and **torchcodec** wheels with PyTorch's Vulkan backend for Linux, macOS and Windows, on x86_64 and arm64/aarch64.

| Script | Runs on | Builds |
|---|---|---|
| `build-torch-vulkan.sh` | Linux, macOS (bash 3.2+, so macOS's stock `/bin/bash` works) | Linux wheels in manylinux_2_28 Docker containers, macOS wheels natively |
| `build-torch-vulkan.cmd` | Windows 10/11, any command prompt | Windows wheels natively with MSVC |

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
| `macos-x86_64-vulkan` | Intel Mac | native, Vulkan through MoltenVK. PyTorch has not supported Intel Macs since 2.2.2, so expect build fixes |
| `macos-arm64-vulkan` | Apple Silicon Mac | native, Vulkan through MoltenVK; MPS stays enabled too |
| `windows-x64-vulkan` | Windows x64 | native, MSVC |
| `windows-arm64-vulkan` | Windows on ARM | native, MSVC |

Builds are native only, with no cross-compiling. Torch's build compiles helper programs and runs them, and the wheel has to match the Python that builds it. QEMU emulation is the only exception.

`--list` shows which targets this machine can build and what's missing for the others.

## Quick start

### Linux

```
chmod +x build-torch-vulkan.sh
./build-torch-vulkan.sh --list
./build-torch-vulkan.sh
```

You need Docker and network access. Docker runs directly as root, or through `sudo` otherwise. Everything else is built inside the container. The Vulkan headers, loader and `glslc` are compiled once per architecture and cached.

### macOS

```
chmod +x build-torch-vulkan.sh
./build-torch-vulkan.sh --list
./build-torch-vulkan.sh
```

You need the Xcode Command Line Tools (`xcode-select --install`), git and curl. When none is found in `~/VulkanSDK`, the script installs the LunarG Vulkan SDK there, checksum-verified. The SDK brings MoltenVK, the loader and `glslc`.

- **Intel Mac:** run `brew install ffmpeg@7 pkg-config` first, otherwise torchcodec is skipped. Homebrew's plain `ffmpeg` is currently newer than torchcodec 0.11.1 supports; the versioned keg is found automatically.
- **Optional:** `brew install libomp` gives torch multi-threaded CPU ops.

### Windows

```
build-torch-vulkan.cmd --list
build-torch-vulkan.cmd
```

Any command prompt works. The script finds Visual Studio 2022, or its Build Tools, with `vswhere` and loads the C++ environment for this machine itself. If they aren't installed, add `--install-buildtools`, which installs them through winget; it needs several GB and shows a UAC prompt. The LunarG Vulkan SDK is installed into `%LOCALAPPDATA%\VulkanSDK` when missing.

Keep the tree short, because torch's sources and build paths go past Windows' 260-character limit:

```
build-torch-vulkan.cmd --root D:\ptv
```

Also enable long paths once, from an admin prompt. The script warns when they're off.

```
reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f
```

## Options

The two scripts share every option. Each option can also be set with the environment variable in brackets.

| Option | Env | Default | Meaning |
|---|---|---|---|
| `-l`, `--list` | | | Show what this machine can build now, and the GPU status where the install job is on |
| `--only "T1 T2"` | `ONLY` | all ready targets | Build only these targets (`.sh` only) |
| `--pkgs "torch ..."` | `PKGS` | `torch torchaudio torchcodec` | Packages to build |
| `--torch VER` | `TORCH` | `2.11.0` | torch version (git tag `v<VER>`) |
| `--torchaudio VER` | `AUDIO` | `2.11.0` | torchaudio version |
| `--torchcodec VER` | `CODEC` | `0.11.1` | torchcodec version |
| `--py "3.10 3.12"` | `PYS` | `3.12` | Python versions; each one is a full torch build |
| `--suffix TAG` | `SUFFIX` | `vulkan` | Local version tag: `2.11.0+vulkan` |
| `--root DIR` | `ROOT` | `./pytorch-vulkan` | Sources, tools, venvs and wheels |
| `--jobs N` | `JOBS` | CPU threads, capped by RAM | Parallel compile jobs: about 2 GB of RAM each; on Windows (RAM − 8 GB kept for linking) ÷ 3 GB per MSVC job |
| `--clean` | `CLEAN=1` | | `git clean` the checkouts first; do this when changing versions |
| `--codec-ffmpeg MODE` | `CODEC_FFMPEG` | `auto` | Where torchcodec's FFmpeg comes from, see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg) |
| `--no-bundle` | `NO_BUNDLE=1` | | Don't put the Vulkan loader (macOS: plus MoltenVK) into the torch wheel |
| `--no-install-sdk` | `INSTALL_SDK=0` | installs it | Don't install the LunarG SDK when it's missing (macOS, Windows) |
| `--install-vulkan` | `INSTALL_VK=1` | arm64 hosts only | Run the [Vulkan install job](#vulkan-install-job) on any host |
| `--no-install-vulkan` | `INSTALL_VK=0` | | Never run it |
| `--macos-min X.Y` | `MACOS_MIN` | `11.0` | Oldest macOS the wheels run on (`.sh` only) |
| `--keep-images` | `KEEP_IMAGES=1` | removed | Keep the Docker images this run pulled (`.sh` only) |
| `--install-buildtools` | `INSTALL_BT=1` | | Install Visual Studio 2022 Build Tools with C++ through winget (`.cmd` only) |
| `-h`, `--help` | | | Full help |

### Examples

```
./build-torch-vulkan.sh --py "3.10 3.12" --jobs 8
./build-torch-vulkan.sh --only linux-aarch64-vulkan-qemu --jobs 16
./build-torch-vulkan.sh --pkgs "torchaudio torchcodec"     # reuse the torch wheel already in dist/
build-torch-vulkan.cmd --root D:\ptv --jobs 12
```

## What a run does

1. **Checks the host.**
   - **Linux:** Docker, plus QEMU for the `-qemu` target.
   - **macOS:** Xcode Command Line Tools and the SDK. It refuses to run under Rosetta.
   - **Windows:** Visual Studio, matched to this machine's architecture, the SDK and git.
   - **Selection:** ready targets build. Targets with something missing are skipped, with the reason. A target named with `--only` that can't build stops the run.
2. **Prepares the toolchain.**
   - **Linux:** inside each container it builds the Vulkan headers, loader and `glslc` once per architecture into `<root>/tools/<arch>`.
   - **macOS and Windows:** it uses the LunarG SDK, installing it if missing.
   - **Python:** uv provides it, installed if missing. On Linux it comes from the manylinux image's `/opt/python`.
3. **Syncs the sources.** It clones or updates pytorch, audio and torchcodec in `<root>/src-<target>` and checks out the `v<version>` tags with all submodules. On Windows, git's long-path support is switched on for every repository.
4. **Builds torch** with `USE_VULKAN=1`, CUDA/ROCm/XPU off, and the version set to `<ver>+<suffix>`. It first checks that the torch tag still contains the Vulkan backend.
5. **Bundles the Vulkan loader** into the torch wheel (see [Vulkan loader bundling](#vulkan-loader-bundling)). On Linux the wheels are then retagged `manylinux_2_28_<arch>`.
6. **Builds torchaudio, then torchcodec,** against the new torch, then installs each wheel into the build venv.
7. **Runs the op probe** for each Python version.
8. **Runs the Vulkan install job** where enabled (see [Vulkan install job](#vulkan-install-job)). On Linux this ends with a second probe on the host's own GPU.

Checkouts and build trees are kept, so a rerun after a failure picks up where it stopped. Use `--clean` when you change versions.

## Output

```
<root>/
  dist/<target>/
    torch-2.11.0+vulkan-cp312-cp312-manylinux_2_28_x86_64.whl    (Linux)
    torch-2.11.0+vulkan-cp312-cp312-macosx_11_0_arm64.whl        (macOS)
    torch-2.11.0+vulkan-cp312-cp312-win_amd64.whl                (Windows)
    torchaudio-2.11.0+vulkan-...whl
    torchcodec-0.11.1+vulkan-...whl
  src-<target>/{torch,torchaudio,torchcodec}    git checkouts and build trees
  venv-<target>-<python>/                       build venv, with the fresh wheels installed
  tools/<arch>/                                 Linux: Vulkan headers + loader, glslc
  tools/vulkanrt-<arch>/                        Windows: vulkan-1.dll fetched for bundling, if needed
```

Install the wheels with `pip install torch-2.11.0+vulkan-...whl torchaudio-...whl torchcodec-...whl`.

## Vulkan loader bundling

On desktop systems torch links the Vulkan loader directly; only Android builds load it at runtime. A plain build would therefore fail to `import torch` on any machine without a loader. The scripts put a loader into the torch wheel instead:

| OS | Bundled into `torch/lib` | How it is found |
|---|---|---|
| Linux | `libvulkan.so.1`, built in the container against glibc 2.28 | `$ORIGIN` added to RUNPATH where missing |
| macOS | `libvulkan.1.dylib`, `libMoltenVK.dylib`, `MoltenVK_icd.json` | dylibs relinked to `@rpath`, re-signed ad hoc; a small hook in `torch/__init__.py` points `VK_DRIVER_FILES` at the bundled MoltenVK unless you set it yourself |
| Windows | `vulkan-1.dll`, from the SDK, LunarG's runtime package or System32 | torch loads every DLL in `torch\lib` at import |

With the loader bundled, `import torch` works everywhere. `torch.is_vulkan_available()` is `True` only where a GPU driver provides Vulkan. Use `--no-bundle` to rely on the system loader instead.

## torchcodec and FFmpeg

torchcodec links against FFmpeg at build time. `--codec-ffmpeg` picks the source:

| Mode | What it does |
|---|---|
| `s3` | PyTorch's prebuilt LGPL FFmpeg builds, majors 4–8, like the official wheels. These exist for Linux x86_64/aarch64, macOS arm64 and Windows x64 only |
| `local` | The FFmpeg that `pkg-config` finds. The wheel is only redistributable if that FFmpeg is an LGPL build (no `--enable-gpl` / `--enable-nonfree`) |
| `auto` | `s3` where it exists, else `local` if found, else torchcodec is skipped with a note |

In `local` mode the script accepts only the FFmpeg majors the torchcodec checkout lists (4–8 for 0.11.1). If the default FFmpeg is newer, it tries Homebrew's keg-only `ffmpeg@8` down to `ffmpeg@4` and uses the newest supported one.

So on an Intel Mac or Windows on ARM, `auto` needs a local FFmpeg:

- **Intel Mac:** `brew install ffmpeg@7 pkg-config`
- **Windows on ARM:** a shared LGPL FFmpeg with its `.pc` files on `PKG_CONFIG_PATH`, and `pkg-config`

At runtime, torchcodec still needs an FFmpeg installed on the user's machine.

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

**Windows.** The job looks for a Vulkan driver in the registry, then confirms with the SDK's `vulkaninfoSDK`. Without a driver the wheels still build, and the probe is skipped with a hint:

- **Snapdragon X:** update the Qualcomm graphics driver.
- **Older Snapdragons:** install Microsoft's *OpenCL, OpenGL, and Vulkan Compatibility Pack* from the Microsoft Store.
- **Other GPUs:** install the vendor driver.

## The op probe

Each build ends with:

```
torch 2.11.0+vulkan vulkan_available True
torchaudio 2.11.0+vulkan
torchcodec 0.11.1+vulkan
  softmax      OK
  gelu         OK
  layer_norm   OK
  matmul       OK
  conv1d       OK
  stft         FAIL ...
  multinomial  FAIL ...
```

These lines show the expected format, not results from a real run. The first `FAIL` among the ops a model uses tells you whether that model can run on Vulkan at all. `vulkan_available False` means no usable Vulkan device on that machine, and the op lines are then skipped.

## Upstream workarounds applied automatically

Each one is applied only where needed. Where a source file is patched, it is restored after the build, so the checkouts stay clean.

| Problem | Where | Workaround |
|---|---|---|
| Submodule files longer than 260 characters | Windows | `git -c core.longpaths=true` before `clone`, so it also reaches the submodules; saved in every repository's config |
| `vswhere` path contains `(x86)` | Windows | run outside any `( )` block, read back through a temp file |
| `M_SQRT2` / `M_2_SQRTPI` undeclared in `vulkan/ops/Clamp.cpp` | Windows (MSVC) | `#define _USE_MATH_DEFINES` added as line 1 for the build |
| `find_package(pybind11)` can't see pip's pybind11 | all | `pybind11_ROOT` and `CMAKE_PREFIX_PATH` set from `python -m pybind11 --cmakedir` |
| CMake picks another Python (e.g. Homebrew's framework 3.14) instead of the build venv's | all | `VIRTUAL_ENV` exported for the build venv; CMake's FindPython checks it first |
| `Unsupported libavcodec version` (FFmpeg newer than torchcodec supports) | `local` mode | supported majors read from the checkout; Homebrew `ffmpeg@N` kegs tried |
| `Python3_LIBRARY` NOTFOUND: manylinux Pythons ship no `libpython`, on purpose | Linux | torchcodec's `find_package(Python3 ... Development)` switched to `Development.Module` for the build |
| torchcodec refuses to build against a local FFmpeg | `local` mode | `I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1`, with the LGPL warning printed |
| Linking `torch_cpu` runs out of memory next to parallel compiles | all | links run one at a time (CMake job pool `vk_link=1`); a tree configured before this is reconfigured once with `CMAKE_FRESH=1`, and compiled objects are kept |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `missing: ...` from `--list` or at start | Install what it names; `--help` lists each requirement |
| Compiler killed partway through the torch build | Lower `--jobs`; budget about 2 GB of RAM per job |
| Windows: `C1002 compiler is out of heap space`, `C1356 unable to find mspdbcore.dll` or `LNK1102 out of memory` | All three mean MSVC ran out of memory. The default `--jobs` keeps 8 GB free for linking `torch_cpu.dll`, links run one at a time, and a failed torch build resumes once with 1 job. If it still fails, the commit limit (RAM + pagefile) is too small: set the pagefile to *System managed size* (System Properties → Advanced → Performance → Virtual memory) and reboot; the script warns when the pagefile adds under 8 GB |
| `Filename too long`, or odd file-not-found errors on Windows | Enable long paths (see [Windows](#windows)) and use a short `--root`, e.g. `D:\ptv` |
| `torch X has no aten/src/ATen/native/vulkan` | That torch version no longer contains the Vulkan backend; use an older `--torch` |
| Build broke after changing versions | Rerun with `--clean` |
| `vulkan_available False` in the probe | No Vulkan driver on that machine; run `--list` on arm64 hosts to see the GPU status |
| torchcodec skipped | No prebuilt FFmpeg for this target; install a local one (see [torchcodec and FFmpeg](#torchcodec-and-ffmpeg)) |

## Status

| Platform | State |
|---|---|
| Linux x86_64 | Builds end to end: torch, torchaudio, torchcodec, manylinux_2_28 |
| Windows x64 | Runs from any prompt; torch compiles with the MSVC fixes above; full run pending |
| macOS x86_64 | torch and torchaudio build; torchcodec fixes for FFmpeg and Python selection added, rerun pending |
| Linux aarch64, QEMU, macOS arm64, Windows arm64 | Written to the same pattern; first real runs pending |

Untested parts:

- **macOS:** the unattended SDK installer run, and relinking and re-signing the bundled dylibs.
- **Windows:** the PowerShell GPU check, and the layout of LunarG's runtime zip.
- **Intel Mac:** relinking and re-signing the bundled dylibs (torch itself builds).
