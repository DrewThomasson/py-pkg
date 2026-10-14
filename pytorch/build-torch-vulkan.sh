#!/usr/bin/env bash
# Builds torch/torchaudio/torchcodec wheels with the PyTorch Vulkan backend.
# Linux: one manylinux_2_28 Docker container per target (glibc >= 2.28). macOS: native build, Vulkan through MoltenVK (LunarG SDK).
# Windows: build-torch-vulkan.cmd. Run ./build-torch-vulkan.sh --help for the targets and options, --list for this machine.
# Kept bash 3.2 compatible so it runs with macOS's stock /bin/bash.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="${ROOT:-$PWD/pytorch-vulkan}"
TORCH="${TORCH:-2.11.0}"
AUDIO="${AUDIO:-2.11.0}"
CODEC="${CODEC:-0.11.1}"
SUFFIX="${SUFFIX:-vulkan}"
PYS="${PYS:-3.12}"
PKGS="${PKGS:-torch torchaudio torchcodec}"
JOBS="${JOBS:-}"
VK_TAG="${VK_TAG:-v1.4.365}"
SHADERC_TAG="${SHADERC_TAG:-v2026.4}"
ONLY="${ONLY:-}"
CLEAN="${CLEAN:-0}"
KEEP_IMAGES="${KEEP_IMAGES:-0}"
NO_BUNDLE="${NO_BUNDLE:-0}"
CODEC_FFMPEG="${CODEC_FFMPEG:-auto}"
MACOS_MIN="${MACOS_MIN:-11.0}"
LIST=0
IN_CONTAINER=""
log(){ echo "[vk-build] $*"; }
die(){ echo "[vk-build] ERROR: $*" >&2; exit 1; }
OS="$(uname -s)"
case "$OS" in
  Linux) [ -n "$JOBS" ] || JOBS=$(nproc); MEM_GB=$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo);;
  Darwin) [ -n "$JOBS" ] || JOBS=$(sysctl -n hw.ncpu); MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ));;
  *) die "unsupported system $OS - on Windows use build-torch-vulkan.cmd";;
esac
usage(){
cat <<EOF
Usage: ./build-torch-vulkan.sh [options]
Builds torch, torchaudio and torchcodec wheels with the PyTorch Vulkan backend for the targets this machine can build.
The torch wheel carries its own Vulkan loader (macOS: plus MoltenVK), so it imports on machines without one; Vulkan is
then simply unavailable. Using a GPU still needs that GPU's Vulkan driver (Mesa RADV/ANV, NVIDIA, ...) except on macOS.
Windows wheels: build-torch-vulkan.cmd, on Windows.
Targets
  linux-x86_64-vulkan        on an x86_64 Linux machine, in a manylinux_2_28 container
  linux-aarch64-vulkan       on an aarch64 Linux machine, in a manylinux_2_28 container
  linux-aarch64-vulkan-qemu  on an x86_64 Linux machine through QEMU, ~10-20x slower (a day or more): only built with --only
  macos-x86_64-vulkan        on an Intel Mac, native (no official torch for Intel Macs after 2.2.2: expect build fixes)
  macos-arm64-vulkan         on an Apple Silicon Mac, native (MPS stays enabled too)
Options                                                                                   [env]
  -l, --list              what this machine can build now
  --only "T1 T2"          build only these targets                                        [ONLY]
  --pkgs "torch ..."      packages to build                                               [PKGS]    default: $PKGS
  --torch VER             default: $TORCH                                                  [TORCH]
  --torchaudio VER        default: $AUDIO                                                  [AUDIO]
  --torchcodec VER        default: $CODEC                                                  [CODEC]
  --py "3.10 3.12"        Python versions, one full torch build each                       [PYS]     default: $PYS
  --suffix TAG            local version tag, e.g. $TORCH+$SUFFIX                           [SUFFIX]  default: $SUFFIX
  --root DIR              sources, build tools, venvs and wheels                           [ROOT]    default: ./pytorch-vulkan
  --jobs N                parallel compile jobs, ~2 GB RAM each                            [JOBS]    default: $JOBS
  --clean                 git clean the checkouts first (do it when changing versions)     [CLEAN=1]
  --codec-ffmpeg MODE     torchcodec FFmpeg: auto, s3 (PyTorch's LGPL builds, all majors), [CODEC_FFMPEG] default: auto
                          local (pkg-config; the wheel is only redistributable if that FFmpeg is LGPL)
                          auto = s3 where it exists (Linux, macOS arm64), else local if found, else torchcodec is skipped
  --no-bundle             do not put the Vulkan loader (macOS: + MoltenVK) into the torch wheel   [NO_BUNDLE=1]
  --macos-min X.Y         oldest macOS the wheels run on                                   [MACOS_MIN] default: $MACOS_MIN
  --keep-images           keep the Docker images this run pulled                           [KEEP_IMAGES=1] default: removed
  -h, --help
Output
  <root>/dist/<target>/<pkg>-<ver>+<suffix>-cpXY-cpXY-<platform>.whl (Linux: manylinux_2_28_<arch>)
  Linux: Vulkan headers + loader ($VK_TAG) and glslc (shaderc $SHADERC_TAG) are compiled once per arch into <root>/tools/<arch>
  Sources stay in <root>/src-<target> for fast rebuilds. Each build ends with a probe of the Vulkan ops TTS models use.
Needs
  Linux: Docker (used directly as root, through sudo otherwise) and network access
    linux-aarch64-vulkan-qemu: QEMU arm64 binfmt (docker run --privileged --rm tonistiigi/binfmt --install arm64)
  macOS: Xcode Command Line Tools, git, curl, the LunarG Vulkan SDK (found in ~/VulkanSDK, or VULKAN_SDK=<sdk>/macOS)
    macos-x86_64-vulkan torchcodec: brew install ffmpeg pkg-config
  uv is installed if missing; Python versions come from uv (macOS) or the manylinux image (Linux)
Examples
  ./build-torch-vulkan.sh --list
  ./build-torch-vulkan.sh
  ./build-torch-vulkan.sh --py "3.10 3.12" --jobs 8
  ./build-torch-vulkan.sh --only linux-aarch64-vulkan-qemu --jobs 16
  ./build-torch-vulkan.sh --pkgs "torchaudio torchcodec"
EOF
}
need(){ [ $# -ge 2 ] || die "$1 needs a value (see --help)"; }
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--list) LIST=1;;
    --only) need "$@"; ONLY="$2"; shift;;
    --pkgs) need "$@"; PKGS="$2"; shift;;
    --torch) need "$@"; TORCH="$2"; shift;;
    --torchaudio) need "$@"; AUDIO="$2"; shift;;
    --torchcodec) need "$@"; CODEC="$2"; shift;;
    --py) need "$@"; PYS="$2"; shift;;
    --suffix) need "$@"; SUFFIX="$2"; shift;;
    --root) need "$@"; ROOT="$2"; shift;;
    --jobs) need "$@"; JOBS="$2"; shift;;
    --codec-ffmpeg) need "$@"; CODEC_FFMPEG="$2"; shift;;
    --macos-min) need "$@"; MACOS_MIN="$2"; shift;;
    --clean) CLEAN=1;;
    --no-bundle) NO_BUNDLE=1;;
    --keep-images) KEEP_IMAGES=1;;
    --in-container) need "$@"; IN_CONTAINER="$2"; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac
  shift
done
case "$CODEC_FFMPEG" in auto|s3|local) ;; *) die "--codec-ffmpeg must be auto, s3 or local";; esac
for p in $PKGS; do case "$p" in torch|torchaudio|torchcodec) ;; *) die "unknown package $p (torch, torchaudio, torchcodec)";; esac; done
want(){ case " $PKGS " in *" $1 "*) return 0;; esac; return 1; }
macos_sdk(){
  if [ -n "${VULKAN_SDK:-}" ]; then echo "$VULKAN_SDK"; return 0; fi
  ls -d "$HOME"/VulkanSDK/*/macOS 2>/dev/null | sort -V | tail -1 || true
}
local_ffmpeg(){ command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libavutil libavcodec libavformat libavfilter libswscale libswresample; }
codec_mode(){  # target -> s3 | local | skip
  if [ "$CODEC_FFMPEG" != auto ]; then echo "$CODEC_FFMPEG"; return 0; fi
  case "$1" in
    macos-x86_64-*) if local_ffmpeg; then echo local; else echo skip; fi;;
    *) echo s3;;
  esac
}
# ---------------------------------------------------------------- native build (in a manylinux container, or on a Mac)
sync_repo(){  # name url version clean
  local path="$SRC/$1"
  if [ ! -d "$path/.git" ]; then git clone -c core.longpaths=true --recursive "$2" "$path"; fi
  git -C "$path" fetch -q --tags --force origin
  git -C "$path" -c advice.detachedHead=false checkout -q "v$3"
  git -C "$path" submodule sync -q --recursive
  git -C "$path" submodule update -q --init --recursive
  if [ "$4" = 1 ]; then
    git -C "$path" clean -q -xdf
    git -C "$path" submodule foreach -q --recursive git clean -q -xdf
  fi
}
pip_wheel(){  # package dir, env already exported by the caller's subshell
  rm -f "$DIST/$1"-*-"$TAG"-*.whl
  (cd "$SRC/$1" && "$PY" -m pip wheel . --no-build-isolation --no-deps -v -w "$DIST")
  WHL="$(ls "$DIST/$1"-*-"$TAG"-*.whl 2>/dev/null | head -1 || true)"
  [ -n "$WHL" ] || die "no $1 wheel produced in $DIST"
  case "$WHL" in *"+$SUFFIX-"*) ;; *) log "WARNING: $(basename "$WHL") does not carry +$SUFFIX - the repo ignored the version variable";; esac
}
retag(){
  if [ "$OS" = Linux ] && [ -n "${AUDITWHEEL_PLAT:-}" ]; then
    case "$WHL" in *"$AUDITWHEEL_PLAT"*) return 0;; esac
    "$PY" -m wheel tags --platform-tag "$AUDITWHEEL_PLAT" --remove "$WHL" >/dev/null
    WHL="${WHL/linux_$(uname -m)/$AUDITWHEEL_PLAT}"
    [ -f "$WHL" ] || die "retagging to $AUDITWHEEL_PLAT failed"
  fi
}
install_whl(){ "$PY" -m pip install -q --force-reinstall --no-deps "$WHL"; }
bundle_vulkan(){
  local tmp="$DIST/_bundle" pkg lib so ref dylib name signed=""
  name="$(basename "$WHL")"
  rm -rf "$tmp"
  "$PY" -m wheel unpack "$WHL" -d "$tmp" >/dev/null
  pkg="$(ls -d "$tmp"/*/ | head -1)"
  lib="${pkg}torch/lib"
  if [ "$OS" = Linux ]; then
    cp -L "$LOADER" "$lib/libvulkan.so.1"
    for so in "$lib"/*.so*; do
      [ -L "$so" ] && continue
      case "$(basename "$so")" in libvulkan.so*) continue;; esac
      if readelf -d "$so" | grep -q '(NEEDED).*\[libvulkan\.so'; then
        readelf -d "$so" | grep -q 'ORIGIN' || patchelf --add-rpath '$ORIGIN' "$so"
      fi
    done
  else
    cp -L "$LOADER" "$lib/libvulkan.1.dylib"
    cp -L "$VULKAN_SDK/lib/libMoltenVK.dylib" "$lib/libMoltenVK.dylib"
    chmod u+w "$lib/libvulkan.1.dylib" "$lib/libMoltenVK.dylib"
    sed 's|"library_path"[[:space:]]*:[[:space:]]*"[^"]*"|"library_path": "./libMoltenVK.dylib"|' "$VULKAN_SDK/share/vulkan/icd.d/MoltenVK_icd.json" > "$lib/MoltenVK_icd.json"
    install_name_tool -id @rpath/libvulkan.1.dylib "$lib/libvulkan.1.dylib"
    install_name_tool -id @rpath/libMoltenVK.dylib "$lib/libMoltenVK.dylib"
    for dylib in "$lib"/*.dylib; do
      case "$(basename "$dylib")" in libvulkan.1.dylib|libMoltenVK.dylib) continue;; esac
      [ -L "$dylib" ] && continue
      local refs; refs="$(otool -L "$dylib" | tail -n +2 | awk '{print $1}' | grep libvulkan || true)"
      [ -n "$refs" ] || continue
      for ref in $refs; do
        [ "$ref" = @rpath/libvulkan.1.dylib ] || install_name_tool -change "$ref" @rpath/libvulkan.1.dylib "$dylib"
      done
      otool -l "$dylib" | grep -q 'path @loader_path ' || install_name_tool -add_rpath @loader_path "$dylib"
      signed="$signed $dylib"
    done
    for dylib in "$lib/libvulkan.1.dylib" "$lib/libMoltenVK.dylib" $signed; do codesign --force --sign - "$dylib" 2>/dev/null; done
    local init="${pkg}torch/__init__.py" hook="$tmp/hook.py"
    if ! grep -q vulkan-bundle "$init"; then
cat > "$hook" <<'EOF'
# vulkan-bundle: point the bundled Vulkan loader at the bundled MoltenVK, unless the user set a driver list
import os as _vk_os
_vk_icd = _vk_os.path.join(_vk_os.path.dirname(_vk_os.path.abspath(__file__)), "lib", "MoltenVK_icd.json")
if _vk_os.path.isfile(_vk_icd) and not (_vk_os.environ.get("VK_DRIVER_FILES") or _vk_os.environ.get("VK_ICD_FILENAMES")):
    _vk_os.environ["VK_DRIVER_FILES"] = _vk_icd
    _vk_os.environ["VK_ICD_FILENAMES"] = _vk_icd
del _vk_os, _vk_icd
EOF
      awk -v hf="$hook" 'done!=1 && /^import /{while((getline l < hf)>0)print l; done=1} {print}' "$init" > "$init.new" && mv "$init.new" "$init"
      rm -f "$hook"
    fi
  fi
  rm -f "$WHL"
  "$PY" -m wheel pack "$pkg" -d "$DIST" >/dev/null
  rm -rf "$tmp"
  [ -f "$DIST/$name" ] || die "repacking $name failed"
  log "bundled the Vulkan loader$( [ "$OS" = Darwin ] && echo ' + MoltenVK') into $name"
}
build_torch(){
  [ -d "$SRC/torch/aten/src/ATen/native/vulkan" ] || die "torch $TORCH has no aten/src/ATen/native/vulkan - the Vulkan backend is gone from this tree, pick an older --torch"
  local r
  for r in requirements-build.txt requirements.txt; do
    if [ -f "$SRC/torch/$r" ]; then "$PY" -m pip install -q -r "$SRC/torch/$r"; fi
  done
  (
    # USE_VULKAN_WRAPPER is Android-only in torch: desktop builds always link the Vulkan loader, hence the bundling
    export USE_VULKAN=1 USE_VULKAN_WRAPPER=0 USE_VULKAN_SHADERC_RUNTIME=0 USE_VULKAN_FP16_INFERENCE=0 USE_VULKAN_RELAXED_PRECISION=0
    export BUILD_TEST=0 PYTORCH_BUILD_VERSION="$TORCH+$SUFFIX" PYTORCH_BUILD_NUMBER=1
    pip_wheel torch
    echo "$WHL" > "$DIST/.whl"
  )
  WHL="$(cat "$DIST/.whl")"
  if [ "$NO_BUNDLE" != 1 ]; then bundle_vulkan; fi
  retag
  install_whl
  BUILT="$BUILT $WHL"
}
build_torchaudio(){
  (
    export USE_FFMPEG=0 BUILD_SOX=0 BUILD_VERSION="$AUDIO+$SUFFIX"
    pip_wheel torchaudio
    echo "$WHL" > "$DIST/.whl"
  )
  WHL="$(cat "$DIST/.whl")"
  retag
  install_whl
  BUILT="$BUILT $WHL"
}
build_torchcodec(){
  local mode; mode="$(codec_mode "$TARGET")"
  if [ "$mode" = skip ]; then
    log "skipping torchcodec: no prebuilt FFmpeg for $TARGET and no local one (brew install ffmpeg pkg-config, or --codec-ffmpeg)"
    return 0
  fi
  "$PY" -m pip install -q pybind11
  (
    export BUILD_VERSION="$CODEC+$SUFFIX"
    if [ "$mode" = s3 ]; then
      export BUILD_AGAINST_ALL_FFMPEG_FROM_S3=1
    else
      local_ffmpeg || die "pkg-config cannot find a complete shared FFmpeg dev set (set PKG_CONFIG_PATH, or --codec-ffmpeg s3)"
      export I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1
      log "WARNING: torchcodec built against the local FFmpeg - only redistribute it if that FFmpeg is an LGPL build"
    fi
    pip_wheel torchcodec
    echo "$WHL" > "$DIST/.whl"
  )
  WHL="$(cat "$DIST/.whl")"
  retag
  install_whl
  BUILT="$BUILT $WHL"
}
probe(){
  log "Vulkan op probe for python $V (FAIL = op not implemented on the Vulkan backend):"
  "$PY" - <<'EOF' || true
import torch,torch.nn.functional as F
print('torch',torch.__version__,'vulkan_available',torch.is_vulkan_available())
for mod in ['torchaudio','torchcodec']:
    try:
        m=__import__(mod)
        print(mod,m.__version__)
    except Exception as e:
        print(mod,'not available:',str(e).splitlines()[0][:120])
if torch.is_vulkan_available():
    x=torch.randn(1,8,64)
    tests=dict(
        softmax=lambda:torch.softmax(x.vulkan(),-1).cpu(),
        gelu=lambda:F.gelu(x.vulkan()).cpu(),
        layer_norm=lambda:F.layer_norm(x.vulkan(),[64]).cpu(),
        matmul=lambda:torch.matmul(torch.randn(64,64).vulkan(),torch.randn(64,64).vulkan()).cpu(),
        conv1d=lambda:F.conv1d(x.vulkan(),torch.randn(8,8,3)).cpu(),
        stft=lambda:torch.stft(torch.randn(16000).vulkan(),n_fft=1024,return_complex=True).cpu(),
        multinomial=lambda:torch.multinomial(torch.rand(4,100).vulkan(),1).cpu(),
    )
    for name,fn in tests.items():
        try:
            fn()
            print(f'  {name:12s} OK')
        except Exception as e:
            print(f'  {name:12s} FAIL',str(e).splitlines()[0][:120])
EOF
}
native_build(){  # target
  TARGET="$1"
  SRC="$ROOT/src-$TARGET"
  DIST="$ROOT/dist/$TARGET"
  mkdir -p "$SRC" "$DIST"
  export MAX_JOBS="$JOBS" CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
  export USE_CUDA=0 USE_ROCM=0 USE_XPU=0 USE_CUDNN=0 USE_NCCL=0 ENABLE_CUDA=0
  if [ "$OS" = Darwin ]; then
    VULKAN_SDK="$(macos_sdk)"
    export VULKAN_SDK MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
    export PATH="$VULKAN_SDK/bin:$PATH"
    LOADER="$VULKAN_SDK/lib/libvulkan.1.dylib"
    if ! command -v uv >/dev/null 2>&1; then curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$PATH"; fi
  else
    export USE_MPS=0
    LOADER="$VULKAN_SDK/lib/libvulkan.so.1"
  fi
  log "$TARGET: torch $TORCH, torchaudio $AUDIO, torchcodec $CODEC (+$SUFFIX), python $PYS, $JOBS jobs, packages: $PKGS"
  log "Vulkan SDK $VULKAN_SDK, glslc $(command -v glslc), torchcodec FFmpeg: $(codec_mode "$TARGET")"
  local base_path="$PATH" clean_now="$CLEAN" venv interp
  BUILT=""
  for V in $PYS; do
    TAG="cp${V/./}"
    venv="$ROOT/venv-$TARGET-$V"
    if [ -n "$IN_CONTAINER" ]; then
      interp="/opt/python/$TAG-$TAG/bin/python"
      [ -x "$interp" ] || die "python $V is not in this manylinux image ($(ls /opt/python | tr '\n' ' '))"
    else
      interp="$V"
    fi
    log "--- python $V"
    rm -rf "$venv"
    uv venv -q --seed --python "$interp" "$venv"
    PY="$venv/bin/python"
    export PATH="$venv/bin:$base_path"
    "$PY" -m pip install -q cmake ninja setuptools wheel
    if want torch; then sync_repo torch https://github.com/pytorch/pytorch.git "$TORCH" "$clean_now"; fi
    if want torchaudio; then sync_repo torchaudio https://github.com/pytorch/audio.git "$AUDIO" "$clean_now"; fi
    if want torchcodec; then sync_repo torchcodec https://github.com/pytorch/torchcodec.git "$CODEC" "$clean_now"; fi
    if want torch; then
      build_torch
    else
      WHL="$(ls "$DIST"/torch-"$TORCH"+"$SUFFIX"-"$TAG"-*.whl 2>/dev/null | head -1 || true)"
      [ -n "$WHL" ] || die "torch is not in --pkgs and no torch-$TORCH+$SUFFIX $TAG wheel is in $DIST to build against"
      install_whl
    fi
    if want torchaudio; then build_torchaudio; fi
    if want torchcodec; then build_torchcodec; fi
    probe
    clean_now=1
  done
  rm -f "$DIST/.whl"
  log "built wheels:"
  for WHL in $BUILT; do log "  $WHL"; done
}
# ---------------------------------------------------------------- inside the manylinux container
container_setup(){
  local T="$ROOT/tools/$ARCH"
  git config --global --add safe.directory '*'
  mkdir -p "$T/bin"
  /opt/python/cp312-cp312/bin/python -m pip install -q --root-user-action=ignore uv
  export PATH="/opt/python/cp312-cp312/bin:/tmp/tools/bin:$T/bin:$PATH"
  uv venv -q --seed --python /opt/python/cp312-cp312/bin/python /tmp/tools
  uv pip install -q --python /tmp/tools/bin/python cmake ninja
  if [ ! -f "$T/vulkan/lib/libvulkan.so.1" ]; then
    log "building Vulkan headers + loader $VK_TAG (once per arch)"
    rm -rf /tmp/vk && mkdir /tmp/vk && cd /tmp/vk
    git clone -q -c advice.detachedHead=false --depth 1 -b "$VK_TAG" https://github.com/KhronosGroup/Vulkan-Headers.git
    git clone -q -c advice.detachedHead=false --depth 1 -b "$VK_TAG" https://github.com/KhronosGroup/Vulkan-Loader.git
    cmake -S Vulkan-Headers -B bh -G Ninja -DCMAKE_INSTALL_PREFIX="$T/vulkan" >/dev/null && cmake --install bh >/dev/null
    cmake -S Vulkan-Loader -B bl -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$T/vulkan" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$T/vulkan" -DUPDATE_DEPS=OFF -DBUILD_TESTS=OFF -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF -DBUILD_WSI_DIRECTFB_SUPPORT=OFF >/dev/null
    cmake --build bl -j"$JOBS" && cmake --install bl >/dev/null
  fi
  if [ ! -x "$T/bin/glslc" ]; then
    log "building glslc from shaderc $SHADERC_TAG (once per arch)"
    rm -rf /tmp/sc && git clone -q -c advice.detachedHead=false --depth 1 -b "$SHADERC_TAG" https://github.com/google/shaderc.git /tmp/sc && cd /tmp/sc
    /tmp/tools/bin/python utils/git-sync-deps
    cmake -S . -B b -G Ninja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSKIP_GLSLANG_INSTALL=ON -DSKIP_SPIRV_TOOLS_INSTALL=ON >/dev/null
    cmake --build b --target glslc_exe -j"$JOBS"
    cp b/glslc/glslc "$T/bin/glslc"
  fi
  export VULKAN_SDK="$T/vulkan"
  cd "$ROOT"
}
if [ -n "$IN_CONTAINER" ]; then
  ROOT=/work
  ARCH="$(uname -m)"
  trap 'chown -R "$HOST_ID" /work 2>/dev/null || true' EXIT
  container_setup
  native_build "$IN_CONTAINER"
  exit 0
fi
# ---------------------------------------------------------------- host: targets, checks, dispatch
HOST_ARCH="$(uname -m)"
if [ "$OS" = Darwin ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then die "this shell runs under Rosetta - use a native arm64 terminal"; fi
  case "$HOST_ARCH" in
    x86_64) ALL="macos-x86_64-vulkan";;
    arm64) ALL="macos-arm64-vulkan";;
    *) die "unsupported machine: $HOST_ARCH";;
  esac
else
  case "$HOST_ARCH" in
    x86_64) ALL="linux-x86_64-vulkan linux-aarch64-vulkan-qemu";;
    aarch64|arm64) HOST_ARCH=aarch64; ALL="linux-aarch64-vulkan";;
    *) die "unsupported machine: $HOST_ARCH";;
  esac
fi
HOST="$OS-$HOST_ARCH"
if [ "$(id -u)" = 0 ]; then DOCKER="docker"; else DOCKER="sudo docker"; fi
missing(){
  local m="" sdk
  command -v git >/dev/null 2>&1 || m="$m git,"
  case "$1" in
    linux-*)
      command -v docker >/dev/null 2>&1 || m="$m Docker,"
      case "$1" in *-qemu) [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || m="$m QEMU arm64 binfmt,";; esac;;
    macos-*)
      xcode-select -p >/dev/null 2>&1 || m="$m Xcode Command Line Tools (xcode-select --install),"
      command -v uv >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || m="$m curl (to install uv),"
      sdk="$(macos_sdk)"
      if [ -z "$sdk" ] || [ ! -f "$sdk/include/vulkan/vulkan.h" ]; then
        m="$m LunarG Vulkan SDK (or VULKAN_SDK=<sdk>/macOS),"
      else
        [ -x "$sdk/bin/glslc" ] || m="$m glslc in $sdk/bin,"
        [ -f "$sdk/lib/libvulkan.1.dylib" ] || m="$m Vulkan loader in $sdk/lib,"
        [ -f "$sdk/lib/libMoltenVK.dylib" ] || m="$m MoltenVK in $sdk/lib,"
      fi
      if want torchcodec && [ "$CODEC_FFMPEG" = local ] && ! local_ffmpeg; then m="$m FFmpeg dev libs (brew install ffmpeg pkg-config),"; fi;;
  esac
  if [ -n "$m" ]; then echo "missing:${m%,} (see --help)"; fi
}
note(){
  case "$1" in *-qemu) echo " (only with --only)";; esac
  if want torchcodec && [ "$(codec_mode "$1")" = skip ]; then echo " (torchcodec skipped: no local FFmpeg)"; fi
}
if [ "$LIST" = 1 ]; then
  echo "targets on this $HOST machine:"
  for T in $ALL; do r="$(missing "$T")"; printf '  %-28s %s\n' "$T" "${r:-ready$(note "$T" | tr -d '\n')}"; done
  exit 0
fi
if [ -n "$ONLY" ]; then
  for T in $ONLY; do
    case " $ALL " in *" $T "*) ;; *) die "$T cannot be built on a $HOST machine (see --list)";; esac
    r="$(missing "$T")"; [ -z "$r" ] || die "$T: $r"
  done
else
  for T in $ALL; do
    case "$T" in *-qemu) continue;; esac
    r="$(missing "$T")"
    if [ -z "$r" ]; then ONLY="$ONLY $T"; else log "skipping $T: $r"; fi
  done
  [ -n "$ONLY" ] || die "nothing can be built on this machine yet (see --list)"
fi
[ $((JOBS*2)) -le "$MEM_GB" ] || log "warning: $JOBS jobs want ~$((JOBS*2)) GB RAM, this machine has $MEM_GB GB - lower --jobs if the compiler gets killed"
mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"
for T in $ONLY; do
  case "$T" in
    macos-*) native_build "$T";;
    linux-*)
      case "$T" in linux-x86_64-*) A=x86_64; PLAT=linux/amd64;; *) A=aarch64; PLAT=linux/arm64;; esac
      IMG="quay.io/pypa/manylinux_2_28_$A"
      PULLED=0
      if ! $DOCKER image inspect "$IMG" >/dev/null 2>&1; then $DOCKER pull --platform "$PLAT" "$IMG"; PULLED=1; fi
      log "=== $T in $IMG"
      $DOCKER run --rm --platform "$PLAT" -v "$ROOT":/work -v "$SELF":/build-torch-vulkan.sh:ro -e TORCH="$TORCH" -e AUDIO="$AUDIO" -e CODEC="$CODEC" -e SUFFIX="$SUFFIX" -e PYS="$PYS" -e PKGS="$PKGS" -e JOBS="$JOBS" -e CLEAN="$CLEAN" -e NO_BUNDLE="$NO_BUNDLE" -e CODEC_FFMPEG="$CODEC_FFMPEG" -e VK_TAG="$VK_TAG" -e SHADERC_TAG="$SHADERC_TAG" -e HOST_ID="$(id -u):$(id -g)" "$IMG" bash /build-torch-vulkan.sh --in-container "$T"
      if [ "$PULLED" = 1 ] && [ "$KEEP_IMAGES" != 1 ]; then $DOCKER rmi "$IMG" >/dev/null || true; fi;;
  esac
done
log "done: wheels in $ROOT/dist/"
