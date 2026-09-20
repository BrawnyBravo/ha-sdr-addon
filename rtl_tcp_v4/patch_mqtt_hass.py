#!/usr/bin/env python3
"""Add the utility-meter reading fields upstream's MQTT discovery bridge misses.

rtl_433_mqtt_hass.py advertises a Home Assistant discovery config for every
message field it recognises, matching keys exactly and case-sensitively. Its
mapping table contains a lowercase "consumption" entry named "SCMplus
Consumption Value" -- but SCM+ emits "Consumption" with a capital C, so that
entry can never match an SCM+ message. The result is that a meter decodes
cleanly, its reading sits in the MQTT payload, and the only entities that ever
appear are rssi, snr and noise. The reading itself -- the whole point -- is
silently dropped. IDM and NETIDM lose their readings the same way.

Lowercase "consumption" is not dead code: across src/devices/ exactly one
decoder emits it (neptune_r900.c), so it quietly serves Neptune R900 water
meters under an SCM+ label. This patch is therefore strictly additive -- it
adds the missing keys and changes no existing entry, so no R900 user loses an
entity.

Field names below were read from the decoders in merbanan/rtl_433 master:
  scmplus.c  -> Consumption, MeterType
  ert_idm.c  -> LastConsumption, LastConsumptionCount, LastConsumptionNet,
                ConsumptionIntervalCount, DifferentialConsumptionIntervals,
                MeterType

Run against the installed bridge; idempotent, and verifies the result parses.
"""

import ast
import sys

ANCHOR = '    "consumption_data": {'

EXTRA = '''    # --- added by the RTL-SDR Radio add-on: see patch_mqtt_hass.py ---
    # SCM+ emits "Consumption" (capital C). Upstream only maps lowercase
    # "consumption", which in practice serves Neptune R900, so SCM+ gas,
    # electric and water readings are never discovered without this.
    "Consumption": {
        "device_type": "sensor",
        "object_suffix": "consumption",
        "config": {
            "name": "Consumption",
            "value_template": "{{ value|int }}",
            "state_class": "total_increasing",
        }
    },

    # IDM / NETIDM running totals.
    "LastConsumptionCount": {
        "device_type": "sensor",
        "object_suffix": "last_consumption_count",
        "config": {
            "name": "Last Consumption Count",
            "value_template": "{{ value|int }}",
            "state_class": "total_increasing",
        }
    },

    "LastConsumption": {
        "device_type": "sensor",
        "object_suffix": "last_consumption",
        "config": {
            "name": "Last Consumption",
            "value_template": "{{ value|int }}",
            "state_class": "total_increasing",
        }
    },

    "LastConsumptionNet": {
        "device_type": "sensor",
        "object_suffix": "last_consumption_net",
        "config": {
            "name": "Last Consumption Net",
            "value_template": "{{ value|int }}",
            "state_class": "total_increasing",
        }
    },

    # Tells gas from electric from water without opening the payload.
    "MeterType": {
        "device_type": "sensor",
        "object_suffix": "meter_type",
        "config": {
            "name": "Meter Type",
            "value_template": "{{ value }}",
        }
    },
    # --- end add-on additions ---

'''


def main(path):
    with open(path, encoding="utf-8") as fh:
        src = fh.read()

    if '"Consumption": {' in src:
        print("patch_mqtt_hass: already applied, nothing to do")
        return 0

    if src.count(ANCHOR) != 1:
        print("patch_mqtt_hass: ERROR anchor %r found %d times, expected 1"
              % (ANCHOR, src.count(ANCHOR)), file=sys.stderr)
        return 1

    patched = src.replace(ANCHOR, EXTRA + ANCHOR, 1)

    # A broken bridge is worse than an unpatched one: refuse to write
    # anything that does not parse.
    try:
        ast.parse(patched)
    except SyntaxError as exc:
        print("patch_mqtt_hass: ERROR patched file does not parse: %s" % exc,
              file=sys.stderr)
        return 1

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(patched)
    print("patch_mqtt_hass: added 5 meter field mappings")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else "/usr/local/bin/rtl_433_mqtt_hass.py"))
