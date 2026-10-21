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
| jetson5-sm72-sm87, jetson6-sm87, jetson7-sm87-sm110 | aarch64 Linux (Docker) | none |
| macos-arm64, macos-x86_64 | Mac | theirs need macOS 13.3, these start on 11.0 |
| macos-x86_64-vulkan | Intel Mac | none (theirs is CPU only on Intel) |

Windows needs nothing: audio.cpp's own CPU, Vulkan and CUDA 12.4 / 13.3 packages (with their cudart zips) cover it.

What every package has: `audiocpp_server` (static, only libc/libm/libdl on Linux, no OpenMP, no OpenSSL), the CUDA
runtime and cuBLAS in `lib/` for the CUDA ones (driver only for users), `model_specs/`, `LICENSE`, `LICENSE-ggml`,
`NOTICE`. By default only the model families e2a uses are compiled in (`--models e2a`, half the build);
`--models full` builds every family.

## Build and publish

```bash
./build-audiocpp.sh --list                 # what this machine can build now
./build-audiocpp.sh                        # every target this machine can build
./build-audiocpp.sh --only "jetson6-sm87" --jobs 4
gh release upload audiocpp --clobber audio.cpp/audiocpp-server-*.tar.gz
```

`--tag` must match e2a's `audiocpp_version` (lib/conf_models.py). Once a package is uploaded, remove
`"enabled": False` from its entry in e2a's `audiocpp_packages`; e2a downloads it once per URL.

Licenses: audio.cpp Apache-2.0, ggml MIT, cpp-httplib / cJSON / libyaml / utf8proc MIT, sentencepiece Apache-2.0; the
CUDA libraries are redistributed under the NVIDIA CUDA Toolkit EULA, the Mac Vulkan loader and MoltenVK under
Apache-2.0 (LunarG Vulkan SDK).
