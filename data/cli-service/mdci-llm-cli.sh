#!/bin/sh
# MDCI LLM CLI service — ForceCommand allowlist (dedicated non-root SSH user).
# Runs under the mdci-cli user; every command is logged, anything outside the
# allowlist is denied. No interactive shell is permitted.

set -u

CMD="${SSH_ORIGINAL_COMMAND:-}"
if [ -f /etc/mdci-llm-cli.env ]; then
	. /etc/mdci-llm-cli.env
fi
# The daemon step owns the runtime file, so the runtime and the name the server
# answers as come from there. An absent file is a refusal, never a default: guessing
# ollama would send a vLLM host requests on paths its server does not serve.
[ -f /etc/mdci-llm-runtime.env ] || { echo "ERROR: /etc/mdci-llm-runtime.env is missing, so the runtime is unknown" >&2; exit 1; }
. /etc/mdci-llm-runtime.env
MODEL_ADDR="${MDCI_MODEL_ADDR:-127.0.0.1:11434}"
MODEL="${MDCI_MODEL_SERVED_NAME}"
RUNTIME="${MDCI_MODEL_RUNTIME}"

# The two runtimes answer on different paths, so every command follows the runtime
# the daemon step wrote and never asks a path its server lacks.
case "${RUNTIME}" in
	ollama) PROBE_PATH="/api/version" ;;
	vllm)   PROBE_PATH="/v1/models" ;;
	*)      echo "ERROR: unknown runtime ${RUNTIME}" >&2; exit 1 ;;
esac

logger -t mdci-llm-cli "user=${USER:-?} cmd=${CMD:-<shell-denied>}"

case "${CMD}" in
	"" )
		echo "ERROR: interactive shell denied; use one of: ask, health, gpu, models" >&2
		exit 1
		;;

	ask:* | ask\ * )
		PROMPT="${CMD#ask}"
		PROMPT="${PROMPT#:}"
		PROMPT="${PROMPT# }"
		[ -n "${PROMPT}" ] || { echo "ERROR: empty prompt" >&2; exit 1; }
		case "${RUNTIME}" in
			ollama)
				body="$(jq -cn --arg model "$MODEL" --arg prompt "$PROMPT" '{model:$model, prompt:$prompt, stream:false}')"
				curl -fsS --max-time 600 "http://${MODEL_ADDR}/api/generate" -d "$body" \
					| jq -r '.response // .error // "no response"'
				;;
			vllm)
				body="$(jq -cn --arg model "$MODEL" --arg prompt "$PROMPT" '{model:$model, messages:[{role:"user",content:$prompt}], max_tokens:8192}')"
				# vLLM answers 400 to a JSON body sent with no content type, unlike Ollama.
				curl -fsS --max-time 600 "http://${MODEL_ADDR}/v1/chat/completions" \
					-H 'Content-Type: application/json' -d "$body" \
					| jq -r '.choices[0].message.content // .error // "no response"'
				;;
		esac
		;;

	health )
		echo "model-addr=${MODEL_ADDR} model=${MODEL}"
		systemctl is-active mdci-llm.service 2>&1 || true
		if curl -fsS --max-time 10 "http://${MODEL_ADDR}${PROBE_PATH}" >/dev/null 2>&1; then
			echo "model-daemon=up"
		else
			echo "model-daemon=down"
		fi
		;;

	gpu )
		case "${MDCI_ACCELERATOR:-nvidia}" in
			nvidia) nvidia-smi 2>&1 || echo "ERROR: nvidia-smi not available" >&2 ;;
			amd)    rocm-smi 2>&1 || echo "ERROR: rocm-smi not available (AMD planned)" >&2 ;;
			*)      echo "ERROR: unknown accelerator" >&2; exit 1 ;;
		esac
		;;

	models )
		case "${RUNTIME}" in
			ollama) curl -fsS --max-time 10 "http://${MODEL_ADDR}/api/tags" | jq -r '.models[]?.name' 2>/dev/null ;;
			vllm)   curl -fsS --max-time 10 "http://${MODEL_ADDR}/v1/models" | jq -r '.data[]?.id' 2>/dev/null ;;
		esac
		;;

	* )
		logger -t mdci-llm-cli "DENIED: ${CMD}"
		echo "ERROR: command not in allowlist" >&2
		exit 1
		;;
esac
