#!/usr/bin/env python3
"""Container-native launcher for vLLM 0.29 Gemma E2B on Jetson Orin.

Runs `vllm serve` directly as PID 1 (the container is the process/isolation
boundary, so server.py's run-env.sh + venv + process-group logic is not needed).
Model locations are env-driven so they map to bind mounts, defaulting to the
paths this machine already uses.

Flags (all optional):
  --config {A,B,C}   A=BF16 baseline, B=INT4 body+BF16 head, C=INT4 body+head (default C)
  --mtp {0,1,2,4}    speculative draft tokens (default 4)
  --context N        max model len (default 32768)
  --gpu-memory-utilization F   fraction of the 61 GB unified pool (default 0.45)
  --multimodal [--max-images N]   enable the vision tower (default off)
  --host / --port    default 0.0.0.0 : 8002
Env: LLM_API_KEY (adds --api-key), and the *_PATH overrides below.
"""
import argparse, json, os, sys

HF = os.environ.get("HF_HOME", "/mnt/ros_data/hf") + "/hub"
# config -> (served name, env var for the target checkpoint, default path)
CONFIGS = {
    "A": ("google/gemma-4-E2B-it",
          "MODEL_PATH_A",
          f"{HF}/models--google--gemma-4-E2B-it/snapshots/3e22461f65e89153144f8adb70e3b8c2cc9845a7"),
    "B": ("local/e2b-gptq-g128-head-bf16",
          "MODEL_PATH_B",
          "/mnt/ros_data/vllm29/quantization/runner/runs/full-001/bf16-head"),
    "C": ("local/e2b-gptq-g128-head-int4",
          "MODEL_PATH_C",
          "/mnt/ros_data/vllm29/quantization/runner/runs/full-001/int4-head"),
}
DRAFT = os.environ.get(
    "DRAFT_PATH",
    f"{HF}/models--google--gemma-4-E2B-it-assistant/snapshots/2d874ef7d29f9a30599a1e4b3c1cbc9595f005df")

p = argparse.ArgumentParser()
p.add_argument("--config", type=str.upper, choices=list(CONFIGS), default="C")
p.add_argument("--mtp", type=int, choices=[0, 1, 2, 4], default=4)
p.add_argument("--context", type=int, default=32768)
p.add_argument("--gpu-memory-utilization", type=float, default=0.45)
p.add_argument("--multimodal", action="store_true")
p.add_argument("--max-images", type=int, default=1)
p.add_argument("--host", default="0.0.0.0")
p.add_argument("--port", type=int, default=8002)
a = p.parse_args()

name, env_key, default_path = CONFIGS[a.config]
model = os.environ.get(env_key, default_path)
if not os.path.isdir(model):
    sys.exit(f"[entrypoint] checkpoint for config {a.config} not found: {model}\n"
             f"  bind-mount it into the container (see DEPLOY.md), or set {env_key}.")

cmd = ["vllm", "serve", model,
       "--served-model-name", name,
       "--host", a.host, "--port", str(a.port),
       "--dtype", "bfloat16",
       "--gpu-memory-utilization", str(a.gpu_memory_utilization),
       "--attention-config", '{"backend":"TRITON_ATTN"}',
       "--no-enable-prefix-caching",
       "--max-model-len", str(a.context),
       "--max-num-batched-tokens", "4096", "--max-num-seqs", "1",
       "--no-enable-log-requests", "--enable-per-request-metrics"]
if a.mtp:
    if not os.path.isdir(DRAFT):
        sys.exit(f"[entrypoint] MTP requested but draft model not found: {DRAFT}")
    cmd += ["--speculative-config",
            json.dumps({"method": "mtp", "model": DRAFT, "num_speculative_tokens": a.mtp})]
if a.multimodal:
    cmd += ["--limit-mm-per-prompt", json.dumps({"image": a.max_images, "video": 0, "audio": 0}),
            "--mm-processor-cache-gb", "0.5"]
else:
    cmd += ["--language-model-only"]
if os.environ.get("LLM_API_KEY"):
    cmd += ["--api-key", os.environ["LLM_API_KEY"]]

print("[entrypoint]", " ".join(cmd), flush=True)
os.execvp(cmd[0], cmd)   # replace PID 1 with vllm
