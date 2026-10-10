/// The Copy Text mode's rules: when it is on, who froze the live view, and what each event asks the
/// Viewer to do. The mode always works on a still picture: turned on over the live view it freezes
/// it, and leaving unfreezes only a freeze of its own. The Viewer drives it and carries out the
/// steps it returns, in order.
struct CopyTextMode: Equatable, Sendable {
    /// What the Viewer shows: the live view, or a still picture (a frozen frame, a recent capture,
    /// an opened image).
    enum Picture: Equatable, Sendable {
        case live
        case still
    }

    enum Step: Equatable, Sendable {
        /// Turn the Select tool off, which drops its selection.
        case turnOffSelect
        /// Freeze the live view.
        case freeze
        /// Resume the live view.
        case unfreeze
        /// Put the text layer over the picture and read the text of what shows.
        case showText
        /// Take the text layer away and stop reading.
        case hideText
        /// Drop the text selection.
        case clearTextSelection
        /// Nothing to freeze: the mode stays off.
        case beep
    }

    private(set) var isOn = false
    /// Whether turning the mode on froze the live view.
    private(set) var frozeLive = false

    /// Turns the mode on over `picture`, the Select tool off, and freezes the live view. When the
    /// live view can't be frozen (no frame yet) the mode stays off.
    mutating func turnOn(over picture: Picture, canFreeze: Bool, selectIsOn: Bool) -> [Step] {
        guard !isOn else { return [] }
        if picture == .live, !canFreeze { return [.beep] }
        isOn = true
        frozeLive = picture == .live
        return (selectIsOn ? [.turnOffSelect] : []) + (frozeLive ? [.freeze] : []) + [.showText]
    }

    /// Leaves the mode, resuming the live view only when the mode froze it.
    mutating func turnOff() -> [Step] {
        guard isOn else { return [] }
        let unfreezes = frozeLive
        isOn = false
        frozeLive = false
        return [.hideText] + (unfreezes ? [.unfreeze] : [])
    }

    /// The toolbar button and View › Copy Text.
    mutating func toggle(over picture: Picture, canFreeze: Bool, selectIsOn: Bool) -> [Step] {
        isOn ? turnOff() : turnOn(over: picture, canFreeze: canFreeze, selectIsOn: selectIsOn)
    }

    /// The Select tool came on: the two are never on together. The picture stays as it is: a
    /// freeze of the mode's becomes an ordinary one, which leaving Select doesn't resume.
    mutating func selectTurnedOn() -> [Step] {
        guard isOn else { return [] }
        isOn = false
        frozeLive = false
        return [.hideText]
    }

    /// Another picture shows, or the live view was frozen or resumed. A still one is read again; the
    /// live view, which the mode never works on, ends it, with nothing left to unfreeze.
    mutating func pictureChanged(to picture: Picture) -> [Step] {
        guard isOn else { return [] }
        guard picture == .live else { return [.showText] }
        isOn = false
        frozeLive = false
        return [.hideText]
    }

    /// Space while the mode is on leaves it and goes back to live, as Space resumes from Freeze:
    /// `showsFrozenLive` says the picture is the live view frozen, by the mode or before it. Over a
    /// recent capture it only leaves (and resumes a freeze of its own under the capture). `nil`
    /// while the mode is off: Space does what it does without it.
    mutating func space(showsFrozenLive: Bool) -> [Step]? {
        guard isOn else { return nil }
        let steps = turnOff()
        return showsFrozenLive && !steps.contains(.unfreeze) ? steps + [.unfreeze] : steps
    }

    /// Escape drops the text selection first, then leaves the mode. `nil` while the mode is off:
    /// Escape does what it does without it.
    mutating func escape(hasTextSelection: Bool) -> [Step]? {
        guard isOn else { return nil }
        return hasTextSelection ? [.clearTextSelection] : turnOff()
    }
}
