# Spaces — Eat. Change. Evolve.

A minimalist iOS game: you are always a dot. Explore a huge white space, eat
icon-based collectibles, transform gradually toward whatever you eat most,
complete forms, and unlock abilities. Built from `AI_Game_Master_Build_Prompt.md`
(the full design spec, also saved in this project's Claude project docs).

This build covers **Phase 1–2** of the spec's development plan (§88): a
complete, playable, *offline* White Space core loop. Dark Space (competitive
multiplayer), real-time chat, and the AI+ premium store are architected for
but not built yet — they need a live backend, which is out of scope for a
locally-generated project. See "What's next" below.

## What's actually playable right now

- **Launch flow**: a splash screen redrawing the Vision 1 logo's dot cluster
  (same layout/colors as `assets/logo.png`, minus the grid) with each dot
  jittering independently on its own timing, "Powered by Spacechat" pinned
  at the bottom, then either straight into the game (if already signed in)
  or a "Spaces" screen with small dots up top and a plain white
  **Continue** button — a temporary stand-in for a real Sign in with Apple
  button so the app is fully testable without a paid Apple Developer account
  yet; the "Sign in with Apple" capability is still wired up at the project
  level (`AI.entitlements`) for whenever that button comes back — see "Sign
  in with Apple setup" below.
- **Main menu**: after signing in you land on a menu with a few small
  animated preview cards (the blue dot's squash-and-stretch body + eyes,
  self-animating) and a single **Play** button — White Space itself only
  starts once you tap it.
- **A White Space round is timed**: 15 minutes per session (countdown badge
  at the bottom; assumed 15 *minutes* — easy to change to seconds if that's
  not what was meant, see `GameEngine.roundDuration`), a minimap (top-right)
  showing your position and nearby collectibles against the whole world, and
  a quit button (top-left) back to the main menu. Time running out shows a
  brief "TIME'S UP" banner and returns you to the menu automatically.
- A window-pane grid background (the same light gray lines as the app's dot
  logo, plus a faint finer subdivision for texture) fills White Space,
  anchored to world space so it scrolls with you instead of sitting fixed on
  screen, with a soft pulsing aura around your dot tinted toward whatever
  you're becoming.
- A dot (you), in a huge white world, moved by dragging anywhere on screen —
  it squashes and stretches toward your direction of travel instead of
  sliding as a rigid circle, and has two simple eyes that blink and glance
  around (toward your heading while moving, a slow up/down glance while
  idle).
- Eating something plays a brief "liquid" travel effect — a droplet of the
  collectible's color flows from where it was eaten into your dot, with a
  soft burst on arrival — instead of the collectible just vanishing.
- ~30 emoji-based collectibles across 8 categories (food, nature, body, tech,
  space, emotion, animal, objects), each with its own rarity and color.
- Eating something raises that form's completion % (visible in the top-left
  HUD); your dot's color gradually blends toward whatever you're actively
  pursuing.
- Reaching 100% unlocks the form permanently, plays a short completion
  animation + haptic, and (for forms that have one) unlocks an active ability
  usable from the bottom-right button once equipped. 10 of the 12 abilities
  have a real local effect (speed bursts, a bigger reach, an instant nearby
  burst-eat, slowing the round clock, pulling collectibles in); Scan and
  Eagle Eye are still visual-only stubs — see `GameEngine.triggerAbility` —
  since their natural payoff (revealing other players/threats) needs the
  multiplayer Dark Space this build doesn't have yet.
- A Collection screen (grid icon, bottom-left) shows every form, filterable
  by category, with progress/rarity/ability.
- Intelligence points and levels accrue from discovering new icons and
  completing forms.
- A simple local "Signal" event occasionally appears with a bonus rare spawn.
- A handful of ambient wandering dots make the world feel a little less
  empty (local-only stand-ins for other players, per §23).
- Settings screen (sound/music/haptics/reduce motion toggles).
- Progress saves to a local JSON file automatically and reloads on relaunch.
- First-launch onboarding follows the exact beats from §61 ("This is
  you." → "Move." → "Eat it." → "Everything you eat changes you.").

The player is rendered as a plain circle with a soft top-right highlight —
same visual language as the app icon and the project's dot logo — and never
becomes a character, ship, or creature, per the spec's core rule (§82).

## Project layout

```
Sources/AI/
  App/           AIApp.swift (entry point), RootView.swift (splash → sign-in → onboarding/game)
  Auth/          AuthState.swift (local Sign in with Apple state — see below)
  Models/        Collectible.swift, CollectibleCatalog.swift (data-driven ~30 items),
                 WorldEntities.swift (spawned collectibles, ambient dots, signals)
  State/         PlayerState.swift (live @Published state + the saved PlayerProfile)
  Engine/        TransformationEngine.swift (absorb → progress → completion, pure logic),
                 GameEngine.swift (movement, spawning, collisions, abilities — the sim loop)
  Persistence/   SaveManager.swift (local JSON save/load; swap for a backend later)
  Views/         SplashView, SignInView, MainMenuView (Play + preview cards),
                 WhiteSpaceView (the game screen/canvas),
                 WorldBackground (shared grid renderer, White/Dark Space palettes),
                 CollectionView, SettingsView, OnboardingView, DotRenderer (shared dot style)
  Utilities/     HapticsManager, AudioManager (plays the bundled sound effects below)
  Resources/     Assets.xcassets (AppIcon — single dot per §110 — AccentColor, and
                 Logo — the real Vision 2 logo, used by SplashView), Sounds/
                 (small synthesized .wav files: eat, rare eat, form complete,
                 level up, ability, plus a soft looping ambient.wav that plays
                 while White Space is open)
AI.entitlements  Sign in with Apple capability (repo root, referenced by project.yml)
```

This mirrors the module list in §89 of the spec. `WorldEngine`/`WhiteSpaceWorld`
duties live in `GameEngine` for now since there's only one world; splitting it
apart is straightforward once `DarkSpaceWorld` needs to exist alongside it.

## Opening this in Xcode

The generated `AI.xcodeproj`, shared `AI` scheme, and `Sources/AI/Info.plist`
are committed so Xcode Cloud can build a clean checkout without installing
XcodeGen. Open `AI.xcodeproj` in Xcode. If you change `project.yml`, regenerate
and commit the resulting project and plist as well:

```bash
xcodegen generate
open AI.xcodeproj
```

Then in Xcode: pick an iPhone simulator (this is configured iPhone-only,
portrait, per your request) and hit Run. No signing/account setup is needed
to run in the Simulator; running on a physical device will ask you to select
your own Apple ID team under Signing & Capabilities.

If you'd rather not install XcodeGen, you can instead create a new Xcode
project yourself (iOS App → SwiftUI → Swift) and drag the `Sources/AI`
folder's contents into it, making sure "Copy items if needed" is checked and
the `Assets.xcassets` you drag in replaces the default one.

## Sign in with Apple setup

The sign-in screen currently shows a plain **Continue** button
(`AuthState.completeTestSignIn()`) instead of Apple's real
`SignInWithAppleButton`, so the whole app is testable without a paid Apple
Developer account. The "Sign in with Apple" capability is still wired up at
the project level — `AI.entitlements` plus `CODE_SIGN_ENTITLEMENTS` in
`project.yml`, so `xcodegen generate` sets it up automatically — ready for
whenever `SignInView` swaps back to the real button. A few things worth
knowing about that real button, for when it's back:

- **In the Simulator**: this just works with automatic signing, as long as
  Xcode is signed in with your own Apple ID (Xcode → Settings → Accounts).
  No paid developer account needed for Simulator testing.
- **On a physical device**: you'll need your bundle identifier
  (`com.husseinalaa.ai`, or whatever you change it to in `project.yml`)
  registered with the "Sign in with Apple" capability enabled in your Apple
  Developer account, and Xcode's automatic signing will otherwise handle
  provisioning.
- There's no backend yet to verify the Apple credential against, so
  `AuthState` just remembers the Apple user identifier locally (in
  UserDefaults) so a returning player skips straight past this screen. This
  is a clearly-marked placeholder for a real backend-verified session later.

## What's next (not built yet, but designed for)

Following the phase order in §88:

- **Phase 3 — Multiplayer foundation**: replace the local `ambientWanderers`
  with real synced players over a backend (server-authoritative position,
  per §58), plus real chat-above-dots (§24).
- **Phase 4 — Dark Space**: the black competitive map, neutral growth dots,
  size-based PvP, respawn, leaderboard (§18–21).
- **Phase 5 — Premium**: AI+ membership via StoreKit, premium dot
  materials/rings/trails, entitlement checks, Restore Purchases (§27–40).
- **Phase 6 — Polish**: audio is done (effects + a looping ambient track, see
  "Project layout" above) — what's left here is App Store screenshots/
  metadata and moderation tooling for chat.

## Design source of truth

`AI_Game_Master_Build_Prompt.md` is the full spec this build follows and is
saved in this Claude project's docs — check it before extending any system
(rarity tiers, ability list, monetization rules, etc. are all defined there).

## Xcode Cloud

Use the shared **AI** scheme and **Release** Archive configuration. In the AI
target's Signing & Capabilities pane, enable automatic signing and select
your enrolled Apple Developer team. Keep `DEVELOPMENT_TEAM` in `project.yml`
in sync if you regenerate the project. The bundle ID is `com.husseinalaa.ai`;
it must match the App Store Connect app record.

Connect this GitHub repository when creating the first Xcode Cloud workflow.
Choose an iOS Archive action with **App Store Connect** distribution. The
project has no XCTest target, so do not add a Test action until one exists.
Test the processed build in TestFlight, then select it on the App Store
version page and complete the metadata before submitting for review.

Versions come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
Xcode Cloud manages its build numbers; for manual uploads, increment the
build number before archiving another build of the same version.
