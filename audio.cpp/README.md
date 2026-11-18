# audiocpp-server builds for ebook2audiobook

`build-audiocpp.sh` builds the `audiocpp_server` packages (audio.cpp, 0xShug0) that audio.cpp's own releases leave out,
for e2a's audio.cpp engines. e2a downloads them from the `audiocpp` release of this repository, then falls back to
audio.cpp's own packages.

| Package | Built on | Why audio.cpp's own does not cover it |
|---|---|---|
| linux-x64-cpu-avx2, linux-x64-cpu-sse42 | x86_64 Linux (zig) | theirs need glibc 2.38, GLIBCXX_3.4.32 and libgomp |
| linux-x64-vulkan | x86_64 Linux (zig) | same |
| linux-x64-cuda12, linux-x64-cuda13 | x86_64 Linux (Docker) | theirs (Colab) needs the system's CUDA and OpenSSL |
| linux-aarch64, linux-aarch64-v82, linux-aarch64-cuda12, linux-aarch64-cuda13 | aarch64 Linux (Docker) | none |
| linux-aarch64-vulkan | aarch64 Linux (Docker) | none; the GPU path of Jetson Xavier / JetPack 5 (no CUDA 12 there) |
| jetson6-sm87, jetson7-sm87-sm110 | aarch64 Linux (Docker) | none |
| macos-arm64, macos-x86_64 | Mac | theirs need macOS 13.3, these start on 11.0 |
| macos-x86_64-vulkan | Intel Mac | none (theirs is CPU only on Intel) |
| windows-arm64-cpu, windows-arm64-cpu-v82 | Windows arm64 (`build-audiocpp.cmd`) | none: theirs are Windows x64 only |
| windows-arm64-vulkan | Windows arm64 (`build-audiocpp.cmd`) | none; the GPU path of Snapdragon (Adreno) PCs |

No JetPack 5 package: audio.cpp needs CUDA 12 or newer and refuses JetPack 5's CUDA 11.4, so Xavier and JetPack 5
Orin get their GPU through linux-aarch64-vulkan (JetPack's Vulkan driver), else linux-aarch64 on CPU (Orin can move to
JetPack 6 for jetson6-sm87).

Windows x64 needs nothing: audio.cpp's own CPU, Vulkan and CUDA 12.4 / 13.3 packages (with their cudart zips) cover it.
Windows arm64 has no audio.cpp package (their releases, up to v0.9.5, are Windows x64 only): `build-audiocpp.cmd` builds
it natively on a Windows arm64 machine with Visual Studio's ARM64 clang-cl (ggml takes no MSVC for its ARM code), the
LunarG arm64 Vulkan SDK for the Vulkan one, and the static C runtime (system DLLs only). It fixes a NEON macro of
audio.cpp's ggml that clang-cl builds wrongly (`ggml_vld1q_u32`, the MSVC form, `{a, c, 0, 0}` instead of
`{a, b, c, d}` in the IQ3 / IQ1_M kernels) with ggml's later fix. CPU part: ARMv8.0, or ARMv8.2 + dotprod + fp16 for
-v82 (Snapdragon 850 and newer); ARMv8.0 under Vulkan.

What every package has: `audiocpp_server` (static, only libc/libm/libdl on Linux, system DLLs on Windows, no OpenMP,
no OpenSSL), the CUDA runtime, cuBLAS and cuFFT in `lib/` for the CUDA ones (driver only for users), `model_specs/`,
`LICENSE`, `LICENSE-ggml`, `NOTICE`. By default only the model families e2a uses are compiled in (`--models e2a`, half
the build); `--models full` builds every family.

## Build and publish

```bash
./build-audiocpp.sh --list                 # what this machine can build now
./build-audiocpp.sh                        # every target this machine can build
./build-audiocpp.sh --only "jetson6-sm87" --jobs 4
gh release upload audiocpp --clobber audio.cpp/audiocpp-server-*.tar.gz
```

On Windows arm64, from any command prompt (it loads the Visual Studio C++ environment itself, and adds clang-cl and the
Vulkan SDK when missing):

```bat
build-audiocpp.cmd --list
build-audiocpp.cmd
build-audiocpp.cmd --only windows-arm64-cpu-v82
```

Then upload `audio.cpp\audiocpp-server-windows-arm64-*.zip` the same way.

Both scripts build audio.cpp v0.9.5 by default; `--tag` must match e2a's `audiocpp_version` (lib/conf_models.py). An
existing source tree is moved to `--tag` (local changes dropped): a tree from an earlier release is not rebuilt as is.
Once a package is uploaded, remove `"enabled": False` from its entry in e2a's `audiocpp_packages`; e2a downloads it
once per URL.

Jetson packages use JetPack's own CUDA libraries (nothing bundled).

Licenses: audio.cpp Apache-2.0, ggml MIT, cpp-httplib / cJSON / libyaml / utf8proc MIT, sentencepiece Apache-2.0; the
CUDA libraries are redistributed under the NVIDIA CUDA Toolkit EULA, the Mac Vulkan loader and MoltenVK under
Apache-2.0 (LunarG Vulkan SDK).