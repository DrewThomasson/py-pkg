# build-zonos2.sh / build-zonos2.cmd

Builds the `zonos2-server` packages that ebook2audiobook (e2a) uses for its Zonos engine (ZONOS2, from [Zyphra's zonos2.cpp](https://github.com/Zyphra/zonos2.cpp)), for the machines Zyphra ships no build for, or ships one that old computers cannot run.

The script looks at the machine it runs on and builds every package that machine can make. Each package is packed as `zonos2-server-<target>.tar.gz` (`.zip` for Windows) in the `zonos2.cpp` folder. The packages are published in the `zonos2` release of [ROBERT-MCDOWELL/py-pkg](https://github.com/ROBERT-MCDOWELL/py-pkg/releases/tag/zonos2) under these same names, and `lib/conf_models.py` in e2a points to them there.

Two scripts, one per kind of build machine: `build-zonos2.sh` on Linux and macOS, `build-zonos2.cmd` on Windows x64 for the Windows packages (CPU, Vulkan, CUDA 12 and CUDA 13), built natively with clang-cl and MSVC + nvcc. The Windows CPU targets of `build-zonos2.sh` (zig cross-builds) stay until the `.cmd` builds are published.

## Quick start

```bash
./build-zonos2.sh --list     # what this machine can build now
./build-zonos2.sh            # build all of it
./build-zonos2.sh --help     # every target and option
```

On Windows x64, from any command prompt:

```bat
build-zonos2.cmd --list
build-zonos2.cmd
build-zonos2.cmd --help
```

`build-zonos2.cmd` loads the Visual Studio C++ environment itself and installs what is missing: the LunarG Vulkan SDK, and the CUDA 12 and 13 compilers, runtimes and cuBLAS from NVIDIA's redistributable archives (checksums verified, no installer, no driver, side by side under `zonos2-tools`). No GPU is needed for any build. `--install-buildtools` installs Visual Studio 2022 Build Tools with C++ and clang-cl through winget.

`--list` shows each target of this machine and whether it can be built right now. On an x86_64 Linux machine with all tools installed:

```
targets on this Linux-x86_64 machine:
  linux-x64-cpu-avx2       ready
  linux-x64-cpu-sse42      ready
  linux-x64-vulkan         ready
  windows-x64-cpu-avx2     ready
  windows-x64-cpu-sse42    ready
```

A target that cannot be built shows the reason instead of `ready`, for example `missing: glslc, libvulkan.so (dev package) (see --help)` or `Docker is not installed`.

Run without options, the script builds every target that is `ready` and skips the others with their reason. With an explicit `--only`, a target that cannot be built stops the run instead, so a requested build is never skipped silently.

## Supported machines

| Machine | How it builds | Targets |
|---|---|---|
| Linux aarch64 (e.g. a JetPack 5 Jetson Xavier) | one Docker container per target | Jetson, aarch64 CPU, aarch64 CUDA servers |
| Linux x86_64 | zig (installed with pip) | x64 CPU and Vulkan, Windows CPU |
| Linux x86_64 | Docker, NVIDIA's CUDA images | x64 CUDA 12 and CUDA 13, runtime bundled |
| Windows x64 | `build-zonos2.cmd`: clang-cl, MSVC + nvcc | Windows CPU, Vulkan, CUDA 12 and CUDA 13, runtime bundled |
| Intel Mac | native clang | macOS Intel CPU |

Apple Silicon has nothing to build: e2a uses Zyphra's own `macos-arm64-metal` package there. Other CPU types (32-bit ARM, RISC-V, PowerPC) are not supported.

## Targets

### On Linux aarch64, in Docker

| Target | For | Notes |
|---|---|---|
| `jetson5-sm72-sm87` | JetPack 5.x, CUDA 11.4 | Xavier + Orin |
| `jetson6-sm87` | JetPack 6.x, CUDA 12.6 | Orin |
| `jetson7-sm87-sm110` | JetPack 7.x, CUDA 13 | Thor (7.0+), Orin (7.2+) |
| `linux-aarch64` | CPU, ARMv8.0, any aarch64 Linux | glibc >= 2.31, only `libc`/`libm` needed |
| `linux-aarch64-v82` | CPU, ARMv8.2 + dotprod + fp16 (Pi 5, Orin, Graviton2+) | same |
| `linux-aarch64-cuda13` | ARM GPU servers, CUDA 13, driver >= 580 | T4, A100, A10, L40, H100, B200, RTX 50, Orin, Thor, GB10 |
| `linux-aarch64-cuda12` | same, CUDA 12.8, driver >= 525 | without Orin/Thor/GB10; only built with `--only` |

### On Linux x86_64, with zig

zig compiles against an old glibc (2.28) from a modern system, or for Windows, and links its C++ library into the binary.

| Target | For | Needs on the user's machine |
|---|---|---|
| `linux-x64-cpu-avx2` | CPU, AVX2/FMA/F16C (2013+) | glibc >= 2.27, only `libc`/`libm` |
| `linux-x64-cpu-sse42` | CPU, SSE4.2, no AVX (2008+) | same |
| `linux-x64-vulkan` | GPU via Vulkan (discrete or integrated), CPU part AVX2 | same + `libvulkan.so.1` |
| `windows-x64-cpu-avx2` | Windows 10+, CPU, AVX2 | system DLLs only (UCRT, no VC++ runtime) |
| `windows-x64-cpu-sse42` | same, SSE4.2 | same |

Windows GPU users get Zyphra's own `windows-x64-vulkan` build.

### On an Intel Mac

| Target | For | Notes |
|---|---|---|
| `macos-x86_64` | CPU (Accelerate), AVX2 baseline | macOS >= `--macos-min` (default 11.0) |

## Options

Each option also works as the environment variable in brackets.

| Option | Variable | Default | Effect |
|---|---|---|---|
| `-h`, `--help` | | | show the help |
| `-l`, `--list` | | | list this machine's targets and whether each can be built now, then exit |
| `--only "T1 T2 ..."` | `ONLY` | all of this machine's | build only these targets |
| `--jobs N` | `JOBS` | 2 | parallel compile jobs; CUDA needs about 2 GB of RAM per job |
| `--tag vX.Y.Z` | `TAG` | v0.5.2 | zonos2.cpp release to build |
| `--src DIR` | `SRC` | `./zonos2.cpp` | zonos2.cpp source tree, cloned if missing |
| `--bundle` | `BUNDLE=1` | not bundled | put cuBLAS/cudart in `lib/` of the aarch64 CUDA packages (~700 MB instead of the binary alone) |
| `--archs12` / `--archs13 "LIST"` | `ARCHS12` / `ARCHS13` | see the targets | CUDA architectures of `linux-aarch64-cuda12` / `-cuda13` |
| `--keep-images` | `KEEP_IMAGES=1` | removed | keep the Docker images this run pulled (images already on the machine always stay) |
| `--clean` | `CLEAN=1` | kept | delete each `build-<target>` folder after packing (saves GBs, but the next build starts from zero) |
| `--macos-min X.Y` | `MACOS_MIN` | 11.0 | oldest macOS for `macos-x86_64` |

## Requirements on the build machine

| For | Needs |
|---|---|
| every machine | git, curl, python3 (uv, cmake, ninja and, on x86_64, zig are installed by the script) |
| aarch64 targets | Docker (through `sudo` unless the script runs as root) |
| `linux-x64-vulkan` | Vulkan headers, SPIR-V headers, `glslc`, `libvulkan.so`, and more than 4 GB of RAM |
| `macos-x86_64` | Xcode Command Line Tools: `xcode-select --install` |

Installing the Vulkan build tools:

```bash
# Fedora
dnf install vulkan-headers vulkan-loader-devel glslc spirv-headers-devel
# Ubuntu / Debian
apt-get install libvulkan-dev glslc spirv-headers
```

## Examples

```bash
./build-zonos2.sh --list
./build-zonos2.sh
./build-zonos2.sh --only "jetson6-sm87 jetson7-sm87-sm110" --jobs 4
./build-zonos2.sh --only linux-x64-vulkan --jobs 1
./build-zonos2.sh --only linux-aarch64-cuda13 --archs13 "80-real;90-real;100-real;121"
```

## What a package contains

```
zonos2-server-<target>/
  zonos2-server            (zonos2-server.exe on Windows)
  emotion_directions/      needed for emotion
  web/                     the server's optional web UI
  lib/                     only with --bundle: cudart and cuBLAS
  LICENSE-ggml
  NOTICE                   licenses of zonos2.cpp, cpp-httplib, nlohmann/json, ggml (and zig / NVIDIA where used)
```

## How e2a uses the packages

- e2a picks a package per machine from `lib/conf_models.py`: the platform, the CPU's features (AVX2 or SSE4.2 on x64, dot-product on ARM), the JetPack version and Jetson board, and the glibc version.
- It downloads the chosen package once, into `lib/classes/tts_engines/venvs/zonos/<package>`, and uses that copy from then on: it never checks for or downloads a newer build. A user gets a rebuilt package only by deleting that folder.
- On a GPU, e2a tries the GPU packages first. If one cannot be downloaded or started (not uploaded yet, no `libvulkan.so.1`, ...), it shows a warning and falls back to the next GPU package, then to the matching CPU package.
- CUDA packages built without `--bundle` use the machine's CUDA runtime, or the NVIDIA libraries that e2a's own CUDA PyTorch installed into its Python environment.
- An entry with `"enabled": False` in `lib/conf_models.py` (a package not uploaded yet) is skipped. Remove that flag once the package is uploaded.
- Zyphra's own packages come from their latest release (`releases/latest/download/...`).

## Publishing a package

Upload to the `zonos2` release of `py-pkg`, replacing a previous build of the same name:

```bash
gh release upload zonos2 --repo ROBERT-MCDOWELL/py-pkg --clobber zonos2-server-<target>.tar.gz
```

No change in e2a is needed, unless the package is new to `lib/conf_models.py` or still marked `"enabled": False`. New e2a installs get the new build; existing installs keep the copy they downloaded. Because every e2a version downloads the same names, keep the server's command-line options and HTTP API compatible; for a zonos2.cpp release that changes them, use a new release tag and point e2a to it.

## Changes to zonos2.cpp v0.5.2

The script applies these to the sources and build settings itself:

- **Integrated GPUs.** zonos2.cpp v0.5.2 only looks for a discrete GPU, but ggml reports every Jetson and integrated Intel/AMD GPUs as "integrated", so they ran on CPU. The script patches `src/zonos2.cpp` and `src/dac.cpp` to also take an integrated GPU, once per source tree.
- **No NCCL.** NCCL (multi-GPU only) is not part of a JetPack install; CUDA builds leave it out (`-DGGML_CUDA_NCCL=OFF`).
- **Portable CPU code.** Every build uses a fixed CPU target (`GGML_NATIVE=OFF`) instead of the build machine's CPU. The x86 instruction levels are set explicitly, because ggml turns them all off when cross-compiling for Windows.
- **Portable libraries.** The CPU and Vulkan builds have no OpenMP and link their C++ library in, so they only need `libc`/`libm`. The Jetson builds keep JetPack's own.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ggml/ does not contain a CMakeLists.txt` | The source tree was cloned without submodules. The script fetches ggml itself; if that fails, delete `zonos2.cpp` and run again. |
| `linux-x64-vulkan ... missing: ...` | Install the Vulkan build tools (see above). |
| A compile process is killed during the Vulkan build | One generated shader file is about 200 MB. Use `--jobs 1`, more RAM, or swap. |
| A Docker target fails before compiling | Check the Docker output above the error: the image has to be pullable from `nvcr.io` or Docker Hub. |
| Startup log shows `zonos2: backend = CPU` on a Jetson | The package was built without the integrated-GPU fix; rebuild it with this script. |
