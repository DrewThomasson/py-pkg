#!/usr/bin/env bash
# build-torch-jetson.bash — torch+torchaudio wheels for JetPack 5 / 6 / 7, all built in docker from a Xavier NX R35 host
# layout: ROOT = folder of this script ; $ROOT/pytorch/torch, $ROOT/pytorch/torchaudio (shared git repos) ; $ROOT/v5|v6|v7/{venv,wheels,*.log} (per target)
# usage:  ./build-torch-jetson.bash 5|6|7 [torch_ver] [audio_ver]
# env:    RESUME=1 (skip checkout/clean, continue existing build/), ROOT, PYVER (default 3.10, uv-managed CPython), MAX_JOBS (default 3), CCCL_DIR (JP5 only, must live under $ROOT: newer CUB/Thrust headers for CUDA 11.4)
set -euo pipefail
JP="${1:?usage: $0 5|6|7 [torch_ver] [audio_ver]}"
ROOT="${ROOT:-$(cd "$(dirname "$(realpath "$0")")"&&pwd)}"
case "$JP" in
	5) TAG=v5;LOCAL=jetson5;TORCH_VER="${2:-2.3.1}";AUDIO_VER="${3:-2.3.1}";MAXVER=2.4.1;ARCH="7.2;8.7";IMAGE="nvcr.io/nvidia/l4t-jetpack:r35.4.1";GPU="--runtime nvidia";;
	6) TAG=v6;LOCAL=jetson6;TORCH_VER="${2:-2.8.0}";AUDIO_VER="${3:-2.8.0}";ARCH="8.7";IMAGE="nvcr.io/nvidia/l4t-jetpack:r36.4.0";GPU="";;
	7) TAG=v7;LOCAL=jetson7;TORCH_VER="${2:-2.9.1}";AUDIO_VER="${3:-2.9.1}";ARCH="8.7;11.0";IMAGE="nvcr.io/nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04";GPU="";;
	*) echo "JP must be 5, 6 or 7";exit 1;;
esac
if test -n "${MAXVER:-}"&&test "$(printf '%s\n%s\n' "$TORCH_VER" "$MAXVER"|sort -V|tail -1)" != "$MAXVER";then
	echo "JP$JP supports torch <= $MAXVER (asked $TORCH_VER)";exit 1
fi
PYVER="${PYVER:-3.10}"
# repos under $ROOT/pytorch, or next to this script when it lives in that folder itself ($ROOT/torch already a clone)
REPOS="${REPOS:-$ROOT/pytorch}"
if test ! -d "$REPOS/torch/.git" -a -d "$ROOT/torch/.git";then
	REPOS="$ROOT"
fi
OUT="$ROOT/$TAG"
LOCK="$REPOS/.build.lock"
deps(){
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y git build-essential cmake ninja-build ccache curl ca-certificates libopenblas-dev libjpeg-dev zlib1g-dev
	command -v uv >/dev/null||curl -LsSf https://astral.sh/uv/install.sh|env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
	export UV_PYTHON_INSTALL_DIR="$ROOT/.uv/python" UV_CACHE_DIR="$ROOT/.uv/cache"
	uv python install "$PYVER"
}
checkout(){
	# $1=repo dir, $2=url, $3=tag
	test -d "$1/.git"||git clone --no-checkout "$2" "$1"
	cd "$1"
	git fetch --force origin tag "$3" --no-tags
	git checkout -f "$3"
	git submodule sync --recursive
	git submodule update --init --recursive --force --jobs 4
	git clean -xdff
	git submodule foreach --recursive 'git clean -xdff'
}
build(){
	mkdir -p "$OUT/wheels"
	if test "${RESUME:-0}" != 1;then
		checkout "$REPOS/torch" https://github.com/pytorch/pytorch "v$TORCH_VER"
		checkout "$REPOS/torchaudio" https://github.com/pytorch/audio "v$AUDIO_VER"
	fi
	if test -x "$OUT/venv/bin/python";then
		test "$("$OUT/venv/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)" = "$PYVER"||rm -rf "$OUT/venv"
	else
		rm -rf "$OUT/venv"
	fi
	test -d "$OUT/venv"||uv venv --seed --python "$PYVER" --managed-python "$OUT/venv"
	source "$OUT/venv/bin/activate"
	pip install -U pip setuptools wheel ninja
	pip install -r "$REPOS/torch/requirements.txt"
	pip install "cmake>=3.27,<4"
	export CMAKE_POLICY_VERSION_MINIMUM=3.5
	export CUDA_HOME=/usr/local/cuda PATH="/usr/local/cuda/bin:$PATH"
	export USE_CUDA=1 USE_CUDNN=1 TORCH_CUDA_ARCH_LIST="$ARCH" MAX_JOBS="${MAX_JOBS:-3}"
	export USE_NCCL=0 USE_MPI=0 USE_DISTRIBUTED=1 USE_QNNPACK=0 USE_PYTORCH_QNNPACK=0 BUILD_TEST=0
	export USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_PRIORITIZED_TEXT_FOR_LD=1
	export PYTORCH_BUILD_VERSION="$TORCH_VER+$LOCAL" PYTORCH_BUILD_NUMBER=1
	if test "$JP" = 5 -a -n "${CCCL_DIR:-}";then
		export TORCH_NVCC_FLAGS="-I$CCCL_DIR/cub -I$CCCL_DIR/thrust -I$CCCL_DIR/libcudacxx/include"
	fi
	# torch < 2.5 appends $LDFLAGS to CMAKE_SHARED_LINKER_FLAGS, which cmake already initialized from it: with
	# USE_PRIORITIZED_TEXT_FOR_LD setup.py puts -T cmake/linker_script.ld in LDFLAGS and ld rejects it twice (libc10.so).
	# Append only when not already there, as torch >= 2.5 does. Re-applied every run (checkout cleans the tree), no-op once patched
	perl -0pi -e 's/  set\(CMAKE_SHARED_LINKER_FLAGS\n\s+"\$\{CMAKE_SHARED_LINKER_FLAGS\} \$ENV\{LDFLAGS\}"\)\n/  string(STRIP "\$ENV{LDFLAGS}" JTB_LDFLAGS)\n  string(FIND "\${CMAKE_SHARED_LINKER_FLAGS}" "\${JTB_LDFLAGS}" JTB_LDFLAGS_POS)\n  if(JTB_LDFLAGS_POS EQUAL -1)\n    set(CMAKE_SHARED_LINKER_FLAGS "\${CMAKE_SHARED_LINKER_FLAGS} \${JTB_LDFLAGS}")\n  endif()\n/' "$REPOS/torch/CMakeLists.txt"
	cd "$REPOS/torch"
	python setup.py bdist_wheel -d "$OUT/wheels" 2>&1|tee "$OUT/torch-build.log"
	pip install --force-reinstall --no-deps "$OUT/wheels/torch-$TORCH_VER+$LOCAL-"*.whl
	cd "$REPOS/torchaudio"
	export BUILD_VERSION="$AUDIO_VER+$LOCAL" PYTORCH_VERSION="$TORCH_VER+$LOCAL" USE_FFMPEG=0 BUILD_SOX=0
	python setup.py bdist_wheel -d "$OUT/wheels" 2>&1|tee "$OUT/torchaudio-build.log"
	pip install --force-reinstall --no-deps "$OUT/wheels/torchaudio-$AUDIO_VER+$LOCAL-"*.whl
	cd /tmp
	python -c "import torch,torchaudio;print(torch.__version__,torch.version.cuda,torch.cuda.get_arch_list(),torchaudio.__version__)"
	ls -1 "$OUT/wheels"
}
free -g|awk '/Swap/{if($2<15)print "WARNING: swap < 16G, torch build will likely OOM"}'
if test -z "${IN_CONTAINER:-}";then
	mkdir -p "$REPOS" "$OUT"
	exec 9>"$LOCK";flock -n 9||{ echo "another build is using $REPOS";exit 1;}
	docker run --rm -it $GPU -e IN_CONTAINER=1 -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e PYVER="$PYVER" -e RESUME="${RESUME:-0}" -e ROOT="$ROOT" -e REPOS="$REPOS" -e MAX_JOBS="${MAX_JOBS:-3}" -e CCCL_DIR="${CCCL_DIR:-}" -v "$ROOT:$ROOT" -v "$(realpath "$0"):/build.bash:ro" "$IMAGE" bash -c "bash /build.bash $JP $TORCH_VER $AUDIO_VER"
	exit 0
fi
trap 'chown -R "$HOST_UID:$HOST_GID" "$REPOS" "$OUT" "$ROOT/.uv" 2>/dev/null||true' EXIT
deps
git config --global --add safe.directory '*'
build
