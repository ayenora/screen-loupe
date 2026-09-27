import CoreGraphics
import Testing

struct WindowLevelsTests {
    private func level(_ key: CGWindowLevelKey) -> Int { Int(CGWindowLevelForKey(key)) }

    @Test func framesAreAtTheStatusWindowLevel() {
        #expect(WindowLevels.frames == level(.statusWindow))
    }

    @Test func thePaletteIsAboveTheFramesAndThePicker() {
        #expect(WindowLevels.picker > WindowLevels.frames)
        #expect(WindowLevels.studioPalette > WindowLevels.picker)
    }

    /// Above a Viewer kept on top (floating), ordinary and modal windows, and the main menu, the Dock
    /// and a full-screen app's windows.
    @Test func thePaletteIsAboveOtherAppsAndTheViewer() {
        for key in [
            CGWindowLevelKey.normalWindow, .floatingWindow, .tornOffMenuWindow, .modalPanelWindow, .dockWindow,
            .mainMenuWindow, .statusWindow, .utilityWindow,
        ] {
            #expect(WindowLevels.studioPalette > level(key), "\(key)")
        }
    }

    /// Menus, the pointer and the screen saver stay above it.
    @Test func menusStayAboveThePalette() {
        #expect(WindowLevels.studioPalette < level(.popUpMenuWindow))
        #expect(WindowLevels.studioPalette < level(.screenSaverWindow))
        #expect(WindowLevels.studioPalette < level(.cursorWindow))
    }
}
