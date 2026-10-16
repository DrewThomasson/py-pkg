#!/usr/bin/env bash
# Builds the e2a zonos2-server packages (zonos2.cpp, Zyphra) this machine can build: Linux aarch64 (Jetson, ARM CPU,
# ARM CUDA servers, in Docker), Linux x86_64 (x64 CPU, Vulkan and Windows CPU packages, with zig), an Intel Mac (CPU,
# Vulkan through MoltenVK) or an Apple Silicon Mac (Metal).
# Run ./build-zonos2.sh --help for the targets and options, --list for what this machine can build now.
set -euo pipefail
usage(){
cat <<'USAGE'
Usage: ./build-zonos2.sh [options]

Builds the e2a zonos2-server packages (zonos2.cpp, Zyphra) that this machine can build, each packed as
zonos2-server-<target>.tar.gz (.zip for Windows) in the zonos2.cpp folder, named like e2a downloads it from the
"zonos2" release of ROBERT-MCDOWELL/py-pkg (upload with: gh release upload zonos2 --clobber ...).
The machine type decides the targets; a target whose tools are missing is skipped with the reason (an explicit
--only stops instead).

Targets
  on aarch64 Linux (e.g. a JetPack 5 Xavier), built in Docker:
    jetson5-sm72-sm87      JetPack 5.x, CUDA 11.4: Xavier + Orin
    jetson6-sm87           JetPack 6.x, CUDA 12.6: Orin
    jetson7-sm87-sm110     JetPack 7.x, CUDA 13: Thor (7.0+), Orin (7.2+)
    linux-aarch64          CPU, ARMv8.0, any aarch64 Linux, glibc >= 2.31, only libc/libm
    linux-aarch64-v82      CPU, ARMv8.2 + dotprod + fp16 (Pi 5, Orin, Graviton2+), same
    linux-aarch64-cuda13   ARM GPU servers, CUDA 13 (driver >= 580): T4 A100 A10 L40 H100 B200 RTX50 Orin Thor GB10
    linux-aarch64-cuda12   same, CUDA 12.8 (driver >= 525), without Orin/Thor/GB10 (only with --only)
  on x86_64 Linux, no Docker (zig, installed with pip, compiles for an old glibc or for Windows):
    linux-x64-cpu-avx2     CPU, AVX2/FMA/F16C (2013+), glibc >= 2.27, only libc/libm
    linux-x64-cpu-sse42    CPU, SSE4.2, no AVX (2008+), same
    linux-x64-vulkan       GPU via Vulkan (discrete or integrated), CPU part AVX2, + libvulkan.so.1
    windows-x64-cpu-avx2   Windows 10+, system DLLs only (UCRT, no VC++ runtime)
    windows-x64-cpu-sse42  same, SSE4.2
  on an Intel Mac:
    macos-x86_64           CPU (Accelerate), AVX2 baseline, macOS >= 11.0
    macos-x86_64-vulkan    GPU via Vulkan through MoltenVK (AMD/Intel GPUs with Metal), CPU part AVX2, macOS >= 11.0,
                           + its own Vulkan loader and MoltenVK in lib/ (nothing to install on the user's Mac)
  on an Apple Silicon Mac:
    macos-arm64            GPU via Metal (shaders embedded), CPU part ARMv8.4 + dotprod + fp16 (M1+),
                           macOS >= 11.0 (Zyphra's macos-arm64-metal needs macOS 15)

Options (each one also works as the environment variable in brackets)
  -h, --help             this help
  -l, --list             list this machine's targets and whether each one can be built now, then exit
  --only "T1 T2 ..."     build only these targets                          [ONLY]   default: all of this machine's
  --jobs N               parallel compile jobs                             [JOBS]   default: 2 (CUDA needs ~2 GB each)
  --tag vX.Y.Z           zonos2.cpp release to build                       [TAG]    default: v0.5.2
  --src DIR              zonos2.cpp source tree, cloned if missing         [SRC]    default: ./zonos2.cpp
  --bundle               put cuBLAS/cudart in lib/ of the aarch64 CUDA     [BUNDLE=1] default: not bundled, the
                         packages (~700 MB instead of the binary alone)    target's CUDA or e2a's PyTorch CUDA is used
  --archs12 / --archs13 "LIST"  CUDA architectures of linux-aarch64-cuda12 / -cuda13  [ARCHS12 / ARCHS13]
  --keep-images          keep the Docker images this run pulled           [KEEP_IMAGES=1] default: removed after
                                                                           each target (images already there stay)
  --clean                delete each build-<target> folder after packing  [CLEAN=1] default: kept (fast rebuilds)

Needs
  every machine: git, curl, python3 (uv is installed if missing)
  aarch64 targets: Docker (through sudo unless run as root)
  linux-x64-vulkan: Vulkan headers, SPIR-V headers, glslc, libvulkan.so, and more than 4 GB of RAM
    Fedora: dnf install vulkan-headers vulkan-loader-devel glslc spirv-headers-devel
    Ubuntu: apt-get install libvulkan-dev glslc spirv-headers
  macos-x86_64-vulkan: the LunarG Vulkan SDK for macOS (https://vulkan.lunarg.com, installed in ~/VulkanSDK/<version>,
    or VULKAN_SDK=<sdk>/macOS): headers, glslc, the Vulkan loader and MoltenVK
  macos-x86_64, macos-x86_64-vulkan, macos-arm64: macOS 11 or newer on the build Mac (the packages target macOS 11.0, older SDKs cannot),
    Xcode Command Line Tools (xcode-select --install); the Metal shaders are embedded as source and compiled at
    run time, so the full Xcode (metal compiler) is not needed

Examples
  ./build-zonos2.sh --list
  ./build-zonos2.sh
  ./build-zonos2.sh --only "jetson6-sm87 jetson7-sm87-sm110" --jobs 4
  ./build-zonos2.sh --only linux-x64-vulkan --jobs 1
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
    --bundle) BUNDLE=1;;
    --archs12) ARCHS12="$2"; shift;;
    --archs13) ARCHS13="$2"; shift;;
    --keep-images) KEEP_IMAGES=1;;
    --clean) CLEAN=1;;
    *) echo "unknown option $1 (see --help)"; exit 1;;
  esac
  shift
done
TAG=${TAG:-v0.5.2}
SRC=${SRC:-$PWD/zonos2.cpp}
JOBS=${JOBS:-2}
VER=${TAG#v}
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
  Linux-aarch64) ALL="jetson5-sm72-sm87 jetson6-sm87 jetson7-sm87-sm110 linux-aarch64 linux-aarch64-v82 linux-aarch64-cuda13 linux-aarch64-cuda12";;
  Linux-x86_64) ALL="linux-x64-cpu-avx2 linux-x64-cpu-sse42 linux-x64-vulkan windows-x64-cpu-avx2 windows-x64-cpu-sse42";;
  Darwin-x86_64) ALL="macos-x86_64 macos-x86_64-vulkan";;
  Darwin-arm64) ALL="macos-arm64";;
  *) echo "no zonos2 targets for a $HOST machine (supported: Linux x86_64, Linux aarch64, Mac)"; exit 1;;
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
    jetson*|linux-aarch64*) command -v docker >/dev/null || echo "Docker is not installed";;
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
[ -d "$SRC" ] || git clone --depth 1 -b "$TAG" --recurse-submodules --shallow-submodules https://github.com/Zyphra/zonos2.cpp "$SRC"
# a tree cloned without --recurse-submodules (or copied) has an empty ggml/: fetch the pinned ggml
[ -f "$SRC/ggml/CMakeLists.txt" ] || git -C "$SRC" submodule update --init --recursive --depth 1
[ -f "$SRC/ggml/CMakeLists.txt" ] || { echo "$SRC/ggml is empty and the submodule could not be fetched: remove $SRC and run again"; exit 1; }
# zonos2.cpp v0.5.2 only looks for a discrete GPU, but ggml reports Jetson's CUDA GPU and integrated Vulkan GPUs
# (Intel / AMD laptops) as "IGPU", so those ran on CPU: take an integrated GPU when there is no discrete one
if ! grep -q DEVICE_TYPE_IGPU "$SRC/src/zonos2.cpp"; then
  for f in "$SRC/src/zonos2.cpp" "$SRC/src/dac.cpp"; do
    "${PYTHON:-python3}" - "$f" <<'EOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^( *)if \(use_gpu\) dev = ggml_backend_dev_by_type\(GGML_BACKEND_DEVICE_TYPE_GPU\);\n', lambda m: m.group(0) + m.group(1) + 'if (use_gpu && !dev) dev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);\n', s, flags=re.M)
s = s.replace('m.is_gpu  = (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU);', 'm.is_gpu  = (ggml_backend_dev_type(dev) != GGML_BACKEND_DEVICE_TYPE_CPU);')
open(p, 'w').write(s)
EOF
  done
fi
cd "$SRC"
pack(){ # $1 target, $2 OS (linux/windows/macos); the folder zonos2-server-<target>/ holds the binary (+ lib/)
  local t=$1 os=$2 d="zonos2-server-$1" exe=zonos2-server
  [ "$os" = windows ] && exe=zonos2-server.exe
  cp -R emotion_directions web "$d/"
  cp ggml/LICENSE "$d/LICENSE-ggml"
  {
    echo "zonos2.cpp $TAG (Zyphra), redistributed with authorization"
    echo "cpp-httplib: Copyright (c) 2024 Yuji Hirose, MIT License"
    echo "nlohmann/json 3.11.3: Copyright (c) 2013-2023 Niels Lohmann, MIT License"
    echo "ggml: MIT License, see LICENSE-ggml"
    case "$t" in linux-x64-*|windows-x64-*) echo "Built with zig (LLVM libc++, Apache-2.0 WITH LLVM-exception)";; esac
    case "$t" in
      macos-*-vulkan) echo "lib/: Vulkan loader and MoltenVK (LunarG Vulkan SDK, Khronos), Apache License 2.0";;
      *) [ -d "$d/lib" ] && echo "lib/: NVIDIA CUDA runtime and cuBLAS, redistributed under the NVIDIA CUDA Toolkit EULA";;
    esac
    true
  } > "$d/NOTICE"
  rm -f "$d.tar.gz" "$d.zip"
  if [ "$os" = windows ]; then
    "${PYTHON:-python3}" -c "import shutil,sys;shutil.make_archive(sys.argv[1],'zip',root_dir='.',base_dir=sys.argv[1])" "$d"
    echo "--- $t DLLs:" $(objdump -p "$d/$exe" | awk '/DLL Name/{print $3}' | grep -v '^api-ms-win-crt' | sort -u) "+ UCRT"
    sha256sum "$d.zip"
  else
    tar czf "$d.tar.gz" "$d"
    if [ "$os" = linux ]; then
      echo "--- $t libs:" $(readelf -d "$d/$exe" | grep NEEDED | grep -o '\[.*\]' | tr -d '[]')
      echo "--- $t glibc floor:" $(objdump -T "$d/$exe" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)
      sha256sum "$d.tar.gz"
    else
      shasum -a 256 "$d.tar.gz"
    fi
  fi
  [ "${CLEAN:-0}" = 1 ] && rm -rf "build-$t"
  true
}
# ---- aarch64: one Docker container per target, the image removed afterwards unless it was already there
INNER=$(cat <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git curl ca-certificates build-essential >/dev/null
git config --global --add safe.directory '*'
curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
uv venv -q /opt/zbuild && . /opt/zbuild/bin/activate && uv pip install -q cmake ninja patchelf
FLAGS="-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=$CPU_ARCH"
# portable builds: no OpenMP and libstdc++ linked in, so only libc/libm are needed (Jetson builds keep JetPack's)
[ "$PORTABLE" = 1 ] && FLAGS="$FLAGS -DGGML_OPENMP=OFF -DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++\ -static-libgcc"
# NCCL is multi-GPU only and not part of a JetPack install: left out
[ -n "$ARCHS" ] && FLAGS="$FLAGS -DGGML_CUDA=ON -DGGML_CUDA_NCCL=OFF -DCMAKE_CUDA_ARCHITECTURES='$ARCHS' -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
eval cmake -B "$B" $FLAGS
cmake --build "$B" --target zonos2-server -j"$JOBS"
rm -rf "$D" && mkdir -p "$D"
cp "$B/zonos2-server" "$D/"
if [ -n "$ARCHS" ] && [ "$BUNDLE" = 1 ]; then
  mkdir -p "$D/lib"
  for l in $(ldd "$B/zonos2-server" | awk '/libcudart|libcublas/{print $3}'); do cp -L "$l" "$D/lib/"; done
  patchelf --set-rpath '$ORIGIN/lib' "$D/zonos2-server"
fi
if [ -n "$ARCHS" ]; then
  echo "--- $T GPU code:" $(/usr/local/cuda/bin/cuobjdump --list-elf "$D/zonos2-server" | grep -o 'sm_[0-9]*' | sort -u)
  echo "--- $T CUDA / NCCL libs (libcuda.so.1 is the driver, not found in Docker is expected):"
  env -u LD_LIBRARY_PATH ldd "$D/zonos2-server" | grep -E 'cud|cublas|nccl' || true
fi
chown -R "$HOST_ID" "$B" "$D"
EOF
)
docker_target(){ # $1 target, $2 image, $3 CPU arch, $4 CUDA archs ("" = CPU only), $5 portable (1/0), $6 bundle (1/0)
  local had=0
  $SUDO docker image inspect "$2" >/dev/null 2>&1 && had=1
  $SUDO docker run --rm --runtime runc --security-opt seccomp=unconfined -v "$SRC":/src -w /src \
    -e T="$1" -e B="build-$1" -e D="zonos2-server-$1" -e CPU_ARCH="$3" -e ARCHS="$4" -e PORTABLE="$5" -e BUNDLE="$6" \
    -e JOBS="$JOBS" -e HOST_ID="$(id -u):$(id -g)" "$2" bash -euc "$INNER"
  if [ "$had" = 0 ] && [ "${KEEP_IMAGES:-0}" != 1 ]; then $SUDO docker image rm "$2" >/dev/null && echo "--- removed the Docker image $2"; fi
  pack "$1" linux
}
# ---- x86_64: zig wrappers (CMake wants one executable per tool), explicit x86 levels (ggml turns them off when
# cross-compiling, i.e. for Windows)
zig_setup(){
  command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; command -v uv >/dev/null || { echo "uv could not be installed"; exit 1; }; }
  [ -x "$HOME/zbuild/bin/python" ] || uv venv -q "$HOME/zbuild"
  uv pip install -q --python "$HOME/zbuild/bin/python" cmake ninja ziglang
  export PATH="$HOME/zbuild/bin:$PATH" PYTHON="$HOME/zbuild/bin/python"
  Z="$SRC/.zig"
  mkdir -p "$Z"
  for t in linux:x86_64-linux-gnu.2.28 windows:x86_64-windows-gnu; do
    printf '#!/bin/sh\nexec "%s" -m ziglang cc -target %s "$@"\n' "$PYTHON" "${t#*:}" > "$Z/${t%%:*}-cc"
    printf '#!/bin/sh\nexec "%s" -m ziglang c++ -target %s "$@"\n' "$PYTHON" "${t#*:}" > "$Z/${t%%:*}-c++"
  done
  for tool in ar ranlib rc; do printf '#!/bin/sh\nexec "%s" -m ziglang %s "$@"\n' "$PYTHON" "$tool" > "$Z/$tool"; done
  chmod +x "$Z"/*
}
AVX2="-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON"
SSE42="-DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF"
COMMON="-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_AVX512=OFF -DGGML_CCACHE=OFF"
zig_target(){ # $1 target, $2 os (linux/windows), $3 extra cmake flags
  local t=$1 os=$2 cross=""
  [ "$os" = windows ] && cross="-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=AMD64 -DCMAKE_AR=$Z/ar -DCMAKE_RANLIB=$Z/ranlib -DCMAKE_RC_COMPILER=$Z/rc"
  CC="$Z/$os-cc" CXX="$Z/$os-c++" cmake -B "build-$t" $COMMON $cross $3
  cmake --build "build-$t" --target zonos2-server -j"$JOBS"
  local exe=zonos2-server d="zonos2-server-$t"
  [ "$os" = windows ] && exe=zonos2-server.exe
  rm -rf "$d" && mkdir -p "$d" && cp "build-$t/$exe" "$d/"
  pack "$t" "$os"
  echo "--- $t AVX-512 / AVX:" $(objdump -d --no-show-raw-insn "$d/$exe" | grep -c '%zmm') / $(objdump -d --no-show-raw-insn "$d/$exe" | grep -c '%ymm')
}
case "$HOST" in Linux-x86_64) zig_setup;; esac
for T in $ONLY; do
  echo "=== $T"
  case "$T" in
    jetson5-sm72-sm87) docker_target "$T" nvcr.io/nvidia/l4t-jetpack:r35.4.1 armv8.2-a+fp16 "72;87" 0 0;;
    jetson6-sm87) docker_target "$T" nvcr.io/nvidia/l4t-jetpack:r36.4.0 armv8.2-a+dotprod+fp16 "87" 0 0;;
    jetson7-sm87-sm110) docker_target "$T" nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu24.04 armv8.2-a+dotprod+fp16 "87;110" 0 0;;
    linux-aarch64) docker_target "$T" ubuntu:20.04 armv8-a "" 1 0;;
    linux-aarch64-v82) docker_target "$T" ubuntu:20.04 armv8.2-a+dotprod+fp16 "" 1 0;;
    linux-aarch64-cuda13) docker_target "$T" nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu22.04 armv8.2-a+fp16 "${ARCHS13:-75-real;80-real;86-real;87-real;89-real;90-real;100-real;110-real;120-real;121}" 1 "${BUNDLE:-0}";;
    linux-aarch64-cuda12) docker_target "$T" nvcr.io/nvidia/cuda:12.8.1-devel-ubuntu22.04 armv8.2-a+fp16 "${ARCHS12:-75-real;80-real;86-real;89-real;90-real;100-real;120}" 1 "${BUNDLE:-0}";;
    linux-x64-cpu-avx2) zig_target "$T" linux "$AVX2";;
    linux-x64-cpu-sse42) zig_target "$T" linux "$SSE42";;
    linux-x64-vulkan)
      # the Vulkan / SPIR-V headers in a folder of their own: /usr/include itself would pull the build host's newer
      # glibc headers into the old-glibc target. --allow-shlib-undefined: the host's libvulkan.so needs a newer
      # glibc, only its name (libvulkan.so.1) is recorded, the user's own loader resolves at run time
      VK="$SRC/.vkinc"
      rm -rf "$VK" && mkdir -p "$VK"
      for h in vulkan vk_video spirv; do [ -d "/usr/include/$h" ] && cp -r "/usr/include/$h" "$VK/"; done
      LIBVK=$(ls /usr/lib/x86_64-linux-gnu/libvulkan.so /usr/lib64/libvulkan.so /usr/lib/libvulkan.so 2>/dev/null | head -1 || true)
      [ -f "$VK/vulkan/vulkan.h" ] && [ -f "$VK/spirv/unified1/spirv.hpp" ] && [ -n "$LIBVK" ] && command -v glslc >/dev/null || { echo "linux-x64-vulkan needs the Vulkan headers, SPIR-V headers, glslc and libvulkan.so (see the top of this script)"; exit 1; }
      zig_target "$T" linux "$AVX2 -DGGML_VULKAN=ON -DVulkan_INCLUDE_DIR=$VK -DVulkan_LIBRARY=$LIBVK -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined";;
    windows-x64-cpu-avx2) zig_target "$T" windows "$AVX2";;
    windows-x64-cpu-sse42) zig_target "$T" windows "$SSE42";;
    macos-x86_64|macos-arm64|macos-x86_64-vulkan)
      # native clang, a baseline CPU instead of this Mac's, and an older macOS floor than the one it runs.
      # x86_64: CPU only. ggml's Metal backend targets Apple GPUs (Apple7+ features), Intel Macs stay on Accelerate.
      # arm64: Metal with the shader source embedded (GGML_METAL_EMBED_LIBRARY), so no default.metallib next to the
      # binary and no full Xcode needed. Both target macOS 11.0, the first macOS on Apple Silicon: Zyphra's own build
      # sets no floor and inherits its macOS 15 runner, which leaves Apple Silicon Macs on 11-14 without any package
      # x86_64-vulkan: ggml's Vulkan backend on MoltenVK (Vulkan over Metal), so Intel Macs with an AMD or Intel GPU get
      # a GPU path. The package carries the SDK's loader and MoltenVK in lib/ (found through @executable_path/lib) and
      # MoltenVK_icd.json, which e2a points the loader at (VK_DRIVER_FILES): nothing to install on the user's Mac
      case "$T" in
        macos-arm64) MFLAGS="-DGGML_CPU_ARM_ARCH=armv8.4-a+dotprod+fp16 -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0";;
        macos-x86_64-vulkan)
          VK_SDK="$(vk_sdk)"
          export VULKAN_SDK="$VK_SDK" PATH="$VK_SDK/bin:$PATH"
          MFLAGS="$AVX2 -DGGML_METAL=OFF -DGGML_VULKAN=ON -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,@executable_path/lib";;
        *) MFLAGS="$AVX2 -DGGML_METAL=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0";;
      esac
      command -v uv >/dev/null || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; command -v uv >/dev/null || { echo "uv could not be installed"; exit 1; }; }
      [ -x "$HOME/zbuild/bin/python" ] || uv venv -q "$HOME/zbuild"
      uv pip install -q --python "$HOME/zbuild/bin/python" cmake ninja
      export PATH="$HOME/zbuild/bin:$PATH"
      cmake -B "build-$T" $COMMON $MFLAGS
      cmake --build "build-$T" --target zonos2-server -j"$JOBS"
      d="zonos2-server-$T"
      rm -rf "$d" && mkdir -p "$d" && cp "build-$T/zonos2-server" "$d/"
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
        ref="$(otool -L "$d/zonos2-server" | awk '/libvulkan/{print $1; exit}')"
        [ -n "$ref" ] || { echo "$T: zonos2-server does not link libvulkan, the Vulkan backend was not built"; exit 1; }
        [ "$ref" = @rpath/libvulkan.1.dylib ] || install_name_tool -change "$ref" @rpath/libvulkan.1.dylib "$d/zonos2-server"
        otool -l "$d/zonos2-server" | grep -q 'path @executable_path/lib ' || install_name_tool -add_rpath @executable_path/lib "$d/zonos2-server" 2>/dev/null
        # install_name_tool invalidates the signatures: ad-hoc sign again
        for f in "$d/zonos2-server" "$d/lib/libvulkan.1.dylib" "$d/lib/libMoltenVK.dylib"; do codesign --force --sign - "$f" 2>/dev/null; done
      fi
      echo "--- $T libs:" $(otool -L "$d/zonos2-server" | tail -n +2 | awk '{print $1}')
      # every Mach-O of the package must start on macOS 11: the binary and, for Vulkan, the SDK's loader and MoltenVK
      for f in "$d/zonos2-server" $(ls "$d"/lib/*.dylib 2>/dev/null || true); do
        fl="$(macho_floor "$f" "$ARCH_M")"
        echo "--- $T macOS floor: ${fl:-?} ${f#$d/}"
        if [ -n "$fl" ] && [ "$(printf '%s\n%s\n' "$fl" 11.0 | sort -V | tail -1)" != 11.0 ]; then
          echo "$T: ${f#$d/} needs macOS $fl, the package must start on macOS 11.0 (use a Vulkan SDK whose MoltenVK and loader target 11.0)"
          exit 1
        fi
      done
      pack "$T" macos;;
  esac
done
