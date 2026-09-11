import Foundation
import CoreGraphics

/// Geometry for a horizontally split pane.
///
/// `HSplitView` is backed by `NSSplitView`, which stores divider positions in
/// absolute points. Nested inside a `NavigationSplitView`, showing or hiding the
/// sidebar changes the detail pane's width but leaves those absolute positions
/// untouched, so the divider keeps its old screen position and the leading pane
/// ends up underneath the sidebar. Resolving the widths as a proportion of the
/// *current* container width on every layout pass removes that whole class of bug.
public struct SplitPaneLayout: Equatable, Sendable {
    public let leadingWidth: CGFloat
    public let dividerWidth: CGFloat
    public let trailingWidth: CGFloat

    public init(leadingWidth: CGFloat, dividerWidth: CGFloat, trailingWidth: CGFloat) {
        self.leadingWidth = leadingWidth
        self.dividerWidth = dividerWidth
        self.trailingWidth = trailingWidth
    }

    /// Total width the three pieces occupy. Always equal to the container width
    /// the layout was resolved against, so the panes can never overflow it.
    public var totalWidth: CGFloat {
        leadingWidth + dividerWidth + trailingWidth
    }

    public static let minimumRatio: CGFloat = 0.15
    public static let maximumRatio: CGFloat = 0.85

    /// Resolves pane widths for a container of `totalWidth`.
    ///
    /// - The leading pane takes `ratio` of the space left after the divider,
    ///   clamped so both panes keep their minimum width.
    /// - When the container is too small to honour both minimums, the available
    ///   space is divided in proportion to those minimums rather than overflowing.
    public static func resolve(
        totalWidth: CGFloat,
        ratio: CGFloat,
        dividerWidth: CGFloat = 1,
        minLeading: CGFloat = 200,
        minTrailing: CGFloat = 220
    ) -> SplitPaneLayout {
        guard totalWidth.isFinite, totalWidth > 0 else {
            return SplitPaneLayout(leadingWidth: 0, dividerWidth: 0, trailingWidth: 0)
        }

        let divider = min(max(dividerWidth, 0), totalWidth)
        let available = totalWidth - divider
        guard available > 0 else {
            return SplitPaneLayout(leadingWidth: 0, dividerWidth: divider, trailingWidth: 0)
        }

        let floorLeading = max(minLeading, 0)
        let floorTrailing = max(minTrailing, 0)

        // Container too small for both minimums: share it out proportionally so the
        // panes still add up to exactly the container width.
        if floorLeading + floorTrailing > available {
            let totalFloor = floorLeading + floorTrailing
            guard totalFloor > 0 else {
                let half = available / 2
                return SplitPaneLayout(leadingWidth: half, dividerWidth: divider, trailingWidth: available - half)
            }
            let leading = available * (floorLeading / totalFloor)
            return SplitPaneLayout(
                leadingWidth: leading,
                dividerWidth: divider,
                trailingWidth: available - leading
            )
        }

        let safeRatio = ratio.isFinite ? min(max(ratio, 0), 1) : 0.5
        let desired = available * safeRatio
        let leading = min(max(desired, floorLeading), available - floorTrailing)

        return SplitPaneLayout(
            leadingWidth: leading,
            dividerWidth: divider,
            trailingWidth: available - leading
        )
    }

    /// Ratio produced by dragging the divider so the leading pane becomes
    /// `newLeadingWidth` wide, clamped to the supported range.
    public static func ratio(
        forLeadingWidth newLeadingWidth: CGFloat,
        totalWidth: CGFloat,
        dividerWidth: CGFloat = 1
    ) -> CGFloat {
        let available = totalWidth - min(max(dividerWidth, 0), totalWidth)
        guard available > 0, newLeadingWidth.isFinite else { return minimumRatio }
        let raw = newLeadingWidth / available
        return min(max(raw, minimumRatio), maximumRatio)
    }
}
