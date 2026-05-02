# CCAS

[Simplified Chinese](README_ZH.md)

CCAS, short for Claude Code Account Switcher, is a native macOS menu bar app for switching between multiple Claude Code accounts.

It keeps a small icon in the menu bar. Click the icon, add the Claude Code account that is currently signed in, then select any saved account to switch Claude Code to that identity.

CCAS is not affiliated with Anthropic or Claude.

## Screenshot

![CCAS menu showing account usage](ScreenShot.png)

## Features

- Native macOS menu bar app.
- Add the currently signed-in Claude Code account.
- List saved Claude Code accounts with email, organization name, and plan type.
- Show account usage so you can choose the right account before switching:
  - Pro and Max accounts show 5-hour and weekly usage bars with reset times.
  - Team and Enterprise accounts show credit usage, total limit, usage ratio, and reset time.
- Reuse the last fetched usage data immediately when opening the menu, then refresh it in the background.
- Switch accounts from the menu bar.
- Bilingual UI: English by default, Simplified Chinese when the system language starts with `zh`.
- Stores account metadata under `~/.ccas`.
- Stores credentials locally with macOS Keychain.
- Includes an Xcode project, Swift Package manifest, and a standalone build script.

## Requirements

- macOS 14 or later.
- Xcode with Swift 6 support.
- Claude Code installed and signed in at least once.

## Build

### Xcode

Open the project:

```bash
open CCAS.xcodeproj
```

Select the `CCAS` scheme and run it on `My Mac`.

For stable Keychain permissions while developing, set a Team in `Signing & Capabilities`. macOS may treat ad-hoc signed debug builds as different apps after rebuilds, which can make Keychain permission prompts appear again.

### Script

Build a standalone app bundle:

```bash
./scripts/build_app.sh
```

Run it:

```bash
open dist/CCAS.app
```

The script reads `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `PRODUCT_BUNDLE_IDENTIFIER` from the Xcode project, then writes the expanded values into the generated app bundle.

## Usage

### Add Accounts

1. Sign in to Claude Code with the first account.
2. Open CCAS from the menu bar.
3. Click `Add Account`.
4. Sign in to Claude Code with another account.
5. Click `Add Account` again.

If the same email and organization are detected again, CCAS updates the existing backup instead of creating a duplicate account.

### Switch Accounts

Open the CCAS menu bar panel and click the account you want to use.

After switching, restart Claude Code so it reloads the updated credentials and config.

### Check Usage

Open the CCAS menu bar panel to see saved account usage at a glance. CCAS shows cached usage first to keep the menu height stable, then fetches fresh usage data in the background and updates the panel when it arrives.

The refresh button shows a loading indicator while usage is being fetched. The text between `Add Account` and the refresh button shows when usage data was last updated, such as `12 s` or `4 m`.

## How It Works

Claude Code stores its signed-in state in two places:

- A config file, usually `~/.claude.json` or `~/.claude/.claude.json`.
- A macOS Keychain item whose service is `Claude Code-credentials`.

CCAS saves one backup per account:

- Account index: `~/.ccas/sequence.json`
- Config snapshots: `~/.ccas/configs/`
- Last fetched usage snapshot: `~/.ccas/quota-cache.json`
- Managed account credentials: macOS Keychain service `li.luy.ccas.accounts`

When switching accounts, CCAS:

1. Backs up the current account config.
2. Reads the target account credentials from CCAS's Keychain service.
3. Writes those credentials into Claude Code's `Claude Code-credentials` Keychain item.
4. Replaces the `oauthAccount` section in the Claude Code config file.
5. Updates `~/.ccas/sequence.json`.

The files in `~/.ccas/configs/` are config snapshots. They are not enough to restore an account by themselves because OAuth credentials live in Keychain.

When the menu opens, CCAS reads `~/.ccas/quota-cache.json` first so usage rows can be displayed immediately. It then uses the saved Claude OAuth credentials for each account to request current usage data and updates the cache after a successful refresh.

## Data And Privacy

CCAS is designed as a local-first utility.

- It does not upload credentials.
- It does not include telemetry.
- It stores account metadata and config snapshots under `~/.ccas`.
- It stores cached usage data under `~/.ccas/quota-cache.json`.
- It stores account credentials in macOS Keychain under `li.luy.ccas.accounts`.
- It updates Claude Code's active Keychain item, `Claude Code-credentials`, when switching accounts.
- It makes direct authenticated requests to Anthropic's usage endpoint only to refresh account usage information.

Because CCAS reads and writes Keychain items, macOS may ask for permission. If you trust the build and want to avoid repeated prompts, choose `Always Allow`.

## Troubleshooting

### Keychain Prompts Keep Appearing

Use a stable code signing identity in Xcode:

1. Open `CCAS.xcodeproj`.
2. Select the `CCAS` target.
3. Open `Signing & Capabilities`.
4. Select your Team.
5. Rebuild and run.
6. Choose `Always Allow` when macOS asks for Keychain access.

### Account Backup Is Incomplete

If CCAS says an account is missing saved credentials, the config snapshot exists but the Keychain backup for that account does not.

To repair it:

1. Sign in to that account in Claude Code.
2. Open CCAS.
3. Click `Add Account`.

CCAS will update the existing account backup.

### Switched Account Does Not Take Effect

Restart Claude Code after switching accounts. Claude Code may keep credentials in memory while it is running.

## Project Structure

```text
CCAS.xcodeproj/                  Xcode project
Package.swift                    Swift Package manifest
Sources/CCASApp/                 App source code
Sources/CCASApp/Info.plist       App Info.plist template
Sources/CCASApp/Resources/       App and menu bar icons
scripts/build_app.sh             Standalone app build script
```

## Release Notes For Maintainers

- Use Xcode `General > Version` for `MARKETING_VERSION`.
- Use Xcode `General > Build` for `CURRENT_PROJECT_VERSION`.
- `Info.plist` references those build settings, so Xcode archives expand them automatically.
- The build script also reads those values from the Xcode project before packaging `dist/CCAS.app`.

## License

MIT
