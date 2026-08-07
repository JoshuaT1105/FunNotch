# FunNotch

A free macOS app that puts the space around your MacBook's camera to work — now
playing, a drag-and-drop file shelf, clipboard history, focus sessions and
twelve configurable widgets, all in the notch.

**[funnotch.xyz](https://funnotch.xyz)** · [Download](https://github.com/JoshuaT1105/FunNotch/releases/latest) · [Changelog](https://funnotch.xyz/changelog) · [Install guide](https://funnotch.xyz/install)

macOS 14 Sonoma or later · Apple Silicon and Intel · 2.5 MB · no account, no telemetry

---

## What it does

- **Media** — now playing from Music, Spotify and any browser, with artwork, a
  live spectrum, and a progress bar you can drag to seek.
- **Shelf** — a drag-and-drop file shelf that opens to meet a drag already in
  flight. AirDrop and share straight off it; catches new screenshots and
  finished downloads on its own.
- **Clipboard** — searchable history with pinning. Entries a password manager
  marks concealed are skipped and never recorded.
- **Focus** — sessions that block websites and apps, with Pomodoro cycles.
- **Widgets** — twelve of them, any number either side of the camera.
- **HUD** — volume, brightness and keyboard backlight that *replaces* the
  system overlay rather than sitting beside it.
- **And** — camera mirror, calendar and reminders, meeting-link detection,
  custom themes, a diagnostics screen, and a small game.

## Building

No Xcode project — the app builds with `swiftc` directly.

```bash
./build.sh                      # debug build into build/
./build.sh --universal          # arm64 + x86_64
./build.sh --universal --package # ...and produce dist/*.dmg and dist/*.zip
```

Requires the Xcode command line tools. Everything under `build/` and `dist/` is
generated and git-ignored.

### Signing

Builds are **signed ad-hoc** by default, which is why macOS refuses the first
launch. If you have a paid Apple Developer certificate:

```bash
./build.sh --universal --package \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize your-notary-profile
```

## Verifying a change

There is a self-test that drives the real window manager rather than mocking it
— it opens and closes the notch, simulates drags, and checks the panel geometry.

```bash
build/FunNotch.app/Contents/MacOS/FunNotch --self-test
```

It needs a GUI session, so it will not run over plain SSH. There is also a
preview renderer that writes every notch state to PNG, which is how the
screenshots on the website are produced:

```bash
build/FunNotch.app/Contents/MacOS/FunNotch --render-preview /tmp/shots
```

And a diagnostics dump:

```bash
build/FunNotch.app/Contents/MacOS/FunNotch --diagnostics
```

## Layout

```
Sources/
  App/          Lifecycle, status bar, self-test, preview renderer
  Core/         Settings, extensions, diagnostic log
  Managers/     Media, shelf, clipboard, focus, calendar, HUD, weather
  Settings/     The settings window
  Views/        The notch panel and everything drawn in it
Tools/
  MakeIcon.swift  Generates the app icon at build time
```

The marketing site at [funnotch.xyz](https://funnotch.xyz) is deliberately not
in this repo — it isn't part of the app, and it deploys separately.

## Permissions it asks for

None are required; each one only enables the feature that needs it.

| Permission | Used for |
|---|---|
| Accessibility | The HUD — catching the media key before macOS acts on it |
| Calendar & Reminders | The agenda beside the player |
| Camera | The camera mirror, only while open |
| Location | The weather widget, to pick a forecast |

The app makes network requests in exactly two situations: `api.open-meteo.com`
for the weather widget, and album artwork from whatever URL your media source
provides. There is no analytics, no crash reporting and no telemetry of any
kind. See [the About page](https://funnotch.xyz/about#network).

## Contributing

Issues and pull requests are welcome. A few things worth knowing:

- **Match the surrounding code.** Comments here explain *why*, not *what* —
  if a line needs a comment saying what it does, the line is usually the problem.
- **Run `--self-test` before opening a PR.** If you change window geometry,
  drag handling or the HUD, add a check to `Sources/App/SelfTest.swift`.
- **The notch is a non-activating panel.** It never becomes the key window, so
  keyboard events go to whatever app is actually in front. Anything interactive
  up there has to work from pointer position alone.

## Prior art

FunNotch began as a rebuild of
**[TheBoringNotch](https://github.com/TheBoredTeam/boring.notch)**, which got to
the idea first and is a genuinely good app. There is an
[honest comparison](https://funnotch.xyz/compare) on the website, including the
things theirs does better.

## Licence

[GPL-3.0](LICENSE). If you distribute a modified version, it has to be open
too.
