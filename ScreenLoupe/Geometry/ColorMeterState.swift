import Foundation

/// A colour the Color Meter keeps — in Recent, as a favourite, or in a contrast slot — as it was read
/// from the image: every component of its sample, so each format shows exactly what the live pixel
/// showed, and its position.
struct PickedColor: Codable, Equatable, Sendable {
    var hex: String
    var nativeValues: String
    var nativeSpaceName: String
    /// Where it was picked, in Capture Area pixels.
    var x: Int
    var y: Int
    /// The sample's components 0...1: native and sRGB red, green and blue, and the opacity. `nil`
    /// for a colour saved before they were kept, which has only its HEX.
    var native: [Double]?
    var srgb: [Double]?
    var alpha: Double?

    /// The sample it was picked from; from the HEX for a colour saved without its components.
    var sample: ColorSample {
        guard let native, let srgb, let alpha, native.count == 3, srgb.count == 3 else {
            return ColorSample(srgbHex: hex)
        }
        return ColorSample(
            native: (native[0], native[1], native[2]), nativeSpaceName: nativeSpaceName,
            srgb: (srgb[0], srgb[1], srgb[2]), alpha: alpha)
    }

    /// Unreadable components cost only the exactness: the colour then comes back from its HEX.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = try c.decode(String.self, forKey: .hex)
        nativeValues = try c.decode(String.self, forKey: .nativeValues)
        nativeSpaceName = try c.decode(String.self, forKey: .nativeSpaceName)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        native = c.value(.native, or: nil)
        srgb = c.value(.srgb, or: nil)
        alpha = c.value(.alpha, or: nil)
    }
}

extension PickedColor {
    init(
        hex: String, nativeValues: String, nativeSpaceName: String, x: Int, y: Int, native: [Double]? = nil,
        srgb: [Double]? = nil, alpha: Double? = nil
    ) {
        self.hex = hex
        self.nativeValues = nativeValues
        self.nativeSpaceName = nativeSpaceName
        self.x = x
        self.y = y
        self.native = native
        self.srgb = srgb
        self.alpha = alpha
    }

    init(_ sample: ColorSample, x: Int, y: Int) {
        self.init(
            hex: sample.hex, nativeValues: sample.nativeValues, nativeSpaceName: sample.nativeSpaceName, x: x, y: y,
            native: [sample.native.red, sample.native.green, sample.native.blue],
            srgb: [sample.srgb.red, sample.srgb.green, sample.srgb.blue], alpha: sample.alpha)
    }
}

extension ColorSample {
    /// A sample from its components as kept.
    init(
        native: (red: Double, green: Double, blue: Double), nativeSpaceName: String,
        srgb: (red: Double, green: Double, blue: Double), alpha: Double
    ) {
        self.native = native
        self.nativeSpaceName = nativeSpaceName
        self.srgb = srgb
        self.alpha = alpha
    }
}

/// The favourites and the contrast pair, kept between launches. Recent is kept apart, as it was
/// before these existed.
struct SavedMeterColors: Codable, Equatable {
    /// Exactly `ColorMeterState.favoriteCount` slots, `nil` where empty.
    var favorites: [PickedColor?] = Array(repeating: nil, count: ColorMeterState.favoriteCount)
    var text: PickedColor?
    var background: PickedColor?

    init() {}

    /// An unreadable slot is empty, and missing slots are added or extra ones dropped, so one bad
    /// value costs that slot alone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let slots = c.value(.favorites, or: [Lenient<PickedColor>?]()).map { $0?.value }
        let count = ColorMeterState.favoriteCount
        favorites = Array(slots.prefix(count)) + Array(repeating: nil, count: max(0, count - slots.count))
        text = c.value(.text, or: nil)
        background = c.value(.background, or: nil)
    }
}

/// The Color Meter's colours besides the live pixel, and where the next one goes.
///
/// One colour is in focus: the live pixel, or a recent, favourite or contrast colour clicked in the
/// panel. One element at most is the target, the Text or Background slot or a favourite; a click on
/// the image, and a recent colour clicked while there is a target, go to it. Without a target a click
/// on the image only adds to Recent.
struct ColorMeterState: Equatable {
    enum Slot: Equatable, CaseIterable {
        case text, background

        var title: String { self == .text ? "Text" : "Background" }
    }

    enum Target: Equatable {
        case contrast(Slot)
        case favorite(Int)
    }

    enum Focus: Equatable {
        case live
        case recent(Int)
        case favorite(Int)
        case contrast(Slot)
    }

    static let recentLimit = 8
    static let favoriteCount = 8

    /// Newest first.
    private(set) var recent: [PickedColor]
    private(set) var favorites: [PickedColor?]
    private(set) var text: PickedColor?
    private(set) var background: PickedColor?
    private(set) var target: Target?
    private(set) var focus = Focus.live

    init(recent: [PickedColor] = [], saved: SavedMeterColors = SavedMeterColors()) {
        // An older version kept more; the newest stay.
        self.recent = Array(recent.prefix(Self.recentLimit))
        favorites = saved.favorites
        text = saved.text
        background = saved.background
    }

    var saved: SavedMeterColors {
        var saved = SavedMeterColors()
        saved.favorites = favorites
        saved.text = text
        saved.background = background
        return saved
    }

    subscript(slot: Slot) -> PickedColor? {
        get { slot == .text ? text : background }
        set {
            if slot == .text { text = newValue } else { background = newValue }
        }
    }

    /// The colour in focus, `nil` for the live pixel.
    var focused: PickedColor? {
        switch focus {
        case .live: nil
        case .recent(let index): recent[index]
        case .favorite(let index): favorites[index]
        case .contrast(let slot): self[slot]
        }
    }

    /// The line under the verdicts that says where colours go.
    var hint: String {
        switch target {
        case nil: "Click Text or Background, then click colours for it."
        case .contrast(let slot)?: "Clicks, recent and favourite colours fill \(slot.title). Click it again to stop."
        case .favorite(let index)?: "The next click or recent colour goes into favourite \(index + 1)."
        }
    }

    // MARK: Clicks

    /// A click on the image. A targeted favourite takes the colour and stops being the target, and
    /// Recent, the history of plain picks, doesn't get it: it was saved on purpose. Otherwise the
    /// colour goes to Recent, and to Text or Background when that is the target, which stays it.
    mutating func pick(_ color: PickedColor) {
        if case .favorite? = target { return fillTarget(with: color) }
        recent.insert(color, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        if case .recent(let index) = focus {
            focus = index + 1 < recent.count ? .recent(index + 1) : .live
        }
        fillTarget(with: color)
    }

    /// A click on a Recent row: it comes into focus, and fills the target if there is one.
    mutating func clickRecent(_ index: Int) {
        guard recent.indices.contains(index) else { return }
        focus = .recent(index)
        fillTarget(with: recent[index])
    }

    /// A click on a favourite: with Text or Background the target, a filled one fills it; otherwise
    /// it becomes the target, or stops being it. A filled one comes into focus.
    mutating func clickFavorite(_ index: Int) {
        guard favorites.indices.contains(index) else { return }
        let color = favorites[index]
        if case .contrast(let slot)? = target, let color {
            self[slot] = color
        } else {
            target = target == .favorite(index) ? nil : .favorite(index)
        }
        if color != nil { focus = .favorite(index) }
    }

    /// A click on Text or Background: it becomes the target, or stops being it, and a filled one
    /// comes into focus.
    mutating func clickContrast(_ slot: Slot) {
        target = target == .contrast(slot) ? nil : .contrast(slot)
        if self[slot] != nil { focus = .contrast(slot) }
    }

    /// Swaps the colours of Text and Background. The target stays on its slot; the focus stays on
    /// its colour.
    mutating func swap() {
        (text, background) = (background, text)
        if case .contrast(let slot) = focus { focus = .contrast(slot == .text ? .background : .text) }
    }

    /// Escape: drops the target. `false` when there was none.
    mutating func clearTarget() -> Bool {
        guard target != nil else { return false }
        target = nil
        return true
    }

    /// The pointer moved over the image — in the Viewer, or inside the Capture Area: the live pixel
    /// comes back into focus. `false` when it already was.
    mutating func pointerMovedOverImage() -> Bool {
        guard focus != .live else { return false }
        focus = .live
        return true
    }

    private mutating func fillTarget(with color: PickedColor) {
        switch target {
        case nil: break
        case .contrast(let slot)?: self[slot] = color
        case .favorite(let index)?:
            favorites[index] = color
            target = nil
        }
    }

    // MARK: Editing

    mutating func removeRecent(_ index: Int) {
        guard recent.indices.contains(index) else { return }
        recent.remove(at: index)
        if case .recent(let focused) = focus {
            if focused == index {
                focus = .live
            } else if focused > index {
                focus = .recent(focused - 1)
            }
        }
    }

    mutating func clearRecent() {
        recent.removeAll()
        if case .recent = focus { focus = .live }
    }

    /// Puts a recent colour into the first empty favourite. `false` when all are full.
    mutating func addToFavorites(recent index: Int) -> Bool {
        guard recent.indices.contains(index), let slot = favorites.firstIndex(where: { $0 == nil }) else {
            return false
        }
        favorites[slot] = recent[index]
        return true
    }

    /// Empties a favourite. It stays the target if it was, to be filled again; in focus, it gives
    /// the focus back to the live pixel.
    mutating func removeFavorite(_ index: Int) {
        guard favorites.indices.contains(index) else { return }
        favorites[index] = nil
        if focus == .favorite(index) { focus = .live }
    }
}
