import SwiftUI
import UIKit

/// #30 Part 2 (OPEN_QUESTIONS R229, PROVISIONAL): a one-line text that is too long even at the readable floor, shown WHOLE by
/// the system's own marquee: a `UILabel` with `enablesMarqueeWhenAncestorFocused` (tvOS 12+), which "scrolls its text when
/// any ancestor in its view hierarchy has focus" and then ignores line-break mode and font-size fitting
/// (https://developer.apple.com/documentation/uikit/uilabel/enablesmarqueewhenancestorfocused).
///
/// The text is drawn at the floor: Caption 2, 23 pt at the default size, which is the tvOS minimum size in the HIG
/// Typography table ("tvOS 29 pt default, 23 pt minimum"; tvOS built-in text styles: Caption 2 23 pt). It follows the text
/// size of the environment (the UI-test Larger Text override included) and Bold Text. Unfocused, the label shows the start of
/// the line; whether a SwiftUI focused button counts as the label's "ancestor" is not on Apple's page and is unverified until
/// the next screenshots (56-show-long-episode-caption and -later).
struct MarqueeText: UIViewRepresentable {
    let text: String
    var secondary: Bool = false

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.enablesMarqueeWhenAncestorFocused = true
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = Self.floorFont(size: context.environment.dynamicTypeSize, bold: context.environment.legibilityWeight == .bold)
        label.textColor = secondary ? UIColor.secondaryLabel : UIColor.label
        label.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let font: UIFont = Self.floorFont(size: context.environment.dynamicTypeSize, bold: context.environment.legibilityWeight == .bold)
        let natural: CGFloat = uiView.intrinsicContentSize.width
        // #34 1: typed steps (the #29 pattern), no ternary inside `??`.
        var width: CGFloat = natural
        if let proposed = proposal.width { width = proposed }
        return CGSize(width: width, height: ceil(font.lineHeight))
    }

    /// Caption 2 (the floor) at the environment's text size, bold when Bold Text is on.
    static func floorFont(size: DynamicTypeSize, bold: Bool) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let font: UIFont = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits)
        guard bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
