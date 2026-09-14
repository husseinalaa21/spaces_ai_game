import AVFoundation

/// Minimal sound/music wrapper (§52/§54). Sound effects are small synthesized
/// .wav files bundled in `Resources/Sounds`; `play(_:)` still silently no-ops
/// if a name isn't found, so nothing ever crashes if an asset is missing.
final class AudioManager {
    static let shared = AudioManager()
    var soundEnabled = true
    var musicEnabled = true

    private var players: [String: AVAudioPlayer] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var currentMusicName: String?

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
    func playLevelUp() { play("levelup") }
    func playAbility() { play("ability") }

    /// Starts a soft looping ambient track (currently just "ambient") if
    /// music is enabled and it isn't already the one playing. Safe to call
    /// every time a screen that wants music appears — it won't restart a
    /// track that's already going.
    func startMusic(_ name: String) {
        guard musicEnabled else { return }
        if currentMusicName == name, musicPlayer?.isPlaying == true { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0.55
        player.prepareToPlay()
        player.play()
        musicPlayer = player
        currentMusicName = name
    }

    func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentMusicName = nil
    }

    /// Called whenever the music setting itself changes — stop immediately
    /// when turned off, and pick back up wherever `wantsMusic` says it
    /// should be currently playing when turned back on.
    func setMusicEnabled(_ enabled: Bool, wantsMusic name: String?) {
        musicEnabled = enabled
        if !enabled {
            stopMusic()
        } else if let name {
            startMusic(name)
        }
    }
}
