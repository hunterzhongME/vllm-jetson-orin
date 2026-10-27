#!/usr/bin/env bash
# Checks out vLLM and FlashAttention at the pinned commits under $VLLM_WORK and applies patches/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES="$HERE/../patches"
WORK="${VLLM_WORK:-/mnt/ros_data/vllm29}"
VLLM_COMMIT=98dff2a81d747d1dba01a47f939f48c3526d4206          # v0.29.0
FA_COMMIT=06bdd47c0d0383daf6a2ff0c418faff9c6da16e5

checkout() {  # <url> <dir> <commit>
  if [[ ! -d "$2/.git" ]]; then
    git init -q "$2"
    git -C "$2" remote add origin "$1"
  fi
  git -C "$2" fetch -q --depth 1 origin "$3"
  git -C "$2" checkout -q --detach "$3"
}

mkdir -p "$WORK"
checkout https://github.com/vllm-project/vllm.git "$WORK/src" "$VLLM_COMMIT"
git -C "$WORK/src" apply "$PATCHES/001-native-marlin-sm87.patch" "$PATCHES/003-existing-jetson-torch.patch"

checkout https://github.com/vllm-project/flash-attention.git "$WORK/flash-attention" "$FA_COMMIT"
# Only CUTLASS is needed; composable_kernel / aiter are ROCm-only.
git -C "$WORK/flash-attention" submodule update --init --depth 1 csrc/cutlass
git -C "$WORK/flash-attention" apply "$PATCHES/002-native-flash-attention-sm87.patch"

ln -sfn "$WORK/venv" "$WORK/src/.venv"
echo "sources ready under $WORK"
