#!/usr/bin/env bash
# Saves the image as a zstd tarball with a checksum file next to it.
#   scripts/export-image.sh [out-dir]
set -euo pipefail
IMAGE="${IMAGE:-vllm-orin:0.29}"
OUT="${1:-.}/${IMAGE//:/-}.tar.zst"
docker save "$IMAGE" | zstd -T0 -3 -o "$OUT"
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
ls -lh "$OUT"; cat "$OUT.sha256"
