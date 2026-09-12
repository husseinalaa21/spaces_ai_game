import AVFoundation

/// Minimal sound/music wrapper (§52/§54). Ships silent by default since no
/// audio assets are bundled yet — wire real files into `Resources` and this
/// becomes a drop-in player. Kept deliberately small: a soft pop on eat, a
/// distinct tone on rare pickups, a pulse on form completion.
final class AudioManager {
    static let shared = AudioManager()
    var soundEnabled = true
    var musicEnabled = true

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    /// Looks for "<name>.caf" or "<name>.wav" in the main bundle; silently
    /// no-ops if the asset isn't there yet so the game never crashes on sound.
    func play(_ name: String) {
        guard soundEnabled else { return }
        if let cached = players[name] {
            cached.currentTime = 0
            cached.play()
            return
        }
        let candidates = ["caf", "wav", "mp3"]
        for ext in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let player = try? AVAudioPlayer(contentsOf: url) {
                players[name] = player
                player.play()
                return
            }
        }
        // No asset bundled yet — intentionally silent.
    }

    func playEat() { play("pop") }
    func playRareEat() { play("chime") }
    func playFormComplete() { play("complete") }
}
