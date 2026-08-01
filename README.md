# Teslaris

Your Tesla, in the menu bar.

Teslaris is a tiny native macOS app that shows your Tesla's battery, range,
and charging status in the menu bar. Pure AppKit — no Electron, no SwiftUI,
no background services. It talks only to Tesla's official Fleet API, using
**your own** (free) Tesla developer application, so your data goes between
your Mac and Tesla — nowhere else, and there is nothing to subscribe to.

Sibling project of [Polaris](https://github.com/simonbusborg/polaris)
(the same app for Polestar).

## Features

- Battery %, range (km/mi), charging status, charging power, charge limit
  and time-to-full — refreshed every 15 minutes, or every minute while
  charging
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
   for read-only apps):

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

4. **Register your app with Tesla** (one-time curl; use your region's
   host, `na` or `eu`):

   ```bash
   TOKEN=$(curl -s https://auth.tesla.com/oauth2/v3/token \
     -d grant_type=client_credentials -d client_id=YOUR_CLIENT_ID \
     -d client_secret=YOUR_CLIENT_SECRET \
     -d scope=openid \
     -d audience=https://fleet-api.prd.eu.vn.cloud.tesla.com | jq -r .access_token)
   curl -s -X POST https://fleet-api.prd.eu.vn.cloud.tesla.com/api/1/partner_accounts \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"domain": "YOUR-DOMAIN"}'
   ```

5. **Teslaris**: menu bar icon → Settings… → paste Client ID and Client
   Secret, pick your region, click **Save & Sign in with Tesla…** — your
   browser opens Tesla's login, and you're done.

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

With default polling (15 min parked, 1 min charging, sleeping car left
alone) Teslaris stays around **$5–8/month of Fleet API usage — inside the
$10 free credit** Tesla grants every developer account. The menu's
"Refresh Now" is a real billed request (~$0.002); hammering it is the only
way to spend meaningful money.

## License

MIT. Not affiliated with Tesla.
