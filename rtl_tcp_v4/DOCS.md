# RTL-SDR Radio (RTL-SDR Blog driver)

One USB RTL-SDR dongle, built against the RTL-SDR Blog driver so V3 and V4
hardware actually tunes, with four jobs it can do.

## Why this add-on exists

The `librtlsdr` packaged by most distributions — including what is available
inside Home Assistant OS — does not recognise **RTL-SDR Blog V4** hardware. The
dongle enumerates normally and reports its own name, so everything *looks* fine:

```
Found 1 device(s):
  0:  RTLSDRBlog, Blog V4L, SN: 00000001
Found Rafael Micro R820T tuner
[R82XX] PLL not locked!
```

That last line is the failure. The tuner is misidentified, every tune attempt
fails, and any decoder downstream sits in silence forever without printing an
error of its own — which makes a driver problem look like a weak signal or a bad
antenna. A working V4 reports this instead:

```
RTL-SDR Blog V4 Lite Detected
```

There is no runtime flag for it. The vendor's fork has to be compiled in, which
is what the `Dockerfile` does. Every mode below inherits that fix, and the
add-on prints the detection line on startup so you never have to guess.

## One dongle, one band at a time

A dongle tunes to a single slice of spectrum. It cannot follow utility meters
and aircraft simultaneously — that is physics, not a software limit. Pick a mode,
or add a second dongle and a second instance.

## Modes

### `rtl_tcp` (default)

Serves the raw stream on port 1234 so any machine on the network can borrow the
dongle: `rtl_433`, SDR++, GQRX, SDRangel, or `rtlamr2mqtt` via its
`rtltcp_host` setting. One client at a time.

### `rtl_433`

Decodes several hundred device types and publishes them to MQTT: utility meters,
cheap weather and temperature sensors, tyre pressure sensors, door sensors, soil
probes. Home Assistant hands the add-on the broker details automatically, so no
separate MQTT account is needed — set `mqtt_host` only to override it.

With `mqtt_ha_discovery` on, entities create themselves.

Set `decoder_frequencies` to the bands you care about:

| Band | Typically |
|---|---|
| `433.92M` | Most cheap consumer sensors |
| `868M` | European sensors |
| `912.6M` | North American utility meters |
| `315M` | Tyre pressure sensors, some remotes |

Leave `decoder_protocols` empty to decode everything, or list protocol numbers
to cut noise. `rtl_433 -R help` lists them.

### `adsb`

Basic aircraft frames to the log and to `share/rtlsdr/adsb-frames.txt`.
Deliberately minimal — for a proper map and a feeder, run `rtl_tcp` mode and
point a dedicated aircraft decoder at this machine.

### `survey`

Sweeps a frequency range and writes a spectrum file to
`share/rtlsdr/survey_<date>.csv`. Use it to find out what your antenna can
actually hear from where it sits, with measurements rather than guesswork. Runs
once, then idles.

## Options

| Option | Default | Applies to | Notes |
|---|---|---|---|
| `mode` | `rtl_tcp` | all | `rtl_tcp`, `rtl_433`, `adsb`, `survey` |
| `device_index` | `0` | all | Which dongle, if you have several |
| `gain` | `0` | all | `0` is automatic |
| `ppm_error` | `0` | all | Crystal correction |
| `bind_address` | `0.0.0.0` | rtl_tcp | Listen address |
| `tcp_sample_rate` | `2048000` | rtl_tcp | Samples per second |
| `tcp_frequency` | `912600000` | rtl_tcp | Start frequency, Hz; clients retune |
| `tcp_max_buffers` | `500` | rtl_tcp | Raise if the log reports drops |
| `decoder_frequencies` | `912.6M` | rtl_433 | One or more bands to hop |
| `decoder_protocols` | *(empty)* | rtl_433 | Empty decodes everything |
| `decoder_extra_args` | *(empty)* | rtl_433 | Passed through verbatim |
| `mqtt_host` … `mqtt_password` | *(unset)* | rtl_433 | Only to override Home Assistant's broker |
| `mqtt_topic_prefix` | `rtl_433` | rtl_433 | Topic root |
| `mqtt_ha_discovery` | `true` | rtl_433 | Create entities automatically |
| `survey_from` / `survey_to` | `400M` / `1000M` | survey | Sweep range |
| `survey_bin_size` | `100k` | survey | Resolution |
| `survey_minutes` | `10` | survey | How long to sweep |

## What one short vertical whip gets you

This add-on is built around the antenna that comes with a dongle: a short
telescopic whip stood upright, set to roughly 3 inches. That is a quarter wave
at 900 MHz, and it is close enough to a quarter wave at 1090 MHz that the same
antenna, unchanged, covers:

| Use | Band | With this antenna |
|---|---|---|
| Utility meters | ~912 MHz | Its design point. Works well. |
| Aircraft | 1090 MHz | Works well — 3 inches is near ideal here too. |
| Tyre pressure sensors | 315 / 433 MHz | Short for the band, so range is poor — but a car in the driveway is close, which is all this needs. |
| Cheap sensors | 433 MHz | Same caveat. Extending the whip to about 6.5 inches helps if you are only doing 433. |

Bands this antenna genuinely cannot reach — weather radio, emergency services,
ham repeaters, weather satellites — all sit near 140–170 MHz and need a much
longer element. They are out of scope here on purpose.

## Utility meter readings, and a fix this add-on carries

Upstream's Home Assistant MQTT discovery bridge (`rtl_433_mqtt_hass.py`) drops the
one field a utility meter exists to report. It matches message keys exactly and
case-sensitively, and its mapping table has a lowercase `consumption` entry
labelled "SCMplus Consumption Value" -- but SCM+ emits `Consumption` with a
capital C. That entry can therefore never match an SCM+ message. IDM and NETIDM
lose their readings the same way: `LastConsumption`, `LastConsumptionCount` and
`LastConsumptionNet` are not in the table at all.

The symptom is confusing, because nothing looks broken. The decode is CRC-valid,
the reading is sitting in the MQTT payload, the bridge logs no error -- and the
only entities that ever appear for the meter are `rssi`, `snr` and `noise`. The
reading has to be hand-built as a template sensor to be usable.

On one receiver here the split is stark. ERT-SCM emits `consumption_data`, which
*is* in the table, and all 22 ERT-SCM meters in range produced a reading entity.
The 56 SCM+, IDM and NETIDM meters in range produced none between them.

This add-on patches the bridge at build time (`patch_mqtt_hass.py`). The patch is
strictly **additive**: it adds `Consumption`, `LastConsumption`,
`LastConsumptionCount`, `LastConsumptionNet` and `MeterType`, and changes no
existing entry. That matters, because lowercase `consumption` is not dead code --
across all of upstream's decoders exactly one emits it (`neptune_r900.c`), so it
quietly serves Neptune R900 water meters under an SCM+ label. Nobody using an
R900 loses an entity. The build fails rather than shipping a bridge that does not
parse, and re-running the patch is a no-op.

Applies to `rtl_433` mode with MQTT discovery enabled. If you already hand-built
a template sensor for your meter, it keeps working; the discovered entity appears
alongside it, so pick one and remove the other to avoid double-counting.

## Practical notes

- **Use a USB 2 port.** USB 3 controllers emit broadband noise right across the
  900 MHz band, which is where utility meters transmit.
- **Antenna orientation matters.** Utility meters transmit vertically, so stand
  the antenna upright. For 900 MHz, extend telescopic elements to roughly
  3 inches — much shorter than looks right.
- **Not everything is readable.** Meters using two-way mesh radios (for example
  Tantalus TUNet modules) do not broadcast in the clear and cannot be decoded by
  anything here, no matter the antenna or driver.

## Licence

MIT. `librtlsdr` and `rtl_433` are built from source at image build time and
remain under their own licences.
