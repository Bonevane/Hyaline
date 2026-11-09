<!-- Banner to come: assets/hyaline-banner.png -->

# Hyaline

<p align="center">
  <b>Live desktop widgets for your Mac, made of real Liquid Glass</b>
</p>
<p align="center">
  Sixty-three widgets that sit beside Apple's own, update live and look like they shipped with macOS.
</p>

<div align="center">

  <img src="https://img.shields.io/badge/Status-Working%20Prototype-8E9BB0?style=for-the-badge&labelColor=1B1D22" alt="Status" />
  <img src="https://img.shields.io/badge/Stack-Swift%20%7C%20SwiftUI%20%7C%20AppKit-8E9BB0?style=for-the-badge&labelColor=1B1D22" alt="Stack" />
  <img src="https://img.shields.io/badge/Platforms-macOS%2026%2B-8E9BB0?style=for-the-badge&labelColor=1B1D22" alt="Platforms" />

</div>

<br>

## <img src="https://api.iconify.design/lucide/telescope.svg?color=%238E9BB0" width="20" height="20">&nbsp; The Problem
macOS 26 put widgets on the desktop and made them beautiful. Then it made them hard to build on.

<table width="100%">
  <tr>
    <td width="33%" valign="top" align="center">
      <br>
      <h3 align="center"><img src="https://api.iconify.design/lucide/timer-off.svg?color=%238E9BB0" width="18" height="18">&nbsp; Not Live</h3>
      <p align="center">WidgetKit widgets are snapshots on a refresh budget. A CPU graph, a seek bar or a fan speed can't update while you watch.</p>
      <br>
    </td>
    <td width="33%" valign="top" align="center">
      <br>
      <h3 align="center"><img src="https://api.iconify.design/lucide/square-dashed.svg?color=%238E9BB0" width="18" height="18">&nbsp; Not Glass</h3>
      <p align="center">Live desktop widget tools draw their own panels. Next to Apple's widgets they look flat, the wrong colour and the wrong shape.</p>
      <br>
    </td>
    <td width="33%" valign="top" align="center">
      <br>
      <h3 align="center"><img src="https://api.iconify.design/lucide/layers.svg?color=%238E9BB0" width="18" height="18">&nbsp; Not at Home</h3>
      <p align="center">They float above windows, overlap Apple's widgets, ignore their grid, linger in Mission Control and vanish while you swipe between desktops.</p>
      <br>
    </td>
  </tr>
</table>

<br>

## <img src="https://api.iconify.design/lucide/cpu.svg?color=%238E9BB0" width="20" height="20">&nbsp; The Solution
Hyaline puts each widget in **its own window on the desktop layer**, one step below Apple's widgets, and builds the plate from the same glass macOS uses. The content is live SwiftUI, so it updates as often as it needs to, and slows down on battery.

### How it works

1.  **Glass:** every plate is an `NSGlassEffectView` on the private variant that draws Apple's rim and edge lensing, shaded to match Apple's widgets side by side. The lock-screen clock's numerals are glass too, cut to the shape of each digit.
2.  **Placement:** sizes match Apple's exactly (164 and 344pt plates, 16pt gutters). Widgets snap to Apple's widgets, to 16pt gutters, to the screen edges and its centre, and never overlap. Two slim widgets stack to a medium, and a medium plus two slims to a large.
3.  **Spaces:** widgets join every normal desktop but stay out of full-screen apps, the same Spaces Apple's widgets live in, so they slide with the desktop when you swipe. They fade out with Mission Control and stay put when you click the wallpaper.
4.  **Layout:** each widget remembers its distance from the nearest edges, its share of the screen, or its place next to one of Apple's widgets. Change the resolution and everything follows, including Apple's own widgets as macOS moves them.
5.  **Power:** one sampler feeds every system widget, polling stops when no widget is visible, and every timer runs slower on battery.
6.  **Gallery:** the menu bar opens a gallery with every widget live at its real size. Click to add, drag onto the desktop to place, or use the pencil to pick Glass, Frosted or Clear and set its options first.

> Hyaline follows System Settings › Appearance › Widget style. Clear and Tinted give monochrome widgets, as Apple's do.

<br>

## <img src="https://api.iconify.design/lucide/shield-alert.svg?color=%238E9BB0" width="20" height="20">&nbsp; Private Interfaces
The public API can't do any of this, so Hyaline uses a few private macOS interfaces. All of them live in one file, [`PrivateAPI.swift`](Sources/HyalineKit/Support/PrivateAPI.swift), so a macOS update that changes them is a one-file fix. This also means Hyaline can't go on the Mac App Store.

| **Interface**                        | **What Hyaline uses it for**                                                                  | **If it breaks**                                    |
| :----------------------------------- | :-------------------------------------------------------------------------------------------- | :-------------------------------------------------- |
| **Glass variant and shape**          | Apple's rim and lensing on the plates, and glass cut into clock numerals                      | Plates fall back to the public frosted glass        |
| **Window server Spaces**             | Keeping widgets on normal desktops and out of full-screen apps                                | Widgets also show over full-screen apps             |
| **Window server events**             | Fading widgets out the moment Mission Control opens                                           | Widgets stay visible in Mission Control             |
| **HID event system**                 | Temperature sensors on Apple silicon                                                          | Temperature widgets show dashes                     |

Nothing here needs root, a kernel extension or SIP changes. The only network requests are for weather (Open-Meteo), your place name (Apple), album art from the playing app, and the GitHub user and feeds you set.

<br>

## <img src="https://api.iconify.design/lucide/layout-grid.svg?color=%238E9BB0" width="20" height="20">&nbsp; Widgets

| **Group**            | **Widgets**                                                                                              |
| :------------------- | :------------------------------------------------------------------------------------------------------- |
| **Clock**            | Stretched lock screen (large and tall, glass numerals), stacked, word clock, split flap, minimal dial, day arc, world arcs, strip |
| **Mood**             | Phrase, serif, poster, ticker                                                                            |
| **CPU and system**   | Arc gauge, cores, load graph, strip, system overview                                                     |
| **Memory**           | Pressure level, breakdown, top apps, strip                                                               |
| **Battery**          | Big number, charge level, battery glyph (small and slim), charge history, health, all devices            |
| **Network**          | Up and down, speeds, connection                                                                          |
| **Storage**          | Storage column, storage strip                                                                            |
| **Energy**           | Energy list, power strip, biggest drain                                                                  |
| **Temperatures**     | Sensors, CPU, GPU and fans, thermometer                                                                  |
| **Time**             | Countdown, focus timer, sun path                                                                         |
| **Calendar**         | Week strip (medium and slim), next up (small and slim), month and agenda, year in dots, day timeline     |
| **Reminders**        | Reminders, ticked off from the widget                                                                    |
| **Weather**          | Big temperature, temperature curve, week ranges, strip                                                   |
| **Now Playing**      | Artwork, player with a working seek bar, strip, vinyl (Spotify and Music)                                |
| **Notes**            | Note                                                                                                     |
| **Scripts and web**  | Script output, GitHub contribution grid, feed headlines                                                  |

A click on any widget opens what it shows: Calendar, Activity Monitor, the playing app, the right System Settings pane, and so on.

<br>

## <img src="https://api.iconify.design/lucide/layers.svg?color=%238E9BB0" width="20" height="20">&nbsp; Tech Stack
Swift, SwiftUI and AppKit, built as a Swift package with the Command Line Tools. No Xcode project and no dependencies.

| **Component**        | **Technology**                                                                                                | **Description**                                                                            |
| :------------------- | :------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------- |
| **Widgets**          | <img src="https://skillicons.dev/icons?i=swift" valign="middle" />                                             | SwiftUI views, one file per group, listed in [`Registry.swift`](Sources/HyalineKit/Widgets/Registry.swift). |
| **Desktop**          | <img src="https://skillicons.dev/icons?i=apple" valign="middle" />                                             | AppKit panels on the desktop layer: glass surface, snapping, layout, Spaces and Mission Control. |
| **Data**             | <img src="https://api.iconify.design/lucide/activity.svg?color=%238E9BB0" width="36" valign="middle" />        | Mach and IOKit for system stats, EventKit, CoreLocation, AppleScript for Now Playing, the SMC for fans. |
| **Weather**          | <img src="https://api.iconify.design/lucide/cloud-sun.svg?color=%238E9BB0" width="36" valign="middle" />       | [Open-Meteo](https://open-meteo.com), free and keyless.                                    |

```
Sources/
  Hyaline/          the app: starts HyalineKit
  HyalineKit/
    App/            startup, menu bar, debug self-checks
    Desktop/        widget windows, glass, snapping, layout, Spaces, Mission Control
    Gallery/        the Widget Gallery
    Widgets/        every widget, one file per group, and the registry
    Data/           system readings and services
    Support/        appearance, battery pacing, the mark, private interfaces
  hyaline-check/    checks that run without a screen
scripts/            build-app.sh, make-icon.sh
```

<br>

## <img src="https://api.iconify.design/lucide/rocket.svg?color=%238E9BB0" width="20" height="20">&nbsp; Getting Started

### Install
There's no release yet, so build it from source below. When there is, it will be a DMG on [Releases](https://github.com/Bonevane/Hyaline/releases).

The first time a widget needs Calendar, Reminders, Location or Automation (for Spotify and Music), macOS asks. The menu bar icon opens the gallery; right-click a widget for its look, options, snapping and Remove.

### Build from source

```bash
xcode-select --install
```

```bash
scripts/build-app.sh && open build/Hyaline.app
```
Builds and signs `build/Hyaline.app` ad hoc. Set `SIGN_IDENTITY` to a Developer ID to sign for release, and `VERSION` and `BUILD` to stamp the version.

### Test

```bash
swift run hyaline-check
```
Checks the widget sizes stack the way Apple's do, snapping and overlap, layouts across resolution changes (next to Apple's widgets, centred and edge-anchored), the widget list and the mark.

```bash
CONFIG=debug scripts/build-app.sh && HYALINE_GALLERY=/some/folder build/Hyaline.app/Contents/MacOS/Hyaline
```
Debug builds add self-checks that render every widget, or the gallery, to PNGs from off-screen windows. [`SelfChecks.swift`](Sources/HyalineKit/App/SelfChecks.swift) lists them. Nothing on your screen is ever captured. Hold Option while opening the menu for the Developer menu of glass controls.

<br>

## <img src="https://api.iconify.design/lucide/map.svg?color=%238E9BB0" width="20" height="20">&nbsp; Roadmap
- [x] **Real Liquid Glass:** Apple's variant and shade, matched side by side
- [x] **Glass clock:** numerals cut from glass, with an optional date
- [x] **Apple-sized widgets:** small, medium, large, tall and slim, with slims that stack
- [x] **Snapping:** to Apple's widgets, gutters, edges and the centre, with no overlaps
- [x] **Spaces and Mission Control:** behaves like Apple's widgets when swiping and in Mission Control
- [x] **Resolution changes:** layouts follow, anchored to Apple's widgets where they touch
- [x] **Battery pacing:** every widget still updates on battery, just less often
- [x] **Click to open:** each widget opens its app or settings pane
- [x] **Widget Gallery:** live previews, click or drag to add, style and options before adding
- [x] **Open at login** from the menu bar
- [ ] **Notarized DMG** and updates from GitHub
- [ ] **Settings window**
- [ ] **Edit placed widgets** with the gallery's style popup
- [ ] **Multiple displays**
- [ ] **More widgets**

<br>

## <img src="https://api.iconify.design/lucide/heart-handshake.svg?color=%238E9BB0" width="20" height="20">&nbsp; Acknowledgements
- [Open-Meteo](https://open-meteo.com): free weather data, no key needed
- Apple's desktop widgets: the reference for every size, gap and shade here
- [Bridge](https://github.com/Bonevane/Bridge) and [WheelBridge](https://github.com/Bonevane/WheelBridge): Hyaline's older siblings

Copyright © 2026 Bonevane. Hyaline is released under the [GNU General Public License v3.0](LICENSE). See [`NOTICE`](NOTICE) for details.

<br>

<div align="center">

[![GitHub](https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white)](https://github.com/bonevane)
[![Portfolio](https://img.shields.io/badge/Portfolio-4285F4?style=flat&logo=googlechrome&logoColor=white)](https://bonevane.dev)
[![Email](https://img.shields.io/badge/Email-34A853?style=flat&logo=gmail&logoColor=white)](mailto:rahmad.atomic44@gmail.com)

</div>

<p align="center">
  <sub>Made with &nbsp;<sub><img src="https://api.iconify.design/lucide/heart.svg?color=%238E9BB0" width="14" height="14"></sub>&nbsp; by Bonevane</sub>
</p>
