# MAGIC.md — setup.machine-mgpu

Maintainer notes for the GPU machine floor. Users read `README.md`. How the packages compose, and the `*` vs `**` rule: `../MAGIC.md`.

## Linux + CUDA is the decision; AMD/ROCm is planned but postponed

- Ubuntu (x86_64) with an NVIDIA driver + CUDA toolkit is the current platform. The headless compute-only install (no display stack) is the `nvidia` branch of the `standard-mgpu-machine.1.accelerator.txt` builder: cuda-keyring → pin-branch → `libnvidia-compute nvidia-dkms`, then `cuda-toolkit`.
- AMD/ROCm is still planned, not abandoned: the metric collector and the CLI-service `gpu` command already branch on `MDCI_ACCELERATOR` (`nvidia-smi`/NVML now, `rocm-smi` stubbed for later), so adding it is an `amd` branch in the same builder, not a rewrite of the base or the service layer.

## `MDCI_ACCELERATOR` is the pluggable seam

- The accelerators are NOT separate projects — they are branches of `setup.machine-mgpu`'s own `1.accelerator` builder, selected by the `MDCI_ACCELERATOR` context variable (`define:nvidia`, `amd` later). The variable is namespaced (`MDCI_`), never a bare `ACCELERATOR`.
- To switch to AMD when it lands: the instance overrides `image-install:context-variable:MDCI_ACCELERATOR:define:amd`; nothing else in the base, the metric collector, the CLI service, or the model daemon changes.
- `MDCI_NVIDIA_CUDA_SUITE` / `MDCI_NVIDIA_PIN_BRANCH` tune the `nvidia` branch only; an AMD branch will add its own `MDCI_AMD_*` variables.

## Secrets are deferred, never committed

- The CLI-service public key is `MDCI_AGENT_PKEY`, supplied by the instance at deploy time — never a literal in these packages. The builder skips the `authorized_keys` write when it is absent.
- No host name, token, or customer name appears anywhere: the model name (`qwen`) is a configurable default, and the rest is `mdci`/`MDCI_`-named.

## The model is served over HTTPS + ACL, not a tunnel

- The rig reaches the model through the nginx TLS gateway on the fixed port 8443, which fronts Ollama's loopback OpenAI-compatible API. Access is two gates: a bearer token (`MDCI_API_KEY`) checked per request, and an nftables IP ACL that opens the gateway port only to `MDCI_RIG_IP`.
- The SSH `ask:`/`health`/`gpu`/`models` ForceCommand stays for human one-shot ops only; it is not the harness's path.

## The firewall is applied atomically, never by hand

- The `nftables.conf` drop-in is deployed and `nftables.service` enabled by the ubuntu floor; this floor moves sshd to the non-standard port, syncs the firewall's SSH rule to it, then applies the ruleset atomically (`nft -f`). It is safe over the live session because the INPUT chain accepts `ct state { established, related }`, so the deploy's own connection survives; a ruleset that fails to parse leaves the previous one untouched.
- Ollama stays loopback (`127.0.0.1:11434`); only the fixed TLS gateway port 8443 is opened, and only to `MDCI_RIG_IP`.

## The new contracts use `*`, not `**`

- `gpu-metrics` and `cli-service` are this machine's own contracts, so they use `image-prepare:sync-source-files:*` (this project + dependents), like `setup.feature-monit`'s `monit` contract — not `**` (every project), which the ubuntu floor reserves for its shared collection points.
