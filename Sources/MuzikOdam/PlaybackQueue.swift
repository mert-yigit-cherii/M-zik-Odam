import Foundation

/// A lightweight, local representation of manually scheduled tracks.
/// IDs keep the queue resilient to library metadata refreshes without copying audio or artwork.
struct PlaybackQueueState: Codable, Equatable {
    var upNextTrackIDs: [String] = []
    var historyTrackIDs: [String] = []
}
