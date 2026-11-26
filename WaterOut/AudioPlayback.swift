import ActivityKit
import AVFAudio
import Combine
import Foundation
import UIKit

private actor AudioSamples {
    private var cache: [SoundJob: AVAudioPCMBuffer] = [:]

    func buffer(for job: SoundJob) -> AVAudioPCMBuffer? {
        if let buffer = cache[job] { return buffer }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundSignal.rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(job.duration * SoundSignal.rate)),
              let samples = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            let sample = SoundSignal.stereo(job, elapsed: Double(frame) / SoundSignal.rate)
            samples[0][frame] = sample.0
            samples[1][frame] = sample.1
        }
        if cache.count >= 5 { cache.removeAll(keepingCapacity: true) }
        cache[job] = buffer
        return buffer
    }
}

@MainActor
final class AudioPlayback: ObservableObject {
    @Published private(set) var output: OutputKind = .unknown
    @Published private(set) var job: SoundJob?
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var preparing = false
    @Published private(set) var problem: String?

    private let session = AVAudioSession.sharedInstance()
    private let samples = AudioSamples()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var token = PlaybackToken()
    private var ticker: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var subscriptions: [NSObjectProtocol] = []
    private var activity: Activity<PlaybackActivity>?
    private var routeSignature: [String] = []
    private var activeConditions: ListeningConditions?
    private var completion: ((ListeningConditions) -> Void)?
    private var sessionActive = false
    private var configuringSession = false
    private var volumeChanged = false

    var busy: Bool { job != nil }
    var remaining: Int { Int(ceil(max(0, (job?.duration ?? 0) - elapsed))) }
    var activeChannel: Channel? { job?.channel(at: elapsed) }
    var allowsMonoFallback: Bool { problem == "audio.mono" || problem == "audio.stereoUnknown" }
    var needsPhoneOutput: Bool { problem == "audio.external" }
    var receiverUnavailable: Bool { problem == "audio.receiver" }

    init() {
        refreshRoute()
        if Launch.testing { return }
        observe(AVAudioSession.interruptionNotification) { audio, note in
            if note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                audio.stop(message: "audio.interrupted")
            }
        }
        observe(AVAudioSession.routeChangeNotification) { audio, note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let sameCategoryChange = raw == AVAudioSession.RouteChangeReason.categoryChange.rawValue &&
                audio.signature == audio.routeSignature
            if audio.busy && !audio.configuringSession && !sameCategoryChange {
                audio.stop(message: "audio.routeChanged")
            }
            audio.refreshRoute()
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { audio, _ in
            audio.stop(message: "audio.interrupted")
            audio.refreshRoute()
        }
        observe(UIApplication.willResignActiveNotification) { audio, _ in audio.stop(message: "audio.interrupted") }
        observe(UIAccessibility.monoAudioStatusDidChangeNotification) { audio, _ in
            if audio.job?.requiresStereo == true { audio.stop(message: "audio.routeChanged") }
        }
    }

    private func observe(_ name: Notification.Name, action: @escaping (AudioPlayback, Notification) -> Void) {
        let handle = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self, note)
            }
        }
        subscriptions.append(handle)
    }

    private var signature: [String] {
        session.currentRoute.outputs.map { $0.portType.rawValue + ":" + $0.uid }
    }

    private var currentOutput: OutputKind {
        if Launch.testing {
            if Launch.arguments.contains("-route-error") { return .bluetooth }
            if job?.target == .receiver && !Launch.arguments.contains("-receiver-error") { return .receiver }
            return .speaker
        }
        let routes = session.currentRoute.outputs
        guard routes.count == 1, let route = routes.first else { return routes.isEmpty ? .unknown : .other }
        switch route.portType {
        case .builtInSpeaker: return .speaker
        case .builtInReceiver: return .receiver
        case .headphones, .lineOut, .usbAudio: return .wired
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
        default: return .other
        }
    }

    func refreshRoute() { output = currentOutput }
    func clearProblem() { problem = nil }

    func start(_ request: SoundJob, onFinish: @escaping (ListeningConditions) -> Void) {
        guard let generation = token.begin() else { return }
        problem = nil
        elapsed = 0
        job = request
        preparing = true
        completion = onFinish
        routeSignature = signature

        if Launch.testing {
            configure(request, generation: generation, buffer: nil)
            return
        }
        preparation = Task { [weak self] in
            guard let self else { return }
            let buffer = await samples.buffer(for: request)
            guard token.matches(generation) else { return }
            guard let buffer else { stop(message: "audio.failed"); return }
            configure(request, generation: generation, buffer: buffer)
        }
    }

    private func configure(_ request: SoundJob, generation: Int, buffer: AVAudioPCMBuffer?) {
        do {
            guard Launch.testing || UIApplication.shared.applicationState == .active else {
                stop(message: "audio.interrupted")
                return
            }
            let receiver = request.target == .receiver
            let simulatedBlock = Launch.testing && Launch.arguments.contains("-route-error")
            if simulatedBlock || (!Launch.testing && request.target != .stereo && currentOutput.isExternal) {
                stop(message: "audio.external")
                return
            }
            if !Launch.testing {
                try activateSession(receiver: receiver)
            }
            let detected = currentOutput
            output = detected
            routeSignature = signature
            if receiver && detected != .receiver {
                stop(message: "audio.receiver")
                return
            }
            if request.target == nil || request.target == .speaker {
                guard detected == .speaker else {
                    stop(message: detected.isExternal ? "audio.external" : "audio.speaker")
                    return
                }
            }
            if request.requiresStereo {
                let mono = Launch.testing ? Launch.arguments.contains("-mono") : UIAccessibility.isMonoAudioEnabled
                let count = session.currentRoute.outputs.first?.channels?.count ?? session.outputNumberOfChannels
                if mono || (!Launch.testing && count == 1) { stop(message: "audio.mono"); return }
                if !Launch.testing && (count < 2 || session.currentRoute.outputs.count != 1 || detected == .receiver) {
                    stop(message: "audio.stereoUnknown")
                    return
                }
            }
            if request == .monoSample && detected == .unknown {
                stop(message: "audio.failed")
                return
            }
            let volume = Launch.testing ? 35 : Int((session.outputVolume * 100).rounded())
            volumeChanged = false
            activeConditions = ListeningConditions(output: detected, volume: volume)
            if let buffer {
                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                self.engine = engine
                self.player = player
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                engine.prepare()
                try engine.start()
                guard signature == routeSignature else { stop(message: "audio.routeChanged"); return }
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in self?.finish(generation) }
                }
                player.play()
            }
            preparing = false
            beginClock(request, generation: generation)
        } catch {
            stop(message: request.target == .receiver ? "audio.receiver" : "audio.failed")
        }
    }

    private func activateSession(receiver: Bool) throws {
        configuringSession = true
        defer { configuringSession = false }
        try session.setCategory(receiver ? .playAndRecord : .playback, mode: .default, options: [])
        try session.setActive(true)
        sessionActive = true
    }

    private func beginClock(_ request: SoundJob, generation: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        if request.target == nil && !Launch.testing && ActivityAuthorizationInfo().areActivitiesEnabled {
            let date = Date()
            activity = try? Activity.request(attributes: PlaybackActivity(),
                content: ActivityContent(state: .init(start: date, end: date.addingTimeInterval(request.duration)),
                                         staleDate: date.addingTimeInterval(request.duration)), pushType: nil)
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(65))
                guard !Task.isCancelled, let self, token.matches(generation) else { return }
                let time = start.duration(to: clock.now).components
                elapsed = min(request.duration, Double(time.seconds) + Double(time.attoseconds) / 1e18)
                if !Launch.testing && Int((session.outputVolume * 100).rounded()) != activeConditions?.volume {
                    volumeChanged = true
                }
                if elapsed >= request.duration {
                    if Launch.testing { finish(generation) }
                    if !Launch.testing && start.duration(to: clock.now) >= .seconds(request.duration + 1) {
                        stop(message: "audio.interrupted")
                    }
                }
            }
        }
    }

    private func finish(_ generation: Int) {
        guard token.matches(generation), let original = activeConditions else { return }
        if !Launch.testing && (signature != routeSignature || UIApplication.shared.applicationState != .active ||
            (job?.requiresStereo == true && UIAccessibility.isMonoAudioEnabled)) {
            stop(message: "audio.interrupted")
            return
        }
        let callback = completion
        let volume = Launch.testing ? 35 : Int((session.outputVolume * 100).rounded())
        let stableVolume = volume == original.volume && !volumeChanged
        stop()
        callback?(ListeningConditions(output: original.output, volume: stableVolume ? volume : -1))
    }

    func stop(message: String? = nil) {
        guard token.stop() else { return }
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        ticker?.cancel()
        ticker = nil
        preparation?.cancel()
        preparation = nil
        if sessionActive {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        if let activity {
            self.activity = nil
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        job = nil
        preparing = false
        completion = nil
        activeConditions = nil
        problem = message
        if !Launch.testing { refreshRoute() }
    }
}
