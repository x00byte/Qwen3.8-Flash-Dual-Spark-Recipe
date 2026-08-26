#!/usr/bin/env bash
set -euo pipefail

# Download RadixArk/Qwen3.8-Flash-Next-NVFP4 (126 GiB) using the recipe image's
# own `hf` CLI — no host Python needed. Set HF_TOKEN if the repo is gated.
#   https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4

MODEL_REPO="${MODEL_REPO:-RadixArk/Qwen3.8-Flash-Next-NVFP4}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/RadixArk/Qwen3.8-Flash-Next-NVFP4}"
IMAGE="${IMAGE:-oxbyte/qwen3.8-flash-next-dual-spark:latest}"

if [[ -f "$MODEL_DIR/model.safetensors.index.json" ]]; then
  echo "[download] $MODEL_DIR already has the checkpoint — skipping."
  exit 0
fi

mkdir -p "$MODEL_DIR"

HF_ARGS=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  HF_ARGS+=(--token "$HF_TOKEN")
fi

echo "[download] pulling $MODEL_REPO into $MODEL_DIR (this is ~126 GiB)..."
# Run as the host user so the checkpoint files are owned by the same user that
# will rsync them to the worker node (avoids root-owned files breaking rsync -a).
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e HF_HOME=/tmp/hf-cache \
  -e HF_TOKEN="${HF_TOKEN:-}" \
  -v "$MODEL_DIR":/model \
  --entrypoint /usr/local/bin/hf \
  "$IMAGE" download "$MODEL_REPO" --local-dir /model "${HF_ARGS[@]}"

echo "[download] done: $MODEL_DIR"
