#!/usr/bin/env bash
# Runs a command inside the wheel-build environment (venv, CUDA, caches under $VLLM_WORK).
# Usage: wheel/run-env.sh <command...>
set -euo pipefail
export V29="${VLLM_WORK:-/mnt/ros_data/vllm29}"
unset PYTHONPATH PYTHONHOME VLLM_ROOT VLLM_USE_PRECOMPILED VLLM_USE_PRECOMPILED_RUST
unset PYTORCH_CUDA_ALLOC_CONF PYTORCH_ALLOC_CONF
export PYTHONNOUSERSITE=1
export VIRTUAL_ENV="$V29/venv"
export PATH="$V29/tools:$V29/venv/bin:/usr/local/cuda/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
export CUDA_HOME=/usr/local/cuda
export CPATH=/usr/local/cuda/include
export LD_LIBRARY_PATH="$V29/venv/lib/python3.10/site-packages/nvidia/cu12/lib:/usr/local/cuda/lib64:/usr/local/cuda/targets/aarch64-linux/lib"
export HF_HOME="${HF_HOME:-/mnt/ros_data/hf}"
export PIP_CACHE_DIR="$V29/.pip-cache"
export UV_CACHE_DIR="$V29/cache/uv"
export UV_SYSTEM_CERTS=true
export PIP_CONSTRAINT="$(cd "$(dirname "$0")" && pwd)/constraints.txt"
export VLLM_CACHE_ROOT="$V29/cache/vllm"
export TRITON_CACHE_DIR="$V29/cache/triton"
export TORCHINDUCTOR_CACHE_DIR="$V29/cache/torchinductor"
export TORCH_EXTENSIONS_DIR="$V29/cache/torch-extensions"
export CUDA_CACHE_PATH="$V29/cache/cuda"
export TORCH_CUDA_ARCH_LIST=8.7
export VLLM_TARGET_DEVICE=cuda
export VLLM_USE_FLASHINFER_SAMPLER=0
export VLLM_VERSION_OVERRIDE=0.29.0+jetson.sm87.cu126
# Six jobs with one nvcc thread each is what fit in the Orin's 64 GB during the original build.
export MAX_JOBS=6
export NVCC_THREADS=1
export VLLM_FLASH_ATTN_SRC_DIR="$V29/flash-attention"
export NO_PROXY="127.0.0.1,localhost,${NO_PROXY:-}"
export no_proxy="$NO_PROXY"
exec "$@"
