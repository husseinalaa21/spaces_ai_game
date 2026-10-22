# Shared Spacechat account integration

Spacechat's website is the behavior reference: `client/src/pages/LoginPage.jsx`, `client/src/components/PinSetupPrompt.jsx`, `client/src/pages/SettingsPage.jsx`, `client/src/lib/accountDatabaseBackup.js`, and the corresponding native implementations in `ios/App/App/Features/Authentication/Login/LoginView.swift` and `Features/Settings/AccountView.swift`.

## Contract (before implementation)

- Phrase login: `POST /api/dna`, `{passphrase,databaseMode,native:true}`. Generate 12 words; accept existing 12–18-word phrases. Require `connected`, session and username. Parse `mes`, `error`, `message` on failure; do not commit a failed login.
- Provider login: `POST /api/auth/social/config` and `/api/auth/social/login`, `{provider,idToken,authorizationCode?,databaseMode,native:true,newPassphrase?}`. Verify with the server first; `needsAccount:true` requests a new generated phrase. Never derive an account locally from an Apple user identifier. A provider returning an existing account cannot reveal its original phrase; the server deliberately does not store it.
- Bootstrap: `POST /api/session/bootstrap`, authenticated with `x-spacechat-session`, returns identity, reference ID, profile, database mode, cloud access and optional full database. Preserve unrecognized response fields.
- Profile: `POST /api/profile/update`, `{name,description,avatarBackground,profileTheme,pictureDataUrl?,removeCustomPicture?}`; updates the shared account on both apps. `/api/username/set` changes public username with `{username}`. Require `ok:true` and display server errors and retry state.
- Storage: `POST /api/session/database-mode`, `{databaseMode:browser|prepaid|none}`. Adopt returned session token. Device-only and no-cloud modes must never report a successful cloud save. Cloud access is determined by the server, not assumed from a login method.
- First login on this device: recovery backup screen with reveal/hide, copy, download and Continue; acknowledge per account only after Continue. Phrase stays in Keychain, not ordinary preferences or cloud state.
- Settings: account/profile editor, recovery backup, storage choice, explicit sync/reload and portable database download/upload. Export includes the selected account's game state; phrase inclusion requires a deliberate user choice. Import validates account ownership before restoring.
- Account deletion: `POST /api/account/delete`, `{confirm:DELETE}`; only explicit confirmation can call it. Ordinary sign-out revokes the session and clears this device's credentials.

## Game cloud persistence

Existing `/api/user-db` replaces the whole Spacechat database; a game must not write a stale snapshot over messages/profile edits from another app. Add authenticated `POST /api/spaces/game-state` with a separate account-owned Mongo record in the same service, preserving the legacy `spacesDotsGame` read path. Reads return `{ok,profile,version,updatedAt}`; writes `{profile,expectedVersion}` require a matching revision and return 409 `GAME_SAVE_CONFLICT` otherwise. Require active server cloud access and cloud mode, bound payload size, and keep account deletion responsible for these records. No local fallback may masquerade as a durable cloud save.

All screens retain native loading, empty, offline, failure, retry and back states. Reuse the game's existing grouped settings and white theme. Provider sheets use the established Spacechat native OAuth flow. Live provider success requires configuring this app's distinct bundle/OAuth client IDs on the service; local fixtures cannot prove production provider configuration.

## Implemented and verified (2026-10-21)

Both native apps now gate a fresh login on a recovery-backup screen, acknowledged per account/device. A recovery flow explicitly shows the newly generated words again. Provider login to an existing account whose phrase is not on the device explains that the server cannot retrieve the original words; it never invents replacement credentials. Native Spacechat retains its existing optional PIN/Face ID and saved-account vault.

Space – Dots & AI now offers shared profile name/bio/photo/username editing, verified account email, Apple/Google link/unlink, recovery phrase exports, reference-ID recovery/support request, storage selection, game database download/upload, explicit cloud reload/save and shared account deletion. Import ownership recognizes both native Spacechat's nested account shape and web's flat shape, and uses the stable reference after phrase recovery. Profile changes use the existing service; no second account database is created for identity.

Game cloud records are bounded to 256 KB and keyed by the account's authenticated, stable reference ID. The service enforces cloud entitlement, a revision comparison and a per-account request limit. New devices never silently replace an existing cloud save; differing progress requires a choice in Settings. Device game files also use stable account scopes, including safe migration from the previous save. Cloud autosave is debounced in the foreground and retries do not overwrite conflicts. Logout clears credentials; confirmed deletion removes the cloud record and this app's local game, inbox and AI-chat cache for that account.

Spacechat login/bootstrap responses augment the shared database with the authoritative game section. Web canonicalization and native database merge/export retain it without altering messaging sections. The native app's approved four-Dot branding remains the default.

Validation:

- `Tests/run-account-checks.sh`: **32 passed** against fixture HTTP, in-memory credentials and temporary save directories. Covers first-login backup, provider signup, missing phrases, failed login, nested/native backups, account ownership, revision conflicts, local switching, delayed saves and missing deployment behavior.
- `Tests/run-messaging-checks.sh`: **31 passed**, no live messages.
- `Tests/run-agent-checks.sh`: **28 passed**.
- Shared service/web-data suites: **34 passed** across game-state, client game-state retention, social login, account deletion, account recovery and prepaid ownership.
- Native Spacechat `AccountIsolationTests`: **9 passed**, including real `SpacechatSession.login` first-login backup and native game-section merge/export. One existing fixture was narrowed to `/api/user-db` so startup health requests cannot overwrite its observed header.
- Both apps: Debug iOS simulator builds succeeded. Spacechat's native XCTest target also built and ran on an isolated iOS 27 simulator, removed after verification.
- Spacechat Vite build succeeded into `/tmp/spacechat-shared-account-web-validation`; existing large-chunk warnings remain. Source `client/dist` was not replaced.

No real accounts, provider credentials, recovery claims, support tickets, messages or production database writes were used for these checks. No production deployment or App Store release was performed.

## Release boundary and remaining parity

The reviewed backend changes must be released before `/api/spaces/game-state` and the app-specific provider config are live. `GOOGLE_SPACES_IOS_CLIENT_ID` must identify an OAuth iOS client registered for `com.husseinalaa.ai`; the app hides Google if the server does not advertise this app's config. The backend accepts this owned app's Apple audience when Apple sign-in is enabled, with `APPLE_SPACES_IOS_BUNDLE_ID` available as an explicit override. Apple Developer configuration/grouping and real provider login require live verification.

This change shares identity, recovery, public profile and game/account-data contracts. It does not combine the two app binaries or automatically merge two already-distinct accounts. The game's local folder bookmarks, agent workspaces/projects and its own premium entitlement remain app-specific; the full Spacechat saved-account PIN/Face ID vault is not ported to the game in this change. Device game saves remain available while cloud storage is off; the game's "No cloud storage" choice intentionally does not delete local gameplay progress.
