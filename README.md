# Net Rain

A tiny, purely visual network monitor for the Omarchy (Quattro) top bar.

- Download dots fall from the top, upload dots rise from the bottom, mixed in one 90 px panel.
- More traffic means more dots, faster dots and hotter colour: green (kb/s), yellow (1-9 Mb/s), red (10-50 Mb/s), purple (50+ Mb/s), blended smoothly.
- No text and no hover. The background is black with a faint green CRT tint, and a single click makes it transparent (click again to bring the black back).
- When the network goes offline, the dots fade to grey and freeze in place. When it comes back, they fade back to colour and keep moving.

## Install

```sh
omarchy plugin add https://github.com/soham3301/net-rain.git --enable
omarchy bar move io.github.soham3301.net-rain --section right
```

## Settings

Add keys to the widget's entry in `~/.config/omarchy/shell.json`:

| Key           | Default | Meaning                                                    |
| ------------- | ------- | ---------------------------------------------------------- |
| `width`       | `90`    | Length of the display in px                                |
| `dotSize`     | `4`     | Square size in px                                          |
| `dotGap`      | `2`     | Gap between squares in px                                  |
| `maxRows`     | `5`     | Most dot rows allowed (also limited by bar height)         |
| `interface`   | `auto`  | `auto` (en*, eth*, wl*, ww*), or names like `wlan0,enp3s0` |
| `transparent` | `false` | Start with a transparent background instead of black       |

Clicking the widget flips the background for the current session. To make a choice permanent, set `transparent` in `shell.json`.

## How it works

Every 500 ms it reads `/proc/net/dev` and turns byte deltas into Mb/s. VPN and virtual interfaces are skipped in `auto` mode so traffic is not counted twice.

It counts the network as offline when there is no default route on a selected interface (read from `/proc/net/route` and `/proc/net/ipv6_route`). A connection that is up but has no internet access still counts as online.

## Security

Omarchy plugins run unsandboxed inside the shell. This plugin only reads `/proc/net/dev`, `/proc/net/route` and `/proc/net/ipv6_route`, spawns no processes and makes no network requests.

## Changelog

- **1.1.0**: click to toggle a transparent background; dots turn grey and freeze when offline.
- **1.0.0**: first release.

## Remove

```sh
omarchy plugin remove io.github.soham3301.net-rain
```
