import CoreGraphics

public struct SplitWindowFrames: Equatable, Sendable {
    public let main: CGRect
    public let attention: CGRect

    public init(main: CGRect, attention: CGRect) {
        self.main = main
        self.attention = attention
    }
}

public enum LayoutEngine {
    public static let minimumRatio = 0.45
    public static let maximumRatio = 0.78

    public static func split(
        visibleFrame: CGRect,
        mainRatio: Double,
        gap: CGFloat = 8,
        mainOnLeft: Bool = true
    ) -> SplitWindowFrames {
        let ratio = min(max(mainRatio, minimumRatio), maximumRatio)
        let safeGap = min(max(gap, 0), visibleFrame.width)
        let availableWidth = max(visibleFrame.width - safeGap, 0)
        let mainWidth = floor(availableWidth * ratio)
        let attentionWidth = availableWidth - mainWidth

        if mainOnLeft {
            let mainFrame = CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: mainWidth,
                height: visibleFrame.height
            ).integral
            let attentionFrame = CGRect(
                x: visibleFrame.minX + mainWidth + safeGap,
                y: visibleFrame.minY,
                width: attentionWidth,
                height: visibleFrame.height
            ).integral
            return SplitWindowFrames(main: mainFrame, attention: attentionFrame)
        }

        let attentionFrame = CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: attentionWidth,
            height: visibleFrame.height
        ).integral
        let mainFrame = CGRect(
            x: visibleFrame.minX + attentionWidth + safeGap,
            y: visibleFrame.minY,
            width: mainWidth,
            height: visibleFrame.height
        ).integral
        return SplitWindowFrames(main: mainFrame, attention: attentionFrame)
    }

    /// Keeps a window inside its assigned workspace zone without forcing a
    /// smaller window to fill the whole zone. A screen-sized "maximize" frame
    /// is therefore reduced to the zone, while ordinary in-zone resizing is
    /// left untouched.
    public static func constrain(_ frame: CGRect, to zone: CGRect) -> CGRect {
        guard zone.width > 0, zone.height > 0 else {
            return zone.integral
        }

        let width = min(max(frame.width, 0), zone.width)
        let height = min(max(frame.height, 0), zone.height)
        let maximumX = zone.maxX - width
        let maximumY = zone.maxY - height
        let x = min(max(frame.minX, zone.minX), maximumX)
        let y = min(max(frame.minY, zone.minY), maximumY)

        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}

public enum ScreenCoordinateMapper {
    /// Converts an AppKit screen rectangle (bottom-left origin) into the global
    /// Accessibility coordinate space (top-left origin on the menu-bar screen).
    public static func appKitToAccessibility(
        _ rect: CGRect,
        menuBarScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: menuBarScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func accessibilityToAppKit(
        _ rect: CGRect,
        menuBarScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: menuBarScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
