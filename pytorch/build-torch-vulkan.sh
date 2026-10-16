#!/usr/bin/env bash
# Builds torch/torchaudio/torchcodec wheels with the PyTorch Vulkan backend.
# Linux: one manylinux_2_28 Docker container per target (glibc >= 2.28). macOS: native build, Vulkan through MoltenVK (LunarG SDK).
# Windows: build-torch-vulkan.cmd. Run ./build-torch-vulkan.sh --help for the targets and options, --list for this machine.
# Kept bash 3.2 compatible so it runs with macOS's stock /bin/bash.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="${ROOT:-$PWD/pytorch-vulkan}"
TORCH="${TORCH:-}"
AUDIO="${AUDIO:-2.11.0}"
CODEC="${CODEC:-}"
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
INSTALL_VK="${INSTALL_VK:-auto}"
INSTALL_SDK="${INSTALL_SDK:-1}"
INSTALL_FFMPEG="${INSTALL_FFMPEG:-1}"
FORCE="${FORCE:-0}"
LIST=0
IN_CONTAINER=""
log(){ echo "[vk-build] $*"; }
die(){ echo "[vk-build] ERROR: $*" >&2; exit 1; }
OS="$(uname -s)"
case "$OS" in
  Linux) CPUS=$(nproc); MEM_GB=$(awk '/MemTotal/{print int($2/1048576)}' /proc/meminfo);;
  Darwin) CPUS=$(sysctl -n hw.ncpu); MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ));;
  *) die "unsupported system $OS - on Windows use build-torch-vulkan.cmd";;
esac
HOST_ARCH="$(uname -m)"
if [ "$OS" = Linux ] && [ "$HOST_ARCH" = arm64 ]; then HOST_ARCH=aarch64; fi
JOBS_USER=0
if [ -n "$JOBS" ]; then JOBS_USER=1; else JOBS=$CPUS; MJ=$((MEM_GB / 2)); [ "$MJ" -ge 1 ] || MJ=1; [ "$MJ" -ge "$JOBS" ] || JOBS=$MJ; fi
usage(){
cat <<EOF
Usage: ./build-torch-vulkan.sh --torch=VER --torchcodec=VER [options]
Builds torch, torchaudio and torchcodec wheels with the PyTorch Vulkan backend for the targets this machine can build.
The torch wheel carries its own Vulkan loader (macOS: plus MoltenVK), so it imports on machines without one; Vulkan is
then simply unavailable. Using a GPU still needs that GPU's Vulkan driver (Mesa RADV/ANV, NVIDIA, ...) except on macOS.
Windows wheels: build-torch-vulkan.cmd, on Windows.
Targets
  linux-x86_64-vulkan        on an x86_64 Linux machine, in a manylinux_2_28 container
  linux-aarch64-vulkan       on an aarch64 Linux machine, in a manylinux_2_28 container
  linux-aarch64-vulkan-qemu  on an x86_64 Linux machine through QEMU, ~10-20x slower (a day or more): only built with --only
  macos-x86_64-vulkan        on an Intel Mac, native (PyTorch stopped at 2.2.2 there: this is the only current torch)
  macos-arm64-vulkan         on an Apple Silicon Mac, native (MPS stays enabled too)
Versions (no built-in default for torch and torchcodec: name them on every run)
  --torch=VER             torch to build, e.g. 2.14.1 (the Vulkan backend is in the tree up to 2.14.1)    [TORCH]
  --torchcodec=VER        torchcodec to build, e.g. 0.17.0 (>= 0.12 works with every torch >= 2.11);       [CODEC]
                          only required when torchcodec is in --pkgs
  --torchaudio=VER        default: $AUDIO, the last torchaudio release (stable ABI: any torch >= 2.11)       [AUDIO]
Options taking a value accept both --option=VALUE and --option VALUE                      [env]
  -l, --list              what this machine can build now
  --only "T1 T2"          build only these targets                                        [ONLY]
  --pkgs "torch ..."      packages to build                                               [PKGS]    default: $PKGS
  --py "3.10 3.12"        Python versions, one full torch build each                       [PYS]     default: $PYS
  --suffix TAG            local version tag, e.g. 2.14.1+$SUFFIX                           [SUFFIX]  default: $SUFFIX
  --root DIR              sources, build tools, venvs and wheels                           [ROOT]    default: ./pytorch-vulkan
  --jobs N                parallel compile jobs, ~2 GB RAM each                            [JOBS]    default: $JOBS (CPU threads, capped by RAM)
  --clean                 git clean the checkouts first                                    [CLEAN=1]
  --force                 rebuild packages whose wheel is already in dist/                 [FORCE=1]
                          default: a package whose <pkg>-<ver>+<suffix> wheel for this Python is already in
                          <root>/dist/<target> is skipped (no sync, no build) and that wheel is used
  --codec-ffmpeg MODE     torchcodec FFmpeg: auto, s3 (PyTorch's LGPL builds, all majors), [CODEC_FFMPEG] default: auto
                          local (pkg-config; the wheel is only redistributable if that FFmpeg is LGPL)
                          auto = s3 where it exists (Linux, macOS arm64), else local if found, else torchcodec is skipped
  --no-bundle             do not put the Vulkan loader (macOS: + MoltenVK) into the torch wheel   [NO_BUNDLE=1]
  --macos-min X.Y         oldest macOS the wheels run on                                   [MACOS_MIN] default: $MACOS_MIN
  --keep-images           keep the Docker images this run pulled                           [KEEP_IMAGES=1] default: removed
  --no-install-sdk        macOS: do not install the LunarG SDK when it is missing          [INSTALL_SDK=0] default: installs it
  --no-install-ffmpeg     macOS: do not install an ffmpeg@N keg for torchcodec             [INSTALL_FFMPEG=0] default: installs it
                          (latest SDK into ~/VulkanSDK, checksum-verified; brings MoltenVK, the loader and glslc)
  --install-vulkan        run the Vulkan install job on any host                           [INSTALL_VK=1]
  --no-install-vulkan     never run it                                                     [INSTALL_VK=0]  default: arm64/aarch64 hosts
                          macOS: reports whether the GPU has Metal (MoltenVK runs on it)
                          Linux: detects the GPU and, if it has a Vulkan driver (Jetson, Pi 4/5 V3DV, Mali PanVK,
                          Adreno Turnip, AMD RADV, NVIDIA, NVK), installs the loader + driver packages, then runs the
                          op probe on this host with the built wheels; a GPU without one is reported and the probe skipped
  -h, --help
Output
  <root>/dist/<target>/<pkg>-<ver>+<suffix>-cpXY-cpXY-<platform>.whl (Linux: manylinux_2_28_<arch>)
  Linux: Vulkan headers + loader ($VK_TAG) and glslc (shaderc $SHADERC_TAG) are compiled once per arch into <root>/tools/<arch>
  Sources stay in <root>/src-<target> for fast rebuilds. Each build ends with a probe of the Vulkan ops TTS models use.
Needs
  Linux: Docker (used directly as root, through sudo otherwise) and network access
    linux-aarch64-vulkan-qemu: QEMU arm64 binfmt (docker run --privileged --rm tonistiigi/binfmt --install arm64)
  macOS: Xcode Command Line Tools, git, curl, the LunarG Vulkan SDK (found in ~/VulkanSDK, or VULKAN_SDK=<sdk>/macOS)
    macos-x86_64-vulkan torchcodec: Homebrew; the newest ffmpeg@N keg torchcodec accepts is installed automatically
  uv is installed if missing; Python versions come from uv (macOS) or the manylinux image (Linux)
  Vulkan install job on Linux: apt, dnf or pacman, through sudo when not root
Examples
  ./build-torch-vulkan.sh --list
  ./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0
  ./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --py="3.10 3.12" --jobs=8
  ./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --only=linux-aarch64-vulkan-qemu --jobs=16
  ./build-torch-vulkan.sh --torch=2.14.1 --pkgs=torch            # torch only, no torchcodec version needed
  ./build-torch-vulkan.sh --torch=2.14.1 --torchcodec=0.17.0 --pkgs="torchaudio torchcodec"
EOF
}
need(){ [ $# -ge 2 ] || die "$1 needs a value (see --help)"; }
while [ $# -gt 0 ]; do
  # --option=value is the same as --option value
  case "$1" in --*=*) a="$1"; shift; set -- "${a%%=*}" "${a#*=}" "$@";; esac
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
    --jobs) need "$@"; JOBS="$2"; JOBS_USER=1; shift;;
    --codec-ffmpeg) need "$@"; CODEC_FFMPEG="$2"; shift;;
    --macos-min) need "$@"; MACOS_MIN="$2"; shift;;
    --clean) CLEAN=1;;
    --no-bundle) NO_BUNDLE=1;;
    --keep-images) KEEP_IMAGES=1;;
    --install-vulkan) INSTALL_VK=1;;
    --no-install-vulkan) INSTALL_VK=0;;
    --no-install-sdk) INSTALL_SDK=0;;
    --no-install-ffmpeg) INSTALL_FFMPEG=0;;
    --force) FORCE=1;;
    --in-container) need "$@"; IN_CONTAINER="$2"; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac
  shift
done
case "$CODEC_FFMPEG" in auto|s3|local) ;; *) die "--codec-ffmpeg must be auto, s3 or local";; esac
for p in $PKGS; do case "$p" in torch|torchaudio|torchcodec) ;; *) die "unknown package $p (torch, torchaudio, torchcodec)";; esac; done
want(){ case " $PKGS " in *" $1 "*) return 0;; esac; return 1; }
# torch's version is needed on every build (torchaudio / torchcodec build against that torch wheel), torchcodec's only
# when it is built; --list needs neither
if [ "$LIST" != 1 ]; then
  [ -n "$TORCH" ] || die "--torch=VER is required, e.g. --torch=2.14.1 (see --help)"
  if want torchcodec && [ -z "$CODEC" ]; then die "--torchcodec=VER is required when torchcodec is built, e.g. --torchcodec=0.17.0 (or leave it out of --pkgs)"; fi
fi
macos_sdk(){
  if [ -n "${VULKAN_SDK:-}" ]; then echo "$VULKAN_SDK"; return 0; fi
  ls -d "$HOME"/VulkanSDK/*/macOS 2>/dev/null | sort -V | tail -1 || true
}
codec_avcodec_ok(){  # libavcodec major -> ok if this torchcodec supports it (read from its checkout, 58..62 = FFmpeg 4..8 otherwise)
  local f majors="58 59 60 61 62"
  f="${SRC:-/nonexistent}/torchcodec/src/torchcodec/share/cmake/TorchCodec/ffmpeg_versions.cmake"
  if [ -f "$f" ]; then majors="$(grep -o 'libavcodec_major_version} STREQUAL "[0-9]*"' "$f" | grep -o '"[0-9]*"' | tr -d '"' | tr '\n' ' ')"; fi
  case " $majors " in *" $1 "*) return 0;; esac
  return 1
}
ffmpeg_pc_dir(){  # prints the pkg-config dir to prepend ("" = the default one) for an FFmpeg this torchcodec supports
  command -v pkg-config >/dev/null 2>&1 || return 1
  local d v pcp bp="" cands="DEFAULT"
  if command -v brew >/dev/null 2>&1; then bp="$(brew --prefix 2>/dev/null || true)"; fi
  if [ -n "$bp" ]; then
    for d in ffmpeg@8 ffmpeg@7 ffmpeg@6 ffmpeg@5 ffmpeg@4; do if [ -d "$bp/opt/$d/lib/pkgconfig" ]; then cands="$cands $bp/opt/$d/lib/pkgconfig"; fi; done
  fi
  for d in $cands; do
    if [ "$d" = DEFAULT ]; then pcp=""; else pcp="$d"; fi
    v="$(PKG_CONFIG_PATH="$pcp${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config --modversion libavcodec 2>/dev/null || true)"
    [ -n "$v" ] || continue
    codec_avcodec_ok "${v%%.*}" || continue
    PKG_CONFIG_PATH="$pcp${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config --exists libavutil libavcodec libavformat libavfilter libswscale libswresample || continue
    echo "$pcp"
    return 0
  done
  return 1
}
ffmpeg_hint(){  # why no usable local FFmpeg was found, and what to install
  local v; v="$(pkg-config --modversion libavcodec 2>/dev/null || true)"
  if [ -n "$v" ] && ! codec_avcodec_ok "${v%%.*}"; then echo "the installed FFmpeg (libavcodec $v) is newer than torchcodec $CODEC supports"
  else echo "no FFmpeg dev libs found - set PKG_CONFIG_PATH, or on macOS let the script install one with Homebrew"; fi
}
local_ffmpeg(){ ffmpeg_pc_dir >/dev/null; }
codec_ffmpeg_majors(){  # FFmpeg majors this torchcodec maps libavcodec to, newest first (8 7 6 5 4 for 0.11.1)
  local f="${SRC:-/nonexistent}/torchcodec/src/torchcodec/share/cmake/TorchCodec/ffmpeg_versions.cmake"
  if [ -f "$f" ]; then grep -o 'set(ffmpeg_major_version "[0-9]*")' "$f" | grep -o '[0-9][0-9]*' | sort -rn | uniq | tr '\n' ' '; else echo "8 7 6 5 4"; fi
}
can_brew_ffmpeg(){ [ "$OS" = Darwin ] && [ "$INSTALL_FFMPEG" = 1 ] && command -v brew >/dev/null 2>&1; }
brew_install_ffmpeg(){  # install the newest Homebrew ffmpeg@N keg whose libavcodec this torchcodec accepts
  local n bp v
  can_brew_ffmpeg || return 1
  bp="$(brew --prefix)"
  if ! command -v pkg-config >/dev/null 2>&1; then log "installing pkgconf with Homebrew"; brew install -q pkgconf || return 1; fi
  for n in $(codec_ffmpeg_majors); do
    # already installed (by name, or as an alias of the main ffmpeg formula): ffmpeg_pc_dir has judged it, never touch it
    [ -d "$bp/opt/ffmpeg@$n/lib/pkgconfig" ] && continue
    if brew list --versions "ffmpeg@$n" >/dev/null 2>&1; then continue; fi
    log "installing ffmpeg@$n with Homebrew for torchcodec (keg-only: your default ffmpeg is left as it is)"
    if ! brew install -q "ffmpeg@$n"; then log "ffmpeg@$n is not installable here, trying the next major"; continue; fi
    if ffmpeg_pc_dir >/dev/null; then return 0; fi
    v="$(PKG_CONFIG_PATH="$bp/opt/ffmpeg@$n/lib/pkgconfig" pkg-config --modversion libavcodec 2>/dev/null || echo '?')"
    log "ffmpeg@$n has libavcodec $v, which torchcodec $CODEC does not accept - removing it again"
    brew uninstall -q "ffmpeg@$n" >/dev/null 2>&1 || true
  done
  return 1
}
codec_mode(){  # target -> s3 | local | skip
  if [ "$CODEC_FFMPEG" != auto ]; then echo "$CODEC_FFMPEG"; return 0; fi
  case "$1" in
    macos-x86_64-*) if local_ffmpeg || can_brew_ffmpeg; then echo local; else echo skip; fi;;
    *) echo s3;;
  esac
}
# ---------------------------------------------------------------- Vulkan install job
install_on(){
  case "$INSTALL_VK" in 1) return 0;; 0) return 1;; esac
  case "$HOST_ARCH" in aarch64|arm64) return 0;; esac
  return 1
}
gpu_check(){  # sets GPU_OK (1/0), GPU_NAME, GPU_NOTE, GPU_MESA (Mesa driver family to install, empty if the driver ships its own)
  GPU_OK=0; GPU_NAME="none"; GPU_NOTE=""; GPU_MESA=""
  if [ "$OS" = Darwin ]; then
    GPU_NAME="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2; exit}')"
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -q 'Metal'; then GPU_OK=1; GPU_NOTE="Metal GPU, Vulkan through MoltenVK"; else GPU_NOTE="no Metal support, MoltenVK cannot run"; fi
    return 0
  fi
  if [ -f /etc/nv_tegra_release ]; then
    GPU_OK=1; GPU_NAME="NVIDIA Jetson, L4T $(sed -n '1s/^# R\([0-9]*\).*REVISION: \([0-9.]*\).*/\1.\2/p' /etc/nv_tegra_release)"; GPU_NOTE="Vulkan driver ships with JetPack"
    return 0
  fi
  local d drv found=""
  for d in /sys/class/drm/card[0-9]*; do
    [ -e "$d/device/driver" ] || continue
    drv="$(basename "$(readlink -f "$d/device/driver")")"
    case " $found " in *" $drv "*) ;; *) found="$found $drv";; esac
  done
  for drv in $found; do
    case "$drv" in
      v3d) GPU_OK=1; GPU_NAME="Broadcom VideoCore VI/VII, v3d"; GPU_MESA=broadcom; GPU_NOTE="Mesa V3DV";;
      panfrost|panthor) GPU_OK=1; GPU_NAME="Arm Mali, $drv"; GPU_MESA=panfrost; GPU_NOTE="Mesa PanVK, needs a recent Mesa";;
      msm) GPU_OK=1; GPU_NAME="Qualcomm Adreno, msm"; GPU_MESA=freedreno; GPU_NOTE="Mesa Turnip";;
      amdgpu) GPU_OK=1; GPU_NAME="AMD, amdgpu"; GPU_MESA=radeon; GPU_NOTE="Mesa RADV";;
      nouveau) GPU_OK=1; GPU_NAME="NVIDIA, nouveau"; GPU_MESA=nouveau; GPU_NOTE="Mesa NVK, Turing or newer with Mesa 24.1+";;
      nvidia|nvidia-drm) GPU_OK=1; GPU_NAME="NVIDIA, proprietary driver"; GPU_NOTE="Vulkan ships with the NVIDIA driver";;
      i915|xe) GPU_OK=1; GPU_NAME="Intel, $drv"; GPU_MESA=intel; GPU_NOTE="Mesa ANV";;
    esac
    if [ "$GPU_OK" = 1 ]; then return 0; fi
  done
  if [ -n "$found" ]; then GPU_NAME="${found# }"; GPU_NOTE="no Vulkan driver exists for this GPU (vc4, lima, etnaviv, ...)"; else GPU_NOTE="no GPU under /sys/class/drm"; fi
}
vk_working(){ command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary 2>/dev/null | grep -i 'deviceName' | grep -qiv 'llvmpipe'; }
install_vulkan_linux(){
  if vk_working; then log "Vulkan already works on this host"; return 0; fi
  local sudo="" mesa=""
  if [ "$(id -u)" != 0 ]; then sudo="sudo"; fi
  log "installing the Vulkan loader and driver for: $GPU_NAME"
  if command -v apt-get >/dev/null 2>&1; then
    if [ -n "$GPU_MESA" ]; then mesa="mesa-vulkan-drivers"; fi
    $sudo apt-get update -qq
    $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libvulkan1 vulkan-tools $mesa
  elif command -v dnf >/dev/null 2>&1; then
    if [ -n "$GPU_MESA" ]; then mesa="mesa-vulkan-drivers"; fi
    $sudo dnf install -y -q vulkan-loader vulkan-tools $mesa
  elif command -v pacman >/dev/null 2>&1; then
    if [ -n "$GPU_MESA" ]; then mesa="vulkan-$GPU_MESA"; fi
    $sudo pacman -S --needed --noconfirm vulkan-icd-loader vulkan-tools $mesa
  else
    log "WARNING: no apt, dnf or pacman - install the Vulkan loader, vulkaninfo and your GPU's Vulkan driver by hand"
    return 0
  fi
  if vk_working; then
    log "Vulkan works: $(vulkaninfo --summary 2>/dev/null | awk -F'= ' '/deviceName/{print $2; exit}')"
  else
    log "WARNING: still no Vulkan device after installing - the driver may need a newer Mesa or kernel (see vulkaninfo --summary)"
  fi
}
install_vulkan_macos(){
  local ver tmp app exe exp got
  ver="$(curl -fsSL https://vulkan.lunarg.com/sdk/latest/mac.txt)" || die "cannot reach vulkan.lunarg.com"
  tmp="$(mktemp -d)"
  log "installing the LunarG Vulkan SDK $ver into $HOME/VulkanSDK/$ver"
  curl -fL -o "$tmp/vulkan_sdk.zip" "https://sdk.lunarg.com/sdk/download/$ver/mac/vulkan_sdk.zip"
  exp="$(curl -fsSL "https://sdk.lunarg.com/sdk/sha/$ver/mac/vulkan_sdk.zip.txt" 2>/dev/null | awk '{print $1; exit}' || true)"
  if [ ${#exp} = 64 ]; then
    got="$(shasum -a 256 "$tmp/vulkan_sdk.zip" | awk '{print $1}')"
    [ "$(echo "$exp" | tr 'A-F' 'a-f')" = "$got" ] || die "checksum mismatch for vulkan_sdk.zip"
  else
    log "WARNING: no published checksum for vulkan_sdk.zip, skipping verification"
  fi
  (cd "$tmp" && unzip -q vulkan_sdk.zip)
  app="$(find "$tmp" -maxdepth 2 -name '*.app' -type d | head -1)"
  [ -n "$app" ] || die "no installer app inside vulkan_sdk.zip"
  exe="$(ls "$app/Contents/MacOS/" | head -1)"
  "$app/Contents/MacOS/$exe" --root "$HOME/VulkanSDK/$ver" --accept-licenses --default-answer --confirm-command install
  rm -rf "$tmp"
  [ -f "$HOME/VulkanSDK/$ver/macOS/include/vulkan/vulkan.h" ] || die "the SDK install did not produce $HOME/VulkanSDK/$ver/macOS"
}
host_probe(){  # target: install the built wheels into a host venv and run the op probe on this host's GPU
  local T="$1" venv w
  DIST="$ROOT/dist/$T"
  if ! command -v uv >/dev/null 2>&1; then curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$PATH"; fi
  for V in $PYS; do
    TAG="cp${V/./}"
    venv="$ROOT/venv-probe-$T-$V"
    rm -rf "$venv"
    uv venv -q --seed --python "$V" "$venv"
    PY="$venv/bin/python"
    export VIRTUAL_ENV="$venv"
    WHL="$(ls -t "$DIST/torch-$TORCH+$SUFFIX-$TAG"-*.whl 2>/dev/null | head -1 || true)"
    if [ -z "$WHL" ]; then log "no torch $TORCH+$SUFFIX $TAG wheel in $DIST to probe"; continue; fi
    "$PY" -m pip install -q "$WHL"
    WHL="$(ls -t "$DIST/torchaudio-$AUDIO+$SUFFIX-$TAG"-*.whl 2>/dev/null | head -1 || true)"
    if [ -n "$WHL" ]; then install_whl; fi
    WHL="$(ls -t "$DIST/torchcodec-$CODEC+$SUFFIX-$TAG"-*.whl 2>/dev/null | head -1 || true)"
    if [ -n "$WHL" ]; then install_whl; fi
    log "host probe on $GPU_NAME:"
    probe
  done
}
# ---------------------------------------------------------------- native build (in a manylinux container, or on a Mac)
sync_repo(){  # name url version clean
  local path="$SRC/$1"
  if [ ! -d "$path/.git" ]; then git clone -c core.longpaths=true --recursive "$2" "$path"; fi
  git -C "$path" fetch -q --tags --force origin
  # builds rewrite tracked files (torchcodec <= 0.11 writes BUILD_VERSION into version.txt): restore them, or
  # switching to another tag is refused
  if ! git -C "$path" diff --quiet -- version.txt 2>/dev/null; then git -C "$path" checkout -q -- version.txt; fi
  if [ "$4" = 1 ]; then
    git -C "$path" reset -q --hard
    git -C "$path" clean -q -xdf
    git -C "$path" submodule foreach -q --recursive "git reset -q --hard; git clean -q -xdf"
  fi
  git -C "$path" -c advice.detachedHead=false checkout -q "v$3" || die "$1: cannot switch to v$3 - local changes in $path (git -C $path status), rerun with --clean to reset it"
  git -C "$path" submodule sync -q --recursive
  git -C "$path" submodule update -q --init --recursive
}
built_whl(){  # package version -> the wheel already in dist/ for this version, suffix and Python ("" if none or --force)
  if [ "$FORCE" = 1 ]; then return 0; fi
  ls -t "$DIST/$1-$2+$SUFFIX-$TAG"-*.whl 2>/dev/null | head -1 || true
}
pip_wheel(){  # package version; env already exported by the caller's subshell. Other versions in dist/ are kept
  rm -f "$DIST/$1-$2+"*-"$TAG"-*.whl "$DIST/$1-$2-$TAG"-*.whl
  (cd "$SRC/$1" && "$PY" -m pip wheel . --no-build-isolation --no-deps -v -w "$DIST")
  WHL="$(ls -t "$DIST/$1"-*-"$TAG"-*.whl 2>/dev/null | head -1 || true)"
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
    # rpaths into the Vulkan SDK would load the SDK's loader before the bundled one (and leak the build path)
    for dylib in "$lib"/*.dylib; do
      [ -L "$dylib" ] && continue
      local rp drop=""
      for rp in $(otool -l "$dylib" | awk '/cmd LC_RPATH/{getline;getline;print $2}'); do
        case "$rp" in "$VULKAN_SDK"*) install_name_tool -delete_rpath "$rp" "$dylib"; drop=1;; esac
      done
      if [ -n "$drop" ]; then case " $signed " in *" $dylib "*) ;; *) signed="$signed $dylib";; esac; fi
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
  # a build tree from another torch version (or from before this marker existed) is started over once
  if [ -d "$SRC/torch/build" ] && [ "$(cat "$SRC/torch/build/.vk_tag" 2>/dev/null)" != "$TORCH" ]; then
    log "torch: build tree is not from $TORCH - removing it, full build"
    rm -rf "$SRC/torch/build"
  fi
  local r
  for r in requirements-build.txt requirements.txt; do
    if [ -f "$SRC/torch/$r" ]; then "$PY" -m pip install -q -r "$SRC/torch/$r"; fi
  done
  # x86_64: MKL for BLAS/FFT like the official wheels (without it torch falls back to Eigen's BLAS, much slower matmuls).
  # pip's mkl-static links in statically; Linux threads it with GNU OpenMP like torch, macOS uses the sequential MKL
  # so no Intel OpenMP runtime is needed. Enabling it changes torch's config: reconfigure once (marker file)
  local mkl=0 pfx
  case "$TARGET" in
    *x86_64*) if "$PY" -m pip install -q mkl-static mkl-include; then mkl=1; else log "WARNING: MKL not installable here, torch keeps Eigen's slower BLAS"; fi;;
  esac
  pfx="$("$PY" -c 'import sys;print(sys.prefix)')"
  (
    if [ "$mkl" = 1 ]; then
      export CMAKE_PREFIX_PATH="$pfx${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
      if [ "$OS" = Darwin ]; then export MKL_THREADING=SEQ; fi
      if [ -f "$SRC/torch/build/CMakeCache.txt" ] && [ ! -f "$SRC/torch/build/.vk_mkl" ]; then
        export CMAKE_FRESH=1
        log "torch: reconfiguring once to build with MKL - this recompiles a large part of ATen"
      fi
    fi
    # USE_VULKAN_WRAPPER is Android-only in torch: desktop builds always link the Vulkan loader, hence the bundling
    export USE_VULKAN=1 USE_VULKAN_WRAPPER=0 USE_VULKAN_SHADERC_RUNTIME=0 USE_VULKAN_FP16_INFERENCE=0 USE_VULKAN_RELAXED_PRECISION=0
    export BUILD_TEST=0 PYTORCH_BUILD_VERSION="$TORCH+$SUFFIX" PYTORCH_BUILD_NUMBER=1
    # link one library at a time: linking libtorch_cpu alone takes many GB next to the parallel compiles;
    # a build tree configured before this gets one reconfigure (compiled objects are kept)
    export CMAKE_JOB_POOLS="vk_link=1" CMAKE_JOB_POOL_LINK=vk_link
    if [ -f "$SRC/torch/build/CMakeCache.txt" ] && ! grep -q CMAKE_JOB_POOL_LINK "$SRC/torch/build/CMakeCache.txt"; then export CMAKE_FRESH=1; fi
    pip_wheel torch "$TORCH"
    echo "$WHL" > "$DIST/.whl"
  )
  if [ "$mkl" = 1 ]; then touch "$SRC/torch/build/.vk_mkl"; fi
  echo "$TORCH" > "$SRC/torch/build/.vk_tag"
  WHL="$(cat "$DIST/.whl")"
  if [ "$NO_BUNDLE" != 1 ]; then bundle_vulkan; fi
  retag
  install_whl
  BUILT="$BUILT $WHL"
}
build_torchaudio(){
  (
    export USE_FFMPEG=0 BUILD_SOX=0 BUILD_VERSION="$AUDIO+$SUFFIX"
    pip_wheel torchaudio "$AUDIO"
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
    log "skipping torchcodec: no prebuilt FFmpeg for $TARGET and no usable local one: $(ffmpeg_hint)"
    return 0
  fi
  # torchcodec >= 0.12 builds with scikit-build-core (no build isolation here, so it must be in the venv)
  "$PY" -m pip install -q pybind11 scikit-build-core
  # torchcodec builds in minutes: always configure fresh, a cached CMake keeps the Python and the FFmpeg it found first
  rm -rf "$SRC/torchcodec/build"
  local cml=src/torchcodec/_core/CMakeLists.txt
  git -C "$SRC/torchcodec" checkout -q -- "$cml"
  if { [ -n "${AUDITWHEEL_PLAT:-}" ] || [ "$OS" = Darwin ]; } && grep -q 'COMPONENTS Development[ )]' "$SRC/torchcodec/$cml"; then
    # an extension module must get its Python symbols from the running interpreter, not link libpython: manylinux
    # Pythons ship no libpython on purpose, and on macOS linking it bakes the build machine's absolute path into
    # the wheel. Only the headers (Development.Module) are needed; macOS also needs -undefined dynamic_lookup
    sed -i.orig 's/COMPONENTS Development\([ )]\)/COMPONENTS Development.Module\1/' "$SRC/torchcodec/$cml" && rm -f "$SRC/torchcodec/$cml.orig"
    log "torchcodec: Python Development.Module only, no libpython link"
  fi
  (
    export BUILD_VERSION="$CODEC+$SUFFIX"
    # torchcodec >= 0.12 also builds image decoders, each one required (libjpeg, libpng, libwebp, libavif, libheif...);
    # audio/video only unless asked for: TORCHCODEC_BUILD_IMAGE=1
    export TORCHCODEC_BUILD_IMAGE="${TORCHCODEC_BUILD_IMAGE:-0}"
    if [ "$OS" = Darwin ]; then export LDFLAGS="-undefined dynamic_lookup${LDFLAGS:+ $LDFLAGS}"; fi
    # torchcodec's CMake does find_package(pybind11), which never looks inside a pip-installed pybind11
    pybind11_ROOT="$("$PY" -m pybind11 --cmakedir)"
    export pybind11_ROOT CMAKE_PREFIX_PATH="$pybind11_ROOT${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    if [ "$mode" = s3 ]; then
      export BUILD_AGAINST_ALL_FFMPEG_FROM_S3=1
    else
      local pcp
      if ! pcp="$(ffmpeg_pc_dir)"; then
        brew_install_ffmpeg || die "no usable local FFmpeg for torchcodec: $(ffmpeg_hint)"
        pcp="$(ffmpeg_pc_dir)"
      fi
      if [ -n "$pcp" ]; then export PKG_CONFIG_PATH="$pcp${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"; fi
      log "torchcodec: FFmpeg $(pkg-config --modversion libavcodec | cut -d. -f1) libavcodec from ${pcp:-the default pkg-config path}"
      export I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1
      log "WARNING: torchcodec built against the local FFmpeg - only redistribute it if that FFmpeg is an LGPL build"
    fi
    pip_wheel torchcodec "$CODEC"
    echo "$WHL" > "$DIST/.whl"
  )
  git -C "$SRC/torchcodec" checkout -q -- "$cml"
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
cfg=torch.__config__.show()
print('cpu blas:','MKL' if 'USE_MKL=ON' in cfg else 'Accelerate' if 'accelerate' in cfg.lower() else 'OpenBLAS' if 'openblas' in cfg.lower() else 'Eigen (slow)' if 'USE_EIGEN_FOR_BLAS=ON' in cfg else 'unknown')
for mod in ['torchaudio','torchcodec']:
    try:
        m=__import__(mod)
        print(mod,m.__version__)
    except Exception as e:
        print(mod,'not available:')
        for l in str(e).splitlines()[:12]:print('   ',l[:160])
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
    if [ -z "$VULKAN_SDK" ] || [ ! -f "$VULKAN_SDK/include/vulkan/vulkan.h" ]; then
      if [ "$INSTALL_SDK" = 1 ]; then install_vulkan_macos; VULKAN_SDK="$(macos_sdk)"; else die "no Vulkan SDK (see --help)"; fi
    fi
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
    # CMake's FindPython checks VIRTUAL_ENV before macOS framework Pythons (e.g. Homebrew's) and PATH
    export VIRTUAL_ENV="$venv"
    "$PY" -m pip install -q cmake ninja setuptools wheel
    # a package whose wheel for this version, suffix and Python is already in dist/ is skipped (no sync, no build)
    tw="$(built_whl torch "$TORCH")"; aw="$(built_whl torchaudio "$AUDIO")"; cw="$(built_whl torchcodec "$CODEC")"
    if want torch && [ -z "$tw" ]; then sync_repo torch https://github.com/pytorch/pytorch.git "$TORCH" "$clean_now"; fi
    if want torchaudio && [ -z "$aw" ]; then sync_repo torchaudio https://github.com/pytorch/audio.git "$AUDIO" "$clean_now"; fi
    if want torchcodec && [ -z "$cw" ]; then sync_repo torchcodec https://github.com/pytorch/torchcodec.git "$CODEC" "$clean_now"; fi
    if want torch && [ -z "$tw" ]; then
      build_torch
    else
      WHL="$tw"
      if [ -z "$WHL" ]; then WHL="$(ls -t "$DIST/torch-$TORCH+$SUFFIX-$TAG"-*.whl 2>/dev/null | head -1 || true)"; fi
      [ -n "$WHL" ] || die "torch is not in --pkgs and no torch-$TORCH+$SUFFIX $TAG wheel is in $DIST to build against"
      if want torch; then log "torch $TORCH+$SUFFIX ($TAG) already built, skipped: $(basename "$WHL")"; BUILT="$BUILT $WHL"; fi
      "$PY" -m pip install -q "$WHL"
    fi
    if want torchaudio; then
      if [ -n "$aw" ]; then log "torchaudio $AUDIO+$SUFFIX ($TAG) already built, skipped: $(basename "$aw")"; WHL="$aw"; install_whl; BUILT="$BUILT $WHL"; else build_torchaudio; fi
    fi
    if want torchcodec; then
      if [ -n "$cw" ]; then log "torchcodec $CODEC+$SUFFIX ($TAG) already built, skipped: $(basename "$cw")"; WHL="$cw"; install_whl; BUILT="$BUILT $WHL"; else build_torchcodec; fi
    fi
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
    aarch64) ALL="linux-aarch64-vulkan";;
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
        [ "$INSTALL_SDK" = 1 ] || m="$m LunarG Vulkan SDK (or VULKAN_SDK=<sdk>/macOS, or drop --no-install-sdk),"
      else
        [ -x "$sdk/bin/glslc" ] || m="$m glslc in $sdk/bin,"
        [ -f "$sdk/lib/libvulkan.1.dylib" ] || m="$m Vulkan loader in $sdk/lib,"
        [ -f "$sdk/lib/libMoltenVK.dylib" ] || m="$m MoltenVK in $sdk/lib,"
      fi
      if want torchcodec && [ "$CODEC_FFMPEG" = local ] && ! local_ffmpeg && ! can_brew_ffmpeg; then m="$m usable FFmpeg - $(ffmpeg_hint),"; fi;;
  esac
  if [ -n "$m" ]; then echo "missing:${m%,} (see --help)"; fi
}
note(){
  case "$1" in *-qemu) echo " (only with --only)";; esac
  case "$1" in macos-*) if [ "$INSTALL_SDK" = 1 ] && [ ! -f "$(macos_sdk)/include/vulkan/vulkan.h" ]; then echo " (installs the Vulkan SDK first)"; fi;; esac
  if want torchcodec && [ "$(codec_mode "$1")" = skip ]; then echo " (torchcodec skipped: $(ffmpeg_hint))"; fi
  if want torchcodec && [ "$(codec_mode "$1")" = local ] && ! local_ffmpeg; then echo " (installs a torchcodec-compatible ffmpeg@N with Homebrew)"; fi
}
if [ "$LIST" = 1 ]; then
  echo "targets on this $HOST machine:"
  for T in $ALL; do r="$(missing "$T")"; printf '  %-28s %s\n' "$T" "${r:-ready$(note "$T" | tr -d '\n')}"; done
  if install_on; then
    gpu_check
    echo "GPU: $GPU_NAME - $GPU_NOTE"
    if [ "$OS" = Linux ]; then
      if [ "$GPU_OK" != 1 ]; then echo "Vulkan install job: nothing to install for this GPU, the host probe is skipped"
      elif vk_working; then echo "Vulkan install job: Vulkan already works, the built wheels get probed on this host"
      else echo "Vulkan install job: installs the loader + driver packages, then probes the built wheels on this host"; fi
    fi
  fi
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
GPU_OK=0
if install_on; then
  gpu_check
  log "GPU: $GPU_NAME - $GPU_NOTE"
  if [ "$OS" = Linux ]; then
    if [ "$GPU_OK" = 1 ]; then install_vulkan_linux; else log "no Vulkan-capable GPU here: the wheels still build, the host probe is skipped"; fi
  fi
fi
for T in $ONLY; do
  case "$T" in
    macos-*) native_build "$T";;
    linux-*)
      case "$T" in linux-x86_64-*) A=x86_64; PLAT=linux/amd64;; *) A=aarch64; PLAT=linux/arm64;; esac
      IMG="quay.io/pypa/manylinux_2_28_$A"
      PULLED=0
      if ! $DOCKER image inspect "$IMG" >/dev/null 2>&1; then $DOCKER pull --platform "$PLAT" "$IMG"; PULLED=1; fi
      log "=== $T in $IMG"
      $DOCKER run --rm --platform "$PLAT" -v "$ROOT":/work -v "$SELF":/build-torch-vulkan.sh:ro -e TORCH="$TORCH" -e AUDIO="$AUDIO" -e CODEC="$CODEC" -e SUFFIX="$SUFFIX" -e PYS="$PYS" -e PKGS="$PKGS" -e JOBS="$JOBS" -e CLEAN="$CLEAN" -e NO_BUNDLE="$NO_BUNDLE" -e CODEC_FFMPEG="$CODEC_FFMPEG" -e FORCE="$FORCE" -e VK_TAG="$VK_TAG" -e SHADERC_TAG="$SHADERC_TAG" -e HOST_ID="$(id -u):$(id -g)" "$IMG" bash /build-torch-vulkan.sh --in-container "$T"
      if [ "$PULLED" = 1 ] && [ "$KEEP_IMAGES" != 1 ]; then $DOCKER rmi "$IMG" >/dev/null || true; fi;;
  esac
done
if [ "$OS" = Linux ] && [ "$GPU_OK" = 1 ] && vk_working; then
  for T in $ONLY; do
    case "$T" in *-qemu) continue;; linux-"$HOST_ARCH"-*) host_probe "$T";; esac
  done
fi
log "done: wheels in $ROOT/dist/"
