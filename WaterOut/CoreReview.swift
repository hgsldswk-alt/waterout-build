import SwiftUI

@MainActor
final class CoreReview: ObservableObject {
    static let shared = CoreReview()

    @Published private(set) var pending = false
    private let defaults = UserDefaults.standard
    private let versionKey = "review.automaticVersion"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var canRequest: Bool {
        !(Launch.testing) && defaults.string(forKey: versionKey) != version
    }

    func record(_ storedProgress: CoreReviewProgress?) {
        if storedProgress?.isEligible == true && canRequest { pending = true }
    }

    @discardableResult
    func attempt(ifEligible: () -> Bool = { true }, _ request: () -> Void) -> Bool {
        guard canRequest, UIApplication.shared.applicationState == .active, ifEligible() else { return false }
        request()
        defaults.set(version, forKey: versionKey)
        pending = false
        return true
    }
}

@MainActor
private struct CoreReviewModifier: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var review = CoreReview.shared
    let eligible: Bool
    let request: () -> Void

    private var ready: Bool { eligible && phase == .active && review.pending }

    func body(content: Content) -> some View {
        content.task(id: ready) {
            guard ready else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, ready else { return }
            review.attempt { request() }
        }
    }
}

extension View {
    @MainActor
    func reviewAfterCoreAction(when eligible: Bool, alreadyRequested: Bool = false, _ request: @escaping () -> Void) -> some View {
        modifier(CoreReviewModifier(eligible: eligible && !alreadyRequested, request: request))
    }
}
