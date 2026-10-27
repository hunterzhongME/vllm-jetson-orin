#!/usr/bin/env bash
# Builds the vLLM wheel into $VLLM_WORK/src/dist (several hours on an AGX Orin).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${VLLM_WORK:-/mnt/ros_data/vllm29}"
cd "$WORK/src"
export CMAKE_BUILD_TYPE=Release
date -u '+Build started: %Y-%m-%d %H:%M:%S UTC'
# --build-temp must go on the parent `build` command: on build_ext alone, bdist_wheel
# reinitializes it and packaging fails with a missing CMake cache after the full compile.
bash "$HERE/run-env.sh" uv run --no-project --python .venv/bin/python \
  .venv/bin/python setup.py build --build-temp cmake-build-release bdist_wheel
date -u '+Build finished: %Y-%m-%d %H:%M:%S UTC'
ls -l dist/*.whl
