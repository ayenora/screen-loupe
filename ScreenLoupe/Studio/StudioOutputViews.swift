import SwiftUI

/// The Output list beside the palette: how the studio's pictures are written — Format, Color and
/// Scale, with the choices and titles of Screenshot › Output. Shown in `StudioListPanel`, as the
/// Size list is.
struct StudioOutputList: View {
    let current: StudioOutput
    let chooseFormat: (StudioOutput.Format) -> Void
    let chooseColors: (StudioOutput.Colors) -> Void
    let chooseScale: (StudioOutput.Scale) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            StudioListLook.header("Format")
            ForEach(StudioOutput.Format.allCases, id: \.self) { format in
                StudioListRow(title: format.title, isChecked: format == current.format) { chooseFormat(format) }
            }
            StudioListLook.header("Color")
            ForEach(StudioOutput.Colors.allCases, id: \.self) { colors in
                StudioListRow(title: colors.title, isChecked: colors == current.colors) { chooseColors(colors) }
            }
            StudioListLook.header("Scale")
            ForEach(StudioOutput.Scale.allCases, id: \.self) { scale in
                StudioListRow(title: scale.title, isChecked: scale == current.scale) { chooseScale(scale) }
            }
        }
        .padding(StudioListLook.padding)
        .frame(width: 150)
    }
}
