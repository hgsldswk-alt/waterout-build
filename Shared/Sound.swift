import Foundation

enum SoundMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case basic, low, mid, high, sweep
    var id: Self { self }
    var title: String { L.t("mode.\(rawValue)") }

    var frequencies: (Double, Double) {
        switch self {
        case .basic: return (165, 165)
        case .low: return (125, 125)
        case .mid: return (210, 210)
        case .high: return (280, 280)
        case .sweep: return (125, 280)
        }
    }
}

struct SoundPreset: Codable, Equatable, Hashable {
    static func readFile(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxCodeBytes + 1), data.count <= maxCodeBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static let durations = [5, 10, 15]
    static let standard = Self(mode: .basic, seconds: 15)
    static let maxCodeBytes = 256
    static let prefix = "WT1:"
    let mode: SoundMode
    let seconds: Int
    var valid: Bool { Self.durations.contains(seconds) }

    var code: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return Self.prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ raw: String) -> Self? {
        guard raw.utf8.count <= maxCodeBytes else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(prefix) else { return nil }
        let token = code.dropFirst(prefix.count)
        guard !token.isEmpty, token.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        let padded = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - token.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["mode", "seconds"],
              let result = try? JSONDecoder().decode(Self.self, from: data), result.valid else { return nil }
        return result
    }
}

enum SoundCheck: String, Codable, CaseIterable, Identifiable, Hashable {
    case speaker, receiver, stereo
    var id: Self { self }
    var title: String { L.t("check.\(rawValue)") }
    var subtitle: String { L.t("check.\(rawValue).hint") }
}

enum Channel: String, Codable, CaseIterable, Hashable {
    case left, right
    var title: String { L.t("channel.\(rawValue)") }
}

enum SoundJob: Hashable {
    case tone(SoundPreset)
    case check(SoundCheck, Channel?)
    case monoSample

    var duration: Double {
        switch self {
        case .tone(let preset): return Double(preset.valid ? preset.seconds : SoundPreset.standard.seconds)
        case .check(.stereo, nil): return 4
        case .check(.stereo, .some), .monoSample: return 2
        case .check: return 3
        }
    }

    var target: SoundCheck? {
        switch self {
        case .check(let target, _): return target
        case .monoSample: return .stereo
        case .tone: return nil
        }
    }

    var requiresStereo: Bool {
        if case .check(.stereo, _) = self { return true }
        return false
    }

    func channel(at elapsed: Double) -> Channel? {
        guard case .check(.stereo, let side) = self else { return nil }
        return side ?? (elapsed < duration / 2 ? .left : .right)
    }

    var countsAsCheck: SoundCheck? {
        if case .check(let check, nil) = self { return check }
        return nil
    }
}

enum SoundSignal {
    static let rate = 44_100.0
    static let gainLimit: Float = 0.18

    static func envelope(elapsed: Double, length: Double) -> Double {
        guard elapsed > 0, elapsed < length else { return 0 }
        let ramp = min(1, elapsed / 0.20, (length - elapsed) / 0.16)
        return 0.5 - 0.5 * cos(.pi * ramp)
    }

    static func stereo(_ job: SoundJob, elapsed: Double) -> (Float, Float) {
        guard elapsed > 0, elapsed < job.duration else { return (0, 0) }
        let segment = job.requiresStereo ? min(job.duration, 2) : job.duration
        let offset = job.requiresStereo ? elapsed.truncatingRemainder(dividingBy: segment) : elapsed
        let frequencies: (Double, Double)
        let gain: Float
        switch job {
        case .tone(let preset):
            frequencies = preset.mode.frequencies
            gain = gainLimit
        case .check(.receiver, _):
            frequencies = (550, 550)
            gain = 0.035
        default:
            frequencies = (440, 440)
            gain = 0.09
        }
        let cycles = frequencies.0 * offset + (frequencies.1 - frequencies.0) * offset * offset / (2 * segment)
        let wave = Float(sin(2 * .pi * cycles) * envelope(elapsed: offset, length: segment)) * gain
        switch job.channel(at: elapsed) {
        case .left: return (wave, 0)
        case .right: return (0, wave)
        case nil: return (wave, wave)
        }
    }
}

struct PlaybackToken: Equatable {
    private(set) var generation = 0
    private(set) var active = false

    mutating func begin() -> Int? {
        guard !active else { return nil }
        generation += 1
        active = true
        return generation
    }

    func matches(_ candidate: Int) -> Bool { active && generation == candidate }

    @discardableResult
    mutating func stop() -> Bool {
        guard active else { return false }
        active = false
        return true
    }
}
