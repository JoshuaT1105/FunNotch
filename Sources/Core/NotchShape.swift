//
//  NotchShape.swift
//  FunNotch
//
//  The rounded "pill with inverted top corners" silhouette that lets the
//  window blend into the physical notch. Both radii are animatable so the
//  shape can morph as the notch opens.
//

import SwiftUI

struct NotchShape: InsettableShape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    /// How far the outline is pulled inside its frame. `strokeBorder` uses this
    /// to keep a border wholly inside the silhouette instead of straddling the
    /// edge and losing its outer half to the clip.
    private var inset: CGFloat = 0

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in fullRect: CGRect) -> Path {
        buildPath(in: fullRect, closingTheTopEdge: true)
    }

    /// The same outline with the top edge left open.
    ///
    /// The top of the panel is flush with the top of the screen, so a border
    /// stroked all the way round leaves a hairline sitting on the display's own
    /// edge — a white line above the notch with nothing on the other side of
    /// it. Everything else gets an outline; that one segment does not.
    func openTopPath(in fullRect: CGRect) -> Path {
        buildPath(in: fullRect, closingTheTopEdge: false)
    }

    private func buildPath(in fullRect: CGRect, closingTheTopEdge: Bool) -> Path {
        // Insetting the rect alone would leave the corners the wrong roundness.
        // A curve offset inward tightens where the shape bulges out and opens
        // up where it cuts in, so the convex bottom radius shrinks and the
        // concave top radius grows. That is what keeps the outline parallel to
        // the edge the whole way round rather than pinching at the corners.
        let rect = fullRect.insetBy(dx: inset, dy: inset)
        let bottomCornerRadius = max(self.bottomCornerRadius - inset, 0)
        let topCornerRadius = self.topCornerRadius + inset
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Inverted (concave) top-left corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Convex bottom-left corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Convex bottom-right corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Inverted (concave) top-right corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        if closingTheTopEdge { path.closeSubpath() }
        return path
    }
}

/// Just the outline, without the segment along the top of the screen.
struct NotchOutline: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var inset: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
            .inset(by: inset)
            .openTopPath(in: rect)
    }
}

/// A rectangle whose bottom corners only are rounded, used for HUD chips.
struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
