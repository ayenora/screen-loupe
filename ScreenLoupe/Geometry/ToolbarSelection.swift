/// The Viewer toolbar's select-any control — the side panels — whose segments show their model's
/// state. A click flips one segment before the toolbar hears of it; the model then decides, and
/// every segment shows it again.
enum ToolbarSelection {
    /// The segment a click flipped: the first whose shown state differs from its model's. `nil`
    /// when they all agree.
    static func clicked(shown: [Bool], model: [Bool]) -> Int? {
        zip(shown, model).enumerated().first { $0.element.0 != $0.element.1 }?.offset
    }
}
