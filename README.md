# BrawnyBravo SDR for Home Assistant

A Home Assistant add-on that turns an RTL-SDR dongle into a network radio source.

## Add it to Home Assistant

Settings → Apps → three-dot menu → Repositories → add:

```
https://github.com/BrawnyBravo/ha-sdr-addon
```

## Add-ons

| Add-on | What it does |
|---|---|
| [RTL-TCP (RTL-SDR Blog driver)](./rtl_tcp_v4) | An `rtl_tcp` server built from the RTL-SDR Blog driver fork, so V3 and V4 dongles actually tune. |

## Licence

MIT. The RTL-SDR Blog driver is built from source at image build time and remains
under its own GPL-2.0 licence.
