# build-zonos3.sh / build-zonos3.cmd

Builds the `zonos3-server` packages that ebook2audiobook (e2a) uses for its zonos3 engine (ZONOS3-Mini, from zonos3.cpp: the [`servers/ggml`](https://github.com/Zyphra/ZONOS3-Mini/tree/main/servers/ggml) folder of Zyphra's ZONOS3-Mini). Zyphra publishes no zonos3.cpp build, so every package e2a downloads for zonos3 comes from here.

The script looks at the machine it runs on and builds every package that machine can make. Each package is packed as `zonos3-server-<target>.tar.gz` (`.zip` for Windows) in the `ZONOS3-Mini` folder. The packages are published in the `zonos3` release of [ROBERT-MCDOWELL/py-pkg](https://github.com/ROBERT-MCDOWELL/py-pkg/releases/tag/zonos3) under these same names, and `lib/conf_models.py` in e2a points to them there.

Two scripts, one per kind of build machine: `build-zonos3.sh` on Linux and macOS, `build-zonos3.cmd` on Windows x64 for the Windows packages (CPU, Vulkan, CUDA 12 and CUDA 13), built natively with clang-cl and MSVC + nvcc. Unlike zonos2, Windows has no zig cross-build from Linux: zonos3-server links a Rust library that cargo builds for the build machine (see below).

## Quick start

```bash
./build-zonos3.sh --list     # what this machine can build now
./build-zonos3.sh            # build all of it
./build-zonos3.sh --help     # every target and option
```

On Windows x64, from any command prompt:

```bat
build-zonos3.cmd --list
build-zonos3.cmd
build-zonos3.cmd --help
```

`build-zonos3.cmd` loads the Visual Studio C++ environment itself and installs what is missing: Rust (rustup, minimal profile, MSVC host), the LunarG Vulkan SDK, and the CUDA 12 and 13 compilers, runtimes and cuBLAS from NVIDIA's redistributable archives (checksums verified, no installer, no driver, side by side under `zonos3-tools`). No GPU is needed for any build. `--install-buildtools` installs Visual Studio 2022 Build Tools with C++ and clang-cl through winget.

Run without options, the script builds every target that is `ready` and skips the others with their reason. With an explicit `--only`, a target that cannot be built stops the run instead, so a requested build is never skipped silently.

## What differs from zonos2

- **Source.** zonos3.cpp has no repository or release tags of its own: the script fetches the ZONOS3-Mini repository at a commit (`--commit`, default the one e2a pins), with only the two submodules the server builds from, `servers/ggml/ggml` and `third_party/zyphra-textnorm`. The whole tree is needed, not `servers/ggml` alone: the build embeds `model/src/zonos3/registries/*.json` and `servers/api/openapi.json`. zonos3.cpp's CMake applies `servers/ggml/patches/*.patch` to the ggml worktree itself.
- **Rust.** Text normalization is the Rust library zyphra-textnorm (pure Rust, std only), which zonos3.cpp's CMake builds with cargo for the build machine and links into zonos3-server; it cannot be turned off. The scripts install Rust with rustup when missing (the Docker targets in their container). On Windows, cargo's library follows each target's C runtime: `+crt-static` for the clang-cl builds (static runtime), Rust's default for the nvcc ones (DLL runtime, bundled).
- **No source patch.** zonos3.cpp already takes an integrated GPU (Jetson, Intel / AMD iGPUs) when there is no discrete one.
- **Nothing beside the binary.** The emotion directions are the `steer.gguf` steering bundle e2a downloads with the weights, and the server's studio UI is not built (it needs npm): a package holds the server and its licenses only.
- **Apple Silicon.** No Zyphra package exists, so `macos-arm64` (Metal) is built here.

## Supported machines

| Machine | How it builds | Targets |
|---|---|---|
| Linux aarch64 (e.g. a JetPack 5 Jetson Xavier) | one Docker container per target | Jetson, aarch64 CPU, aarch64 CUDA servers |
| Linux x86_64 | zig (installed with pip) | x64 CPU and Vulkan |
| Linux x86_64 | Docker, NVIDIA's CUDA images | x64 CUDA 12 and CUDA 13, runtime bundled |
| Windows x64 | `build-zonos3.cmd`: clang-cl, MSVC + nvcc | Windows CPU, Vulkan, CUDA 12 and CUDA 13, runtime bundled |
| Intel Mac | native clang | macOS Intel CPU, Vulkan through MoltenVK |
| Apple Silicon Mac | native clang | macOS Metal |

Other CPU types (32-bit ARM, RISC-V, PowerPC) are not supported.

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

zig compiles against an old glibc (2.28) from a modern system and links its C++ library into the binary. cargo builds zyphra-textnorm for the build machine's x86_64 Linux target, whose Rust std needs glibc 2.17, so the package keeps the 2.28 floor.

| Target | For | Needs on the user's machine |
|---|---|---|
| `linux-x64-cpu-avx2` | CPU, AVX2/FMA/F16C (2013+) | glibc >= 2.28, only `libc`/`libm` |
| `linux-x64-cpu-sse42` | CPU, SSE4.2, no AVX (2008+) | same |
| `linux-x64-vulkan` | GPU via Vulkan (discrete or integrated), CPU part AVX2 | same + `libvulkan.so.1` |

### On Linux x86_64, in Docker

| Target | For | Notes |
|---|---|---|
| `linux-x64-cuda12` | CUDA 12, Maxwell to Blackwell, driver >= 525 | CPU part SSE4.2, glibc >= 2.31, cudart + cuBLAS in `lib/` |
| `linux-x64-cuda13` | CUDA 13, Turing to Blackwell, driver >= 580 | CPU part SSE4.2, glibc >= 2.35, same |

### On Windows x64, `build-zonos3.cmd`

| Target | For | Notes |
|---|---|---|
| `windows-x64-cpu-avx2` | CPU, AVX2 | clang-cl, static C runtime: system DLLs only |
| `windows-x64-cpu-sse42` | CPU, SSE4.2 | same |
| `windows-x64-vulkan` | GPU via Vulkan, CPU part SSE4.2 | the GPU driver brings `vulkan-1.dll` |
| `windows-x64-cuda12` | CUDA 12, driver 525+ | MSVC + nvcc, CUDA runtime, cuBLAS and VC++ runtime next to the exe |
| `windows-x64-cuda13` | CUDA 13, driver 580+ | same |

### On a Mac

| Target | For | Notes |
|---|---|---|
| `macos-x86_64` | Intel Mac, CPU (Accelerate), AVX2 baseline | macOS >= 11.0 |
| `macos-x86_64-vulkan` | Intel Mac, GPU via Vulkan through MoltenVK, CPU part AVX2 | macOS >= 11.0, its own Vulkan loader and MoltenVK in `lib/` |
| `macos-arm64` | Apple Silicon, GPU via Metal (shaders embedded), CPU part ARMv8.4 + dotprod + fp16 | macOS >= 11.0 |

## Options

Each option also works as the environment variable in brackets.

| Option | Variable | Default | Effect |
|---|---|---|---|
| `-h`, `--help` | | | show the help |
| `-l`, `--list` | | | list this machine's targets and whether each can be built now, then exit |
| `--only "T1 T2 ..."` | `ONLY` | all of this machine's | build only these targets |
| `--jobs N` | `JOBS` | 2 (`.cmd`: all cores) | parallel compile jobs, also cargo's; CUDA needs about 2 GB of RAM per job |
| `--commit SHA` | `COMMIT` | `96d9e0e…` | ZONOS3-Mini commit to build, must match e2a's `commit` |
| `--src DIR` | `SRC` | `./ZONOS3-Mini` | ZONOS3-Mini source tree, fetched if missing |
| `--no-bundle` | `BUNDLE=0` | bundled | leave cuBLAS/cudart out of `lib/` of the Linux CUDA packages |
| `--archs12` / `--archs13 "LIST"` | `ARCHS12` / `ARCHS13` | see the targets | CUDA architectures of the CUDA 12 / 13 targets |
| `--keep-images` | `KEEP_IMAGES=1` | removed | keep the Docker images this run pulled (images already on the machine always stay) |
| `--clean` | `CLEAN=1` | kept | delete each `build-<target>` folder after packing (saves GBs, but the next build starts from zero) |

`build-zonos3.cmd` also takes `--tools`, `--cuda12` / `--cuda13`, `--no-install` and `--install-buildtools` (see its `--help`).

## Requirements on the build machine

| For | Needs |
|---|---|
| every machine | git, curl, python3 (uv, cmake, ninja, Rust and, on x86_64 Linux, zig are installed by the script) |
| aarch64 and `linux-x64-cuda*` targets | Docker (through `sudo` unless the script runs as root) |
| `linux-x64-vulkan` | Vulkan headers, SPIR-V headers, `glslc`, `libvulkan.so`, and more than 4 GB of RAM |
| `macos-*` | macOS 11 or newer, Xcode Command Line Tools: `xcode-select --install` |
| `macos-x86_64-vulkan` | the LunarG Vulkan SDK for macOS (`~/VulkanSDK/<version>/macOS` or `VULKAN_SDK=<sdk>/macOS`) |
| Windows | Visual Studio 2022 C++ build tools (the rest is installed by `build-zonos3.cmd`) |

Installing the Vulkan build tools on Linux:

```bash
# Fedora
dnf install vulkan-headers vulkan-loader-devel glslc spirv-headers-devel
# Ubuntu / Debian
apt-get install libvulkan-dev glslc spirv-headers
```

## Examples

```bash
./build-zonos3.sh --list
./build-zonos3.sh
./build-zonos3.sh --only "jetson6-sm87 jetson7-sm87-sm110" --jobs 4
./build-zonos3.sh --only linux-x64-vulkan --jobs 1
./build-zonos3.sh --only linux-aarch64-cuda13 --archs13 "80-real;90-real;100-real;121"
```

## What a package contains

```
zonos3-server-<target>/
  zonos3-server            (zonos3-server.exe on Windows)
  lib/                     CUDA: cudart and cuBLAS (Linux, unless --no-bundle); Intel Mac Vulkan: loader + MoltenVK
  LICENSE-zonos3, NOTICE-zonos3                      ZONOS3-Mini (MIT) and its third-party notices
  LICENSE-zyphra-textnorm, NOTICE-zyphra-textnorm    zyphra-textnorm (MIT, NeMo grammars Apache-2.0)
  LICENSE-ggml
  licenses/                the third-party license texts (NeMo, Unicode, LMDB, json-schema-validator, ...)
  NOTICE                   what the package holds and under which license
```

Windows CUDA packages keep the CUDA runtime, cuBLAS and the VC++ runtime next to `zonos3-server.exe`.

## How e2a uses the packages

- e2a's zonos3 engine (`lib/classes/tts_engines/zonos3.py`) picks a package per machine from `default_engine_settings['zonos3']['packages']` in `lib/conf_models.py`: the platform, the CPU's features (AVX2 or SSE4.2 on x64, dot-product on ARM), the JetPack version and Jetson board, and the glibc version.
- It downloads the chosen package once, into `lib/classes/tts_engines/venvs/zonos3/<package>`, and uses that copy from then on. It downloads again only when the package's URL in `lib/conf_models.py` changes.
- On a GPU device, e2a tries the GPU packages in order (CUDA 13, CUDA 12, Vulkan); if one cannot be downloaded or started, it shows a warning and tries the next one. A GPU device never falls back to a CPU package: the user selects CPU for that.
- It runs the server with `--zac-threads 1 --batch 2 --port 0` and the GGUF weights of `Zyphra/ZONOS3-Mini` at the revision e2a pins (`backbone-ptq.gguf`, `zac-keep2.gguf`, `spk-encoder.gguf`, `steer.gguf`), and needs `ffmpeg` on PATH for the voice clips (e2a has it).
- CUDA packages built with `--no-bundle` use the machine's CUDA runtime, or the NVIDIA libraries that e2a's own CUDA PyTorch installed into its Python environment.
- An entry with `"enabled": False` in `lib/conf_models.py` is skipped.

## Publishing a package

Create the release once, then upload, replacing a previous build of the same name:

```bash
gh release create zonos3 --repo ROBERT-MCDOWELL/py-pkg --title "zonos3-server" --notes "zonos3.cpp (ZONOS3-Mini 96d9e0e) packages for e2a's zonos3 engine"
gh release upload zonos3 --repo ROBERT-MCDOWELL/py-pkg --clobber zonos3-server-<target>.tar.gz
```

## Moving to a newer ZONOS3-Mini commit

zonos3.cpp refuses GGUFs of another schema, and Zyphra updates the weights of `Zyphra/ZONOS3-Mini` in place. So the build commit and the weights revision move together:

1. Pick the commit, and the `Zyphra/ZONOS3-Mini` Hugging Face revision of the same day (the server checks the GGUF schema at load time: start it on the new weights to confirm).
2. Build every package with `--commit <sha>` (and the new default in both scripts).
3. Upload them under a **new release tag** (e.g. `zonos3-<short sha>`): e2a downloads a package once per URL, so a build uploaded over the old names would never reach existing installs, which would then load the new weights with the old server.
4. In e2a, update `commit`, `revision` and the package URLs of `default_engine_settings['zonos3']` together.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Could NOT find CARGO` at configure | Rust is missing and could not be installed: install it from https://rustup.rs and run again. |
| `Failed to apply ggml patch ...` | The ggml worktree has other changes: `git -C ZONOS3-Mini/servers/ggml/ggml checkout -- . && git -C ZONOS3-Mini/servers/ggml/ggml clean -fd`, then run again. |
| Windows `LNK2038: mismatch detected for 'RuntimeLibrary'` | zyphra-textnorm was built for the other C runtime: delete `build-<target>\textnorm` and run again (the script sets `RUSTFLAGS` per target). |
| `linux-x64-vulkan ... missing: ...` | Install the Vulkan build tools (see above). |
| A compile process is killed during the Vulkan build | One generated shader file is about 200 MB. Use `--jobs 1`, more RAM, or swap. |
| A Docker target fails before compiling | Check the Docker output above the error: the image has to be pullable from `nvcr.io` or Docker Hub. |
