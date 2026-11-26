import StoreKit
import SwiftUI
import UniformTypeIdentifiers

enum Destination: Hashable {
    case settings, help, history, comparison, saved(UUID), presets, importer, card, check(SoundCheck)
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    var file: URL? = nil
}

@MainActor
struct RootView: View {
    @StateObject var audio = AudioPlayback()
    @StateObject var library = LocalLibrary()
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview
    @State var path: [Destination] = []
    @State var playbackFinished = false
    @State var showToneCard = false
    @State var lastCheck: CheckSession?
    @State var lastHearing: Hearing?
    @State var lastCheckWasStereo = false
    @State var pendingCheck: SoundCheck?
    @State var milestone = false
    @State var importedPreview: SoundPreset?
    @State var importText = ""
    @State var importFailed = false
    @State var pickingFile = false
    @State var payload: SharePayload?
    @State var shareRequested = false
    @State var shareCompleted = false
    @State var shareSheetOpen = false
    @State var shareFile: URL?
    @State var pageMessage: String?
    @State var draft = SoundPreset.standard
    @State var before: CheckSession?
    @State var after: CheckSession?
    @State var recordTarget: SoundCheck = .speaker

    var selectedPreset: SoundPreset {
        let chosen = library.data.selected
        let retained = library.data.presets.contains(chosen) || library.data.imported == chosen
        return chosen.valid && (Launch.freePeriod || chosen.mode == .basic || retained) ? chosen : .standard
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Destination.self) { destination in
                    destinationView(destination)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .onAppear { shareRequested = false; pageMessage = nil }
                }
        }
        .tint(Palette.accent)
        .task { await library.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                audio.refreshRoute()
                Task { await library.load(); await library.flush() }
                requestRatingIfReady()
            } else {
                audio.stop(message: "audio.interrupted")
            }
        }
        .onChange(of: path) { _, _ in
            shareRequested = false
            pageMessage = nil
        }
        .reviewAfterCoreAction(when: reviewHome && path.isEmpty) { requestReview() }
        .onChange(of: audio.busy) { _, busy in
            if !busy && !shareRequested { requestRatingIfReady() }
        }
        .onChange(of: audio.problem) { _, problem in
            if path.isEmpty && (problem == "audio.interrupted" || problem == "audio.routeChanged") {
                playbackFinished = true
            }
        }
        .onOpenURL { url in
            guard url.isFileURL, url.pathExtension.lowercased() == "wateroutpreset" else { return }
            audio.stop()
            if path.last != .importer { openPresetImport() }
            readPreset(url)
        }
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: [UTType(exportedAs: "com.hgsldswk.waterout.preset", conformingTo: .plainText)]) { result in
            switch result {
            case .success(let url): readPreset(url)
            case .failure: reportPresetError()
            }
        }
        .sheet(item: $payload, onDismiss: {
            if let shareFile { try? FileManager.default.removeItem(at: shareFile) }
            shareFile = nil
            shareSheetOpen = false
            requestRatingIfReady()
        }) { payload in
            ShareSheet(items: payload.items) { completed in
                shareCompleted = completed
                self.payload = nil
                requestRatingIfReady()
            }
        }
    }

    private var reviewHome: Bool {
        library.ready && library.problem == nil && audio.problem == nil && !audio.busy && payload == nil && !shareSheetOpen
            && !pickingFile && !importFailed && pageMessage == nil
    }

    private func requestRatingIfReady() {
        guard shareCompleted, scenePhase == .active, reviewHome else { return }
        shareCompleted = false
        guard !Launch.testing, library.ready else { return }
        var milestones = library.data.milestones
        if CoreReview.shared.attempt(ifEligible: { milestones.claimRating(idle: true, shared: true) }, { requestReview() }) {
            library.update { $0.milestones = milestones }
        }
    }

    func playTone() {
        playbackFinished = false
        audio.start(.tone(selectedPreset)) { _ in
            playbackFinished = true
            showToneCard = true
            complete(nil, drainage: true)
        }
    }

    func runCheck(_ check: SoundCheck, side: Channel? = nil, mono: Bool = false) {
        audio.stop()
        lastCheck = nil
        lastHearing = nil
        lastCheckWasStereo = false
        let request: SoundJob = mono ? .monoSample : .check(check, side)
        audio.start(request) { conditions in
            lastCheck = CheckSession(check: check, conditions: conditions, hearing: .skip)
            lastCheckWasStereo = request.countsAsCheck == .stereo
            if let completed = request.countsAsCheck { complete(completed) }
        }
    }

    func openCheck(_ check: SoundCheck) {
        lastCheck = nil
        lastHearing = nil
        pendingCheck = check
        audio.stop()
        audio.clearProblem()
        path.append(.check(check))
    }

    func complete(_ check: SoundCheck?, drainage: Bool = false) {
        library.update { data in
            data.milestones.complete(check)
            if drainage && !Launch.testing { data.coreReviewProgress = .recording(data.coreReviewProgress) }
            if data.milestones.markChecklistShown() { milestone = true }
        }
        if drainage && !Launch.testing {
            Task { @MainActor in
                await library.flush()
                if library.problem == nil { CoreReview.shared.record(library.data.coreReviewProgress) }
            }
        }
    }

    func openPresetImport() {
        importText = ""
        importedPreview = nil
        importFailed = false
        path.append(.importer)
    }

    func choosePresetFile() {
        if Launch.testing, let code = ProcessInfo.processInfo.environment["WATEROUT_PRESET_FILE"] {
            let url = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString).appendingPathExtension("wateroutpreset")
            do {
                try Data(code.utf8).write(to: url, options: .atomic)
                readPreset(url, temporary: true)
            } catch { reportPresetError() }
        } else { pickingFile = true }
    }

    func pastePreset(_ text: String) {
        importText = text
        previewPreset()
    }

    func previewPreset() {
        importedPreview = SoundPreset.decode(importText)
        importFailed = importedPreview == nil
    }

    func readPreset(_ url: URL, temporary: Bool = false) {
        let origin = path
        Task {
            defer { if temporary { try? FileManager.default.removeItem(at: url) } }
            let value = await Task.detached { SoundPreset.readFile(url) }.value
            guard path == origin else { return }
            guard let value else { reportPresetError(); return }
            if path.last != .importer { openPresetImport() }
            pastePreset(value)
        }
    }

    private func reportPresetError() {
        importedPreview = nil
        importFailed = true
        if path.last != .importer { pageMessage = "import.invalid" }
    }

    func share(_ items: [Any], file: URL? = nil) {
        guard !audio.busy else { return }
        if Launch.testing {
            if let file { try? FileManager.default.removeItem(at: file) }
            shareRequested = true
        } else {
            shareCompleted = false
            shareSheetOpen = true
            shareFile = file
            payload = SharePayload(items: items)
        }
    }

    func exportPreset() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appendingPathExtension("wateroutpreset")
        do {
            try Data(selectedPreset.code.utf8).write(to: url, options: .atomic)
            share([url], file: url)
        } catch {
            pageMessage = "library.failed"
        }
    }

    @ViewBuilder
    func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .settings: settingsPage
        case .help: helpPage
        case .history: historyPage
        case .comparison: comparisonPage
        case .saved(let id): savedPage(id)
        case .presets: presetsPage
        case .importer: importPage
        case .card: cardPage
        case .check(let check): checkPage(check)
        }
    }

    @ViewBuilder
    var feedback: some View {
        if shareRequested {
            Text(L.t("share.requested")).font(.footnote).accessibilityIdentifier("share.requested")
        }
        if let pageMessage { Hint(L.t(pageMessage)) }
        if let problem = library.problem { Hint(L.t(problem)) }
    }
}
