import Foundation

/// Files the system asks the app to open, held while the app is launching: the request for a file
/// that launched the app comes before launching has finished, when nothing is set up to take it.
struct OpenQueue {
    /// The files asked for so far while launching, in order; `nil` once launching has finished.
    private var waiting: [URL]? = []

    /// The files of a request to open now: `urls` once launching has finished, else none, and they
    /// wait for `finishLaunching()`.
    mutating func receive(_ urls: [URL]) -> [URL] {
        guard waiting != nil else { return urls }
        waiting?.append(contentsOf: urls)
        return []
    }

    /// Launching has finished: the files asked for meanwhile, in order, once. Later requests open
    /// as they come (`receive`).
    mutating func finishLaunching() -> [URL] {
        defer { waiting = nil }
        return waiting ?? []
    }
}
