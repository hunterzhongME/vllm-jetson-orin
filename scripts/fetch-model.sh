#!/usr/bin/env bash
# Downloads a profile's model at its pinned revision into $HF_DIR, using the hf CLI inside the image.
#   scripts/fetch-model.sh [profile]          (default profile: qwen3.6-35b-a3b)
# Without Hugging Face access, rsync models--<org>--<name> from another Orin instead (see README).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-qwen3.6-35b-a3b}"
# shellcheck source=/dev/null
source "$ROOT/profiles/$PROFILE.sh"

IMAGE="${IMAGE:-vllm-orin:0.29}"
HF_DIR="${HF_DIR:-/mnt/ros_data/hf}"
mkdir -p "$HF_DIR"
# The image sets HF_HUB_OFFLINE=1 for serving; downloading needs it off. Pass the host proxy through.
docker run --rm --entrypoint hf -v "$HF_DIR:$HF_DIR" -e HF_HOME="$HF_DIR" -e HF_HUB_OFFLINE=0 \
  -e HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}" -e HF_TOKEN="${HF_TOKEN:-}" \
  --user "$(id -u):$(id -g)" \
  "$IMAGE" download "$MODEL_REPO" --revision "$MODEL_REV"
