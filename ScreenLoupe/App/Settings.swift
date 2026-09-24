import Foundation

/// State kept between launches (TASK.md §20). The Viewer frame is kept by AppKit through its
/// autosave name; everything else lives here.
struct Settings: Codable, Equatable {
    /// Capture Area in AppKit global coordinates.
    var captureArea: CGRect?
}

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "settings"

    private(set) var settings: Settings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: key)
        }
    }
}
