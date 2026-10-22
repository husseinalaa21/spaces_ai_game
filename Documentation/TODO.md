# Space - Dots & AI work list

## Current engineering work

- [x] Research and validate the native app's agent, local search, file access, and scale behavior.
- [x] Implement ranked local research with source citations and bounded indexing.
- [x] Validate model actions and protect file changes across approval waits.
- [x] Run native checks, simulator build/launch, and a repeatable local retrieval benchmark.

## Requested logo update

- [x] Update the **Space - Dots & AI** app logo to show **four high-quality, modern-looking Dots wearing their uniforms**, in **one line**, **standing behind one another toward the right side**.
  - Preserve the app's established modern Dot character style, uniforms, and rendering quality.
  - Applied the user-approved professional v2 four-Dot artwork to the app icon and shared splash/sign-in logo. The previous icon is preserved in store-assets/space-dots-ai-icon-before-four-dots.png.
  - Added gentle floating motion to the approved logo on the opening and sign-in screens, with a static version for Reduce Motion and matching four-color loading dots.

## Shared Spacechat account update

- [x] Keep 12-word generation and compatibility with existing 12–18-word phrases.
- [x] Use server-verified Apple login and the configured Spaces Google client.
- [x] Add phrase/database upload and reference-ID/support recovery options.
- [x] Show recovery backup after first login, with reveal/copy/download/Continue, in both native apps.
- [x] Add shared profile/photo/username/email settings and provider connection controls.
- [x] Add account-scoped device game saves, revisioned cloud saves, and explicit device/cloud conflict choice.
- [x] Preserve game data in Spacechat web/native database snapshots and exports.
- [x] Test authentication, backup ownership, deletion, messages, native account isolation, and both iOS builds.
- [ ] Release the reviewed shared backend changes and configure the Spaces Google iOS OAuth client before validating live provider/cloud flows.

See `Shared-account-contract.md` for scope, API contracts and validation evidence.

## Dmap movement correction

- [x] Share consistent camera movement across the Dmap, team map, and project universe.
- [x] Correct release drift, interrupted drag/pinch state, zoom focus, and background grid scaling.
- [x] Prevent map drags from activating moving map buttons.
- [x] Add repeatable camera regression checks and a simulator UI gesture runner.

See `Dmap-movement-validation.md` for checks and simulator results.

## Version 4 login polish

- [x] Match Spacechat's login button hierarchy, capsule sizing, gradient and provider branding.
- [x] Match phrase/recovery option cards and support wrapping at larger text sizes.
- [x] Set version 4.0, build 4 in the project and project generator.
