#!/usr/bin/env bash
# Starts `vllm serve` for a profile in the container and waits until the model is listed.
#   scripts/serve.sh [profile] [extra vllm serve args...]     (default profile: qwen3.6-35b-a3b)
# Env: IMAGE, NAME, PORT, HF_DIR (holds hub/), CACHE_DIR (torch.compile/Triton cache),
#      VLLM_DOCKER_ARGS (extra `docker run` args, e.g. -v to swap a file in the image).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-qwen3.6-35b-a3b}"; shift || true
# shellcheck source=/dev/null
source "$ROOT/profiles/$PROFILE.sh"

IMAGE="${IMAGE:-vllm-orin:0.29}"
NAME="${NAME:-vllm-test}"
PORT="${PORT:-8091}"
HF_DIR="${HF_DIR:-/mnt/ros_data/hf}"
CACHE_DIR="${CACHE_DIR:-/mnt/ros_data/docker/volumes/vllm-cache/_data}"
MODEL="$HF_DIR/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REV"
read -r -a DOCKER_EXTRA <<< "${VLLM_DOCKER_ARGS:-}"

[[ -d "$MODEL" ]] || { echo "model not found: $MODEL (copy it first, see README)"; exit 1; }
mkdir -p "$CACHE_DIR"

docker rm -f "$NAME" >/dev/null 2>&1 || true
# --runtime nvidia: the default runtime on JetPack is runc, which hides the GPU.
# --shm-size 8g: the EngineCore is a second process over shared memory; the 64 MB default crashes it.
docker run -d --name "$NAME" --runtime nvidia --shm-size 8g -p "$PORT:$PORT" --entrypoint vllm \
  "${DOCKER_EXTRA[@]}" \
  -v "$HF_DIR:$HF_DIR" -v "$CACHE_DIR:/root/.cache" \
  -e HF_HOME="$HF_DIR" -e HF_HUB_OFFLINE=1 -e VLLM_USE_FLASHINFER_SAMPLER=0 \
  "$IMAGE" serve "$MODEL" --served-model-name "$SERVED" --host 0.0.0.0 --port "$PORT" \
  --max-model-len "$MAX_LEN" --max-num-seqs 1 --gpu-memory-utilization "$GPU_MEM" \
  --limit-mm-per-prompt "$MM_LIMIT" --no-enable-log-requests "${EXTRA_ARGS[@]}" "$@" >/dev/null

for _ in $(seq 1 150); do
  if curl --noproxy '*' -s -m 2 "localhost:$PORT/v1/models" | grep -q "$SERVED"; then
    echo "$SERVED ready on :$PORT"; exit 0
  fi
  docker ps --format '{{.Names}}' | grep -q "^$NAME\$" || { docker logs "$NAME" 2>&1 | grep -i error | tail -3; exit 1; }
  sleep 10
done
echo "timeout (see: docker logs $NAME)"; exit 1
