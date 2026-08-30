import SwiftUI

/// Every Liquid Glass API call in the app lives here.
///
/// Two reasons. First, feature code should read as intent — `.glassCard()`, not
/// effect plumbing. Second, this is the containment boundary that makes the
/// iOS 26 deploy target a reversible decision: supporting an older OS means
/// rewriting this file's bodies, not touching a single view.
///
/// The governing rule is Apple's: **content is opaque, chrome is glass.**
/// Glass floats above content and refracts it. Putting glass on top of more
/// glass, or text directly on glass over a busy image, destroys legibility —
/// which is the one thing a podcast app's episode list cannot afford.
extension View {

    /// A floating panel above content: the player transport, a mini player.
    func glassCard(cornerRadius: CGFloat = 26) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// A transport control that responds to touch. `.interactive()` gives the
    /// press feedback Apple's own controls have.
    func glassTransport(tinted: Bool = false, cornerRadius: CGFloat = 28) -> some View {
        glassEffect(
            tinted ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// A circular control — play, pause, skip.
    func glassCircle(tinted: Bool = false) -> some View {
        glassEffect(
            tinted ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .circle
        )
    }

    /// Lets podcast artwork bleed under the navigation bar on the detail header.
    func glassHeaderBackground() -> some View {
        backgroundExtensionEffect()
    }

    /// Softens the top scroll edge so content dissolves under the bar rather
    /// than being clipped by it.
    func softScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// Groups adjacent glass elements so they blend and morph as one shape rather
/// than as separate overlapping panes.
///
/// Wrap any cluster of glass controls in this — the transport row, for example.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}
