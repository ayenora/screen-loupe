import CoreGraphics
import Testing

struct SquareOutlineTests {
    @Test(arguments: [
        // 100 % and 200 % on a 2× display, 100 % and 300 % on a 1× one: the square alone.
        (CGFloat(0.5), false), (1, false), (3, false), (3.99, false),
        // From 4 pt on: 400 % on a 1× display, 800 % on a 2× one, and up.
        (4, true), (8, true), (64, true),
    ])
    func thePointedPixelIsOutlinedOnlyWhenLargeEnough(side: CGFloat, outlined: Bool) {
        #expect(SquareOutline.outlinesPixel(side: side) == outlined)
    }
}
