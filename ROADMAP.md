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
- [ ] Menu bar widget, at parity with Polaris
      (`Sources/PolarisWidget`, `WidgetSnapshot.swift`, `WidgetBridge.swift`,
      app-group entitlement). New Xcode target + new App Group
      registration — not small, do after the core app is verified and
      signed.

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
re-propose unless this changes.
