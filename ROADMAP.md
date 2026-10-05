# Roadmap

## Before first signed release

- [ ] Confirm real Tesla data renders in the app (not just that the OAuth
      grant succeeds) — SB Auto's authorization was confirmed by Tesla
      2026-10-05; still need to see battery/range/charging data actually
      show up in the menu bar against a real vehicle.
- [ ] Flip `docs/index.html`'s dev banner and README's status section
      once the above is confirmed — currently say "not yet confirmed
      ready" pending that test.
- [ ] Code signing + notarization: secrets already exist at
      `/home/simon/.apple-signing/` (same Developer ID used for Polaris),
      just need `gh secret set` on this repo —
      `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`,
      `NOTARY_APP_PASSWORD`, `NOTARY_TEAM_ID`. Workflow already supports
      it (`.github/workflows/release.yml:55-92`), just never switched on.
- [ ] Real screenshot for the docs site, taken from Simon's Mac
      (Polaris already has one; Teslaris's docs still need it).
- [ ] Cut the first signed release (`make release VERSION=x.y.z`).

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

- [ ] Sparkle auto-update feed (Polaris has `SUFeedURL`/`SUPublicEDKey`
      in its Info.plist; Teslaris has neither).
- [ ] Homebrew cask + tap, as Polaris's release workflow publishes.

## Read-only Fleet API ideas (no cost beyond the request itself)

- [ ] `release_notes`
- [ ] `recent_alerts`
- [ ] `nearby_charging_sites`
- [ ] `dx`/warranty info
- [ ] vehicles-list `state` field, to distinguish asleep from offline

## Explicitly out of scope

Vehicle commands (`vehicle_charging_cmds`) and location
(`vehicle_location`) were proposed and declined 2026-08-02 — Teslaris
stays read-only by design, that's part of the product pitch. Don't
re-propose unless this changes.
