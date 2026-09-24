import Foundation

/// State kept between launches (TASK.md §20). The Viewer frame is kept by AppKit through its
/// autosave name; everything else lives here.
struct Settings: Codable, Equatable {
    /// Capture Area in AppKit global coordinates.
    var captureArea: CGRect?
    /// Keep the Viewer above the windows of other apps.
    var viewerAlwaysOnTop = false

    init() {}

    /// Keys missing from settings saved by an older version keep their defaults instead of failing
    /// the whole decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureArea = try container.decodeIfPresent(CGRect.self, forKey: .captureArea)
        viewerAlwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .viewerAlwaysOnTop) ?? false
    }
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
