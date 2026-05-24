# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

CCAS (Claude Code Account Switcher) is a SwiftUI / AppKit menu bar app for macOS 14+. It backs up and switches between Claude Code accounts by reading/writing Claude Code's local config file and its `Claude Code-credentials` Keychain item. The app runs as `LSUIElement` (no Dock icon) and uses `MenuBarExtra` for the UI.

## Build & Run

Two parallel build systems coexist — keep them in sync:

- **Xcode** (preferred for dev — stable code signing keeps Keychain ACLs intact): `open CCAS.xcodeproj`, scheme `CCAS`, target `My Mac`. Set a Team under Signing & Capabilities; ad-hoc rebuilds invalidate Keychain ACLs and reprompt the user.
- **SPM / standalone bundle**: `./scripts/build_app.sh` produces `dist/CCAS.app`. The script reads `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `PRODUCT_BUNDLE_IDENTIFIER` from the Xcode project via `xcodebuild -showBuildSettings`, then plist-buddies them into the built bundle.
- **Raw SPM build** (no bundle): `swift build -c release`. The binary itself is launchable but lacks the `.app` wrapper.

`Package.swift` injects `Sources/CCASApp/Info.plist` into the executable via `-sectcreate __TEXT __info_plist`. Editing `Info.plist` keys (e.g. `LSUIElement`) requires a clean rebuild, since the section is embedded at link time.

### Release pipeline

`./scripts/package_release.sh` produces signed/notarized ZIP + DMG in `dist/`. Required env vars: `SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`. The script stages the bundle at `/tmp/ccas/` because iCloud/Dropbox xattrs (`com.apple.FinderInfo`, fileprovider attrs) cause `codesign` to fail inside the project tree. Set `SKIP_NOTARIZE=1` to sign without submitting. GitHub Actions (`.github/workflows/release.yml`) runs this on `v*` tag push.

There is no test target. Verification is manual against the app bundle.

## Architecture

### Source layout (`Sources/CCASApp/`)

- `CCASApp.swift` — `@main` entry; sets `NSApplication.setActivationPolicy(.accessory)` and renders `MenuBarExtra`.
- `MenuContentView.swift` — popover UI.
- `AccountSwitcherViewModel.swift` — `@MainActor` `ObservableObject`. Owns quota fetching, cooldown bookkeeping, and rate-limit state.
- `ClaudeAccountStore.swift` — the core. All Claude Code config / Keychain / quota I/O lives here.
- `KeychainClient.swift` — shells out to `/usr/bin/security` rather than using the `SecKey` API (see "Keychain quirks" below).
- `FileLock.swift` — `flock`-based exclusive lock around `~/.ccas/.lock` for switch operations.
- `AccountModels.swift` — `AccountRecord`, `SequenceData`, `AccountQuotaInfo`, all `AccountSwitcherError` cases, `DebugLogger` (no-op in release).
- `Localization.swift` — `L10n.string(.key, args…)`. Language is picked at runtime: Chinese if `Locale.preferredLanguages.first` starts with `zh`, otherwise English.
- `AppAssets.swift` — loads PNGs from `Bundle.main` (use `Bundle.main`, not `Bundle.module` — SPM module resources were the cause of a prior `.app` crash, see commit `18981a1`).

### State, on disk and in Keychain

CCAS owns these locations — never mix them up with Claude Code's own state:

| Path | Owner | Purpose |
|---|---|---|
| `~/.claude.json` or `~/.claude/.claude.json` | Claude Code | Live config. CCAS picks the most recently modified file that contains `oauthAccount`. |
| Keychain `Claude Code-credentials` | Claude Code | Live OAuth credentials. CCAS overwrites this on switch. |
| `~/.ccas/sequence.json` | CCAS | Index: `{ activeAccountNumber, sequence: [Int], accounts: [String: AccountRecord], lastUpdated }`. Account numbers are stringified Int keys, monotonically increasing. |
| `~/.ccas/configs/.claude-config-<n>-<email>.json` | CCAS | Per-account snapshot of `~/.claude.json`. Not sufficient to restore an account alone — OAuth tokens live in Keychain. |
| `~/.ccas/quota-cache.json` | CCAS | Last-known quota per account; shown immediately on menu open before live refresh. |
| `~/.ccas/.lock` | CCAS | `flock` target serializing switch operations. |
| Keychain `li.luy.ccas.accounts`, account `account-<n>-<email>` | CCAS | Backup of each managed account's OAuth credentials JSON. |

### Switch flow (in `ClaudeAccountStore.switchToAccount`)

Wrapped in `FileLock.withExclusiveLock`. The sequence is: snapshot current account's config to its backup → write target credentials to `Claude Code-credentials` Keychain → splice the target's `oauthAccount` object into the live config file → bump `sequence.json`. The function tracks `wroteCredentials` / `wroteConfig` and rolls each back independently on error. When editing this flow, preserve the rollback invariants — partial writes across config + Keychain are the failure mode that motivated the lock.

### Quota fetch

Live usage: `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <accessToken>` and `anthropic-beta: oauth-2025-04-20`. OAuth refresh: `POST https://platform.claude.com/v1/oauth/token`, `grant_type=refresh_token`.

**Active accounts are never refreshed by CCAS — Claude Code owns those credentials.** The active account's tokens are read directly from `Claude Code-credentials` (the live Keychain) on every usage poll, never from the backup. Anthropic's token endpoint rotates the refresh token on every refresh and invalidates the old one; if CCAS refreshed the active account, it would race Claude Code's own background refreshes and whichever side refreshed second would get `invalid_grant`. If the live access token happens to be expired when usage is polled, surface as unavailable — Claude Code's next run will refresh it.

Inactive accounts are read from the backup Keychain and CCAS does refresh them when expiring/expired, persisting the rotated refresh token back to the backup. Nothing else touches an inactive account's backup, so this loop is safe.

`AccountSwitcherViewModel.loadQuotaInformation` enforces a 60s per-account cooldown and honors `Retry-After` on 429s by storing `quotaRateLimitedUntil[number]`. A `quotaRefreshGeneration` counter cancels stale in-flight refreshes when the user reopens the menu.

`AccountQuotaInfo` dispatches by plan: `pro`/`max` → personal (5h + weekly windows); `team`/`enterprise` → monetary (credit usage). `unknown` falls back based on which fields the API returned.

### Account record migration

Older `sequence.json` files predate `organizationUuid` / `organizationName`. `migrateOrganizationFieldsIfNeeded` runs at the start of `listAccounts` / `addCurrentAccount` / `switchToAccount`, hydrating those fields from each per-account config snapshot (or the live identity for the active account). `AccountRecord.init(from:)` tolerates missing fields and sets `hasOrganizationFields` based on key presence. Don't drop this migration — old user data is in the wild.

## Keychain quirks

`KeychainClient` shells out to `/usr/bin/security` (commit `b61c155`). This is intentional:

- It avoids per-build-signature ACL prompts that hit the `SecItem*` API after rebuilds.
- `security ... -w` prints the password as **lowercase hex with no `0x` prefix** whenever stored bytes contain any non-printable ASCII. Claude Code's pretty-printed JSON credentials trigger this path because they contain `\n`. `decodedFromHexOutput` decodes it; if you touch `passwordString`, preserve both the hex and UTF-8 branches.
- Writes use `add-generic-password -X <hex>` after deleting all matching entries (loop in `removeAllMatching`) — `security` does not have an upsert, and stale duplicates accumulate otherwise.
- `isNotFound` checks `terminationStatus == 44` **and** scans stderr for "could not be found" — both forms occur depending on the macOS version.

**Claude Code's keychain entry is multi-tenant.** A single `Claude Code-credentials` entry holds Claude OAuth AND every MCP plugin's OAuth as top-level keys (`claudeAiOauth` + `mcpOAuth`). Between sign-out and sign-in the entry can transiently lack `claudeAiOauth` while `mcpOAuth` still populates it — non-empty but useless to us. Any code path that snapshots live → backup (add, switch) or restores backup → live (switch) MUST gate the write through `hasUsableClaudeOAuthPayload` (presence + non-empty `claudeAiOauth.accessToken`). Writing such a blob silently corrupts the destination and Claude Code prompts /login on the next read.

`DebugLogger` is a no-op in release builds (`#if DEBUG`). Don't replace its callsites with `print`/`NSLog` directly.

## Versioning

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the Xcode project (`CCAS.xcodeproj/project.pbxproj`). `Info.plist` references them via `$(...)` substitution, which Xcode expands on archive and which `scripts/build_app.sh` re-expands via `PlistBuddy` after the SPM build. Bump versions through Xcode's General tab (or edit the pbxproj directly) — do **not** hardcode versions into `Info.plist`.
