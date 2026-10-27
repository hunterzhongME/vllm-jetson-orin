# vLLM 0.29 native sm_87 for Jetson AGX Orin 64GB (JetPack 6.2 / L4T R36.4.3 only).
# GPU driver comes from the host at runtime via `--runtime nvidia`; the CUDA
# toolkit (headers, ptxas, cuBLAS) ships inside this base image.
FROM nvcr.io/nvidia/l4t-jetpack:r36.4.0

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1

# The l4t-jetpack base ships no pip for the system python. Install it (+ a
# toolchain, in case any pinned dep is sdist-only for aarch64).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3-pip python3-dev build-essential git \
      libopenblas0-pthread libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# --- Python deps -----------------------------------------------------------
# torch/torchvision/triton/cudss are the Jetson-index wheels, baked into the
# build context (the index isn't reachable through this network's proxy from a
# build container, and baking makes the image reproducible offline). Everything
# else is pinned from the frozen venv and comes from PyPI. vLLM last, --no-deps.
COPY requirements-docker.txt /build/requirements-docker.txt
COPY wheels/ /build/wheels/
# 100% offline: every wheel is baked in /build/wheels (the full frozen closure of
# the working venv). No build-time network -> the network proxy can't interfere,
# and the image builds reproducibly on any Orin from the docker/ folder alone.
# vLLM is --no-deps on purpose: its METADATA lists x86/CUDA phantoms (flashinfer,
# torchcodec, quack-kernels...) with no aarch64 wheels that the venv omits.
RUN P="python3 -m pip install --no-index --find-links /build/wheels" \
 && $P --upgrade pip \
 && $P --no-deps \
      /build/wheels/torch-2.11.0-*.whl \
      /build/wheels/torchvision-0.26.0-*.whl \
      /build/wheels/triton-3.6.0-*.whl \
      /build/wheels/nvidia_cudss_cu12-0.8.0.10-*.whl \
 && $P --no-deps -r /build/requirements-docker.txt \
 && $P --no-deps /build/wheels/vllm-0.29.0+jetson.sm87.cu126-cp310-cp310-linux_aarch64.whl

# --- Jetson library fixes (baked, deterministic; replaces fix-jetson-libs.py) ---
# pip's CUDA 12.9 libs shadow the system 12.6 via torch RPATH -> CUBLAS_STATUS_ALLOC_FAILED;
# triton's wheel ships no cuda.h / ptxas; torch needs libcudss.so.0 in its lib dir.
# Paths are constructed from site-packages directly (NOT via `import torch`),
# because torch cannot import until libcudss is linked here -- that would be circular.
RUN set -euo pipefail; \
    SP=$(python3 -c 'import site;print(site.getsitepackages()[0])'); \
    SYS=/usr/local/cuda/targets/aarch64-linux/lib; \
    for l in cublas/lib/libcublas.so.12 cublas/lib/libcublasLt.so.12 \
             cublas/lib/libnvblas.so.12 cuda_nvrtc/lib/libnvrtc.so.12; do \
      src="$SYS/$(basename $l)"; dst="$SP/nvidia/$l"; \
      if [[ -e "$src" && -e "$dst" ]]; then mv "$dst" "$dst.pip-original"; ln -sf "$src" "$dst"; fi; \
    done; \
    TRI="$SP/triton/backends/nvidia"; \
    mkdir -p "$TRI/include" "$TRI/bin"; \
    ln -sf /usr/local/cuda/include/cuda.h "$TRI/include/cuda.h"; \
    ln -sf /usr/local/cuda/bin/ptxas      "$TRI/bin/ptxas"; \
    for c in "$SP"/nvidia/cu12/lib/libcudss*.so.0; do [[ -e "$c" ]] && ln -sf "$c" "$SP/torch/lib/$(basename $c)"; done; \
    echo "jetson lib fixes applied under $SP"

# --- Runtime config --------------------------------------------------------
# Required for this install; matches SERVING.md / the working venv.
ENV VLLM_USE_FLASHINFER_SAMPLER=0 \
    VLLM_ENABLE_FUSED_MOE_ACTIVATION_CHUNKING=0 \
    HF_HOME=/mnt/ros_data/hf \
    HF_HUB_OFFLINE=1

COPY entrypoint.py /app/entrypoint.py
WORKDIR /app

# Fail fast at build time if the native sm_87 images or imports are wrong.
RUN python3 -c "import vllm, torch; print('vllm', vllm.__version__, '| torch', torch.__version__, torch.version.cuda)"

EXPOSE 8002
ENTRYPOINT ["python3", "/app/entrypoint.py"]
CMD ["--config", "C", "--mtp", "4"]
