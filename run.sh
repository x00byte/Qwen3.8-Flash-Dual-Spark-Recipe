#!/usr/bin/env bash
set -euo pipefail

# Qwen3.8 Flash Next Dual Spark Recipe — one-command bring-up.
# Run this ON THE HEAD node (node 0). The worker (node 1) is driven over SSH.
#
# What it does:
#   1. pulls the image on both nodes
#   2. downloads the model on the head (if missing)
#   3. rsyncs the model to the worker
#   4. drops page cache on both nodes (GB10 unified-memory load safety)
#   5. launches worker (headless) then head (API server)

IMAGE="${IMAGE:-oxbyte/qwen3.8-flash-next-dual-spark:latest}"
WORKER="${WORKER:-user@worker-ip}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
MODEL_REPO="${MODEL_REPO:-RadixArk/Qwen3.8-Flash-Next-NVFP4}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/RadixArk/Qwen3.8-Flash-Next-NVFP4}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/qwen38-flash-next-dual-spark}"
NAME="${NAME:-qwen38-flash-next-nvfp4-vllm}"
MASTER_ADDR="${MASTER_ADDR:-192.168.1.1}"
MASTER_PORT="${MASTER_PORT:-29501}"
SPEC_TOKENS="${SPEC_TOKENS:-4}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-8}"

SSH=(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$WORKER")

echo "[recipe] 1/5 pull image on both nodes"
docker pull "$IMAGE"
"${SSH[@]}" "docker pull $IMAGE"

echo "[recipe] 2/5 download model on head (if missing)"
MODEL_REPO="$MODEL_REPO" MODEL_DIR="$MODEL_DIR" IMAGE="$IMAGE" ./download-model.sh

echo "[recipe] 3/5 sync model to worker"
"${SSH[@]}" "mkdir -p $MODEL_DIR"
rsync -a --info=progress2 \
  -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=no" \
  "$MODEL_DIR/" "$WORKER:$MODEL_DIR/"

echo "[recipe] 4/5 drop page cache on both nodes"
docker run --rm --privileged --entrypoint sh "$IMAGE" \
  -c 'sync; echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1 || true
"${SSH[@]}" "docker run --rm --privileged --entrypoint sh $IMAGE -c 'sync; echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1 || true"

echo "[recipe] 5/5 launch worker (rank 1) + head (rank 0)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
"${SSH[@]}" "docker rm -f $NAME >/dev/null 2>&1 || true"

mkdir -p "$CACHE_DIR"/{hf,vllm,triton,inductor,torch}
"${SSH[@]}" "mkdir -p $CACHE_DIR/{hf,vllm,triton,inductor,torch}"

COMMON="--network host --ipc host --privileged --gpus all --shm-size 32g --device /dev/infiniband --ulimit memlock=-1 --ulimit stack=67108864"
ENVS="-e NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1 -e NCCL_SOCKET_IFNAME=enp1s0f1np1 -e GLOO_SOCKET_IFNAME=enp1s0f1np1 -e NCCL_IB_ROCE_VERSION_NUM=2 -e NCCL_CUMEM_ENABLE=0 -e NCCL_NVLS_ENABLE=0 -e HF_HOME=/compile-cache/hf -e HF_HUB_OFFLINE=1 -e TRANSFORMERS_OFFLINE=1 -e VLLM_CACHE_ROOT=/compile-cache/vllm -e TRITON_CACHE_DIR=/compile-cache/triton -e TORCHINDUCTOR_CACHE_DIR=/compile-cache/inductor -e TORCH_HOME=/compile-cache/torch"
VOLS="-v $MODEL_DIR:/model:ro -v $CACHE_DIR:/compile-cache"
TUNE="-e MASTER_ADDR=$MASTER_ADDR -e MASTER_PORT=$MASTER_PORT -e SPEC_TOKENS=$SPEC_TOKENS -e MAX_MODEL_LEN=$MAX_MODEL_LEN -e MAX_NUM_SEQS=$MAX_NUM_SEQS"

echo "[recipe] starting worker (node-rank 1) on $WORKER"
"${SSH[@]}" "docker run -d --name $NAME $COMMON $ENVS $VOLS $TUNE -e NODE_RANK=1 -e HEADLESS=1 $IMAGE"

echo "[recipe] starting head (node-rank 0) on this node"
docker run -d --name "$NAME" $COMMON $ENVS $VOLS $TUNE -e NODE_RANK=0 "$IMAGE"

echo "[recipe] launched. Watch with:"
echo "  docker logs -f $NAME               (head)"
echo "  ssh $WORKER docker logs -f $NAME   (worker)"
echo "  curl http://127.0.0.1:8888/v1/models"
