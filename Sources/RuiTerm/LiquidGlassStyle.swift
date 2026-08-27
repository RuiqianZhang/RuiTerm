import SwiftUI

struct LiquidGlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: Rectangle())
                .overlay {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(backdropTintOpacity))
                }

            LinearGradient(
                colors: [
                    .white.opacity(colorScheme == .dark ? 0.035 : 0.07),
                    .clear,
                    .black.opacity(colorScheme == .dark ? 0.045 : 0.01),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.07 : 0.11), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 560
            )

            RadialGradient(
                colors: [Color.blue.opacity(colorScheme == .dark ? 0.025 : 0.04), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 640
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.42))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.14))
                .frame(height: 1)
        }
        .allowsHitTesting(false)
    }

    private var backdropTintOpacity: Double {
        guard appearance.usesLiquidGlassEffects else {
            return colorScheme == .dark ? 0.92 : 0.96
        }
        if appearance.isFullGlassMode {
            return colorScheme == .dark ? 0.22 : 0.32
        }
        return colorScheme == .dark ? 0.36 : 0.50
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearance = AppearanceSettings.shared

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if enabled && appearance.isFullGlassMode {
            content
                .background {
                    shape
                        .fill(.clear)
                        .glassEffect(.clear, in: shape)
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.035 : 0.09),
                                        Color(nsColor: .windowBackgroundColor).opacity(panelTintOpacity),
                                        Color.blue.opacity(colorScheme == .dark ? 0.014 : 0.022),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                }
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.34 : 0.72),
                                .white.opacity(colorScheme == .dark ? 0.10 : 0.24),
                                .black.opacity(colorScheme == .dark ? 0.24 : 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .overlay {
                    shape
                        .inset(by: 1)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.07 : 0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.09), radius: 18, y: 8)
                .clipShape(shape)
        } else if !appearance.reduceLiquidGlassEffects {
            content
                .glassEffect(.regular, in: shape)
                .clipShape(shape)
        } else {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay {
                    shape.stroke(.separator.opacity(0.55), lineWidth: 1)
                }
                .clipShape(shape)
        }
    }

    private var panelTintOpacity: Double {
        if appearance.isFullGlassMode {
            return colorScheme == .dark ? 0.16 : 0.24
        }
        return colorScheme == .dark ? 0.34 : 0.50
    }
}

extension View {
    func liquidGlassPanel(enabled: Bool, cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassPanelModifier(enabled: enabled, cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func conditionalGlassEffect<S: Shape>(enabled: Bool, shape: S) -> some View {
        if enabled {
            glassEffect(.regular, in: shape)
        } else {
            self
        }
    }
}
