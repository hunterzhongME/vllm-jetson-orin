# vllm-jetson-orin

vLLM 0.29 built natively for sm_87, packaged as a Docker image (`vllm-orin:0.29`) for the
**Jetson AGX Orin 64GB on JetPack 6.2 (L4T R36.4.x)**. It serves the VLM that the
DMSHI-PALette-PoC `Realtime/` work-mistake detection calls through the OpenAI-compatible API.

The image will not run on Orin NX/Nano, on another JetPack version or on a discrete GPU:
the wheel is compiled for sm_87 against CUDA 12.6 and torch 2.11.

This repo holds the recipe only. Binaries stay out of git and are checked by hash:

| Artifact | Size | Hash |
| --- | --- | --- |
| Image `ghcr.io/hunterzhongme/vllm-orin:0.29` | 16.3 GB | image ID in `artifacts.lock.json` |
| vLLM wheel | 126 MB | `artifacts.lock.json` |
| `docker/wheels/` (full offline wheel closure for the image build) | 1.5 GB | `docker/wheels.sha256` |

The image already contains the vLLM wheel and all of `docker/wheels/` (in `/build/wheels`),
so the image is the only binary that needs storing. To recover the wheels for a rebuild:

```bash
docker create --name w vllm-orin:0.29 && docker cp w:/build/wheels docker/wheels && docker rm w
```
| Model `cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit` | 24 GB | HF revision in `profiles/` |

The original working machine keeps everything under `/mnt/ros_data/vllm29` (build tree) and
`/mnt/ros_data/hf` (models).

## Deploying to another Orin

The image is pulled from ghcr.io. Rebuilding the wheel takes hours.

```bash
git clone https://github.com/hunterzhongME/vllm-jetson-orin && cd vllm-jetson-orin
scripts/check-host.sh

# Needs a classic PAT with read:packages (ghcr rejects GitHub CLI login tokens).
# Paste it into a file with an editor; in vim, press i before pasting.
docker login ghcr.io -u hunterzhongme --password-stdin < ~/.ghcr.pat && rm ~/.ghcr.pat
docker pull ghcr.io/hunterzhongme/vllm-orin:0.29
docker tag ghcr.io/hunterzhongme/vllm-orin:0.29 vllm-orin:0.29

scripts/fetch-model.sh                          # 24 GB from Hugging Face at the pinned revision
scripts/serve.sh                                # qwen3.6-35b-a3b on :8091
```

Without registry or Hugging Face access, copy from an Orin that already has them:

```bash
scripts/export-image.sh /mnt/ros_data          # → vllm-orin-0.29.tar.zst + .sha256
rsync -P /mnt/ros_data/vllm-orin-0.29.tar.zst* target:/mnt/ros_data/
rsync -aP /mnt/ros_data/hf/hub/models--cyankiwi--Qwen3.6-35B-A3B-AWQ-4bit target:/mnt/ros_data/hf/hub/
# on the target
(cd /mnt/ros_data && sha256sum -c vllm-orin-0.29.tar.zst.sha256)
zstd -dc /mnt/ros_data/vllm-orin-0.29.tar.zst | docker load
```

Copy only the model you serve. The whole `/mnt/ros_data/hf` is over 200 GB.

The first start takes a few minutes because of torch.compile and CUDA graph capture. The
result is cached in `CACHE_DIR` (default `/mnt/ros_data/docker/volumes/vllm-cache/_data`),
so later starts skip it. You can copy that directory from the source Orin too; it is valid
only on identical hardware and JetPack.

Check that it is serving:

```bash
curl --noproxy '*' localhost:8091/v1/models
```

The Realtime side reaches it from inside its own container as `http://172.17.0.1:8091/v1`
(set `REALTIME_VLM_URL` / `REALTIME_VLM_MODEL`; see `Realtime/README.md` in the PoC repo).

### serve.sh

```
scripts/serve.sh [profile] [extra vllm serve args...]
```

- A profile in `profiles/` pins the model revision and the serve arguments. To add a model,
  add a profile.
- Environment overrides: `IMAGE`, `NAME` (container, default `vllm-test`), `PORT` (default 8091),
  `HF_DIR`, `CACHE_DIR`, and `VLLM_DOCKER_ARGS` for extra `docker run` arguments.
- Run one server per Orin. Two models do not fit next to each other at these memory settings.

The image's default entrypoint (`docker/entrypoint.py`) is the older Gemma E2B launcher. Its
checkpoints were quantized locally and live only on the original Orin. `serve.sh` bypasses it
with `--entrypoint vllm`.

## Rebuilding the image

The build is fully offline. Every wheel comes from `docker/wheels/`, because the Jetson pip
index can't be reached through the proxy from inside a build container. Put the wheels there
(extract them from the image as shown above) and verify them before building:

```bash
cd docker && sha256sum -c wheels.sha256 && docker build -t vllm-orin:0.29 .
```

The build ends with `import vllm, torch`, so a green build means the native sm_87 binaries load.

## Rebuilding the vLLM wheel

You need this only to change vLLM itself. Everything lives under `VLLM_WORK`
(default `/mnt/ros_data/vllm29`). Put `uv` in `$VLLM_WORK/tools` or on `PATH`.

```bash
export VLLM_WORK=/mnt/ros_data/vllm29
wheel/fetch-sources.sh     # vLLM v0.29.0 + FlashAttention at the pinned commits, patches applied
wheel/bootstrap.sh         # venv with the Jetson torch 2.11 / triton 3.6 / cuDSS wheels
wheel/build-wheel.sh       # hours; the wheel lands in $VLLM_WORK/src/dist
```

Then copy the wheel into `docker/wheels/`, update its line in `docker/wheels.sha256` and
`artifacts.lock.json`, and rebuild the image.

What the patches do:

| Patch | Change |
| --- | --- |
| `001-native-marlin-sm87.patch` | Adds sm_87 to the Marlin (dense/MoE) and Hadacore arch lists and to the FA2 arch list in vLLM. FP8-only lists stay unchanged. |
| `002-native-flash-attention-sm87.patch` | Adds sm_87 to FlashAttention's supported and FA2 arch lists. |
| `003-existing-jetson-torch.patch` | Output of upstream `use_existing_torch.py`: drops the torch pins so the Jetson torch wheels are kept. The real versions are pinned in `wheel/constraints.txt`. |

Things that bite:

- pip's CUDA 12.9 cuBLAS/NVRTC libraries shadow JetPack's 12.6 ones through torch's RPATH, which
  fails with `CUBLAS_STATUS_ALLOC_FAILED`. Triton's wheel also ships without `cuda.h` and `ptxas`,
  and torch needs `libcudss.so.0` in its lib dir. `wheel/fix-jetson-libs.py` (venv) and a `RUN`
  step in the Dockerfile (image) relink them.
- `VLLM_USE_FLASHINFER_SAMPLER=0` must be set: FlashInfer has no aarch64 build here.
- The vLLM wheel is installed with `--no-deps`, because its metadata lists x86-only packages
  (flashinfer, torchcodec, …).
- `--build-temp` goes on `setup.py build`, not `build_ext`. Otherwise packaging fails at the end
  with a missing CMake cache, after the full compile.
