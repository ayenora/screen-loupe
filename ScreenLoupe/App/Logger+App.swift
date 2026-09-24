import OSLog

extension Logger {
    /// The app's log subsystem, also the prefix of its dispatch queue labels.
    static let subsystem = "com.ayenora.screenloupe"

    init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}
