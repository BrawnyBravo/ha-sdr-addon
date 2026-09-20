#!/bin/sh
# One dongle, four jobs. A dongle can only listen to one slice of spectrum at a
# time, so this picks a mode rather than pretending to do everything at once.
set -eu

OPTS=/data/options.json
OUT=/share/rtlsdr
mkdir -p "${OUT}"

log() { echo "[rtl-sdr] $*"; }

# Note the null test rather than jq's "//". A stored "false" is a real answer,
# and "//" would quietly swap it for the default - which would make the
# discovery switch impossible to turn off.
get() {
    jq -r --arg k "$1" --arg f "$2"         'if (.[$k] == null) then $f else (.[$k] | tostring) end'         "${OPTS}" 2>/dev/null || echo "$2"
}

get_list() {
    jq -r --arg k "$1" '(.[$k] // []) | .[]' "${OPTS}" 2>/dev/null || true
}

MODE=$(get mode rtl_tcp)
DEV=$(get device_index 0)
GAIN=$(get gain 0)
PPM=$(get ppm_error 0)
BIND=$(get bind_address 0.0.0.0)

# ------------------------------------------------------------------ mqtt setup
# Home Assistant hands add-ons the broker details, so no separate account is
# needed. Explicit options win if they are set.
mqtt_from_supervisor() {
    [ -n "${SUPERVISOR_TOKEN:-}" ] || return 1
    curl -sf -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/services/mqtt 2>/dev/null
}

resolve_mqtt() {
    MQTT_HOST=$(get mqtt_host "")
    MQTT_PORT=$(get mqtt_port "")
    MQTT_USER=$(get mqtt_user "")
    MQTT_PASS=$(get mqtt_password "")

    if [ -z "${MQTT_HOST}" ]; then
        SVC=$(mqtt_from_supervisor || true)
        if [ -n "${SVC}" ]; then
            MQTT_HOST=$(echo "${SVC}" | jq -r '.data.host // ""')
            MQTT_PORT=$(echo "${SVC}" | jq -r '.data.port // ""')
            MQTT_USER=$(echo "${SVC}" | jq -r '.data.username // ""')
            MQTT_PASS=$(echo "${SVC}" | jq -r '.data.password // ""')
            log "using the broker Home Assistant provided (${MQTT_HOST}:${MQTT_PORT})"
        fi
    else
        log "using the broker from this add-on's settings (${MQTT_HOST}:${MQTT_PORT})"
    fi

    [ -n "${MQTT_PORT}" ] || MQTT_PORT=1883
}

# ---------------------------------------------------------------- driver check
# On a V4 this prints "RTL-SDR Blog V4 Detected", or "... V4 Lite Detected" on
# the Lite. If it instead reports a plain R820T with "PLL not locked", the
# wrong driver got built and nothing downstream will ever decode. Both the
# check and the discovery bridge fail silently, and add-on logs are out of
# reach of anything driving this over the Supervisor WebSocket, so both are
# mirrored to MQTT under <prefix>/radio/diag.
resolve_mqtt
MQTT_USERNAME="${MQTT_USER}"
MQTT_PASSWORD="${MQTT_PASS}"
DIAG_TOPIC="$(get mqtt_topic_prefix rtl_433)/radio/diag"
export MQTT_HOST MQTT_PORT MQTT_USERNAME MQTT_PASSWORD DIAG_TOPIC

log "driver check:"
rtl_test -t 2>&1 | head -n 8 | python3 /usr/local/bin/diag.py driver || true

case "${MODE}" in

# --------------------------------------------------------------------- rtl_tcp
# Serve the raw stream so any machine in the house can borrow the dongle:
# rtl_433, SDR++, GQRX, SDRangel, rtlamr2mqtt's rtltcp_host, and so on.
rtl_tcp)
    RATE=$(get tcp_sample_rate 2048000)
    FREQ=$(get tcp_frequency 912600000)
    BUFS=$(get tcp_max_buffers 500)
    log "mode rtl_tcp - serving on ${BIND}:1234 (one client at a time)"
    exec rtl_tcp -a "${BIND}" -p 1234 -d "${DEV}" -f "${FREQ}" \
        -s "${RATE}" -g "${GAIN}" -P "${PPM}" -n "${BUFS}"
    ;;

# --------------------------------------------------------------------- rtl_433
# Utility meters, cheap weather and temperature sensors, tyre pressure sensors,
# door sensors - several hundred device types, straight into MQTT.
rtl_433)
    PREFIX=$(get mqtt_topic_prefix rtl_433)
    DISCOVERY=$(get mqtt_ha_discovery true)
    EXTRA=$(get decoder_extra_args "")

    set -- -d "${DEV}" -g "${GAIN}" -p "${PPM}" -M time:iso -M level -M protocol

    for f in $(get_list decoder_frequencies); do
        set -- "$@" -f "${f}"
    done
    for r in $(get_list decoder_protocols); do
        set -- "$@" -R "${r}"
    done

    if [ -n "${MQTT_HOST}" ]; then
        # Two streams: one JSON message per decode for the discovery bridge, and
        # the split-out per-field topics Home Assistant actually reads. The
        # bridge builds the second from the first by taking the first two
        # segments of the event topic, so the "/radio/" level has to be here or
        # the sensors it advertises point at topics nothing ever publishes.
        SINK="mqtt://${MQTT_HOST}:${MQTT_PORT},retain=0"
        SINK="${SINK},events=${PREFIX}/radio/events"
        SINK="${SINK},devices=${PREFIX}/radio/devices[/type][/model][/subtype][/channel][/id]"
        # Must be a full if: under "set -e" a bare "test && assign" would take
        # the whole add-on down the moment the broker is anonymous.
        if [ -n "${MQTT_USER}" ]; then
            SINK="${SINK},user=${MQTT_USER},pass=${MQTT_PASS}"
        fi
        set -- "$@" -F "${SINK}"
        log "publishing decodes to MQTT under ${PREFIX}/"

        if [ "${DISCOVERY}" = "true" ]; then
            # Best effort. If the bridge's arguments ever change upstream this
            # must not take the whole add-on down with it - decoding still works,
            # the entities just need adding by hand.
            log "starting the Home Assistant discovery bridge"
            # Left unset, the bridge advertises every device the dongle can
            # hear - which on 915 MHz means the neighbours' utility meters,
            # not just ours - easily hundreds of stray entities belonging to
            # other households. mqtt_discovery_ids restricts it to named meters.
            # Numeric ids only: anything else is logged and dropped rather
            # than handed to the shell, since this comes from user options.
            DISC_IDS=""
            for mid in $(get_list mqtt_discovery_ids); do
                case "${mid}" in
                    ''|*[!0-9]*) log "ignoring non-numeric discovery id: ${mid}" ;;
                    *) DISC_IDS="${DISC_IDS} ${mid}" ;;
                esac
            done
            if [ -n "${DISC_IDS}" ]; then
                log "discovery limited to meter ids:${DISC_IDS}"
            else
                log "discovery covers every device heard - set mqtt_discovery_ids to limit it"
            fi
            # The bridge takes the broker on the command line; only the
            # credentials come from the environment. Handing it the host as an
            # environment variable leaves it on its 127.0.0.1 default, where it
            # connects to nothing and silently advertises no sensors at all.
            # shellcheck disable=SC2086
            python3 -u /usr/local/bin/rtl_433_mqtt_hass.py \
                -H "${MQTT_HOST}" -p "${MQTT_PORT}" \
                -R "${PREFIX}/radio/events" \
                ${DISC_IDS:+-I ${DISC_IDS}} 2>&1 \
                | python3 /usr/local/bin/diag.py discovery &
        fi
    else
        log "no broker available - decodes will only appear in this log"
    fi

    set -- "$@" -F log
    # shellcheck disable=SC2086
    log "mode rtl_433 - decoding"
    exec rtl_433 "$@" ${EXTRA}
    ;;

# ------------------------------------------------------------------------ adsb
# Basic aircraft frames. Deliberately simple: for a full map and a feeder, run
# mode rtl_tcp and point a dedicated aircraft decoder at this machine instead.
adsb)
    log "mode adsb - frames to the log and ${OUT}/adsb-frames.txt"
    exec sh -c "rtl_adsb -d ${DEV} -g ${GAIN} | tee -a ${OUT}/adsb-frames.txt"
    ;;

# ---------------------------------------------------------------------- survey
# Sweep a range and write a spectrum file, to answer "what can this antenna
# actually hear from here" with measurements instead of guesswork.
survey)
    FROM=$(get survey_from 400M)
    TO=$(get survey_to 1000M)
    BINSZ=$(get survey_bin_size 100k)
    MINS=$(get survey_minutes 10)
    STAMP=$(date +%Y-%m-%d_%H%M)
    FILE="${OUT}/survey_${STAMP}.csv"

    log "mode survey - sweeping ${FROM} to ${TO} in ${BINSZ} steps for ${MINS} min"
    log "writing ${FILE}"
    rtl_power -f "${FROM}:${TO}:${BINSZ}" -g "${GAIN}" -p "${PPM}" -d "${DEV}" \
        -i 10 -e "${MINS}m" "${FILE}" || true
    log "survey finished. File is in the share folder under rtlsdr/."
    log "this mode is a one-shot; stop the add-on or switch modes."
    # Idle rather than crash-loop.
    while true; do sleep 3600; done
    ;;

*)
    log "unknown mode '${MODE}'"
    exit 1
    ;;
esac
