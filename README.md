# AI — Eat. Change. Evolve.

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

- A dot (you), in a huge white world, moved by dragging anywhere on screen.
- ~30 emoji-based collectibles across 8 categories (food, nature, body, tech,
  space, emotion, animal, objects), each with its own rarity and color.
- Eating something raises that form's completion % (visible in the top-left
  HUD); your dot's color gradually blends toward whatever you're actively
  pursuing.
- Reaching 100% unlocks the form permanently, plays a short completion
  animation + haptic, and (for forms that have one) unlocks an active ability
  usable from the bottom-right button once equipped.
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
  App/           AIApp.swift (entry point), RootView.swift (onboarding ↔ game)
  Models/        Collectible.swift, CollectibleCatalog.swift (data-driven ~30 items),
                 WorldEntities.swift (spawned collectibles, ambient dots, signals)
  State/         PlayerState.swift (live @Published state + the saved PlayerProfile)
  Engine/        TransformationEngine.swift (absorb → progress → completion, pure logic),
                 GameEngine.swift (movement, spawning, collisions, abilities — the sim loop)
  Persistence/   SaveManager.swift (local JSON save/load; swap for a backend later)
  Views/         WhiteSpaceView (the game screen/canvas), CollectionView, SettingsView,
                 OnboardingView, DotRenderer (shared dot-drawing style)
  Utilities/     HapticsManager, AudioManager (silent no-op until real audio files are added)
  Resources/     Assets.xcassets (AppIcon — single dot per §110 — and AccentColor)
```

This mirrors the module list in §89 of the spec. `WorldEngine`/`WhiteSpaceWorld`
duties live in `GameEngine` for now since there's only one world; splitting it
apart is straightforward once `DarkSpaceWorld` needs to exist alongside it.

## Opening this in Xcode

This repo doesn't include a `.xcodeproj` — it's generated from `project.yml`
with [XcodeGen](https://github.com/yonaskolb/XcodeGen), which keeps the
project file out of source control and merge-conflict-free. One-time setup
on your Mac:

```bash
brew install xcodegen
cd spacesaigame          # this folder
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

## What's next (not built yet, but designed for)

Following the phase order in §88:

- **Phase 3 — Multiplayer foundation**: replace the local `ambientWanderers`
  with real synced players over a backend (server-authoritative position,
  per §58), plus real chat-above-dots (§24).
- **Phase 4 — Dark Space**: the black competitive map, neutral growth dots,
  size-based PvP, respawn, leaderboard (§18–21).
- **Phase 5 — Premium**: AI+ membership via StoreKit, premium dot
  materials/rings/trails, entitlement checks, Restore Purchases (§27–40).
- **Phase 6 — Polish**: real audio assets (the `AudioManager` hooks are
  already in place and just need `.caf`/`.wav` files added to the bundle),
  App Store screenshots/metadata, moderation tooling for chat.

## Design source of truth

`AI_Game_Master_Build_Prompt.md` is the full spec this build follows and is
saved in this Claude project's docs — check it before extending any system
(rarity tiers, ability list, monetization rules, etc. are all defined there).
