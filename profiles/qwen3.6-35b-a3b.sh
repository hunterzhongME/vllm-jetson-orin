# Qwen3.6-35B-A3B AWQ 4-bit: the VLM the Realtime work-mistake detection uses.
MODEL_REPO=cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit
MODEL_REV=00fcea2d3bcf5389b518d4fc082e5590e0ba4844
SERVED=qwen3.6-35b-a3b
MAX_LEN=131072
GPU_MEM=0.6
# Up to 64 images per request: the Realtime side sends a time series of pictures in one request.
MM_LIMIT='{"image":64,"video":0}'
EXTRA_ARGS=(
  --kv-cache-memory 4294967296
  --default-chat-template-kwargs '{"enable_thinking":false}'
  --structured-outputs-config '{"backend": "xgrammar", "disable_any_whitespace": true}'
)
