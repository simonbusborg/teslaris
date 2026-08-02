# Teslaris

Your Tesla, in the menu bar.

Teslaris is a tiny native macOS app that shows your Tesla's battery, range,
and charging status in the menu bar. Pure AppKit — no Electron, no SwiftUI,
no background services. It talks only to Tesla: the official Fleet API,
using **your own** (free) Tesla developer application, plus Tesla's public
image renderer for the car picture. Your data goes between your Mac and
Tesla — nowhere else, and there is nothing to subscribe to.

Sibling project of [Polaris](https://github.com/simonbusborg/polaris)
(the same app for Polestar). Docs and setup guide:
[simonbusborg.github.io/teslaris](https://simonbusborg.github.io/teslaris/).

**[Download Teslaris.dmg](https://github.com/simonbusborg/teslaris/releases/latest/download/Teslaris.dmg)** · [All releases](https://github.com/simonbusborg/teslaris/releases)

## Install

Download `Teslaris.dmg` from the
[latest release](https://github.com/simonbusborg/teslaris/releases/latest),
open it, and drag Teslaris to Applications (a `Teslaris.zip` is also
attached for scripted installs). Releases are built by GitHub Actions —
cut with `make release VERSION=x.y.z`, which bumps `Info.plist`, tags,
and pushes. macOS blocks the first launch of unsigned releases ("Apple
could not verify…"): click **Done**, then **System Settings → Privacy &
Security → Open Anyway**. On macOS 14 and earlier, **right-click → Open
→ Open** also works. This happens once.

## Features

- Battery %, range (km/mi), charging status, charging power, charge limit
  and time-to-full — refreshed every 15 minutes when parked; while
  charging the cadence scales with time-to-full (5 min → 1 min as the
  charge finishes)
- Cabin and outside temperature (in the car's own °C/°F setting),
  door-lock and Sentry Mode status, a warning when a window, door, frunk
  or trunk is left open, and pending software updates — all from the same
  billed request as the charge data, so none of it costs extra
- A side view of your car at the top of the menu, rendered by Tesla's
  configurator (free — not Fleet API traffic). Model, paint and wheels
  are auto-detected; combinations the renderer doesn't support fall back
  to a neutral white car of the right model. To force exact options:
  `defaults write com.weareheavy.teslaris car_image_options '$MTY13,$PRED,$WY20P,$INPB0'`
- Notifications when charging starts, completes, or the charger loses power
- Sleep-aware: a sleeping car is never woken (wakes cost Fleet API credit
  and battery) — the menu shows the last known data, marked as such
- Choose what the menu bar shows; the icon reflects charging state
- Credentials and session in the macOS Keychain, never in plaintext
- Launch at login (optional), once-a-day update check against GitHub
- A single small binary

## Why "bring your own developer app"?

Tesla's Fleet API bills per request, with a free $10/month credit **per
developer account**. If Teslaris shipped with one shared API key, every
user's polling would bill one account and the app would have to charge a
subscription. Instead, each user registers their own free developer
application once (~20 minutes) and Teslaris's modest polling stays
comfortably inside their own free credit. Teslaris requests only the
read-only `vehicle_device_data` scope — it cannot unlock, wake, or drive
your car.

## Setup guide

You need: a Tesla account with a vehicle, and somewhere to host one small
public file (GitHub Pages works — you already have GitHub).

1. **Generate a key pair** (Tesla requires registering a public key even
   for read-only apps). Easiest: the
   [setup guide](https://simonbusborg.github.io/teslaris/#setup) generates
   it in your browser — locally, nothing is sent anywhere — and prefills
   the GitHub commit for step 2. Or in Terminal:

   ```bash
   openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem
   openssl ec -in private-key.pem -pubout -out com.tesla.3p.public-key.pem
   ```

   Keep `private-key.pem` somewhere safe (Teslaris never needs it — it's
   only required if you later want vehicle commands).

2. **Host the public key** at
   `https://YOUR-DOMAIN/.well-known/appspecific/com.tesla.3p.public-key.pem`.
   Easiest: a GitHub Pages repo — create `username.github.io`, commit the
   file under `.well-known/appspecific/`, done.

3. **Create the developer app** at [developer.tesla.com](https://developer.tesla.com):
   sign in with your Tesla account → "Create new application". Use your
   domain from step 2 as *Allowed Origin*, and add
   `http://localhost:8973/callback` as an *Allowed Redirect URI*.
   Request the `vehicle_device_data` scope. Note the **Client ID** and
   **Client Secret**.

4. **Teslaris**: menu bar icon → Settings… → paste Client ID, Client
   Secret and your key domain, pick your region, then click **Register
   App with Tesla** — the app performs the one-time partner registration
   for you. Finally **Save & Sign in with Tesla…** — your browser opens
   Tesla's login, and you're done.

The full guide with copy-paste blocks lives at
[simonbusborg.github.io/teslaris](https://simonbusborg.github.io/teslaris/).

## Try it without a Tesla

- **Demo mode** — a scripted day-in-the-life (park → plug in → charge →
  complete → sleep), no account needed:

  ```bash
  defaults write com.weareheavy.teslaris debug_demo_mode -bool YES
  ```

- **Mock server** — the real client against a local fake Fleet API,
  including asleep (408) and expired-token (401) behavior:

  ```bash
  make mock   # http://localhost:4321
  defaults write com.weareheavy.teslaris debug_base_url http://localhost:4321
  curl localhost:4321/debug/scenario/charging
  ```

  (`defaults delete com.weareheavy.teslaris debug_base_url` to go back.)

## Build from source

Requires macOS 13+ and the Xcode Command Line Tools.

```bash
git clone https://github.com/simonbusborg/teslaris
cd teslaris
make app
open Teslaris.app
```

`make run` builds and runs the bare binary for quick iteration; `make test`
runs the suite (no Tesla account needed — everything is fixture-driven).

## Costs

Teslaris is built so spending **cannot** rocket:

- **Adaptive polling.** Parked: every 15 min. Charging: every 5 min,
  tightening to 1 min only for the final stretch — so an overnight
  charge costs ~$0.20, not ~$1. A sleeping car is polled every 30 min
  and never woken.
- **A visible gauge.** The menu shows credits used on a progress bar —
  the free monthly credit covers ~5,000 requests, so one request is one
  credit. It resets monthly, and no money appears in the app.
- **A brake.** Past ~84% of the monthly credits, all polling stretches
  to 30 min until they reset, and the menu says so.
- **A hard ceiling.** Don't add a payment method to your Tesla
  developer account: Tesla then *suspends* API access at the credit
  limit instead of billing you. Worst case is a paused app — never a
  surprise bill.

With default use Teslaris lands around **$4–7/month of Fleet API usage,
inside the $10 free credit** Tesla grants every developer account. The
menu's "Refresh Now" is a real billed request; hammering it is the only
way to spend meaningfully faster.

## License

MIT. Not affiliated with Tesla.
