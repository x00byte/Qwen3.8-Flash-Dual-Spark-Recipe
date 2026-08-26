#!/usr/bin/env bash
set -euo pipefail

# Qwen3.8 Flash Next NVFP4 — dual DGX Spark (TP=2, vLLM mp executor, no Ray).
# One container per node:
#   head   (node 0): NODE_RANK=0              -> API server + engine core
#   worker (node 1): NODE_RANK=1 HEADLESS=1   -> workers only
# Every tunable is env-overridable so the same image works for any Spark pair.

MODEL="${MODEL:-/model}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen38-flash-next-nvfp4}"
MASTER_ADDR="${MASTER_ADDR:-192.168.1.1}"
MASTER_PORT="${MASTER_PORT:-29501}"
NNODES="${NNODES:-2}"
NODE_RANK="${NODE_RANK:-0}"
TP="${TP:-2}"
SPEC_TOKENS="${SPEC_TOKENS:-4}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.85}"
PORT="${PORT:-8888}"
HEADLESS="${HEADLESS:-}"

ARGS=(
  "$MODEL"
  --served-model-name "$SERVED_MODEL_NAME"
  --quantization modelopt_fp4
  --tensor-parallel-size "$TP"
  --pipeline-parallel-size 1
  --nnodes "$NNODES"
  --master-addr "$MASTER_ADDR"
  --master-port "$MASTER_PORT"
  --node-rank "$NODE_RANK"
  --distributed-executor-backend mp
  --enforce-eager
  --speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":${SPEC_TOKENS}}"
  --max-model-len "$MAX_MODEL_LEN"
  --max-num-seqs "$MAX_NUM_SEQS"
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS"
  --enable-chunked-prefill
  --enable-prefix-caching
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
  --tool-call-parser qwen3_coder
  --enable-auto-tool-choice
  --reasoning-parser qwen3
  --host 0.0.0.0
  --port "$PORT"
)

if [[ "${HEADLESS:-}" == "1" || "${HEADLESS:-}" == "true" ]]; then
  ARGS+=(--headless)
fi

exec vllm serve "${ARGS[@]}" "$@"
