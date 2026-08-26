# Qwen3.8 Flash Next Dual Spark Recipe
# =====================================
# Self-contained vLLM image for serving
#   https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4
# across 2x NVIDIA DGX Spark (GB10 / aarch64 / sm_121a), TP=2 over the RoCE fabric.
#
# This image is meant to be PULLED, not rebuilt:
#   docker pull <your-dockerhub-user>/qwen3.8-flash-next-dual-spark:latest
# The Dockerfile below is only for auditing / rebuilding from NVIDIA's dev base.

FROM vllm/vllm-openai:qwen38-flash-next

# Fix the PLE n-gram embedding quant path for this hybrid NVFP4 + FP8 checkpoint.
# (see README "Why the patch" — without it the PLE table is silently served wrong
#  and then the FP8 scale collides as both parameter and buffer).
COPY ple_layer.py /usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py

# Bake in the dual-spark serve entrypoint (see serve.sh).
COPY serve.sh /usr/local/bin/qwen38-flash-next-serve
RUN chmod +x /usr/local/bin/qwen38-flash-next-serve

ENV MODEL=/model \
    SERVED_MODEL_NAME=qwen38-flash-next-nvfp4

ENTRYPOINT ["/usr/local/bin/qwen38-flash-next-serve"]
