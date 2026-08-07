//
//  Sizing.swift
//  FunNotch
//
//  Geometry constants and the per-display notch measurements everything else
//  is laid out against.
//

import AppKit
import SwiftUI

/// Extra room around the panel so drop shadows are not clipped.
let shadowPadding: CGFloat = 20

/// Size of the expanded notch content area. A little roomier than the
/// reference app's 640×190 so nothing crowds the rounded corners.
let openNotchSize = CGSize(width: 690, height: 216)

/// The window is always big enough to hold the open state plus shadow — on
/// every side, not just below. Without the horizontal margin the open notch is
/// drawn flush against the window edge, so its shadow is clipped to nothing and
/// the panel ends in a hard vertical seam instead of fading out.
let windowSize = CGSize(
    width: openNotchSize.width + shadowPadding * 2,
    height: openNotchSize.height + shadowPadding
)

/// Top radii are the *concave* flares where the panel meets the screen edge.
/// They read much larger than they measure, so the opened one is kept modest —
/// at 19 the panel looked scooped out at both ends.
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) =
    (opened: (top: 11, bottom: 24), closed: (top: 5, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13, closed: 4)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

let downloadSneakSize = CGSize(width: 65, height: 1)
let batterySneakSize = CGSize(width: 160, height: 1)

/// Horizontal padding used inside the expanded notch.
let contentSpacing: CGFloat = 16

extension NSScreen {
    /// A stable identifier for the display, used to remember the user's choice.
    var displayIdentifier: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return localizedName
        }
        return "\(localizedName)-\(number.uint32Value)"
    }

    /// True when the display has a physical notch cutting into the menu bar.
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    static func screen(withIdentifier identifier: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayIdentifier == identifier }
    }
}

/// Measures the collapsed notch for a given display, honouring the user's
/// height mode. Falls back to sensible values on displays without a notch.
@MainActor
func measureClosedNotch(for screen: NSScreen?) -> CGSize {
    let settings = Settings.shared
    var notchHeight: CGFloat = settings.nonNotchHeight
    var notchWidth: CGFloat = 185

    guard let screen else { return CGSize(width: notchWidth, height: notchHeight) }

    if let leftArea = screen.auxiliaryTopLeftArea?.width,
       let rightArea = screen.auxiliaryTopRightArea?.width {
        // +4 hides the hairline seam between the window and the hardware cutout.
        notchWidth = screen.frame.width - leftArea - rightArea + 4
    }

    if screen.hasPhysicalNotch {
        notchHeight = settings.notchHeight
        switch settings.notchHeightMode {
        case .matchRealNotchSize:
            notchHeight = screen.safeAreaInsets.top
        case .matchMenuBar:
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        case .custom:
            break
        }
    } else {
        notchHeight = settings.nonNotchHeight
        switch settings.nonNotchHeightMode {
        case .matchMenuBar:
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
        case .matchRealNotchSize, .custom:
            break
        }
    }

    return CGSize(
        width: notchWidth + settings.notchWidthPadding * 2,
        height: max(notchHeight, 1)
    )
}

/// The display the notch should currently live on.
@MainActor
func preferredScreen() -> NSScreen? {
    let settings = Settings.shared

    if settings.automaticallySwitchDisplay {
        // Follow the display containing the pointer, falling back to the main one.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main
    }

    if !settings.preferredScreenName.isEmpty,
       let screen = NSScreen.screen(withIdentifier: settings.preferredScreenName) {
        return screen
    }

    return NSScreen.screens.first(where: \.hasPhysicalNotch) ?? NSScreen.main
}
