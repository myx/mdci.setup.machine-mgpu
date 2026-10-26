#!/bin/sh
# MDCI LLM CLI service — ForceCommand allowlist (dedicated non-root SSH user).
# Runs under the mdci-cli user; every command is logged, anything outside the
# allowlist is denied. No interactive shell is permitted.

set -u

CMD="${SSH_ORIGINAL_COMMAND:-}"
if [ -f /etc/mdci-llm-cli.env ]; then
	. /etc/mdci-llm-cli.env
fi
MODEL_ADDR="${MDCI_MODEL_ADDR:-127.0.0.1:11434}"
MODEL="${MDCI_MODEL:-qwen}"

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
		body="$(jq -cn --arg model "$MODEL" --arg prompt "$PROMPT" '{model:$model, prompt:$prompt, stream:false}')"
		curl -fsS --max-time 600 "http://${MODEL_ADDR}/api/generate" -d "$body" \
			| jq -r '.response // .error // "no response"'
		;;

	health )
		echo "model-addr=${MODEL_ADDR} model=${MODEL}"
		systemctl is-active mdci-llm.service 2>&1 || true
		if curl -fsS --max-time 10 "http://${MODEL_ADDR}/api/tags" >/dev/null 2>&1; then
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
		curl -fsS --max-time 10 "http://${MODEL_ADDR}/api/tags" | jq -r '.models[]?.name' 2>/dev/null
		;;

	* )
		logger -t mdci-llm-cli "DENIED: ${CMD}"
		echo "ERROR: command not in allowlist" >&2
		exit 1
		;;
esac
