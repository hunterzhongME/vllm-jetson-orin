#!/usr/bin/env bash
# Creates the build venv under $VLLM_WORK with the Jetson torch stack and applies the library fixes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${VLLM_WORK:-/mnt/ros_data/vllm29}"
ENV="$HERE/run-env.sh"
JETSON_INDEX=https://pypi.jetson-ai-lab.io/jp6/cu126

python3 -m venv "$WORK/venv"
bash "$ENV" python -m pip install -U pip 'setuptools>=77.0.3,<81' wheel
bash "$ENV" python -m pip install numpy==2.2.6
bash "$ENV" python -m pip install torch==2.11.0 triton==3.6.0 nvidia-cudss-cu12==0.8.0.10 --index-url "$JETSON_INDEX"
bash "$ENV" python -m pip install --no-deps torchvision==0.26.0 --index-url "$JETSON_INDEX"
bash "$ENV" python "$HERE/fix-jetson-libs.py"
