import Combine
import Foundation

struct LibraryData: Codable {
    var coreReviewProgress: CoreReviewProgress?
    var comparisons: [ListeningComparison] = []
    var presets: [SoundPreset] = []
    var imported: SoundPreset?
    var selected = SoundPreset.standard
    var milestones = Milestones()
}

private actor LibraryFile {
    private var lastRevision = 0
    private let url: URL

    init(testing: Bool) {
        url = URL.applicationSupportDirectory.appending(path: testing ? "WaterOut-Test.json" : "WaterOut-v1.json")
    }

    func read() throws -> LibraryData {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryData() }
        return try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: url))
    }

    func save(_ data: LibraryData, revision: Int) throws {
        guard revision > lastRevision else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
        lastRevision = revision
    }
}

@MainActor
final class LocalLibrary: ObservableObject {
    @Published private(set) var data = LibraryData()
    @Published private(set) var ready = false
    @Published private(set) var problem: String?
    private let file = LibraryFile(testing: Launch.testing)
    private let resetTest = Launch.testing && Launch.arguments.contains("-reset")
    private var loading = false
    private var revision = 0
    private var pendingWrite = false

    init() {
        if resetTest {
            if Launch.arguments.contains("-seed-history") {
                data.comparisons = [.example]
                data.presets = [SoundPreset(mode: .sweep, seconds: 10)]
            }
            if Launch.arguments.contains("-seed-milestone") {
                for check in SoundCheck.allCases { data.milestones.complete(check) }
            }
            ready = true
        }
    }

    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            data = try await file.read()
            ready = true
        } catch {
            problem = "library.failed"
        }
    }

    func update(_ change: (inout LibraryData) -> Void) {
        guard ready else { return }
        change(&data)
        if resetTest { return }
        revision += 1
        pendingWrite = true
        Task { await flush() }
    }

    func flush() async {
        guard pendingWrite else { return }
        let saving = revision
        do {
            try await file.save(data, revision: saving)
            if revision == saving {
                pendingWrite = false
                problem = nil
            }
        } catch {
            if revision == saving { problem = "library.failed" }
        }
    }
}
