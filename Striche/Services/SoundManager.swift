import AVFoundation

/// Plays bundled drink sounds, with a synthesized fallback tone when a file is missing.
final class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private var engine: AVAudioEngine?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ sound: DrinkSound) {
        guard let name = sound.fileName else {
            playFallbackTone(for: sound)
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            playFallbackTone(for: sound)
            return
        }
        do {
            let player: AVAudioPlayer
            if let existing = players[name] {
                player = existing
            } else {
                player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[name] = player
            }
            player.currentTime = 0
            player.play()
        } catch {
            playFallbackTone(for: sound)
        }
    }

    func playFile(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        if let existing = players[name] {
            existing.currentTime = 0
            existing.play()
            return
        }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            players[name] = player
            player.play()
        }
    }

    // Simple sine-blip fallback so taps always feel responsive.
    private func playFallbackTone(for sound: DrinkSound) {
        let freq: Double
        switch sound {
        case .sekt: freq = 880
        case .coffee: freq = 440
        case .grill: freq = 220
        default: freq = 660
        }
        playTone(frequency: freq, duration: 0.18)
    }

    func playTone(frequency: Double, duration: Double) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let sampleRate = 44100.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let ch = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let env = exp(-3.0 * t)            // quick decay
            ch[i] = Float(sin(2 * .pi * frequency * t) * 0.3 * env)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: []) { }
            player.play()
            self.engine = engine
        } catch { }
    }
}
