import SwiftUI

struct TransferButtonView: View {
    @ObservedObject var manager = SFTPTransferManager.shared

    private var popoverBinding: Binding<Bool> {
        Binding(
            get: { manager.isPopoverPresented },
            set: { manager.setPopoverPresented($0) }
        )
    }
    
    var body: some View {
        Button {
            manager.togglePopoverByUser()
        } label: {
            ZStack {
                if manager.activeTasks.isEmpty {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                        .frame(width: 18, height: 18)
                    Circle()
                        .trim(from: 0, to: manager.globalProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .help(Text("传输"))
        .popover(isPresented: popoverBinding, arrowEdge: .bottom) {
            TransferPopoverView()
        }
    }
}

struct TransferPopoverView: View {
    @ObservedObject var manager = SFTPTransferManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("传输")
                        .font(.headline)
                    transferSummary
                }
                Spacer()
                if !manager.tasks.isEmpty {
                    Button("清空全部") {
                        manager.tasks.removeAll(where: {
                            if case .pending = $0.status { return false }
                            if case .transferring = $0.status { return false }
                            return true
                        })
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider()
            
            if manager.tasks.isEmpty {
                Text("没有最近的传输")
                    .foregroundColor(.secondary)
                    .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(manager.tasks.enumerated()), id: \.element.id) { index, task in
                            TransferTaskRow(task: task)
                            if index < manager.tasks.count - 1 {
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: transferListHeight)
            }
        }
        .frame(width: 420)
    }

    @ViewBuilder
    private var transferSummary: some View {
        if manager.activeTasks.isEmpty {
            Text("\(manager.tasks.count) 个最近传输")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(manager.activeTasks.count) 个正在传输")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var transferListHeight: CGFloat {
        let rowsHeight = manager.tasks.reduce(CGFloat.zero) { height, task in
            switch task.status {
            case .pending, .success:
                return height + 68
            case .transferring, .failed:
                return height + 90
            }
        }
        return min(420, max(88, rowsHeight + 8))
    }
}

private struct TransferTaskRow: View {
    let task: TransferTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(directionColor.opacity(0.14))
                Image(systemName: task.type == .upload ? "arrow.up" : "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(directionColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 78)

                if case .transferring(let progress) = task.status {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                pathRow(label: "From", value: task.sourceDescription)
                pathRow(label: "To", value: task.destinationDescription)

                if case .failed(let error) = task.status {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .center, spacing: 2) {
                    statusLabel
                    if let endTime = task.endTime {
                        Text(endTime, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 64, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var directionColor: Color {
        task.type == .upload ? .blue : .green
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch task.status {
        case .pending:
            statusBadge("Waiting", color: .secondary)
        case .transferring:
            statusBadge("Transferring", color: .accentColor)
        case .success:
            statusBadge("Completed", color: .green)
        case .failed:
            statusBadge("Failed", color: .red)
        }
    }

    private func statusBadge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func pathRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }
}
