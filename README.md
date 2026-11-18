# ScreenGlow for macOS

ScreenGlow brings the colors on your Mac display into your room. It syncs compatible Lotus Lantern RGB strips and Apple Home Matter bulbs with screen colors, with optional bass-reactive brightness changes for Matter bulbs.

## Download

[Download ScreenGlow for Mac](https://github.com/mhmdbilal1/ScreenGlow/raw/refs/heads/main/ScreenGlow-macOS.zip), unzip it, and move `ScreenGlow.app` to Applications.

Requires macOS 14 or later. Screen sync needs Screen Recording permission. Lotus Lantern strips need Bluetooth permission. To use Matter bulbs, share them with this Mac through Apple Home. This build is locally signed and not notarized, so macOS may show a first-open Gatekeeper warning.

## Features

- Live screen color matching for Lotus Lantern RGB strips
- Apple Home Matter bulb controls and screen color sync
- A shared color palette for connected bulbs
- Adjustable screen-sync brightness
- Dark-scene dimming
- Optional bass-reactive brightness changes for Matter bulbs
- A short animated launch screen with a reduced-motion friendly presentation

## Build from source

Requirements: macOS 14 or later and Swift 6.0 or later.

```sh
./build-app.sh
```

The script builds `ScreenGlow.app` locally and applies an ad-hoc signature. For wider public distribution, use a Developer ID signature and notarize the app.

## Project files

- [Launch kit](LAUNCH_KIT.md): product copy, community post drafts, and demo outline
- [v1.1.0 release notes](RELEASE_NOTES_v1.1.0.md)

## License

All rights reserved. Contact the repository owner for reuse permissions.
