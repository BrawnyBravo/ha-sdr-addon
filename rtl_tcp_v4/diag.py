#!/usr/bin/env python3
"""Echo stdin to the add-on log and to an MQTT topic.

Add-on logs are only reachable through the web interface: the Supervisor
WebSocket proxy carries JSON, and the log endpoint answers in plain text, so
anything driving this add-on over that route is blind to it. That matters most
for the two things that fail silently - the driver detection line, and the
Home Assistant discovery bridge - so those are piped through here.

Best effort by design. No broker, a bad password or a dropped connection must
never take the radio down with it; the lines still reach the add-on log.
"""
import os
import sys

TOPIC = os.environ.get("DIAG_TOPIC", "rtl_433/radio/diag")
HOST = os.environ.get("MQTT_HOST", "")
PORT = int(os.environ.get("MQTT_PORT") or 1883)
USER = os.environ.get("MQTT_USERNAME", "")
PASS = os.environ.get("MQTT_PASSWORD", "")
PREFIX = sys.argv[1] if len(sys.argv) > 1 else "diag"

client = None
if HOST:
    try:
        import paho.mqtt.client as mqtt
        try:
            client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        except (AttributeError, TypeError):
            client = mqtt.Client()          # paho 1.x
        if USER:
            client.username_pw_set(USER, PASS)
        client.connect(HOST, PORT, 30)
        client.loop_start()
    except Exception as e:                   # noqa: BLE001 - never fatal
        print(f"[diag] no MQTT ({e}); log only", flush=True)
        client = None

for line in sys.stdin:
    line = line.rstrip("\n")
    print(f"[{PREFIX}] {line}", flush=True)
    if client is not None:
        try:
            client.publish(f"{TOPIC}/{PREFIX}", line, retain=False)
        except Exception:                    # noqa: BLE001
            pass
