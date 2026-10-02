#!/usr/bin/env bash
# phone-mcp-call.sh TOOL [ARGS_JSON]
# Env: PHONE_IP (Tailscale IP), PHONE_PORT (default 8462), PHONE_TOKEN_FILE
set -euo pipefail
# NB: do NOT write ${2:-{}} — bash closes the expansion on the first '}',
# yielding default '{' plus a literal '}', which doubles the brace on any
# call that passes args. Set the default explicitly instead.
TOOL="$1"; ARGS="${2:-}"; [ -n "$ARGS" ] || ARGS='{}'
PORT="${PHONE_PORT:-8462}"
TOKEN="$(cat "${PHONE_TOKEN_FILE:?set PHONE_TOKEN_FILE}")"

# --connect-timeout keeps an unreachable phone failing fast even when a caller
# raises PHONE_TIMEOUT: the two answer different questions. ingest.fetch returns
# the whole file base64 in one response, so a 10s cap on THAT is a size limit
# wearing a timeout's clothes — it aborted mid-transfer after the phone had
# already marked the item delivered.
#
# Built with jq so a quote in TOOL cannot break the envelope and malformed
# ARGS fails here instead of as an opaque HTTP error from the phone.
PAYLOAD=$(jq -cn --arg tool "$TOOL" --argjson args "$ARGS" \
  '{jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: $tool, arguments: $args}}')
curl -sf --connect-timeout "${PHONE_CONNECT_TIMEOUT:-5}" --max-time "${PHONE_TIMEOUT:-10}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d "$PAYLOAD" \
  "http://${PHONE_IP}:${PORT}/mcp"
