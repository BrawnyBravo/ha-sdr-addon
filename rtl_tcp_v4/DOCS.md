# RTL-TCP (RTL-SDR Blog driver)

Runs `rtl_tcp` against a USB RTL-SDR dongle and serves the raw IQ stream on port
1234, so other add-ons and machines can use one dongle.

## Why this exists

The `librtlsdr` packaged by most distributions — including the version available
inside Home Assistant OS — does not recognise **RTL-SDR Blog V4** hardware. The
dongle enumerates normally and identifies itself, so everything *looks* fine:

```
Found 1 device(s):
  0:  RTLSDRBlog, Blog V4L, SN: 00000001
Found Rafael Micro R820T tuner
[R82XX] PLL not locked!
```

That last line is the failure. The tuner is misidentified, every tune attempt
fails, and any decoder downstream sits in silence forever without ever printing
an error of its own. A working V4 instead reports:

```
RTL-SDR Blog V4 Lite Detected
```

There is no runtime flag or configuration option for this. The vendor's driver
fork has to be compiled in, which is what this add-on's `Dockerfile` does.

## Installation

1. Plug the dongle into the Home Assistant machine.
2. Install and start this add-on.
3. Check the log. It runs `rtl_test` on startup and prints the result, so you can
   confirm the dongle is properly detected before blaming anything downstream.

## Options

| Option | Default | Notes |
|---|---|---|
| `device_index` | `0` | Which dongle, if you have more than one. |
| `bind_address` | `0.0.0.0` | Listen address inside the container. |
| `sample_rate` | `2048000` | Samples per second. |
| `frequency` | `912600000` | Starting frequency in Hz. Clients usually retune. |
| `gain` | `0` | `0` means automatic gain. |
| `ppm_error` | `0` | Crystal correction, in parts per million. |
| `max_buffers` | `500` | Output buffer depth. Raise if the log reports drops. |

Most clients set frequency, sample rate and gain themselves over the `rtl_tcp`
protocol, so the defaults only matter until a client connects.

## Using it with rtlamr2mqtt

In the `rtlamr2mqtt` add-on configuration, set:

```yaml
general:
  rtltcp_host: "<home assistant address>:1234"
```

That stops it launching its own `rtl_tcp` — the one built against the driver that
cannot drive a V4 — and points it here instead.

## Using it with rtl_433

```
rtl_433 -d rtl_tcp://<home assistant address>:1234 -f 912.6M -s 1024k
```

## Known limits

- One client at a time. `rtl_tcp` does not multiplex.
- Prefer a USB 2 port. USB 3 controllers emit broadband noise across the 900 MHz
  band, which is exactly where utility meters transmit.
- This serves raw IQ. It does no decoding of its own.
