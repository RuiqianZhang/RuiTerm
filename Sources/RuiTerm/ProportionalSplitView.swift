import SwiftUI

struct ProportionalSplitView<First: View, Second: View>: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    let first: () -> First
    let second: () -> Second

    @State private var fraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat? = nil
    @State private var isHovering = false
    @State private var isDragging = false

    private let paneSpacing: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let firstSize = max(0, total * fraction - paneSpacing / 2)
            let secondSize = max(0, total * (1 - fraction) - paneSpacing / 2)

            if axis == .horizontal {
                HStack(spacing: 0) {
                    first()
                        .frame(width: firstSize)
                        .clipped()

                    dividerView(geo: geo)

                    second()
                        .environment(\.titleBarDragAction, { delta, isEnded in
                            handleTitleBarDrag(delta: delta, isEnded: isEnded, total: geo.size.width)
                        })
                        .frame(width: secondSize)
                        .clipped()
                }
            } else {
                VStack(spacing: 0) {
                    first()
                        .frame(height: firstSize)
                        .clipped()

                    dividerView(geo: geo)

                    second()
                        .environment(\.titleBarDragAction, { delta, isEnded in
                            handleTitleBarDrag(delta: delta, isEnded: isEnded, total: geo.size.height)
                        })
                        .frame(height: secondSize)
                        .clipped()
                }
            }
        }
    }

    private func handleTitleBarDrag(delta: CGSize, isEnded: Bool, total: CGFloat) {
        guard total > 0 else { return }
        if isEnded {
            dragStartFraction = nil
            return
        }
        if dragStartFraction == nil {
            dragStartFraction = fraction
        }
        let deltaValue = axis == .horizontal ? delta.width : delta.height
        let newFraction = dragStartFraction! + (deltaValue / total)
        let minLength: CGFloat = axis == .horizontal ? 100 : 80
        let available = total - paneSpacing
        if available > minLength * 2 {
            fraction = max(minLength / available, min(1 - minLength / available, newFraction))
        }
    }

    @ViewBuilder
    private func dividerView(geo: GeometryProxy) -> some View {
        ZStack {
            if isDragging || isHovering {
                Rectangle()
                    .fill(isDragging ? Color.accentColor.opacity(0.6) : Color.accentColor.opacity(0.35))
                    .frame(
                        width: axis == .horizontal ? 2 : nil,
                        height: axis == .vertical ? 2 : nil
                    )
            }
        }
        .frame(
            width: axis == .horizontal ? paneSpacing : nil,
            height: axis == .vertical ? paneSpacing : nil
        )
        .contentShape(Rectangle().inset(by: -4))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
            if hovering {
                if axis == .horizontal {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .local)
                .onChanged { value in
                    if dragStartFraction == nil {
                        dragStartFraction = fraction
                        isDragging = true
                    }
                    let delta = axis == .horizontal ? value.translation.width : value.translation.height
                    let total = axis == .horizontal ? geo.size.width : geo.size.height
                    guard total > 0 else { return }

                    let newFraction = dragStartFraction! + (delta / total)
                    
                    let minLength: CGFloat = axis == .horizontal ? 100 : 80
                    let available = total - paneSpacing
                    if available > minLength * 2 {
                        let minFraction = minLength / available
                        let maxFraction = 1.0 - minFraction
                        fraction = max(minFraction, min(maxFraction, newFraction))
                    } else {
                        // Limit to available bounds gracefully
                        fraction = max(0.1, min(0.9, newFraction))
                    }
                }
                .onEnded { _ in
                    dragStartFraction = nil
                    isDragging = false
                    if !isHovering {
                        NSCursor.pop()
                    }
                }
        )
    }
}
