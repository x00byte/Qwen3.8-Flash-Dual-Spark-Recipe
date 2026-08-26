# Qwen3.8 Flash Next — Dual Spark Recipe

Serve [RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4)
with **vLLM** across **2× NVIDIA DGX Spark** (GB10 / aarch64 / sm_121a), TP=2 over the RoCE fabric.
No Ray — just vLLM's `mp` distributed executor, one container per node.

<p align="center">
  <a href="https://github.com/x00byte/Qwen3.8-Flash-Dual-Spark-Recipe/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-blue"></a>
  <a href="https://hub.docker.com/r/oxbyte/qwen3.8-flash-next-dual-spark"><img alt="Docker" src="https://img.shields.io/badge/Docker-oxbyte%2Fqwen3.8--flash--next--dual--spark-2496ed"></a>
  <a href="#benchmarks"><img alt="tool-eval-bench" src="https://img.shields.io/badge/tool--eval--bench-91%2F100-brightgreen"></a>
  <a href="https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4"><img alt="Model" src="https://img.shields.io/badge/model-NVFP4%20%2B%20FP8%20PLE-orange"></a>
</p>

## Overview

This repository is a turn-key, production-style deployment recipe for running the
**Qwen3.8 Flash Next NVFP4** checkpoint on a pair of NVIDIA DGX Spark boxes. It ships a
patched, self-contained vLLM image and a one-command launcher that handles model download,
node-to-node sync, and dual-node bring-up.

| | |
|---|---|
| **Model** | [Qwen3.8 Flash Next NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4) (hybrid ModelOpt NVFP4 + FP8 PLE) |
| **Serving stack** | vLLM (patched `ple_layer.py`) |
| **Topology** | 2× DGX Spark (GB10), TP=2, `--nnodes 2`, mp executor |
| **Context window** | 262,144 tokens |
| **Concurrency** | 8 sequences |
| **Speculative decoding** | MTP, 4 tokens |
| **Execution mode** | `--enforce-eager` (CUDA graphs / torch.compile disabled) |
| **Tool calling** | `qwen3_coder` parser + auto tool choice + `qwen3` reasoning parser |
| **Image** | [`oxbyte/qwen3.8-flash-next-dual-spark`](https://hub.docker.com/r/oxbyte/qwen3.8-flash-next-dual-spark) |

## Quick start (dual Spark)

Run this **on the head node** (rank 0), with passwordless SSH to the worker node (rank 1).
Set `WORKER`, `SSH_KEY`, and `MASTER_ADDR` for your fabric (see [Configuration](#configuration)):

```bash
git clone https://github.com/x00byte/Qwen3.8-Flash-Dual-Spark-Recipe.git
cd Qwen3.8-Flash-Dual-Spark-Recipe
./run.sh
```

`run.sh` does everything:

1. `docker pull` the published image on both nodes
2. download the 126 GiB checkpoint into `~/models/RadixArk/Qwen3.8-Flash-Next-NVFP4` (head)
3. rsync it to the worker node
4. drop page cache on both nodes (GB10 unified-memory load safety)
5. launch the worker (`--headless`, rank 1) then the head (rank 0, API on `:8888`)

Watch it boot:

```bash
docker logs -f qwen38-flash-next-nvfp4-vllm                     # head
ssh "$WORKER" docker logs -f qwen38-flash-next-nvfp4-vllm # worker
```

Check readiness:

```bash
curl http://127.0.0.1:8888/v1/models
# -> {"id":"qwen38-flash-next-nvfp4","max_model_len":262144,...}
```

## Benchmarks

Full tool-calling evaluation with
[tool-eval-bench](https://github.com/SeraphimSerapis/tool-eval-bench) — the standard **69-scenario**
suite (15 categories), run against the served model at 262K context with thinking disabled
(`seed=42`, `temperature=0`, sequential).

> **Score: 91 / 100 — ★★★★★ Excellent** · 59 passed · 8 partial · 2 failed · 126/138 points

| Metric | Value |
|---|---|
| **Final score** | **91 / 100** |
| **Rating** | ★★★★★ Excellent |
| Passed / Partial / Failed | 59 / 8 / 2 |
| Points | 126 / 138 |
| Quality | 91 / 100 |
| Responsiveness | 62 / 100 (median turn 2.2s) |
| Deployability | 82 / 100 (α=0.7) |
| Total wall time | 562 s (69 scenarios) |
| Engine | vLLM `0.1.dev20073+g8e685d198` |

### Category scores

| Category | Score |
|---|:---:|
| Tool Selection | **100%** (6/6) |
| Parameter Precision | **100%** (6/6) |
| Error Recovery | **100%** (6/6) |
| Localization | **100%** (6/6) |
| Structured Reasoning | **100%** (6/6) |
| Safety & Boundaries | **100%** (26/26) |
| Creative Composition | **100%** (6/6) |
| Multi-Step Chains | 88% (7/8) |
| Toolset Scale | 88% (7/8) |
| Context & State | 85% (17/20) |
| Restraint & Refusal | 83% (5/6) |
| Code Patterns | 83% (5/6) |
| Autonomous Planning | 83% (5/6) |
| Structured Output | 83% (10/12) |
| Instruction Following | 80% (8/10) |

### Difficulty tier breakdown

| Tier | Scenarios | Passed | Pass rate |
|---|:---:|:---:|:---:|
| Trivial (★) | 4 | 3 | 75% |
| Easy (★★) | 17 | 16 | 94% |
| Moderate (★★★) | 31 | 27 | 87% |
| Hard (★★★★) | 17 | 13 | 76% |

### Notable results

- **Safety & Boundaries is perfect (26/26)** — all prompt-injection, authority-escalation,
  and parameter-validation scenarios passed, so the ★★★★★ rating is not safety-capped.
- **100% on six categories**, including tool selection, localization, and structured reasoning.
- **2 failures** (both infrastructure-independent, model-level):
  - `TC-45` tool_choice=required compliance — no tool call emitted despite a required tool.
  - `TC-68` schema violation resistance — called tools when none were needed.
- **8 partials** are mostly "correct but suboptimal" — e.g. reaching for a calculator on trivial
  math (TC-11, TC-39) or an unnecessary extra tool call (TC-28).

The complete per-scenario trace is in [`benchmarks/tool-eval-bench.md`](benchmarks/tool-eval-bench.md).

## Configuration

Everything is env-overridable. `run.sh` handles orchestration; `serve.sh` (baked into the image)
holds the vLLM flags.

| Env | Default | Meaning |
|---|---|---|
| `IMAGE` | `oxbyte/qwen3.8-flash-next-dual-spark:latest` | image to pull/run |
| `WORKER` | `user@worker-ip` | worker node `user@fabric-ip` |
| `SSH_KEY` | `~/.ssh/id_ed25519` | key for the worker node |
| `MODEL_REPO` | `RadixArk/Qwen3.8-Flash-Next-NVFP4` | HuggingFace repo |
| `MODEL_DIR` | `~/models/RadixArk/Qwen3.8-Flash-Next-NVFP4` | local checkpoint path |
| `MASTER_ADDR` | `192.168.1.1` | head node's fabric IP (rank 0) |
| `MASTER_PORT` | `29501` | torch.distributed port |
| `SPEC_TOKENS` | `4` | MTP speculative tokens |
| `MAX_MODEL_LEN` | `262144` | context length |
| `MAX_NUM_SEQS` | `8` | concurrent sequences |
| `GPU_MEMORY_UTILIZATION` | `0.85` | vLLM gpu-memory-utilization |

## Why the patch

The checkpoint is hybrid: routed experts are ModelOpt **NVFP4**, but the PLE n-gram embedding
table ships as **FP8** shards with a single global `ngram_embedding.weight_scale`. vLLM's
`_get_ple_embedding_quant_method()` only enables the FP8 PLE path under an `Fp8Config`, so for
this checkpoint it returns `None` and the PLE is silently served wrong (FP8 bytes upcast to bf16
with no scale applied). Fixing that gate exposes a second bug — `weight_scale` registered as both
parameter and buffer. `ple_layer.py` in this repo fixes both.

## Why `--enforce-eager`

On GB10, enabling CUDA graphs / `torch.compile` (i.e. dropping `--enforce-eager`, or adding
`--optimization-level 1`) makes vLLM enter an inductor compile of the backbone after weight load
that can hang the whole box for tens of minutes and then exit 255. Eager mode is the stable path
here — the benchmark above was produced in eager mode.

## Rebuilding the image

The published image is self-contained (you never need the base). To rebuild or audit:

```bash
docker build -t oxbyte/qwen3.8-flash-next-dual-spark:latest .
```

The `FROM` is NVIDIA's dev image `vllm/vllm-openai:qwen38-flash-next` (sm_121a / aarch64 / CUDA 13).
You only need it if you rebuild — `docker pull` users don't.

## Hardware notes (DGX Spark / GB10)

- RoCE interface `enp1s0f1np1`, MTU 9000, `NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1`.
- Weights load ~61.7 GiB/rank; drop page cache before load or a warm cache can starve the GPU
  allocator midway (`run.sh` does this automatically).
- Load takes ~8–10 minutes for the 126 GiB checkpoint.
- KV cache lands at ~3.16M tokens — 8 concurrent sequences at 262K fits comfortably.

## Repository layout

```
.
├── Dockerfile          # image build (patch + entrypoint)
├── serve.sh            # in-image vLLM entrypoint
├── run.sh              # one-command dual-node bring-up
├── download-model.sh   # HF checkpoint downloader (uses the image's hf CLI)
├── ple_layer.py        # PLE quant path fix
├── benchmarks/         # eval results + methodology
└── README.md
```

## License

Apache 2.0 — see [LICENSE](LICENSE). `ple_layer.py` is derived from vLLM (also Apache 2.0).
