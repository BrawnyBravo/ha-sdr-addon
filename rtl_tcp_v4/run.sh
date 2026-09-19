#!/bin/sh
# Start rtl_tcp with the options Home Assistant wrote to /data/options.json.
set -eu

OPTS=/data/options.json

get() {
    # $1 = key, $2 = fallback
    jq -r --arg fallback "$2" ".${1} // \$fallback" "${OPTS}" 2>/dev/null || echo "$2"
}

DEVICE_INDEX=$(get device_index 0)
BIND_ADDRESS=$(get bind_address 0.0.0.0)
SAMPLE_RATE=$(get sample_rate 2048000)
FREQUENCY=$(get frequency 912600000)
GAIN=$(get gain 0)
PPM_ERROR=$(get ppm_error 0)
MAX_BUFFERS=$(get max_buffers 500)

echo "[rtl_tcp_v4] starting"
echo "[rtl_tcp_v4] device=${DEVICE_INDEX} bind=${BIND_ADDRESS}:1234 freq=${FREQUENCY} rate=${SAMPLE_RATE} gain=${GAIN} ppm=${PPM_ERROR}"

# A quick identity check in the log. On a V4 this prints "RTL-SDR Blog V4 ...
# Detected"; if it instead reports a plain R820T with "PLL not locked", the
# driver in this image is the wrong one and nothing downstream will decode.
rtl_test -t 2>&1 | head -n 6 | sed 's/^/[rtl_tcp_v4] rtl_test: /' || true

exec rtl_tcp \
    -a "${BIND_ADDRESS}" \
    -p 1234 \
    -d "${DEVICE_INDEX}" \
    -f "${FREQUENCY}" \
    -s "${SAMPLE_RATE}" \
    -g "${GAIN}" \
    -P "${PPM_ERROR}" \
    -n "${MAX_BUFFERS}"
