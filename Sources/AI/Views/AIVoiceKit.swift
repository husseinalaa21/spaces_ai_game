import SwiftUI
import AVFoundation
import Speech

// Voice chat for the AI page. Ported from Spacechat's own voice mode
// (ios/App/App/Components/NativeAIVoiceKit.swift) so the two behave the same:
// the same orb, the same turn-taking, the same server voices
// (POST /api/ai/voice/speak) with the device voice only as an offline fallback.


enum AIVoicePhase {
    case thinking
    case listening
    case speaking
}

enum AIVoiceText {
    // Strip anything a TTS voice would read awkwardly (markdown, links, code).
    static func spoken(_ value: String) -> String {
        var text = value
        let patterns: [(String, String)] = [
            ("```[\\s\\S]*?```", " "),
            ("`([^`]*)`", "$1"),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("https?://\\S+", " "),
            ("[*_#>~|]+", " "),
            ("(?m)^\\s*[-•]\\s+", ""),
            // Acronyms spelled the way they should sound (same list as the server's
            // pronounceable()) so the device voice does not read "AI" as a word.
            ("\\bChatGPT\\b", "Chat Gee Pee Tee"),
            ("\\bGPT\\b", "Gee Pee Tee"),
            ("\\bA\\.I\\.?(?=\\W|$)", "Ay Eye"),
            ("\\bAIs?\\b", "Ay Eye"),
            ("\\bLLMs?\\b", "El El Em"),
            ("\\bAPIs?\\b", "Ay Pee Eye"),
            ("\\bVIP\\b", "Vee Eye Pee"),
            ("\\s+", " ")
        ]
        for (pattern, template) in patterns {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Two pieces at most: a short opening (sound starts after one quick
    // synthesis) and the rest in one go. The server splits each piece into
    // phrases and joins them, so fewer, longer pieces keep the voice connected.
    static func chunks(_ text: String, firstMax: Int = 150, maxTotal: Int = 1100) -> [String] {
        let clean = String(text.prefix(maxTotal))
        var sentences: [String] = []
        clean.enumerateSubstrings(in: clean.startIndex..<clean.endIndex, options: .bySentences) { sub, _, _, _ in
            if let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(sub) }
        }
        if sentences.isEmpty { sentences = [clean] }
        var first = ""
        var index = 0
        while index < sentences.count {
            let next = sentences[index]
            if !first.isEmpty && (first + next).count > firstMax { break }
            first += next
            index += 1
            if first.count >= 60 { break }
        }
        let rest = sentences[index...].joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return [first.trimmingCharacters(in: .whitespacesAndNewlines), rest].filter { !$0.isEmpty }
    }
}

// MARK: - Environment backdrop

// The scene's environment as a full-screen backdrop: colors come from the
// server's shared scene for this agent (same for everyone hearing it), with two
// soft glows drifting slowly. Mirrors .ai_voice_backdrop in client styles.css.
struct AIVoiceBackdropView: View {
    let background: [String]
    let glow: String
    /// false = plain still backdrop (the main Spacechat AI): no drifting glows.
    var animated: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = background.count == 3 ? background : ["#0b1b33", "#12082b", "#050505"]
        // White appearance: a white sky with only a faint wash of the agent's colour.
        let isLight = colorScheme == .light
        let skyColors: [Color] = isLight
            ? [.white, Color.voiceTint(glow, 0.93), Color.voiceTint(glow, 0.84)]
            : [Color(voiceHex: colors[0]), Color(voiceHex: colors[1]), Color(voiceHex: colors[2])]
        // A plain still backdrop (the main Spacechat AI) has nothing to animate, so
        // the timeline is paused instead of redrawing every frame.
        TimelineView(.animation(paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RadialGradient(
                    colors: skyColors,
                    center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 560
                )
                if animated {
                GeometryReader { geo in
                    let size = max(geo.size.width, geo.size.height) * 1.1
                    Circle()
                        .fill(RadialGradient(colors: [Color(voiceHex: glow).opacity(isLight ? 0.12 : 0.18), .clear], center: .center, startRadius: 0, endRadius: size / 2))
                        .frame(width: size, height: size)
                        .offset(x: -size * 0.35 + CGFloat(sin(t / 9)) * size * 0.12, y: -size * 0.3 + CGFloat(cos(t / 11)) * size * 0.1)
                    Circle()
                        .fill(RadialGradient(colors: [Color(voiceHex: glow).opacity(isLight ? 0.08 : 0.12), .clear], center: .center, startRadius: 0, endRadius: size / 2))
                        .frame(width: size, height: size)
                        .offset(x: geo.size.width - size * 0.65 + CGFloat(cos(t / 12)) * size * 0.1, y: geo.size.height - size * 0.6 + CGFloat(sin(t / 10)) * size * 0.1)
                }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Orb

private final class AIVoiceOrbAnimator {
    var energy: Double = 0
    /// How loudly the person is speaking right now (0...1), smoothed.
    var hearing: Double = 0
    /// 0...1: how far the circle has slowly shrunk while it hears the person.
    var shrink: Double = 0
    /// The shake only advances while the person speaks, at a pace set by their voice,
    /// so the circle is still when they are quiet.
    var shakePhase: Double = 0
    var lastT: Double = 0
    /// The waves only move while the AI speaks: this clock stands still otherwise.
    var waveClock: Double = 0
    var waveSpeed: Double = 0
    /// When the person's current stretch of talking began, and when we last heard them.
    var talkStart: Double?
    var lastTalk: Double = -10
    var palette: [[Double]] = []
    let start = Date()
}

struct AIVoiceOrbView: View {
    let paletteHex: [String]
    let phase: AIVoicePhase
    let level: () -> Double
    /// True while the person is actually talking to the AI (their words are being
    /// recognised), not just while the microphone hears something.
    var userTalking: () -> Bool = { false }

    @State private var animator = AIVoiceOrbAnimator()

    private static func rgb(_ hex: String) -> [Double] {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt32(value.prefix(6), radix: 16) ?? 0
        return [Double((number >> 16) & 255), Double((number >> 8) & 255), Double(number & 255)]
    }

    private static func color(_ rgb: [Double], _ alpha: Double) -> Color {
        Color(.sRGB, red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, opacity: max(0, min(1, alpha)))
    }

    private static func mix(_ a: [Double], _ b: [Double], _ amount: Double) -> [Double] {
        (0..<3).map { a[$0] + (b[$0] - a[$0]) * amount }
    }

    private static let waveLayers = 9

    // Rotates the hue of an rgb colour (degrees) so the waves use several related colours.
    private static func shiftHue(_ rgb: [Double], _ degrees: Double, lift: Double = 0) -> [Double] {
        let r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        var h = 0.0
        var sat = 0.0
        if maxV != minV {
            let d = maxV - minV
            sat = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if maxV == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        h = (h + degrees / 360 + 1).truncatingRemainder(dividingBy: 1)
        sat = min(1, sat * 1.1 + 0.1)
        let light = min(0.85, max(0.2, l + lift))
        let q = light < 0.5 ? light * (1 + sat) : light + sat - light * sat
        let p = 2 * light - q
        func hue(_ t: Double) -> Double {
            let x = (t + 1).truncatingRemainder(dividingBy: 1)
            if x < 1.0 / 6 { return p + (q - p) * 6 * x }
            if x < 1.0 / 2 { return q }
            if x < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - x) * 6 }
            return p
        }
        return [hue(h + 1.0 / 3) * 255, hue(h) * 255, hue(h - 1.0 / 3) * 255]
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(&context, size: size, t: timeline.date.timeIntervalSince(animator.start))
            }
        }
        .accessibilityHidden(true)
    }

    // One crisp-edged circle filled like a glass of water: the agent's colour at the top
    // and layered, colourful gradient waves below that rise and swell with the voice.
    // The wave edges are soft, not sharp. The circle itself only moves in answer to the
    // person talking: it slowly gets smaller and shakes left and right with their voice,
    // and is still when they are quiet. Mirrors client/src/components/AiVoiceOrb.jsx.
    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let dimension = min(size.width, size.height)
        let cx = size.width / 2
        let cy = size.height / 2

        let target = (paletteHex.count == 3 ? paletteHex : ["#8fd8ff", "#3a7bff", "#7a5cff"]).map(Self.rgb)
        if animator.palette.count != 3 { animator.palette = target }
        animator.palette = (0..<3).map { Self.mix(animator.palette[$0], target[$0], 0.06) }
        let pal = animator.palette

        let measured = level()
        let dt = min(0.1, max(0, t - animator.lastT)); animator.lastT = t

        // The smoke of waves rises with the AI's voice and rests when it is not talking.
        var goal = 0.06
        switch phase {
        case .speaking:
            goal = measured > 0.01 ? min(1, measured * 1.5) : 0.28 + 0.14 * sin(t * 5.3) * sin(t * 2.1)
        case .listening: goal = 0.06
        case .thinking: goal = 0.08
        }
        goal = min(1, max(0, goal))
        animator.energy += (goal - animator.energy) * (goal > animator.energy ? 0.22 : 0.06)
        let energy = animator.energy
        // The waves' own clock: it runs while the AI speaks and eases to a stop after.
        animator.waveSpeed += ((phase == .speaking ? 1.0 : 0.0) - animator.waveSpeed) * 0.05
        animator.waveClock += dt * animator.waveSpeed * (1.0 + energy * 2.4)
        let waveT = animator.waveClock

        // The person talking: real speech only (their words are being recognised), not
        // background sound. A stretch of talking longer than 40 s lets the circle go back
        // to full size until they pause and start again.
        let rawTalking = phase == .listening && userTalking() && measured > 0.08
        if rawTalking {
            if animator.talkStart == nil { animator.talkStart = t }
            animator.lastTalk = t
        } else if t - animator.lastTalk > 1.2 {
            animator.talkStart = nil
        }
        let talking = rawTalking && (t - (animator.talkStart ?? t)) < 40
        let heard = talking ? min(1, 0.35 + measured) : 0
        animator.hearing += (heard - animator.hearing) * (heard > animator.hearing ? 0.07 : 0.06)
        let hearing = animator.hearing
        // Slowly smaller while they talk; back to the normal size once they stop.
        let wantsShrink: Double = talking ? 1 : 0
        animator.shrink += (wantsShrink - animator.shrink) * (wantsShrink > animator.shrink ? 0.008 : 0.05)
        // A gentle sway, only while they talk.
        animator.shakePhase += dt * (2.4 + 2.6 * hearing)
        let shake = (sin(animator.shakePhase) * 0.7 + sin(animator.shakePhase * 1.6 + 1) * 0.3) * hearing

        let r = dimension * 0.46
        let scale = 1 - 0.2 * animator.shrink
        let offset = shake * r * 0.028
        let white: [Double] = [255, 255, 255]
        let body = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

        // The circle moves only with the person's voice (smaller, side to side).
        ctx.translateBy(x: cx + offset, y: cy)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -cx, y: -cy)
        // A crisp circular edge: everything is clipped to the circle, no feathering.
        ctx.clip(to: Path(ellipseIn: body))

        // Sky: deep colour at the top, agent colour in the middle, pale mist below.
        let sky = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: Self.color(Self.mix(pal[2], pal[1], 0.45), 1), location: 0),
                .init(color: Self.color(pal[1], 1), location: 0.45),
                .init(color: Self.color(Self.mix(pal[0], white, 0.8), 1), location: 1)
            ]),
            startPoint: CGPoint(x: cx, y: cy - r), endPoint: CGPoint(x: cx, y: cy + r)
        )
        ctx.fill(Path(body), with: sky)

        // Wave colours: the agent's own tones plus hue-shifted neighbours.
        let waveColors: [[Double]] = [
            Self.mix(white, pal[0], 0.3),
            Self.shiftHue(pal[1], 38, lift: 0.14),
            Self.shiftHue(pal[0], -42, lift: 0.06),
            Self.shiftHue(pal[2], 60, lift: 0.2),
            Self.mix(white, Self.shiftHue(pal[1], -20), 0.35),
            Self.shiftHue(pal[0], 95, lift: 0.12),
            Self.shiftHue(pal[1], -70, lift: 0.1),
            Self.mix(white, Self.shiftHue(pal[2], -35), 0.3),
            Self.shiftHue(pal[0], 150, lift: 0.16)
        ]
        let wt = waveT

        // One stack of travelling waves. dir = 1 fills downward from the wave line
        // (bottom waves), -1 is the mirror image (top waves). Each layer is a smooth
        // vertical gradient: strongest at the crest, fading underneath.
        func drawWaves(_ layerCtx: inout GraphicsContext, dir: Double, lineOffset: Double, power: Double, phaseShift: Double, tilt: Double) {
            layerCtx.translateBy(x: cx, y: cy)
            if dir < 0 { layerCtx.scaleBy(x: 1, y: -1) }
            layerCtx.rotate(by: .radians(tilt * dir))
            layerCtx.translateBy(x: -cx, y: -cy)
            // Soft wave edges instead of sharp ones.
            layerCtx.addFilter(.blur(radius: r * 0.035))
            let line = cy + lineOffset
            for w in 0..<Self.waveLayers {
                let fw = Double(w)
                let wdir: Double = w % 2 == 0 ? 1 : -1
                let amp = r * (0.045 + power * 0.2) * (0.85 + Double(w % 4) * 0.16)
                // Each layer drifts up and down at its own pace, so the waves keep changing
                // their positions instead of sitting in fixed bands.
                let drift = sin(waveT * (0.32 + 0.09 * fw) + fw * 1.9 + phaseShift) * r * (0.06 + power * 0.07)
                let base = line + r * (0.11 * fw - 0.2) + drift
                let k1 = (1.9 + Double(w % 5) * 0.55) / r
                let speed = 1.1 + fw * 0.32
                var outline = Path()
                outline.move(to: CGPoint(x: cx - r * 1.5, y: cy + r * 3))
                var x = -r * 1.5
                while x <= r * 1.5 {
                    let y = base
                        + sin(x * k1 + (wt + phaseShift) * speed * wdir + fw * 2.1) * amp
                        + sin(x * k1 * 2.1 - (wt + phaseShift) * speed * 0.8 + fw) * amp * 0.45
                    outline.addLine(to: CGPoint(x: cx + x, y: y))
                    x += 4
                }
                outline.addLine(to: CGPoint(x: cx + r * 1.5, y: cy + r * 3))
                outline.closeSubpath()
                let front = (fw + 1) / Double(Self.waveLayers)
                let crestAlpha = 0.2 + front * 0.26
                let c1 = waveColors[w % waveColors.count]
                let c2 = waveColors[(w + 1) % waveColors.count]
                let gradient = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: [
                        .init(color: Self.color(c1, crestAlpha), location: 0),
                        .init(color: Self.color(c1, crestAlpha * 0.7), location: 0.25),
                        .init(color: Self.color(waveColors[(w + 2) % waveColors.count], crestAlpha * 0.3), location: 0.6),
                        .init(color: Self.color(c2, 0.04), location: 1)
                    ]),
                    startPoint: CGPoint(x: cx, y: base - amp), endPoint: CGPoint(x: cx, y: base + r * 1.5)
                )
                layerCtx.fill(outline, with: gradient)
            }
        }

        // Waves rise and swell with the voice (the AI's, or the user's mic level).
        ctx.drawLayer { layer in
            drawWaves(&layer, dir: 1, lineOffset: r * (0.32 - energy * 0.5), power: energy, phaseShift: 0, tilt: sin(waveT * 0.9 + energy) * (0.05 + energy * 0.14))
        }
    }
}

// MARK: - Ambience

// Small seeded PRNG (mulberry32) — identical to the web client's
// seededRandom(), so both apps derive the same event timeline from the scene's
// server-provided seed and everyone in the scene hears the same room.
struct AIVoiceSeededRandom {
    private var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 1 : seed }
    mutating func next() -> Double {
        state = state &+ 0x6d2b79f5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

// Soft synthesized background for a shared scene: filtered brown noise that
// "breathes", a quiet human-like murmur (formant-filtered breath + faint
// pitched buzz pulsing at syllable rate, two voices) and a few scene textures
// placed on the shared scene timeline. Mirrors client/src/lib/aiVoiceAmbience.js.
final class AIVoiceAmbience {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let state = RenderState()
    private var scheduled: [DispatchWorkItem] = []

    // Chamberlin state-variable band-pass, normalised to unity peak gain.
    private final class Formant {
        var low: Float = 0
        var band: Float = 0
        let coefficient: Float
        let damping: Float
        let base: Float
        var wobblePhase: Float = 0
        let wobbleStep: Float
        init(hz: Float, q: Float, base: Float, wobbleHz: Float, sampleRate: Float) {
            coefficient = 2 * sin(Float.pi * hz / sampleRate)
            damping = 1 / q
            self.base = base
            wobbleStep = 2 * Float.pi * wobbleHz / sampleRate
        }
        @inline(__always) func process(_ x: Float) -> Float {
            low += coefficient * band
            let high = x - low - damping * band
            band += coefficient * high
            wobblePhase += wobbleStep
            if wobblePhase > 2 * Float.pi { wobblePhase -= 2 * Float.pi }
            return band * damping * base * (1 + 0.9 * sin(wobblePhase))
        }
    }

    private final class MurmurVoice {
        let formants: [Formant]
        let gain: Float
        var buzzPhase: Float = 0
        let buzzStep: Float
        init(pitch: Float, gain: Float, wobbleRates: [Float], sampleRate: Float) {
            let scale = 0.85 + (pitch / 260) * 0.5
            let table: [(Float, Float)] = [(500, 6), (1500, 7), (2500, 8)]
            formants = table.enumerated().map { index, entry in
                Formant(hz: entry.0 * scale, q: entry.1, base: 0.5 - Float(index) * 0.1, wobbleHz: wobbleRates[index], sampleRate: sampleRate)
            }
            self.gain = gain
            buzzStep = pitch / sampleRate
        }
    }

    private final class RenderState {
        var gain: Float = 0
        var targetGain: Float = 0
        var brown: Float = 0
        var lowpassed: Float = 0
        var lowpassCoefficient: Float = 0.02
        var lfoPhase: Float = 0
        var lfoStep: Float = 0
        var dronePhase: Float = 0
        var droneLevel: Float = 0
        var murmur: [MurmurVoice] = []
        var murmurGain: Float = 0
        var eventKind = 0            // 0 none, 1 bell, 2 burst
        var eventEnvelope: Float = 0
        var eventDecay: Float = 0.9999
        var eventFrequency: Float = 880
        var eventPhase: Float = 0
        var burstFiltered: Float = 0
        var eventGain: Float = 0.2
        var sampleRate: Float = 44100
    }

    private(set) var baseLevel: Float = 0.05
    private var ducked = false

    func start(scenario: SpacechatAgentVoiceScenario, clockOffsetMs: Double) {
        stop()
        // 'none' = a plain, silent scene (the main Spacechat AI): no background sound.
        if scenario.ambienceKind == "none" { return }
        let sampleRate: Double = 44100
        let kind = scenario.ambienceKind
        let cutoff = Float(max(120, min(1200, scenario.ambienceCutoff)))
        state.sampleRate = Float(sampleRate)
        state.lowpassCoefficient = 1 - exp(-2 * Float.pi * cutoff / Float(sampleRate))
        state.lfoStep = 2 * Float.pi * (kind == "road" ? 0.12 : 0.09) / Float(sampleRate)
        state.droneLevel = (kind == "hum" ? 0.07 : (kind == "projector" ? 0.05 : 0))
        state.gain = 0
        baseLevel = Float(max(0.1, min(1, scenario.ambienceLevel))) * 0.1
        state.targetGain = baseLevel
        ducked = false

        var random = AIVoiceSeededRandom(seed: scenario.ambienceSeed)
        let murmurLevel = Float(max(0, min(1, scenario.ambienceMurmurLevel)))
        let murmurPitch = Float(max(90, min(260, scenario.ambienceMurmurPitch)))
        state.murmur = []
        state.murmurGain = murmurLevel * 0.55
        if murmurLevel > 0 {
            for (voiceIndex, factor) in ([1.0, 1.27] as [Float]).enumerated() {
                let rates = (0..<3).map { _ in Float(3 + random.next() * 3) }
                state.murmur.append(MurmurVoice(pitch: murmurPitch * factor, gain: voiceIndex == 0 ? 1 : 0.7, wobbleRates: rates, sampleRate: Float(sampleRate)))
            }
        }

        // Scene textures on the shared timeline.
        let spec: (kind: Int, gap: (Double, Double), gain: Float, decay: Double)?
        switch kind {
        case "chime": spec = (1, (7000, 13000), 0.16, 2.6)
        case "paper": spec = (2, (5000, 10000), 0.35, 0.28)
        case "camera": spec = (2, (8000, 15000), 0.45, 0.05)
        case "desk": spec = (2, (2500, 6000), 0.3, 0.03)
        case "metronome": spec = (2, (3800, 4200), 0.25, 0.04)
        default: spec = nil
        }
        state.eventKind = spec?.kind ?? 0
        state.eventGain = spec?.gain ?? 0
        if let spec {
            state.eventDecay = Float(exp(log(0.001) / (spec.decay * sampleRate)))
            let sceneMs = 5.0 * 60 * 1000
            var offset = 0.0
            let nowMs = Date().timeIntervalSince1970 * 1000 + clockOffsetMs
            while offset < sceneMs {
                offset += spec.gap.0 + random.next() * (spec.gap.1 - spec.gap.0)
                let roll = random.next()
                let delayMs = scenario.generatedAt + offset - nowMs
                guard delayMs > 200 else { continue }
                let work = DispatchWorkItem { [weak self] in self?.trigger(roll: roll, doubleClick: kind == "camera") }
                scheduled.append(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + delayMs / 1000, execute: work)
            }
        }

        let render = state
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let white = Float.random(in: -1...1)
                render.brown = (render.brown + 0.02 * white) / 1.02
                let bed = render.brown * 3.5
                render.lowpassed += render.lowpassCoefficient * (bed - render.lowpassed)
                render.lfoPhase += render.lfoStep
                if render.lfoPhase > 2 * Float.pi { render.lfoPhase -= 2 * Float.pi }
                var sample = render.lowpassed * (0.7 + 0.3 * sin(render.lfoPhase))

                if render.droneLevel > 0 {
                    render.dronePhase += 2 * Float.pi * 55 / render.sampleRate
                    if render.dronePhase > 2 * Float.pi { render.dronePhase -= 2 * Float.pi }
                    sample += sin(render.dronePhase) * render.droneLevel
                }

                if !render.murmur.isEmpty {
                    var murmur: Float = 0
                    for voice in render.murmur {
                        voice.buzzPhase += voice.buzzStep
                        if voice.buzzPhase >= 1 { voice.buzzPhase -= 1 }
                        let input = Float.random(in: -1...1) + (voice.buzzPhase * 2 - 1) * 0.05
                        var voiced: Float = 0
                        for formant in voice.formants { voiced += formant.process(input) }
                        murmur += voiced * voice.gain
                    }
                    sample += murmur * render.murmurGain
                }

                if render.eventEnvelope > 0.0005 {
                    if render.eventKind == 1 {
                        render.eventPhase += 2 * Float.pi * render.eventFrequency / render.sampleRate
                        sample += sin(render.eventPhase) * render.eventEnvelope * render.eventGain
                    } else if render.eventKind == 2 {
                        // High-passed noise burst: white minus its own low-passed copy.
                        render.burstFiltered += 0.25 * (white - render.burstFiltered)
                        sample += (white - render.burstFiltered) * render.eventEnvelope * render.eventGain
                    }
                    render.eventEnvelope *= render.eventDecay
                }

                render.gain += (render.targetGain - render.gain) * 0.00006
                let out = sample * render.gain
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = out
                }
            }
            return noErr
        }
        sourceNode = node
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private func trigger(roll: Double, doubleClick: Bool) {
        if state.eventKind == 1 {
            let notes: [Float] = [784, 880, 988, 1175]
            state.eventFrequency = notes[min(notes.count - 1, Int(roll * 4))]
        }
        state.eventPhase = 0
        state.eventEnvelope = 1
        if doubleClick {
            let second = DispatchWorkItem { [weak self] in self?.state.eventEnvelope = 0.8 }
            scheduled.append(second)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: second)
        }
    }

    // Keep the bed quiet while the agent is talking.
    func duck(_ value: Bool) {
        guard value != ducked else { return }
        ducked = value
        state.targetGain = value ? baseLevel * 0.3 : baseLevel
    }

    func stop() {
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
        state.targetGain = 0
        if engine.isRunning { engine.stop() }
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
    }
}

// MARK: - Connecting sound

// Soft "connecting" ring (two short beeps, a pause, repeat — like a call being
// placed) played while a voice conversation is opening; stopped once connected.
// Mirrors startAiVoiceConnectingSound in client/src/lib/aiVoiceAmbience.js.
final class AIVoiceConnectingSound {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private final class Clock { var time: Double = 0; var fade: Float = 0; var fadeTarget: Float = 1 }
    private let clock = Clock()
    private var pendingCleanup: DispatchWorkItem?

    func start() {
        // Tear down any previous run immediately, and cancel its delayed cleanup —
        // otherwise that cleanup would fire 0.15s later and stop THIS new sound.
        pendingCleanup?.cancel()
        pendingCleanup = nil
        if engine.isRunning { engine.stop() }
        if let old = node { engine.detach(old); node = nil }
        let sampleRate = 44100.0
        let clock = self.clock
        clock.time = 0
        clock.fade = 0
        clock.fadeTarget = 1
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let t = clock.time
                let cycle = t.truncatingRemainder(dividingBy: 1.8)
                var env = 0.0
                for start in [0.0, 0.32] where cycle >= start && cycle < start + 0.22 {
                    let local = cycle - start
                    env = min(local / 0.02, min(1, (0.22 - local) / 0.04))
                }
                let tone = sin(2 * Double.pi * 440 * t) + sin(2 * Double.pi * 480 * t)
                clock.fade += (clock.fadeTarget - clock.fade) * 0.0008
                let out = Float(tone * env * 0.02) * clock.fade
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = out
                }
                clock.time += 1 / sampleRate
            }
            return noErr
        }
        self.node = node
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    func stop() {
        clock.fadeTarget = 0
        guard let node = self.node else { return }
        self.node = nil
        // Let the tone fade out instead of clicking off.
        let cleanup = DispatchWorkItem { [engine] in
            if engine.isRunning { engine.stop() }
            engine.detach(node)
        }
        pendingCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: cleanup)
    }
}

// MARK: - Speech output

@MainActor
final class AIVoicePlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var token = 0
    private var pending: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // 0..1 loudness of the audio playing right now.
    var level: Double {
        if let player, player.isPlaying {
            player.updateMeters()
            let decibels = player.averagePower(forChannel: 0)
            let linear = pow(10, Double(decibels) / 20)
            return min(1, linear * 3.2)
        }
        // AVSpeechSynthesizer (the on-device fallback voice) exposes no real-time
        // metering, so without this a reply spoken that way would report 0 here the
        // whole time it is audibly speaking. That silently breaks the loudness gate
        // handleText() uses to tell the AI's own voice (bouncing off the speaker,
        // into the mic - there is no echo cancellation) apart from a real
        // interruption: the gate collapses to its floor, the echo clears it, and
        // the AI's own reply gets captured as something the user said and sent
        // right back to it the moment playback ends. A steady non-zero level while
        // the fallback voice is genuinely speaking keeps the gate meaningful.
        return synthesizer.isSpeaking ? 0.6 : 0
    }

    private func resumePending(_ played: Bool = true) {
        if let continuation = pending {
            pending = nil
            continuation.resume(returning: played)
        }
    }

    func stop() {
        token += 1
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        resumePending(false)
    }

    /// Speaks `text` in the persona's voice. `onStart` fires when sound begins,
    /// `onEnd` when it finishes (not when it was stopped or superseded).
    func speak(
        _ text: String,
        persona: String,
        scenario: SpacechatAgentVoiceScenario?,
        api: SpacesVoiceAPI,
        sessionToken: String,
        onStart: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) {
        stop()
        let clean = AIVoiceText.spoken(text)
        guard !clean.isEmpty else { onEnd(); return }
        let myToken = token
        let chunks = AIVoiceText.chunks(clean)

        Task { @MainActor in
            var spokeWithServer = false
            var started = false
            var upcoming: Task<Data?, Never>? = chunks.first.map { chunk in
                Task { await Self.fetchAudio(api: api, text: chunk, persona: persona, sessionToken: sessionToken) }
            }
            for index in chunks.indices {
                let data = await upcoming?.value
                guard myToken == token else { return }
                guard let data else {
                    if index == 0 { break }
                    // Mid-reply failure: speak the remainder with the device voice.
                    if !started { onStart() }
                    await speakWithDevice(chunks[index...].joined(separator: " "), persona: persona, scenario: scenario, myToken: myToken)
                    if myToken == token { onEnd() }
                    return
                }
                upcoming = index + 1 < chunks.count
                    ? Task { await Self.fetchAudio(api: api, text: chunks[index + 1], persona: persona, sessionToken: sessionToken) }
                    : nil
                if !started { started = true; onStart() }
                spokeWithServer = true
                let played = await play(data, myToken: myToken)
                guard myToken == token else { return }
                if !played {
                    // A successful HTTP response can still contain audio this OS
                    // version cannot decode or play. Do not report a silent reply:
                    // finish this and the remaining text with the device voice.
                    await speakWithDevice(chunks[index...].joined(separator: " "), persona: persona, scenario: scenario, myToken: myToken)
                    if myToken == token { onEnd() }
                    return
                }
            }
            if spokeWithServer {
                if myToken == token { onEnd() }
                return
            }
            guard myToken == token else { return }
            onStart()
            await speakWithDevice(clean, persona: persona, scenario: scenario, myToken: myToken)
            if myToken == token { onEnd() }
        }
    }

    nonisolated private static func fetchAudio(api: SpacesVoiceAPI, text: String, persona: String, sessionToken: String) async -> Data? {
        guard let response = try? await api.aiVoiceSpeak(text: text, persona: persona, session: sessionToken),
              response.ok == true,
              let audio = response.audio,
              let data = Data(base64Encoded: audio), !data.isEmpty else { return nil }
        return data
    }

    private func play(_ data: Data, myToken: Int) async -> Bool {
        guard myToken == token, let audioPlayer = try? AVAudioPlayer(data: data) else { return false }
        audioPlayer.delegate = self
        audioPlayer.isMeteringEnabled = true
        player = audioPlayer
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pending = continuation
            if !audioPlayer.play() { resumePending(false) }
        }
    }

    private func speakWithDevice(_ text: String, persona: String, scenario: SpacechatAgentVoiceScenario?, myToken: Int) async {
        guard myToken == token else { return }
        let utterance = AVSpeechUtterance(string: String(text.prefix(900)))
        utterance.voice = Self.deviceVoice(for: persona)
        let requestedRate = scenario?.rate ?? 0.94
        utterance.rate = Float(max(0.34, min(0.58, 0.48 * requestedRate / 0.94)))
        utterance.pitchMultiplier = Float(max(0.5, min(2.0, scenario?.pitch ?? 1.0)))
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pending = continuation
            synthesizer.speak(utterance)
        }
    }

    // Each persona lands on a different voice from the best installed tier.
    private static func deviceVoice(for persona: String) -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return AVSpeechSynthesisVoice(language: "en-US") }
        let best = english.map { $0.quality.rawValue }.max() ?? 0
        let ranked = english.filter { $0.quality.rawValue == best }.sorted { $0.identifier < $1.identifier }
        var hash: UInt32 = 2166136261
        for byte in persona.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return ranked[Int(hash) % ranked.count]
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumePending(flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resumePending(false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumePending() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumePending(false) }
    }
}

// MARK: - Speech input

enum AIVoiceListenResult {
    case listening
    case microphoneDenied
    case speechDenied
    case unavailable
}

// Thread-safe holder for the live recognition request, so the audio tap (which
// runs off the main thread) always feeds the CURRENT request even after the
// recognizer has been restarted.
private final class AIVoiceRequestBox {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = newRequest
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}

@MainActor
final class AIVoiceListener {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private let requestBox = AIVoiceRequestBox()
    private var task: SFSpeechRecognitionTask?
    private var restartWork: DispatchWorkItem?
    // Cancelling a recognition task makes ITS callback fire with an error. Each
    // task is tagged so a cancelled (stale) task can never trigger another restart.
    private var taskGeneration = 0
    private var isActive = false
    private var contextualStrings: [String] = []
    // Streaming: the microphone and recognizer stay live for the whole
    // conversation. `currentText` is everything said in the current turn
    // (carried across the recognizer's own session restarts, so a turn is never
    // cut mid-sentence); the controller decides when the turn is over and calls
    // consume().
    private var carry = ""
    private var sessionText = ""
    private(set) var currentText = ""
    private var onText: ((String) -> Void)?
    private(set) var level: Double = 0
    /// Loudest microphone moment of the current turn (0...1).
    private(set) var peak: Float = 0
    /// True when the system is removing the AI's own voice from the microphone
    /// (voice processing). Only then is it safe to let the person talk over it.
    private(set) var echoCancelled = false

    func start(hints: [String] = [], onText: @escaping (String) -> Void) async -> AIVoiceListenResult {
        stop()
        self.onText = onText
        contextualStrings = hints

        let micAllowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micAllowed else { return .microphoneDenied }

        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .speechDenied }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return .unavailable }
        self.recognizer = recognizer
        carry = ""
        sessionText = ""
        currentText = ""
        peak = 0

        let input = engine.inputNode
        // Echo cancellation: the AI's voice comes out of the speaker, so without
        // this it goes back into the microphone and is heard as the person talking.
        // Must be switched on before the format is read and the tap installed.
        echoCancelled = false
        if !engine.isRunning, (try? input.setVoiceProcessingEnabled(true)) != nil { echoCancelled = true }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return .unavailable }
        input.removeTap(onBus: 0)
        let box = requestBox
        // Quiet talkers are lifted (never more than 4x, never clipping) so the
        // recognizer still gets a healthy signal; loud talkers pass unchanged.
        var smoothedGain: Float = 1
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            var rms: Float = 0
            if let channels = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for index in 0..<count { sum += channels[0][index] * channels[0][index] }
                rms = count > 0 ? sqrt(sum / Float(count)) : 0
                if rms > 0.004 {
                    let target = min(4, max(1, 0.1 / rms))
                    smoothedGain += (target - smoothedGain) * 0.2
                    if smoothedGain > 1.05 {
                        for channel in 0..<Int(buffer.format.channelCount) {
                            for index in 0..<count {
                                channels[channel][index] = max(-1, min(1, channels[channel][index] * smoothedGain))
                            }
                        }
                    }
                }
            }
            box.append(buffer)
            let measured = rms * max(1, smoothedGain)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let scaled = min(1, Double(measured) * 8)
                self.level = self.level * 0.6 + scaled * 0.4
                self.peak = max(self.peak, Float(scaled))
            }
        }

        engine.prepare()
        do { try engine.start() } catch { return .unavailable }
        isActive = true
        beginRecognitionTask()
        return .listening
    }

    private func emit() {
        let next = "\(carry) \(sessionText)".split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard next != currentText else { return }
        currentText = next
        if !next.isEmpty { onText?(next) }
    }

    // SFSpeechRecognizer sessions end on their own after a pause or about a
    // minute; the text so far is carried over so nothing is lost.
    private func beginRecognitionTask() {
        guard isActive, let recognizer else { return }
        taskGeneration += 1
        let generation = taskGeneration
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if !contextualStrings.isEmpty { request.contextualStrings = contextualStrings }
        requestBox.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, generation == self.taskGeneration else { return }
                if let result {
                    self.sessionText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.emit()
                }
                if error != nil || result?.isFinal == true {
                    self.carry = self.currentText
                    self.sessionText = ""
                    self.scheduleRestart()
                }
            }
        }
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.beginRecognitionTask() }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Takes the current turn's text and starts a fresh turn.
    @discardableResult
    func consume() -> String {
        let text = currentText
        carry = ""
        sessionText = ""
        currentText = ""
        peak = 0
        // A fresh recognition session, so the old session's cumulative partial
        // results can't bring the consumed words back.
        if isActive { beginRecognitionTask() }
        return text
    }

    func stop() {
        isActive = false
        taskGeneration += 1
        restartWork?.cancel()
        restartWork = nil
        task?.cancel()
        task = nil
        requestBox.set(nil)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        onText = nil
        carry = ""
        sessionText = ""
        currentText = ""
        level = 0
    }
}

// MARK: - Controller

/// Runs one voice conversation: greet -> listen -> think -> speak -> listen.
@MainActor
final class NativeAIVoiceController: ObservableObject {
    @Published var phase: AIVoicePhase = .thinking {
        didSet { ambience.duck(phase == .speaking) }
    }
    @Published var scenario: SpacechatAgentVoiceScenario?
    @Published var microphoneDenied = false
    @Published var speechDenied = false
    @Published var recognitionUnavailable = false
    // While the conversation is opening: red waves + a soft ring; once the first
    // spoken line starts the waves ease to the agent's colours and the ring stops.
    @Published var connecting = true

    private let player = AIVoicePlayer()
    private let listener = AIVoiceListener()
    private let ambience = AIVoiceAmbience()
    private let connectingSound = AIVoiceConnectingSound()
    private var connectFailsafe: DispatchWorkItem?
    private var closed = true
    private var persona = "spaceai"
    private var agentName = ""
    private var api: SpacesVoiceAPI?
    private var sessionToken = ""
    private var sendTurn: ((String) async -> String)?
    private var rolloverTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var sceneClockOffsetMs: Double = 0
    // Live turn-taking state (never shown on screen).
    private var turnStartedAt: Date?
    private var turnLastChange: Date?
    private var turnMaxPause: TimeInterval = 0
    private var turnVersion = 0
    private var turnMaxTask: Task<Void, Never>?
    private var turnTimerTask: Task<Void, Never>?
    // What the user said while the AI was talking (answered when the AI finishes).
    private var spokenDuringAI = ""
    // The AI answers once the user has been quiet this long, and never listens to one turn
    // for longer than the maximum: it then answers what it heard so far.
    private static let replyAfterSilence: UInt64 = 3_000_000_000
    private static let maxListen: UInt64 = 30_000_000_000

    func level() -> Double {
        phase == .speaking ? player.level : listener.level
    }

    var paletteHex: [String] {
        if connecting { return ["#ffb4b4", "#ef4444", "#991b1b"] }
        return scenario?.palette ?? ["#8fd8ff", "#3a7bff", "#7a5cff"]
    }

    private func markConnected() {
        guard connecting else { return }
        connectFailsafe?.cancel()
        connectFailsafe = nil
        withAnimation(.easeInOut(duration: 0.8)) { connecting = false }
        connectingSound.stop()
    }

    func begin(
        persona: String,
        agentName: String = "",
        api: SpacesVoiceAPI,
        sessionToken: String,
        greeting: String,
        sendTurn: @escaping (String) async -> String
    ) {
        // SwiftUI can call onAppear again without an onDisappear in between; a
        // second begin would stack another interruption observer, failsafe and
        // greeting on top of the live conversation.
        guard closed else { return }
        closed = false
        self.persona = persona
        self.agentName = agentName
        self.api = api
        self.sessionToken = sessionToken
        self.sendTurn = sendTurn
        microphoneDenied = false
        speechDenied = false
        recognitionUnavailable = false
        phase = .thinking
        configureAudioSession()
        connecting = true
        // No ring or background sound while connecting or waiting: only the agent's voice is heard.
        let failsafe = DispatchWorkItem { [weak self] in self?.markConnected() }
        connectFailsafe = failsafe
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: failsafe)
        // A phone call, Siri or an alarm silently stops the audio engines; when
        // the interruption ends, bring listening and the background sound back.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in self?.handleInterruption(typeRaw: raw) }
        }

        Task { @MainActor in
            let fetched = try? await api.agentVoiceScenario(persona: persona, session: sessionToken)
            guard !closed else { return }
            let scene = fetched?.scenario
            scenario = scene
            applyScene(scene, serverNow: fetched?.serverNow)
            speak(greeting)
        }
        // The microphone opens once and stays live for the whole conversation.
        startListening()
    }

    // Shows a scene (colours only, no background sound); then waits for its
    // five-minute end to swap in the next one the server prepared.
    private func applyScene(_ scene: SpacechatAgentVoiceScenario?, serverNow: Double?) {
        scenario = scene
        rolloverTask?.cancel()
        guard let scene else { return }
        let clockOffset = serverNow.map { $0 - Date().timeIntervalSince1970 * 1000 } ?? 0
        sceneClockOffsetMs = clockOffset
        // A scene that rolls over while the agent is talking must start ducked.
        ambience.duck(phase == .speaking)
        let waitMs = max(1000, scene.expiresAt - (Date().timeIntervalSince1970 * 1000 + clockOffset) + 300)
        let persona = self.persona
        rolloverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(waitMs * 1_000_000))
            // A failed fetch, or one that lands just before the server's boundary
            // and returns the same scene, retries a few times — otherwise the
            // scene would stay stale (or re-apply itself and restart the sound).
            for attempt in 0..<9 {
                guard let self, !Task.isCancelled, !self.closed, let api = self.api else { return }
                let next = try? await api.agentVoiceScenario(persona: persona, session: self.sessionToken)
                if let fetched = next?.scenario, fetched.expiresAt > scene.expiresAt {
                    withAnimation(.easeInOut(duration: 1.2)) { self.applyScene(fetched, serverNow: next?.serverNow) }
                    return
                }
                if attempt < 8 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?) {
        guard !closed, let raw = typeRaw, AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        configureAudioSession()
        if phase == .speaking {
            // The interrupted reply is cut off — carry on by listening.
            player.stop()
            phase = .listening
            resetTurn()
        }
        startListening()
    }

    func end() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        rolloverTask?.cancel()
        resetTurn()
        connectFailsafe?.cancel()
        connectingSound.stop()
        closed = true
        player.stop()
        listener.stop()
        ambience.stop()
        sendTurn = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func retryListening() {
        guard !closed else { return }
        startListening()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? audioSession.setActive(true)
    }

    private func speak(_ text: String) {
        guard !closed, let api else { return }
        player.speak(
            text,
            persona: persona,
            scenario: scenario,
            api: api,
            sessionToken: sessionToken,
            onStart: { [weak self] in
                guard let self, !self.closed else { return }
                self.markConnected()
                self.phase = .speaking
            },
            onEnd: { [weak self] in
                guard let self, !self.closed else { return }
                self.markConnected()
                self.phase = .listening
                // The mic's own text from the AI's turn is dropped; what the user really said
                // over the AI (loud, clear speech) is answered right away.
                let heard = self.spokenDuringAI.trimmingCharacters(in: .whitespacesAndNewlines)
                self.spokenDuringAI = ""
                self.listener.consume()
                self.resetTurn()
                if !heard.isEmpty { Task { await self.respond(forcedText: heard) } }
            }
        )
    }

    private func startListening() {
        guard !closed else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.listener.start(hints: [self.agentName]) { [weak self] text in
                Task { @MainActor [weak self] in self?.handleText(text) }
            }
            guard !self.closed else { self.listener.stop(); return }
            switch result {
            case .listening:
                self.microphoneDenied = false
                self.speechDenied = false
            case .microphoneDenied: self.microphoneDenied = true
            case .speechDenied: self.speechDenied = true
            case .unavailable: self.recognitionUnavailable = true
            }
        }
    }

    private func resetTurn() {
        turnMaxTask?.cancel()
        turnTimerTask?.cancel()
        turnMaxTask = nil
        turnTimerTask = nil
        turnStartedAt = nil
        turnLastChange = nil
        turnMaxPause = 0
        turnVersion += 1
    }

    private var lastUserTextAt = Date.distantPast
    /// True while the person is talking to the AI: their words changed a moment ago.
    func userTalking() -> Bool {
        phase == .listening && Date().timeIntervalSince(lastUserTextAt) < 0.9
    }

    // Every change to what the user is saying lands here — live, not per sentence.
    private func handleText(_ text: String) {
        guard !closed else { return }
        if phase == .listening, !text.trimmingCharacters(in: .whitespaces).isEmpty { lastUserTextAt = Date() }
        if phase == .speaking {
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            if listener.echoCancelled {
                // Echo is removed, so speech over the AI is the person really talking:
                // the AI stops and listens, like a conversation.
                guard words >= 2, listener.level >= 0.12 else { return }
                player.stop()
                spokenDuringAI = ""
                phase = .listening
                resetTurn()
            } else {
                // No echo cancellation: the AI is not cut off by what the microphone hears
                // (it could be its own voice). Clear, loud speech is remembered and answered after.
                let bar = max(0.25, player.level * 0.8 + 0.1)
                if words >= 3, listener.level >= bar { spokenDuringAI = text }
                return
            }
        }
        let now = Date()
        if turnStartedAt == nil {
            turnStartedAt = now
            // Never listen to one turn for more than 30 s: answer what was heard by then.
            turnMaxTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.maxListen)
                guard let self, !Task.isCancelled else { return }
                await self.respond()
            }
        } else if let last = turnLastChange, now.timeIntervalSince(last) > 0.3 {
            turnMaxPause = max(turnMaxPause, now.timeIntervalSince(last))
        }
        turnLastChange = now
        if phase != .listening { return } // buffered until the AI is done

        // Every new word restarts the wait; three quiet seconds after the last one and the
        // AI answers at once (no server round trip in between).
        turnTimerTask?.cancel()
        turnVersion += 1
        // A finished sentence is answered sooner than one that trails off.
        let spokenWords = text.split(whereSeparator: { $0.isWhitespace }).count
        let endedSentence = text.last.map { ".?!".contains($0) } ?? false
        let wait: UInt64 = spokenWords < 3 ? 2_200_000_000 : (endedSentence ? 1_100_000_000 : 1_700_000_000)
        turnTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            guard let self, !Task.isCancelled else { return }
            await self.respond()
        }
    }

    private func respond(forcedText: String? = nil) async {
        guard !closed, phase == .listening else { return }
        let text = forcedText ?? listener.consume()
        resetTurn()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let sendTurn else { return }
        phase = .thinking
        let reply = await sendTurn(text)
        guard !closed else { return }
        let continued = listener.currentText
        if !continued.trimmingCharacters(in: .whitespaces).isEmpty {
            // The person kept talking while the answer was being written: that
            // answer stays in the chat but is not spoken — carry on with the new words.
            phase = .listening
            handleText(continued)
            return
        }
        if reply.isEmpty {
            phase = .listening
            return
        }
        speak(reply)
    }
}

extension Color {
    /// The agent colour lightened towards white (amount 0 = the colour, 1 = white) — used
    /// for the white appearance's soft tinted sky.
    static func voiceTint(_ hex: String, _ amount: Double) -> Color {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt32(value.prefix(6), radix: 16) ?? 0x5ca9ff
        let r = Double((number >> 16) & 255) / 255
        let g = Double((number >> 8) & 255) / 255
        let b = Double(number & 255) / 255
        return Color(.sRGB, red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, opacity: 1)
    }

    /// "#rrggbb" / "#rgb" from the server's agent palette.
    init(voiceHex hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt32(value.prefix(6), radix: 16) ?? 0x5ca9ff
        self.init(.sRGB, red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, opacity: 1)
    }
}


// MARK: - Voice screen (per agent)

/// Full-screen voice conversation with ONE AI model or agent. It is presented
/// from that agent's own voice button, so the voice, colors, background scene
/// and Voice Friend all belong to `persona`. Mirrors
/// client/src/components/AiVoiceOverlay.jsx.
struct NativeAIVoiceScreen: View {
    let persona: String
    let agentName: String
    let greeting: String
    let api: SpacesVoiceAPI
    let sessionToken: String
    /// text spoken by the user -> the assistant's reply text
    let sendTurn: (String) async -> String
    /// true when the user chose "Type text"
    let onClose: (Bool) -> Void

    @StateObject private var voice = NativeAIVoiceController()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        voiceContent
    }

    // Dark in the dark appearance, white in the white appearance.
    private var isLight: Bool { colorScheme == .light }
    private var ink: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.161) : Color(red: 0.918, green: 0.953, blue: 1.0) }
    private var accentHex: String { voice.scenario?.palette[1] ?? "#3a7bff" }

    private func startAIVoice() {
        let first = greeting.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.begin(
            persona: persona,
            agentName: agentName,
            api: api,
            sessionToken: sessionToken,
            greeting: first.isEmpty ? "Hi, I'm \(agentName). Ask me something and I will answer out loud." : first,
            sendTurn: { text in await sendTurn(text) }
        )
    }

    private var voiceHint: String {
        if voice.microphoneDenied { return "Microphone access was blocked, so I can’t hear you. Enable it in Settings > Spaces." }
        if voice.speechDenied { return "Speech recognition is off, so I can’t understand you. Enable it in Settings > Spaces." }
        if voice.recognitionUnavailable { return "Speech recognition isn’t available right now. You can still hear replies — type in the chat." }
        return "Say something — I’m listening and will answer out loud."
    }

    private func endVoice(typeText: Bool = false) {
        voice.end()
        onClose(typeText)
    }

    private var voiceContent: some View {
        ZStack {
            AIVoiceBackdropView(
                background: voice.scenario?.background ?? ["#1c1c1c", "#0a0a0a", "#030303"],
                glow: voice.scenario?.palette[1] ?? "#3a7bff",
                animated: voice.scenario?.ambienceKind != "none"
            )
            .id(voice.scenario?.id ?? "scene")
            .transition(.opacity)

            VStack(spacing: 26) {
                Spacer()
                let orbSize = min(UIScreen.main.bounds.width * 0.72, 300)
                ZStack {
                    // A soft glow of the agent's colour behind the orb.
                    Circle()
                        .fill(RadialGradient(colors: [Color(voiceHex: voice.paletteHex.count == 3 ? voice.paletteHex[1] : accentHex).opacity(isLight ? 0.30 : 0.38), .clear], center: .center, startRadius: 0, endRadius: orbSize * 0.85))
                        .frame(width: orbSize * 1.7, height: orbSize * 1.7)
                        .blur(radius: 26)
                    AIVoiceOrbView(paletteHex: voice.paletteHex, phase: voice.phase, level: { voice.level() }, userTalking: { voice.userTalking() })
                        .frame(width: orbSize, height: orbSize)
                        .shadow(color: Color(voiceHex: voice.paletteHex.count == 3 ? voice.paletteHex[1] : accentHex).opacity(isLight ? 0.30 : 0.22), radius: 30, y: 10)
                }
                .frame(width: orbSize, height: orbSize)
                if voice.microphoneDenied || voice.speechDenied || voice.recognitionUnavailable {
                    Text(voiceHint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ink.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
                if voice.microphoneDenied || voice.speechDenied {
                    Button(action: { voice.retryListening() }) {
                        Text("Try again")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 22)
                            .frame(height: 36)
                            .background(Color(red: 0.23, green: 0.48, blue: 1.0), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button(action: { endVoice() }) {
                        Text("End")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(ink)
                            .frame(minWidth: 108, minHeight: 42)
                            .background(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button(action: { endVoice(typeText: true) }) {
                        Text("Type text")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(isLight ? Color.white : Color(red: 0.027, green: 0.063, blue: 0.114))
                            .frame(minWidth: 108, minHeight: 42)
                            .background(ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 32)
            }

        }
        .onAppear { startAIVoice() }
        .onDisappear { voice.end() }
    }

}

// MARK: - Server contracts used by voice (copied from Spacechat's APIModels)

struct SpacechatAgentVoiceScenario: Decodable, Hashable {
    let persona: String
    let scenario: String
    let voice: String
    let tone: String
    let pitch: Double
    let rate: Double
    let environment: String
    let noise: String
    let noiseFrequency: Double
    let color: String
    // Three-tone orb palette and the procedural background-sound recipe the
    // server picks per agent (mind/brain/agent-voice.js VOICE_PROFILES).
    let palette: [String]
    let ambienceKind: String
    let ambienceLevel: Double
    let ambienceCutoff: Double
    let ambienceMurmurPitch: Double
    let ambienceMurmurLevel: Double
    let ambienceSeed: UInt32
    // Shared scene identity + backdrop colors written by the server.
    let id: String
    let background: [String]
    let generatedAt: Double
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case id, persona, scenario, voice, tone, pitch, rate, environment, noise, noiseFrequency, color, palette, background, ambience, generatedAt, expiresAt
    }

    private struct Ambience: Decodable {
        let kind: String?
        let level: Double?
        let cutoff: Double?
        let murmurPitch: Double?
        let murmurLevel: Double?
        let seed: Double?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persona = (try? c.decodeIfPresent(String.self, forKey: .persona)) ?? "spaceai"
        scenario = (try? c.decodeIfPresent(String.self, forKey: .scenario)) ?? ""
        voice = (try? c.decodeIfPresent(String.self, forKey: .voice)) ?? "Spacechat Guide"
        tone = (try? c.decodeIfPresent(String.self, forKey: .tone)) ?? "warm"
        pitch = (try? c.decodeIfPresent(Double.self, forKey: .pitch)) ?? 1
        rate = (try? c.decodeIfPresent(Double.self, forKey: .rate)) ?? 0.94
        environment = (try? c.decodeIfPresent(String.self, forKey: .environment)) ?? "quiet studio"
        noise = (try? c.decodeIfPresent(String.self, forKey: .noise)) ?? "soft room tone"
        noiseFrequency = (try? c.decodeIfPresent(Double.self, forKey: .noiseFrequency)) ?? 180
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "#5ca9ff"
        let decodedPalette = (try? c.decodeIfPresent([String].self, forKey: .palette)) ?? []
        palette = decodedPalette.count == 3 ? decodedPalette : ["#8fd8ff", "#3a7bff", "#7a5cff"]
        let ambience = try? c.decodeIfPresent(Ambience.self, forKey: .ambience)
        ambienceKind = ambience?.kind ?? "room"
        ambienceLevel = ambience?.level ?? 0.45
        ambienceCutoff = ambience?.cutoff ?? 400
        ambienceMurmurPitch = ambience?.murmurPitch ?? 160
        ambienceMurmurLevel = ambience?.murmurLevel ?? 0.1
        ambienceSeed = UInt32(clamping: Int(ambience?.seed ?? 1))
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        let decodedBackground = (try? c.decodeIfPresent([String].self, forKey: .background)) ?? []
        background = decodedBackground.count == 3 ? decodedBackground : ["#0b1b33", "#12082b", "#050505"]
        generatedAt = (try? c.decodeIfPresent(Double.self, forKey: .generatedAt)) ?? 0
        expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? 0
    }
}

// POST /api/ai/voice/speak — `audio` is a base64 MP3 in the agent's own voice;
// `ok: false` + `fallback: "browser"` means the server could not synthesize

struct AIVoiceSpeakResponse: Decodable {
    let ok: Bool?
    let audio: String?
    let provider: String?
    let voice: String?
    let fallback: String?
    let error: String?
}

struct SpacechatAgentVoiceScenarioResponse: Decodable {
    let ok: Bool?
    let scenario: SpacechatAgentVoiceScenario?
    let next: SpacechatAgentVoiceScenario?
    let serverNow: Double?
    let error: String?
}

/// The two voice endpoints, over Spaces' own session handling.
final class SpacesVoiceAPI {
    private func decode<T: Decodable>(_ path: String, _ body: [String: Any], timeout: TimeInterval) async throws -> T {
        let json = try await SpacechatService.post(path, body: body, timeout: timeout)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func aiVoiceSpeak(text: String, persona: String, session: String) async throws -> AIVoiceSpeakResponse {
        try await decode("ai/voice/speak", ["text": text, "persona": persona], timeout: 20)
    }
    func agentVoiceScenario(persona: String, session: String) async throws -> SpacechatAgentVoiceScenarioResponse {
        try await decode("ai/voice/scenario", ["persona": persona], timeout: 10)
    }
}
