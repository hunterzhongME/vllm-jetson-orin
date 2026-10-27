#!/usr/bin/env bash
# Checks that this Jetson can run the image: AGX Orin, L4T R36.4, nvidia runtime, disk.
set -uo pipefail
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
[[ "$model" == *"AGX Orin"* ]] && ok "board: $model" || bad "board: '$model' (needs Jetson AGX Orin; the wheel is sm_87 only)"

rel=$(head -1 /etc/nv_tegra_release 2>/dev/null)
[[ "$rel" == *"R36 (release), REVISION: 4."* ]] && ok "L4T: $rel" || bad "L4T: '$rel' (needs JetPack 6.2 / R36.4.x)"

mem_gb=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
(( mem_gb >= 60 )) && ok "memory: ${mem_gb} GB" || bad "memory: ${mem_gb} GB (profiles assume the 64 GB Orin)"

docker info 2>/dev/null | grep -q 'Runtimes:.*nvidia' && ok "docker nvidia runtime" \
  || bad "docker nvidia runtime missing (install nvidia-container-toolkit)"

dir="${HF_DIR:-/mnt/ros_data/hf}"
probe="$dir"; while [[ ! -d "$probe" ]]; do probe=$(dirname "$probe"); done
free_gb=$(df -BG --output=avail "$probe" | tail -1 | tr -dc 0-9)
(( free_gb >= 60 )) && ok "free space near $dir: ${free_gb} GB" \
  || bad "free space near $dir: ${free_gb} GB (image ~16 GB + model ~24 GB + cache)"

docker image inspect "${IMAGE:-vllm-orin:0.29}" >/dev/null 2>&1 && ok "image ${IMAGE:-vllm-orin:0.29} loaded" \
  || echo "info  image ${IMAGE:-vllm-orin:0.29} not loaded yet"
exit $fail
