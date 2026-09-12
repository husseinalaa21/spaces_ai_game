import SwiftUI

/// AI — Eat. Change. Evolve.
///
/// Entry point. See `AI_Game_Master_Build_Prompt.md` (in the repo/project
/// root) for the full design spec this build follows. This build covers
/// Phase 1–2 from §88: a fully playable, offline White Space core loop —
/// movement, collectible icons, gradual transformation, form completion,
/// Collection screen, Intelligence progression, one local Signal event, and
/// settings. Dark Space, real-time multiplayer, chat, and the premium store
/// are architected for (see the module layout in §89 and the stub notes in
/// each file) but intentionally not built yet — they need a backend this
/// environment can't stand up.
@main
struct AIApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
