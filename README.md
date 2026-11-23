# setup.machine-mgpu

A GPU machine floor for serving a model (qwen) as a CLI service: Ubuntu x86_64 with an NVIDIA driver + CUDA toolkit, a policy-drop firewall, a systemd-wrapped model daemon, a GPU-metric collector, and a CLI service over SSH.

Maintainer notes: `MAGIC.md`. How the packages compose: `../MAGIC.md`.

## Requires

- `standard/setup.machine-ubuntu` — the Ubuntu OS floor.

## What it installs and configures

Steps (`host/install/standard-mgpu-machine.*.txt`), after the ubuntu floor:

- `0.prepare` — no-op: the ubuntu floor already ran via `Requires`.
- `1.accelerator` — the accelerator, chosen by `MDCI_ACCELERATOR` (`nvidia` now, `amd` planned). The `nvidia` branch is the headless compute-only install (cuda-keyring → pin-branch → `libnvidia-compute nvidia-dkms` + `cuda-toolkit`); the `amd` branch is stubbed (ROCm planned, not yet implemented).

  **Blackwell-class GPUs (RTX PRO 6000, PCI `10de:2bb4`) cannot load the proprietary kernel
  module at all** — the kernel answers *"requires use of the NVIDIA open kernel modules"* and
  `nvidia-smi` reports *"No devices were found"* on a perfectly installed driver. **The
  `nvidia` branch therefore probes `nvidia-smi` after the pinned install and, if the card is
  invisible, installs the **open** modules of the same branch (`nvidia-dkms-<branch>-open`
  with the matching `libnvidia-compute-<branch>` and `nvidia-utils-<branch>`) and checks once
  more.** Older cards keep the proprietary driver unchanged; the probe decides, not a flag.
- `1.firewall-acl` — moves sshd to the allocated port 22022 (fixed, not a variable) and applies the policy-drop ruleset atomically.
- `1.gpu-metric-collector` — installs the collector script, its cron entry, and the persisted `/etc/mdci-gpu-metrics.env` (accelerator + textfile dir).
- `1.cli-service-ssh` — a dedicated non-root user (`mdci-cli`) whose SSH login is a ForceCommand allowlist; the public key is a deferred secret (`MDCI_AGENT_PKEY`).
- `1.model-api-gateway` — an nginx TLS reverse proxy on the fixed port 8443 in front of whichever model runtime the dispatcher starts, with a bearer token (`MDCI_API_KEY`) and an nftables IP ACL (`MDCI_RIG_IP`). It proxies `/v1/` on one loopback address, so both runtimes are reached the same way: Ollama answers `/v1/chat/completions` and `/v1/models` there, and so does vLLM.
- `2.model-daemon` — a dedicated non-root service user (`mdci-llm`), the model runtime named by `MDCI_MODEL_RUNTIME`, and the systemd unit `mdci-llm.service` (loopback only). The unit has one `ExecStart`, `/usr/local/bin/mdci-llm-run`, and that dispatcher reads `/etc/mdci-llm-runtime.env` to start `ollama` or `vllm`.

## The vLLM runtime

The `vllm` branch installs a pinned runtime into a virtual environment and serves a pinned
checkpoint directory. Both pins and the window are required: a floating build, revision or
window reaches a different state a month later.

- Checkpoint: `nvidia/Qwen3.8-27B-NVFP4`, apache-2.0, three safetensors shards totalling
  21.945 GB. Read from huggingface.co on 2026-11-10. The sha256 of every file in that
  revision is in `data/model-runtime/nvfp4-checkpoint.manifest`, and the step verifies each
  one before it is named.
- Runtime build measured on this host: `vllm 0.33.0`, `b12x 1.5.1`, `torch 2.14.0`, python
  3.14.4, driver 595.99.02, compute 12.0, 97887 MiB of video memory.
- Kernel: the step passes `--linear-backend b12x` and fails unless the serve log names
  `B12xNvFp4LinearKernel`. On compute 12x the CUTLASS NVFP4 kernels compute wrongly without
  erroring, and Marlin is the silent fallback. Neither is accepted.
- Memory measured under a real load: 80510 MiB held, of which 20.05 GiB is weights and 54.61
  GiB is the KV cache. That is a pool reserved by `--gpu-memory-utilization 0.85`, not the
  model's own size.
- Window: 262144, the checkpoint's own `max_position_embeddings`. At that window the server
  reports 6.46 concurrent requests. The step also fails when the served window disagrees
  with the 262144 the rig's family table resolves for a qwen 27b.

## Rollback between runtimes

Set `MDCI_MODEL_RUNTIME=ollama` and re-run the daemon step, or change
`/etc/mdci-llm-runtime.env` and restart `mdci-llm.service`. Neither branch prunes the
other's weights: `ollama` keeps `/var/lib/mdci-llm/models`, `vllm` keeps
`/var/lib/mdci-llm/model-repo`. The old model therefore stays available until someone
decides to remove it, which is a separate decision with its own rollback argument.

## Data

| dir | contract | lands in |
|---|---|---|
| `data/nftables.conf/nftables.conf` | `nftables.conf` (ubuntu floor) | `/etc/nftables.conf` |
| `data/os-services-systemd/mdci-llm.service` | `os-services-systemd` (ubuntu floor) | `/usr/local/lib/systemd/system/` |
| `data/model-runtime/` | `model-runtime` (this project) | `/usr/local/mdci-files/model-runtime/` |
| `data/gpu-metrics/` | `gpu-metrics` (this project) | `/usr/local/mdci-files/gpu-metrics/` |
| `data/cli-service/` | `cli-service` (this project) | `/usr/local/mdci-files/cli-service/` |

## Inputs

| variable | default | effect |
|---|---|---|
| `MDCI_ACCELERATOR` | `nvidia` | which accelerator the `1.accelerator` builder installs (`nvidia` now, `amd` planned) |
| `MDCI_MODEL_RUNTIME` | `ollama` | the model server the daemon step installs: `ollama` or `vllm` |
| `MDCI_MODEL` | `qwen3:4b` | with `ollama`, the registry tag the daemon serves (pulled at install) |
| `MDCI_MODEL_SERVED_NAME` | `qwen3.8-27b-nvfp4` | with `vllm`, the id the server answers as |
| `MDCI_MODEL_MAX_LEN` | — | with `vllm`, the served window. Required, never a default |
| `MDCI_MODEL_REVISION` | — | with `vllm`, the checkpoint commit sha. Required |
| `MDCI_MODEL_CACHE` | — | with `vllm`, a directory already holding that revision. Files are copied and still hash-verified |
| `MDCI_VLLM_VERSION` | — | with `vllm`, the runtime build. Required, never `latest` |
| `MDCI_MODEL_ADDR` | `127.0.0.1:11434` | loopback bind of the model daemon, for both runtimes |
| `MDCI_NVIDIA_CUDA_SUITE` | `ubuntu2404` | NVIDIA CUDA repo suite (nvidia branch) |
| `MDCI_NVIDIA_PIN_BRANCH` | `595` | NVIDIA driver pin branch (nvidia branch). The host runs 595.99.02 |
| `MDCI_HOST` | — | public hostname (TLS cert + gateway) |
| `MDCI_RIG_IP` | — | rig IPs allowed to reach the gateway (ACL) |
| `MDCI_API_KEY` | — | bearer token the rig uses (deferred secret) |
| `MDCI_LETSENCRYPT_EMAIL` | — | Let's Encrypt account email (gateway TLS) |
| `MDCI_AGENT_PKEY` | — | CLI-service SSH public key (deferred secret) |

## Commands

- `systemctl restart nftables` — apply the firewall (after verifying SSH on the new port).
