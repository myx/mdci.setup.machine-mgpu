# setup.machine-mgpu

A GPU machine floor for serving a model (qwen) as a CLI service: Ubuntu x86_64 with an NVIDIA driver + CUDA toolkit, a policy-drop firewall, a systemd-wrapped model daemon, a GPU-metric collector, and a CLI service over SSH.

Maintainer notes: `MAGIC.md`. How the packages compose: `../MAGIC.md`.

## Requires

- `standard/setup.machine-ubuntu` — the Ubuntu OS floor.

## What it installs and configures

Steps (`host/install/standard-mgpu-machine.*.txt`), after the ubuntu floor:

- `0.prepare` — no-op: the ubuntu floor already ran via `Requires`.
- `1.accelerator` — the accelerator, chosen by `MDCI_ACCELERATOR` (`nvidia` now, `amd` planned). The `nvidia` branch is the headless compute-only install (cuda-keyring → pin-branch → `libnvidia-compute nvidia-dkms` + `cuda-toolkit`); the `amd` branch is stubbed (ROCm planned, not yet implemented).
- `1.firewall-acl` — moves sshd to the allocated port 22022 (fixed, not a variable) and applies the policy-drop ruleset atomically.
- `1.gpu-metric-collector` — installs the collector script, its cron entry, and the persisted `/etc/mdci-gpu-metrics.env` (accelerator + textfile dir).
- `1.cli-service-ssh` — a dedicated non-root user (`mdci-cli`) whose SSH login is a ForceCommand allowlist; the public key is a deferred secret (`MDCI_AGENT_PKEY`).
- `1.model-api-gateway` — an nginx TLS reverse proxy on the fixed port 8443 in front of Ollama's OpenAI-compatible API, with a bearer token (`MDCI_API_KEY`) and an nftables IP ACL (`MDCI_RIG_IP`).
- `2.model-daemon` — a dedicated non-root service user (`mdci-llm`), the model runtime (Ollama), and the systemd unit `mdci-llm.service` (loopback only, `127.0.0.1:11434`).

## Data

| dir | contract | lands in |
|---|---|---|
| `data/nftables.conf/nftables.conf` | `nftables.conf` (ubuntu floor) | `/etc/nftables.conf` |
| `data/os-services-systemd/mdci-llm.service` | `os-services-systemd` (ubuntu floor) | `/usr/local/lib/systemd/system/` |
| `data/gpu-metrics/` | `gpu-metrics` (this project) | `/usr/local/mdci-files/gpu-metrics/` |
| `data/cli-service/` | `cli-service` (this project) | `/usr/local/mdci-files/cli-service/` |

## Inputs

| variable | default | effect |
|---|---|---|
| `MDCI_ACCELERATOR` | `nvidia` | which accelerator the `1.accelerator` builder installs (`nvidia` now, `amd` planned) |
| `MDCI_MODEL` | `qwen3:4b` | the Ollama model tag the daemon serves (pulled at install) |
| `MDCI_MODEL_ADDR` | `127.0.0.1:11434` | loopback bind of the model daemon |
| `MDCI_NVIDIA_CUDA_SUITE` | `ubuntu2404` | NVIDIA CUDA repo suite (nvidia branch) |
| `MDCI_NVIDIA_PIN_BRANCH` | `590` | NVIDIA driver pin branch (nvidia branch) |
| `MDCI_HOST` | — | public hostname (TLS cert + gateway) |
| `MDCI_RIG_IP` | — | rig IPs allowed to reach the gateway (ACL) |
| `MDCI_API_KEY` | — | bearer token the rig uses (deferred secret) |
| `MDCI_LETSENCRYPT_EMAIL` | — | Let's Encrypt account email (gateway TLS) |
| `MDCI_AGENT_PKEY` | — | CLI-service SSH public key (deferred secret) |

## Commands

- `systemctl restart nftables` — apply the firewall (after verifying SSH on the new port).
