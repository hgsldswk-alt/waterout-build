import ActivityKit
import Foundation

struct PlaybackActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let start: Date
        let end: Date
    }
}
