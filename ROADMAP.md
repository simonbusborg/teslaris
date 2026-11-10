# Roadmap

## Before first signed release

- [x] Confirm real Tesla data renders in the app — confirmed 2026-10-05
      against a real Model Y (battery, range, charger status, temperature,
      doors, odometer, credits all correct). Sign-in is fully working.
- [x] Dev banner and README status section removed 2026-10-05; the site
      and README now carry a real download link and say releases are
      notarized and self-updating. That is only true from the first signed
      release on, so the site must go live together with that release,
      not before it.
- [x] Code signing + notarization: all 5 secrets set on
      `simonbusborg/teslaris` 2026-10-05 (`MACOS_CERT_P12`,
      `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_APP_PASSWORD`,
      `NOTARY_TEAM_ID`, Team ID `C8Y7YNZN9R`). Not yet verified by an
      actual signed release build — do that on the next `make release`.
- [x] In-app updates via Sparkle, added 2026-10-05: `Updater.swift`,
      Settings UI, menu item, `Package.swift`/`Makefile`/`release.yml`
      wiring, `docs/appcast.xml` seed, `SPARKLE_PRIVATE_KEY` secret set
      (reuses Polaris's EdDSA key — same developer, same trust boundary
      as the shared Developer ID cert). Replaces the old manual
      GitHub-releases `UpdateChecker`. **Not yet built or run anywhere**
      — needs a real `make app` / `make release` on Simon's Mac before
      trusting any of it; this was written blind on a Linux box with no
      Swift toolchain.
- [ ] Real screenshot for the docs site, taken from Simon's Mac
      (Polaris already has one; Teslaris's docs still need it).
- [ ] Cut the first signed release (`make release VERSION=x.y.z`) — this
      is also the first real end-to-end test of both the signing secrets
      and the Sparkle wiring above.

## After shipping

- [ ] Revisit the audience-omission / multi-region retry fallback in
      `Sources/Teslaris/TeslaFleetAPI.swift` (`partnerTokenForAnyRegion`,
      `registerPartnerAccount`) — if real sign-ins never trigger the
      fallback, it can likely be simplified now that Tesla's server-side
      bug is fixed.

## Optional, not yet decided

- [ ] Homebrew cask + tap, as Polaris's release workflow publishes.

## Read-only Fleet API ideas (no cost beyond the request itself)

- [ ] `release_notes`
- [ ] `recent_alerts`
- [ ] `nearby_charging_sites`
- [ ] `dx`/warranty info
- [ ] vehicles-list `state` field, to distinguish asleep from offline

## Shipped

Every entry carries the version it shipped in; the release workflow turns
the entries for a version into the notes Sparkle shows in its update panel.

- **Sign-in asks again for missing permissions** (v0.7.1) — if Vehicle
  Information was left unticked when you first signed in, signing in
  again now brings Tesla's permission screen back instead of reusing the
  old answer, and the menu says plainly when that permission is missing.
- **Wake the car from the menu** (v0.7.0) — an opt-in in Settings. With it
  on, Wake Car & Refresh appears while the car sleeps and fetches fresh
  numbers once it answers. Teslaris still never wakes the car by itself;
  waking needs the `vehicle_cmds` scope on your Tesla app and a new
  sign-in, and each wake counts as ten requests against your credits.
- **Errors that say what went wrong** (v0.7.0) — when Tesla refuses a
  request, the menu now shows the status code and Tesla's own message,
  with a hint at the fix for the usual causes: an app not registered in
  your region, the wrong region, or a sign-in that has expired.
- **The car on your desktop** (v0.6.0) — small, medium and large widgets
  with battery, range, charging state and the car itself. They show what
  the app last fetched, so they cost no extra Fleet API credits, and a
  click opens the menu.
- **Low tyre pressure warning** (v0.6.0) — a notification when the car
  flags a tyre as low, once rather than on every refresh, and a row in the
  menu with the pressure for as long as the car keeps flagging it.
- **Car left unlocked** (v0.6.0) — a notification when the car has been
  sitting unlocked with nobody in it for ten minutes. Each of the two has
  its own switch in Settings.
- **Updates inside the app** (v0.5.0) — Teslaris now checks for new
  versions and installs them itself, from Settings or the menu, and
  automatically if you turn that on. Releases are signed and notarized by
  Apple, so they open without the Gatekeeper detour.
- **Low-battery reminder** (v0.5.0) — a notification when the battery drops
  below a level you choose, once per discharge rather than on every
  refresh.
- **Your own refresh pace** (v0.5.0) — choose how often a parked car is
  checked, from every minute to every 15 minutes.
- **Polling that stays inside the free credits** (v0.5.0) — near the
  monthly allowance, updates slow down just enough for the remaining
  credits to last until they reset, and pause if they run out.

## Explicitly out of scope

Vehicle commands (`vehicle_charging_cmds`) and location
(`vehicle_location`) were proposed and declined 2026-08-02 — Teslaris
stays read-only by design, that's part of the product pitch. Don't
re-propose unless this changes. The one exception, added 2026-11-10 for #5: waking the car
is an opt-in in Settings, which adds `vehicle_cmds` (Tesla's only scope
covering wake_up) and uses it for nothing else.
