import CoreGraphics
import Testing
@testable import DesktopCanvasCore

@Suite("Layout engine")
struct LayoutEngineTests {
    @Test("70:30 split preserves the visible frame")
    func splitPreservesBounds() {
        let visibleFrame = CGRect(x: 0, y: 24, width: 1_000, height: 776)
        let frames = LayoutEngine.split(
            visibleFrame: visibleFrame,
            mainRatio: 0.70,
            gap: 8
        )

        #expect(frames.main.minX == visibleFrame.minX)
        #expect(frames.attention.maxX == visibleFrame.maxX)
        #expect(frames.main.height == visibleFrame.height)
        #expect(frames.attention.height == visibleFrame.height)
        #expect(frames.attention.minX - frames.main.maxX == 8)
    }

    @Test("Ratios are clamped to the supported range")
    func ratioIsClamped() {
        let visibleFrame = CGRect(x: 100, y: 40, width: 1_200, height: 800)
        let maximum = LayoutEngine.split(visibleFrame: visibleFrame, mainRatio: 0.95)
        let expected = LayoutEngine.split(
            visibleFrame: visibleFrame,
            mainRatio: LayoutEngine.maximumRatio
        )

        #expect(maximum == expected)
    }

    @Test("Physical sides can swap without changing logical sizes")
    func sidesCanSwap() {
        let visibleFrame = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        let left = LayoutEngine.split(
            visibleFrame: visibleFrame,
            mainRatio: 0.70,
            mainOnLeft: true
        )
        let right = LayoutEngine.split(
            visibleFrame: visibleFrame,
            mainRatio: 0.70,
            mainOnLeft: false
        )

        #expect(left.main.width == right.main.width)
        #expect(left.attention.width == right.attention.width)
        #expect(right.attention.minX == visibleFrame.minX)
    }

    @Test("AppKit and Accessibility coordinate conversion round trips")
    func coordinateConversionRoundTrips() {
        let menuBarScreen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let appKitRect = CGRect(x: 40, y: 24, width: 900, height: 700)

        let accessibilityRect = ScreenCoordinateMapper.appKitToAccessibility(
            appKitRect,
            menuBarScreenFrame: menuBarScreen
        )
        let roundTrip = ScreenCoordinateMapper.accessibilityToAppKit(
            accessibilityRect,
            menuBarScreenFrame: menuBarScreen
        )

        #expect(accessibilityRect.minY == 176)
        #expect(roundTrip == appKitRect)
    }

    @Test("A maximized window is reduced to its assigned zone")
    func maximizedWindowIsConstrained() {
        let wholeScreen = CGRect(x: 0, y: 24, width: 1_440, height: 876)
        let mainZone = CGRect(x: 0, y: 24, width: 1_000, height: 876)

        #expect(LayoutEngine.constrain(wholeScreen, to: mainZone) == mainZone)
    }

    @Test("A smaller window can remain anywhere inside its zone")
    func smallerWindowInsideZoneIsUntouched() {
        let zone = CGRect(x: 0, y: 24, width: 1_000, height: 876)
        let smallerWindow = CGRect(x: 120, y: 100, width: 720, height: 560)

        #expect(LayoutEngine.constrain(smallerWindow, to: zone) == smallerWindow)
    }

    @Test("A smaller window is moved back when it crosses a zone edge")
    func smallerWindowIsKeptInsideZone() {
        let zone = CGRect(x: 1_008, y: 24, width: 432, height: 876)
        let crossingWindow = CGRect(x: 900, y: 10, width: 360, height: 500)
        let constrained = LayoutEngine.constrain(crossingWindow, to: zone)

        #expect(constrained.origin == CGPoint(x: 1_008, y: 24))
        #expect(constrained.size == crossingWindow.size)
    }
}
