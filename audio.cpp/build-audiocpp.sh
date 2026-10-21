#!/usr/bin/env bash
# Builds the e2a audiocpp-server packages (audio.cpp, 0xShug0) that audio.cpp's own releases leave out: Linux aarch64
# (Jetson, ARM CPU, ARM CUDA servers, in Docker), Linux x86_64 for old distros (CPU and Vulkan with zig, CUDA in
# Docker), Intel Macs and Apple Silicon Macs older than macOS 13.3.
# Windows needs nothing: audio.cpp's own Windows CPU, Vulkan and CUDA 12 / 13 packages already cover it.
# Run ./build-audiocpp.sh --help for the targets and options, --list for what this machine can build now.
set -euo pipefail
usage(){
cat <<'USAGE'
Usage: ./build-audiocpp.sh [options]

Builds the e2a audiocpp-server packages (audio.cpp, 0xShug0) that this machine can build, each packed as
audiocpp-server-<target>.tar.gz in the audio.cpp folder, named like e2a downloads it from the "audiocpp" release of
ROBERT-MCDOWELL/py-pkg (upload with: gh release upload audiocpp --clobber ...).
Only what audio.cpp's own releases leave out: their Linux packages need glibc 2.38, GLIBCXX_3.4.32 and libgomp, their
Linux CUDA server needs the system's CUDA and OpenSSL, their Mac packages need macOS 13.3, and there is no Linux ARM
or Jetson package. Windows is fully covered by them (CPU, Vulkan, CUDA 12.4 / 13.3 with their cudart zips).
The machine type decides the targets; a target whose tools are missing is skipped with the reason (an explicit
--only stops instead).

Targets
  on aarch64 Linux (e.g. a Jetson), built in Docker:
    jetson6-sm87           JetPack 6.x, CUDA 12.6: Orin
    jetson7-sm87-sm110     JetPack 7.x, CUDA 13: Thor (7.0+), Orin (7.2+)
    linux-aarch64          CPU, ARMv8.0, any aarch64 Linux, glibc >= 2.31, only libc/libm/libdl
    linux-aarch64-v82      CPU, ARMv8.2 + dotprod + fp16 (Pi 5, Orin, Graviton2+), same
    linux-aarch64-cuda13   ARM GPU servers, CUDA 13 (driver >= 580): T4 A100 A10 L40 H100 B200 RTX50 Orin Thor GB10
    linux-aarch64-cuda12   same, CUDA 12.8 (driver >= 525), without Orin/Thor/GB10 (only with --only)
    no JetPack 5 package: audio.cpp needs CUDA 12 or newer (its CMake refuses JetPack 5's CUDA 11.4, whose nvcc fails
    on its kernels), so Xavier and JetPack 5 Orin run the linux-aarch64 CPU packages (Orin: JetPack 6 for jetson6-sm87)
  on x86_64 Linux, no Docker (zig, installed with pip, compiles for an old glibc):
    linux-x64-cpu-avx2     CPU, AVX2/FMA/F16C (2013+), glibc >= 2.28, only libc/libm/libdl
    linux-x64-cpu-sse42    CPU, SSE4.2, no AVX (2008+), same
    linux-x64-vulkan       GPU via Vulkan (discrete or integrated), CPU part AVX2, + libvulkan.so.1
  on x86_64 Linux, with Docker (NVIDIA's CUDA images, no GPU needed):
    linux-x64-cuda12       GPU via CUDA 12 (Maxwell to Blackwell, driver >= 525), CPU part SSE4.2, glibc >= 2.31,
                           CUDA runtime + cuBLAS + cuFFT bundled in lib/ (nothing but the NVIDIA driver on the user's machine)
    linux-x64-cuda13       GPU via CUDA 13 (Turing to Blackwell, driver >= 580), CPU part SSE4.2, glibc >= 2.35, same
  on an Intel Mac:
    macos-x86_64           CPU (Accelerate), AVX2 baseline, macOS >= 11.0 (audio.cpp's own: CPU only, macOS 13.3)
    macos-x86_64-vulkan    GPU via Vulkan through MoltenVK (AMD/Intel GPUs with Metal), CPU part AVX2, macOS >= 11.0,
                           + its own Vulkan loader and MoltenVK in lib/ (nothing to install on the user's Mac)
  on an Apple Silicon Mac:
    macos-arm64            GPU via Metal (shaders embedded), CPU part ARMv8.4 + dotprod + fp16 (M1+),
                           macOS >= 11.0 (audio.cpp's own macos-arm64-metal needs macOS 13.3)

Options (each one also works as the environment variable in brackets)
  -h, --help             this help
  -l, --list             list this machine's targets and whether each one can be built now, then exit
  --only "T1 T2 ..."     build only these targets                          [ONLY]   default: all of this machine's
  --jobs N               parallel compile jobs                             [JOBS]   default: 2 (CUDA needs ~2 GB each)
  --tag vX.Y.Z           audio.cpp release to build (= e2a's               [TAG]    default: v0.9.2
                         audiocpp_version)
  --src DIR              audio.cpp source tree, cloned if missing          [SRC]    default: ./audio.cpp
  --models e2a|full|"m1,m2"  audio.cpp model families compiled in          [MODELS] default: e2a (the families e2a's
                         engines, ASR and Seed-VC use, about half the build); full = every family, like audio.cpp's
  --no-bundle            leave cudart/cuBLAS/cuFFT out of lib/ of the CUDA [BUNDLE=0] default: bundled, so users need
                         packages (aarch64 and x64, not Jetson)            only the NVIDIA driver (~700 MB unpacked)
  --archs12 / --archs13 "LIST"  CUDA architectures of linux-aarch64-cuda12 / -cuda13  [ARCHS12 / ARCHS13]
  --keep-images          keep the Docker images this run pulled           [KEEP_IMAGES=1] default: removed after
                                                                           each target (images already there stay)
  --clean                delete each build-<target> folder after packing  [CLEAN=1] default: kept (fast rebuilds)

Needs
  every machine: git, curl, python3 (uv is installed if missing)
  aarch64 and linux-x64-cuda* targets: Docker (through sudo unless run as root), no GPU needed
  linux-x64-vulkan: Vulkan headers, SPIR-V headers, glslc, libvulkan.so, and more than 4 GB of RAM
    Fedora: dnf install vulkan-headers vulkan-loader-devel glslc spirv-headers-devel
    Ubuntu: apt-get install libvulkan-dev glslc spirv-headers
  macos-x86_64-vulkan: the LunarG Vulkan SDK for macOS (https://vulkan.lunarg.com, installed in ~/VulkanSDK/<version>,
    or VULKAN_SDK=<sdk>/macOS): headers, glslc, the Vulkan loader and MoltenVK
  macos-x86_64, macos-x86_64-vulkan, macos-arm64: macOS 11 or newer on the build Mac (the packages target macOS 11.0,
    older SDKs cannot), Xcode Command Line Tools (xcode-select --install); the Metal shaders are embedded as source
    and compiled at run time, so the full Xcode (metal compiler) is not needed

Examples
  ./build-audiocpp.sh --list
  ./build-audiocpp.sh
  ./build-audiocpp.sh --only "jetson6-sm87 jetson7-sm87-sm110" --jobs 4
  ./build-audiocpp.sh --only linux-x64-vulkan --jobs 1
USAGE
}
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -l|--list) LIST=1;;
    --only) ONLY="$2"; shift;;
    --jobs) JOBS="$2"; shift;;
    --tag) TAG="$2"; shift;;
    --src) SRC="$2"; shift;;
    --models) MODELS="$2"; shift;;
    --bundle) BUNDLE=1;;
    --no-bundle) BUNDLE=0;;
    --archs12) ARCHS12="$2"; shift;;
    --archs13) ARCHS13="$2"; shift;;
    --keep-images) KEEP_IMAGES=1;;
    --clean) CLEAN=1;;
    *) echo "unknown option $1 (see --help)"; exit 1;;
  esac
  shift
done
TAG=${TAG:-v0.9.2}
SRC=${SRC:-$PWD/audio.cpp}
JOBS=${JOBS:-2}
MODELS=${MODELS:-e2a}
VER=${TAG#v}
# the model families compiled in: e2a's engines (TTS_ENGINES), its reference ASR (qwen3_asr) and its voice conversion
# (seed_vc); their dependencies (miocodec, qwen3_forced_aligner) are linked by audio.cpp itself. moss holds
# moss_tts_local and moss_tts_nano
E2A_MODELS="breeze_tts,chatterbox,confucius4_tts,cosyvoice3,dots_tts,dramabox,fish_audio,firered_audio,fireredtts3,higgs_audio_tts,index_tts2,irodori_tts,kokoro_tts,kugelaudio,magpie_tts,maya1,miotts,moss,neutts,pocket_tts,qwen3_tts,supertonic,vibevoice,voxcpm2,voxtral_tts,seed_vc,qwen3_asr"
case "$MODELS" in
  full) MODEL_FLAGS="-DAUDIOCPP_MODEL_SET=full";;
  e2a) MODEL_FLAGS="-DAUDIOCPP_MODEL_SET=custom -DAUDIOCPP_MODELS=$E2A_MODELS";;
  *) MODEL_FLAGS="-DAUDIOCPP_MODEL_SET=custom -DAUDIOCPP_MODELS=${MODELS// /}";;
esac
# uv and zig keep their caches under XDG_CACHE_HOME (or UV_CACHE_DIR / ZIG_GLOBAL_CACHE_DIR). If one of those points
# to a folder this user cannot write (e.g. a /dev/shm/.cache created by an earlier root run), use ~/.cache instead
writable(){ mkdir -p "$1" 2>/dev/null && [ -w "$1" ]; }
if [ -n "${XDG_CACHE_HOME:-}" ] && ! writable "$XDG_CACHE_HOME"; then
  echo "note: XDG_CACHE_HOME=$XDG_CACHE_HOME is not writable, using $HOME/.cache for this run"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$XDG_CACHE_HOME"
fi
for v in UV_CACHE_DIR ZIG_GLOBAL_CACHE_DIR; do
  if [ -n "${!v:-}" ] && ! writable "${!v}"; then echo "note: $v=${!v} is not writable, using the default"; unset "$v"; fi
done
HOST="$(uname -s)-$(uname -m)"
case "$HOST" in
  Linux-aarch64) ALL="jetson6-sm87 jetson7-sm87-sm110 linux-aarch64 linux-aarch64-v82 linux-aarch64-cuda13 linux-aarch64-cuda12";;
  Linux-x86_64) ALL="linux-x64-cpu-avx2 linux-x64-cpu-sse42 linux-x64-vulkan linux-x64-cuda12 linux-x64-cuda13";;
  Darwin-x86_64) ALL="macos-x86_64 macos-x86_64-vulkan";;
  Darwin-arm64) ALL="macos-arm64";;
  *) echo "no audiocpp targets for a $HOST machine (supported: Linux x86_64, Linux aarch64, Mac; Windows: audio.cpp's own packages)"; exit 1;;
esac
# the macos-* packages target macOS 11.0: a Mac older than that has no SDK for it
if [ "$(uname -s)" = Darwin ]; then
  MACOS_VER="$(sw_vers -productVersion)"
  [ "${MACOS_VER%%.*}" -ge 11 ] || { echo "this Mac runs macOS $MACOS_VER: building the macos-* packages needs macOS 11 or newer"; exit 1; }
fi
# Docker through sudo, except for root
SUDO=sudo
[ "$(id -u)" = 0 ] && SUDO=""
vk_sdk(){ # the LunarG Vulkan SDK's macOS folder: VULKAN_SDK, else the newest one in ~/VulkanSDK
  if [ -n "${VULKAN_SDK:-}" ]; then echo "$VULKAN_SDK"; return 0; fi
  ls -d "$HOME"/VulkanSDK/*/macOS 2>/dev/null | sort -V | tail -1 || true
}
macho_floor(){ # oldest macOS a Mach-O (its x86_64 / arm64 slice $2) starts on
  otool -arch "$2" -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2;exit} /LC_VERSION_MIN_MACOSX/{v=1} v&&/ version /{print $2;exit}'
}
missing(){ # prints why target $1 cannot be built here, nothing when it can
  case "$1" in
    jetson*|linux-aarch64*|linux-x64-cuda*) command -v docker >/dev/null || echo "Docker is not installed";;
    linux-x64-vulkan)
      local m=""
      [ -f /usr/include/vulkan/vulkan.h ] || m="$m Vulkan headers,"
      [ -f /usr/include/spirv/unified1/spirv.hpp ] || m="$m SPIR-V headers,"
      command -v glslc >/dev/null || m="$m glslc,"
      [ -e /usr/lib/x86_64-linux-gnu/libvulkan.so ] || [ -e /usr/lib64/libvulkan.so ] || [ -e /usr/lib/libvulkan.so ] || m="$m libvulkan.so (dev package),"
      [ -n "$m" ] && echo "missing:${m%,} (see --help)";;
    macos-x86_64|macos-arm64) xcode-select -p >/dev/null 2>&1 || echo "Xcode Command Line Tools are missing (xcode-select --install)";;
    macos-x86_64-vulkan)
      local m="" sdk
      xcode-select -p >/dev/null 2>&1 || m="$m Xcode Command Line Tools,"
      sdk="$(vk_sdk)"
      if [ -z "$sdk" ]; then
        m="$m LunarG Vulkan SDK (~/VulkanSDK/<version>/macOS or VULKAN_SDK=<sdk>/macOS),"
      else
        [ -f "$sdk/include/vulkan/vulkan.h" ] || m="$m Vulkan headers in $sdk/include,"
        [ -x "$sdk/bin/glslc" ] || m="$m glslc in $sdk/bin,"
        [ -f "$sdk/lib/libvulkan.1.dylib" ] || m="$m Vulkan loader in $sdk/lib,"
        [ -f "$sdk/lib/libMoltenVK.dylib" ] || m="$m MoltenVK in $sdk/lib,"
        [ -f "$sdk/share/vulkan/icd.d/MoltenVK_icd.json" ] || m="$m MoltenVK_icd.json in $sdk/share/vulkan/icd.d,"
      fi
      [ -n "$m" ] && echo "missing:${m%,} (see --help)";;
  esac
  true
}
if [ "$LIST" = 1 ]; then
  echo "targets on this $HOST machine:"
  for T in $ALL; do r=$(missing "$T"); printf '  %-24s %s\n' "$T" "${r:-ready}"; done
  exit 0
fi
if [ -n "${ONLY:-}" ]; then
  for T in $ONLY; do
    case " $ALL " in *" $T "*) ;; *) echo "$T cannot be built on a $HOST machine (see --list)"; exit 1;; esac
    r=$(missing "$T"); [ -z "$r" ] || { echo "$T: $r"; exit 1; }
  done
else
  # default: every target of this machine that can be built now (linux-aarch64-cuda12 only on request)
  ONLY=""
  for T in $ALL; do
    [ "$T" = linux-aarch64-cuda12 ] && continue
    r=$(missing "$T")
    if [ -z "$r" ]; then ONLY="$ONLY $T"; else echo "skipping $T: $r"; fi
  done
  [ -n "$ONLY" ] || { echo "nothing can be built on this machine yet (see --list)"; exit 1; }
fi
# no submodule needed: the only one (external/audio.cpp-server-frontends) is the optional web frontends, off by default
[ -d "$SRC" ] || git clone --depth 1 -b "$TAG" https://github.com/0xShug0/audio.cpp "$SRC"
[ -f "$SRC/CMakeLists.txt" ] || { echo "$SRC is not an audio.cpp source tree: remove it and run again"; exit 1; }
# the only floating-point std::to_chars (debug trace formatting) is what holds audio.cpp's Mac packages on macOS 13.3,
# libc++ has it from there; GCC has it from 11. The ostringstream fallback below it formats the same value
if grep -q 'std::to_chars(buffer, buffer + sizeof(buffer), value, std::chars_format::general)' "$SRC/src/framework/debug/trace.cpp"; then
  "${PYTHON:-python3}" - "$SRC/src/framework/debug/trace.cpp" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('''    char buffer[64];
    const auto result = std::to_chars(buffer, buffer + sizeof(buffer), value, std::chars_format::general);
    if (result.ec == std::errc()) {
        return std::string(buffer, result.ptr);
    }
    std::ostringstream out;''', '''    std::ostringstream out;''')
open(p, 'w').write(s)
EOF
  grep -q 'std::chars_format::general' "$SRC/src/framework/debug/trace.cpp" && { echo "$SRC/src/framework/debug/trace.cpp: the to_chars patch did not apply (audio.cpp changed it?)"; exit 1; }
fi
cd "$SRC"
pack(){ # $1 target, $2 OS (linux/macos); the folder audiocpp-server-<target>/ holds the server (+ lib/), model_specs/
  local t=$1 os=$2 d="audiocpp-server-$1" exe=audiocpp_server
  # model_specs/ next to the server, as in audio.cpp's own packages (e2a starts it from that folder); the specs are
  # also compiled in (AUDIOCPP_DEPLOYMENT_BUILD)
  cp -R model_specs "$d/"
  cp LICENSE "$d/LICENSE"
  cp external/ggml/LICENSE "$d/LICENSE-ggml"
  {
    echo "audio.cpp $TAG (0xShug0 / ShugoAI LLC), Apache License 2.0, see LICENSE"
    echo "ggml: MIT License, see LICENSE-ggml"
    echo "cpp-httplib (Yuji Hirose), cJSON (Dave Gamble), libyaml (Kirill Simonov, Ingy dot Net), utf8proc: MIT License"
    echo "sentencepiece (Google): Apache License 2.0"
    case "$t" in linux-x64-cpu-*|linux-x64-vulkan) echo "Built with zig (LLVM libc++, Apache-2.0 WITH LLVM-exception)";; esac
    case "$t" in
      macos-*-vulkan) echo "lib/: Vulkan loader and MoltenVK (LunarG Vulkan SDK, Khronos), Apache License 2.0";;
      *) [ -d "$d/lib" ] && echo "lib/: NVIDIA CUDA runtime, cuBLAS and cuFFT, redistributed under the NVIDIA CUDA Toolkit EULA";;
    esac
    true
  } > "$d/NOTICE"
  rm -f "$d.tar.gz"
  tar czf "$d.tar.gz" "$d"
  if [ "$os" = linux ]; then
    echo "--- $t libs:" $(readelf -d "$d/$exe" | grep NEEDED | grep -o '\[.*\]' | tr -d '[]')
    echo "--- $t glibc floor:" $(objdump -T "$d/$exe" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)
    sha256sum "$d.tar.gz"
  else
    shasum -a 256 "$d.tar.gz"
  fi
  [ "${CLEAN:-0}" = 1 ] && rm -rf "build-$t"
  true
}
# ---- Docker targets: one container per target, the image removed afterwards unless it was already there
INNER=$(cat <<'EOF'
export DEBIAN_FRONTEND=noninteractive
# a dropped connection (the PPA's server, a mirror) is retried instead of failing the whole target
echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries
# the build folders stay the host user's even when a step fails (else root-owned: sudo to remove them)
trap 'chown -R "$HOST_ID" "$B" "$D" 2>/dev/null || true' EXIT
apt-get update -qq && apt-get install -y -qq git curl ca-certificates build-essential >/dev/null
git config --global --add safe.directory '*'
curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
uv venv -q /opt/abuild && . /opt/abuild/bin/activate && uv pip install -q cmake ninja patchelf
# audio.cpp is built with GCC 13 upstream: an Ubuntu 20.04 image (glibc 2.31, linux-aarch64*, linux-x64-cuda12) gets
# GCC 13 from the ubuntu-toolchain-r PPA. libstdc++ is linked in either way, so the user's system libstdc++ does not
# matter. nvcc must use it too (CUDAHOSTCXX, CUDA 12.8 takes GCC 13): with its default host compiler (the image's
# GCC 9), CMake puts GCC 9's library folder on the link line and the static libstdc++ comes from GCC 9, which lacks
# what GCC 13's headers call (undefined std::__throw_bad_array_new_length)
if [ "$(gcc -dumpversion | cut -d. -f1)" -lt 11 ]; then
  apt-get install -y -qq software-properties-common gpg-agent >/dev/null
  add-apt-repository -y ppa:ubuntu-toolchain-r/test >/dev/null
  apt-get update -qq && apt-get install -y -qq gcc-13 g++-13 >/dev/null
  export CC=gcc-13 CXX=g++-13 CUDAHOSTCXX=g++-13
fi
# no OpenMP (libgomp is missing on slim and old systems: ggml's own thread pool instead), no model manager (e2a
# downloads the models: no OpenSSL / BoringSSL), libstdc++ and libgcc linked in, so only libc/libm/libdl are needed
FLAGS="-G Ninja -DCMAKE_BUILD_TYPE=Release -DENGINE_ENABLE_NATIVE_CPU=OFF -DENGINE_ENABLE_OPENMP=OFF -DGGML_OPENMP=OFF -DENGINE_ENABLE_VULKAN=OFF -DENGINE_ENABLE_METAL=OFF -DENGINE_ENABLE_LLAMAFILE=ON -DENGINE_BUILD_TESTS=OFF -DAUDIOCPP_DEPLOYMENT_BUILD=ON -DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF -DAUDIOCPP_VERSION=$VER $MODEL_FLAGS -DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++\ -static-libgcc"
# CPU_ARCH: an ARM -march for aarch64, or x86-sse42 for the x64 CUDA builds (the GPU runs the model, so the oldest
# x86-64 level ggml has keeps every CPU of an NVIDIA machine in)
if [ "$CPU_ARCH" = x86-sse42 ]; then
  FLAGS="$FLAGS -DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF -DGGML_AVX512=OFF"
else
  FLAGS="$FLAGS -DGGML_CPU_ARM_ARCH=$CPU_ARCH"
fi
# NCCL is multi-GPU only and not part of a JetPack install: left out
if [ -n "$ARCHS" ]; then
  FLAGS="$FLAGS -DENGINE_ENABLE_CUDA=ON -DENGINE_ENABLE_CUDA_GRAPHS=ON -DGGML_CUDA_NCCL=OFF -DCMAKE_CUDA_ARCHITECTURES='$ARCHS' -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
else
  FLAGS="$FLAGS -DENGINE_ENABLE_CUDA=OFF"
fi
eval cmake -B "$B" $FLAGS
cmake --build "$B" --target audiocpp_server -j"$JOBS"
rm -rf "$D" && mkdir -p "$D"
cp "$B/bin/audiocpp_server" "$D/"
# debug info off (most of the file), before patchelf: strip after patchelf can break the binary
strip --strip-debug "$D/audiocpp_server"
if [ -n "$ARCHS" ] && [ "$BUNDLE" = 1 ]; then
  mkdir -p "$D/lib"
  # audio.cpp links cuFFT too (its CUDA iSTFT), unlike ggml alone
  for l in $(ldd "$B/bin/audiocpp_server" | awk '/libcudart|libcublas|libcufft/{print $3}'); do cp -L "$l" "$D/lib/"; done
  patchelf --set-rpath '$ORIGIN/lib' "$D/audiocpp_server"
fi
if [ -n "$ARCHS" ]; then
  echo "--- $T GPU code:" $(/usr/local/cuda/bin/cuobjdump --list-elf "$D/audiocpp_server" | grep -o 'sm_[0-9]*' | sort -u)
  echo "--- $T CUDA / NCCL libs (libcuda.so.1 is the driver, not found in Docker is expected):"
  env -u LD_LIBRARY_PATH ldd "$D/audiocpp_server" | grep -E 'cud|cublas|nccl' || true
fi
EOF
)
docker_target(){ # $1 target, $2 image, $3 CPU arch, $4 CUDA archs ("" = CPU only), $5 bundle (1/0)
  local had=0
  $SUDO docker image inspect "$2" >/dev/null 2>&1 && had=1
  $SUDO docker run --rm --runtime runc --security-opt seccomp=unconfined -v "$SRC":/src -w /src \
    -e T="$1" -e B="build-$1" -e D="audiocpp-server-$1" -e CPU_ARCH="$3" -e ARCHS="$4" -e BUNDLE="$5" \
    -e VER="$VER" -e MODEL_FLAGS="$MODEL_FLAGS" -e JOBS="$JOBS" -e HOST_ID="$(id -u):$(id -g)" "$2" bash -euc "$INNER"
  if [ "$had" = 0 ] && [ "${KEEP_IMAGES:-0}" != 1 ]; then $SUDO docker image rm "$2" >/dev/null && echo "--- removed the Docker image $2"; fi
  pack "$1" linux
}
# ---- x86_64: zig wrappers (CMake wants one executable per tool), explicit x86 levels
# the host tools (cmake, ninja, ziglang) go in ~/zbuild, the venv build-zonos2.sh makes: one venv for both scripts
zig_setup(){
  command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; command -v uv >/dev/null || { echo "uv could not be installed"; exit 1; }; }
  [ -x "$HOME/zbuild/bin/python" ] || uv venv -q "$HOME/zbuild"
  uv pip install -q --python "$HOME/zbuild/bin/python" cmake ninja ziglang
  export PATH="$HOME/zbuild/bin:$PATH" PYTHON="$HOME/zbuild/bin/python"
  Z="$SRC/.zig"
  mkdir -p "$Z"
  printf '#!/bin/sh\nexec "%s" -m ziglang cc -target x86_64-linux-gnu.2.28 "$@"\n' "$PYTHON" > "$Z/linux-cc"
  # audio.cpp compiles with -pedantic-errors for GCC and Clang (not AppleClang): zig's Clang turns its lambda captures
  # of structured bindings (a C++20 extension GCC takes silently in C++17) into errors, so that one warning is off
  printf '#!/bin/sh\nexec "%s" -m ziglang c++ -target x86_64-linux-gnu.2.28 -Wno-c++20-extensions "$@"\n' "$PYTHON" > "$Z/linux-c++"
  chmod +x "$Z"/*
}
AVX2="-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON"
SSE42="-DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF"
# no OpenMP (libgomp is missing on slim and old systems: ggml's own thread pool instead), no model manager (e2a
# downloads the models: no OpenSSL / BoringSSL), no CUDA / Metal unless a target turns them on
COMMON="-G Ninja -DCMAKE_BUILD_TYPE=Release -DENGINE_ENABLE_NATIVE_CPU=OFF -DENGINE_ENABLE_OPENMP=OFF -DGGML_OPENMP=OFF -DGGML_AVX512=OFF -DENGINE_ENABLE_CUDA=OFF -DENGINE_ENABLE_LLAMAFILE=ON -DENGINE_BUILD_TESTS=OFF -DAUDIOCPP_DEPLOYMENT_BUILD=ON -DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF -DAUDIOCPP_VERSION=$VER $MODEL_FLAGS"
zig_target(){ # $1 target, $2 extra cmake flags
  local t=$1
  CC="$Z/linux-cc" CXX="$Z/linux-c++" cmake -B "build-$t" $COMMON -DENGINE_ENABLE_METAL=OFF $2
  cmake --build "build-$t" --target audiocpp_server -j"$JOBS"
  local d="audiocpp-server-$t"
  rm -rf "$d" && mkdir -p "$d" && cp "build-$t/bin/audiocpp_server" "$d/"
  # zig emits debug info, 90% of the file: off
  strip --strip-debug "$d/audiocpp_server"
  pack "$t" linux
  echo "--- $t AVX-512 / AVX:" $(objdump -d --no-show-raw-insn "$d/audiocpp_server" | grep -c '%zmm') / $(objdump -d --no-show-raw-insn "$d/audiocpp_server" | grep -c '%ymm')
}
case "$HOST" in Linux-x86_64) zig_setup;; esac
for T in $ONLY; do
  echo "=== $T"
  case "$T" in
    jetson6-sm87) docker_target "$T" nvcr.io/nvidia/l4t-jetpack:r36.4.0 armv8.2-a+dotprod+fp16 "87" 0;;
    jetson7-sm87-sm110) docker_target "$T" nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu24.04 armv8.2-a+dotprod+fp16 "87;110" 0;;
    linux-aarch64) docker_target "$T" ubuntu:20.04 armv8-a "" 0;;
    linux-aarch64-v82) docker_target "$T" ubuntu:20.04 armv8.2-a+dotprod+fp16 "" 0;;
    linux-aarch64-cuda13) docker_target "$T" nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu22.04 armv8.2-a+fp16 "${ARCHS13:-75-real;80-real;86-real;87-real;89-real;90-real;100-real;110-real;120-real;121}" "${BUNDLE:-1}";;
    linux-aarch64-cuda12) docker_target "$T" nvcr.io/nvidia/cuda:12.8.1-devel-ubuntu22.04 armv8.2-a+fp16 "${ARCHS12:-75-real;80-real;86-real;89-real;90-real;100-real;120}" "${BUNDLE:-1}";;
    # x64 CUDA: the runtime, cuBLAS and cuFFT go in lib/ (BUNDLE=0 to leave them out), so users need only the NVIDIA driver.
    # Every generation each CUDA release builds for, real code, plus PTX of the newest for later GPUs
    linux-x64-cuda12) docker_target "$T" nvcr.io/nvidia/cuda:12.8.1-devel-ubuntu20.04 x86-sse42 "${ARCHS12_X64:-50-real;52-real;60-real;61-real;70-real;75-real;80-real;86-real;89-real;90-real;100-real;120}" "${BUNDLE:-1}";;
    linux-x64-cuda13) docker_target "$T" nvcr.io/nvidia/cuda:13.0.2-devel-ubuntu22.04 x86-sse42 "${ARCHS13_X64:-75-real;80-real;86-real;89-real;90-real;100-real;120}" "${BUNDLE:-1}";;
    linux-x64-cpu-avx2) zig_target "$T" "$AVX2";;
    linux-x64-cpu-sse42) zig_target "$T" "$SSE42";;
    linux-x64-vulkan)
      # the Vulkan / SPIR-V headers in a folder of their own: /usr/include itself would pull the build host's newer
      # glibc headers into the old-glibc target. --allow-shlib-undefined: the host's libvulkan.so needs a newer
      # glibc, only its name (libvulkan.so.1) is recorded, the user's own loader resolves at run time
      VK="$SRC/.vkinc"
      rm -rf "$VK" && mkdir -p "$VK"
      for h in vulkan vk_video spirv; do [ -d "/usr/include/$h" ] && cp -r "/usr/include/$h" "$VK/"; done
      LIBVK=$(ls /usr/lib/x86_64-linux-gnu/libvulkan.so /usr/lib64/libvulkan.so /usr/lib/libvulkan.so 2>/dev/null | head -1 || true)
      [ -f "$VK/vulkan/vulkan.h" ] && [ -f "$VK/spirv/unified1/spirv.hpp" ] && [ -n "$LIBVK" ] && command -v glslc >/dev/null || { echo "linux-x64-vulkan needs the Vulkan headers, SPIR-V headers, glslc and libvulkan.so (see the top of this script)"; exit 1; }
      zig_target "$T" "$AVX2 -DENGINE_ENABLE_VULKAN=ON -DVulkan_INCLUDE_DIR=$VK -DVulkan_LIBRARY=$LIBVK -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined";;
    macos-x86_64|macos-arm64|macos-x86_64-vulkan)
      # native clang, a baseline CPU instead of this Mac's, and macOS 11.0 as floor (audio.cpp's own: 13.3, for the
      # to_chars patched above). x86_64: CPU only, ggml's Metal backend targets Apple GPUs (Apple7+ features).
      # arm64: Metal with the shader source embedded (GGML_METAL_EMBED_LIBRARY), so no default.metallib next to the
      # binary and no full Xcode needed
      # x86_64-vulkan: ggml's Vulkan backend on MoltenVK (Vulkan over Metal), so Intel Macs with an AMD or Intel GPU get
      # a GPU path. The package carries the SDK's loader and MoltenVK in lib/ (found through @executable_path/lib) and
      # MoltenVK_icd.json, which e2a points the loader at (VK_DRIVER_FILES): nothing to install on the user's Mac
      case "$T" in
        macos-arm64) MFLAGS="-DGGML_CPU_ARM_ARCH=armv8.4-a+dotprod+fp16 -DENGINE_ENABLE_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DENGINE_ENABLE_VULKAN=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0";;
        macos-x86_64-vulkan)
          VK_SDK="$(vk_sdk)"
          export VULKAN_SDK="$VK_SDK" PATH="$VK_SDK/bin:$PATH"
          MFLAGS="$AVX2 -DENGINE_ENABLE_METAL=OFF -DENGINE_ENABLE_VULKAN=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,@executable_path/lib";;
        *) MFLAGS="$AVX2 -DENGINE_ENABLE_METAL=OFF -DENGINE_ENABLE_VULKAN=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0";;
      esac
      command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; command -v uv >/dev/null || { echo "uv could not be installed"; exit 1; }; }
      [ -x "$HOME/zbuild/bin/python" ] || uv venv -q "$HOME/zbuild"
      uv pip install -q --python "$HOME/zbuild/bin/python" cmake ninja
      export PATH="$HOME/zbuild/bin:$PATH"
      cmake -B "build-$T" $COMMON $MFLAGS
      cmake --build "build-$T" --target audiocpp_server -j"$JOBS"
      d="audiocpp-server-$T"
      rm -rf "$d" && mkdir -p "$d" && cp "build-$T/bin/audiocpp_server" "$d/"
      ARCH_M=x86_64
      [ "$T" = macos-arm64 ] && ARCH_M=arm64
      if [ "$T" = macos-x86_64-vulkan ]; then
        mkdir -p "$d/lib"
        for l in libvulkan.1.dylib libMoltenVK.dylib; do
          cp -L "$VK_SDK/lib/$l" "$d/lib/$l"
          chmod u+w "$d/lib/$l"
          # the SDK ships universal dylibs: keep the x86_64 slice only
          if [ "$(lipo -archs "$d/lib/$l" | wc -w)" -gt 1 ]; then lipo "$d/lib/$l" -thin x86_64 -output "$d/lib/$l.thin" && mv "$d/lib/$l.thin" "$d/lib/$l"; fi
          install_name_tool -id "@rpath/$l" "$d/lib/$l" 2>/dev/null
        done
        sed 's|"library_path"[[:space:]]*:[[:space:]]*"[^"]*"|"library_path": "./libMoltenVK.dylib"|' "$VK_SDK/share/vulkan/icd.d/MoltenVK_icd.json" > "$d/lib/MoltenVK_icd.json"
        ref="$(otool -L "$d/audiocpp_server" | awk '/libvulkan/{print $1; exit}')"
        [ -n "$ref" ] || { echo "$T: audiocpp_server does not link libvulkan, the Vulkan backend was not built"; exit 1; }
        [ "$ref" = @rpath/libvulkan.1.dylib ] || install_name_tool -change "$ref" @rpath/libvulkan.1.dylib "$d/audiocpp_server"
        otool -l "$d/audiocpp_server" | grep -q 'path @executable_path/lib ' || install_name_tool -add_rpath @executable_path/lib "$d/audiocpp_server" 2>/dev/null
        # CMake also leaves the build Mac's SDK folder as an rpath (/Users/<you>/VulkanSDK/...): keep only lib/
        for rp in $(otool -l "$d/audiocpp_server" | awk '/LC_RPATH/{r=1} r&&/ path /{print $2;r=0}'); do
          [ "$rp" = @executable_path/lib ] || install_name_tool -delete_rpath "$rp" "$d/audiocpp_server"
        done
        # install_name_tool invalidates the signatures: ad-hoc sign again
        for f in "$d/audiocpp_server" "$d/lib/libvulkan.1.dylib" "$d/lib/libMoltenVK.dylib"; do codesign --force --sign - "$f" 2>/dev/null; done
      fi
      echo "--- $T libs:" $(otool -L "$d/audiocpp_server" | tail -n +2 | awk '{print $1}')
      # the binary and what it links at load time (the Vulkan loader) must start on macOS 11. MoltenVK is not linked:
      # the loader opens it at run time through MoltenVK_icd.json, so its floor is the GPU floor only (an older macOS
      # still starts the server, with no Vulkan device, on CPU). Recent LunarG SDKs build MoltenVK for macOS 12
      GPU_FLOOR=11.0
      for f in "$d/audiocpp_server" $(ls "$d"/lib/*.dylib 2>/dev/null || true); do
        fl="$(macho_floor "$f" "$ARCH_M")"
        echo "--- $T macOS floor: ${fl:-?} ${f#$d/}"
        [ -n "$fl" ] && [ "$(printf '%s\n%s\n' "$fl" 11.0 | sort -V | tail -1)" != 11.0 ] || continue
        if [ "$(basename "$f")" = libMoltenVK.dylib ]; then
          GPU_FLOOR="$fl"
        else
          echo "$T: ${f#$d/} needs macOS $fl, the package must start on macOS 11.0"
          exit 1
        fi
      done
      if [ "$T" = macos-x86_64-vulkan ]; then
        echo "--- $T starts on macOS 11.0, GPU (MoltenVK) from macOS $GPU_FLOOR: set \"macos_min\": \"$GPU_FLOOR\" on its e2a entry"
      fi
      pack "$T" macos;;
  esac
done
