import SwiftUI

struct ResourceInspectorView: View {
    let host: SSHHost
    @ObservedObject var session: SSHSession
    let isActive: Bool
    @StateObject private var provider: RemoteStatsProvider
    @ObservedObject private var appearance = AppearanceSettings.shared

    init(host: SSHHost, session: SSHSession, isActive: Bool = true) {
        self.host = host
        self.session = session
        self.isActive = isActive
        _provider = StateObject(wrappedValue: RemoteStatsProvider(host: host))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("主机状态")
                        .font(.system(size: 13, weight: .semibold))
                    Text(host.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { provider.refresh(manual: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .symbolEffect(.rotate, value: provider.isLoading)
                }
                .buttonStyle(.borderless)
                .disabled(provider.isLoading)
                .help(Text("刷新主机状态"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            OverlayScrollView {
                VStack(spacing: 12) {
                    if let stats = provider.stats {
                        // CPU & Memory Circular Indicators
                        HStack(spacing: 16) {
                            CircularMetric(
                                title: "CPU",
                                percent: stats.cpuPercent,
                                color: progressColor(stats.cpuPercent),
                                detail: stats.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "\(stats.logicalCores) Cores",
                                detailIcon: stats.cpuTemperature != nil ? "thermometer.medium" : "cpu"
                            )
                            
                            CircularMetric(
                                title: "RAM",
                                percent: stats.memoryPercent,
                                color: progressColor(stats.memoryPercent),
                                detail: "\(formatShort(stats.memoryUsedBytes))",
                                detailIcon: "memorychip"
                            )
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        // Network
                        CompactCard(title: "Network", icon: "network") {
                            VStack(spacing: 6) {
                                HStack {
                                    Label("下载", systemImage: "arrow.down")
                                    Spacer()
                                    Text("\(formatShort(stats.networkReceiveBytesPerSecond))/s")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                                HStack {
                                    Label("上传", systemImage: "arrow.up")
                                    Spacer()
                                    Text("\(formatShort(stats.networkSendBytesPerSecond))/s")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        }

                        // Disk
                        CompactCard(title: "Storage", icon: "internaldrive") {
                            VStack(spacing: 8) {
                                VStack(spacing: 6) {
                                    HStack {
                                        Label("读取", systemImage: "arrow.down.to.line")
                                        Spacer()
                                        Text("\(formatShort(stats.diskReadBytesPerSecond))/s")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    }
                                    HStack {
                                        Label("写入", systemImage: "arrow.up.to.line")
                                        Spacer()
                                        Text("\(formatShort(stats.diskWriteBytesPerSecond))/s")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                                
                                if !stats.disks.isEmpty {
                                    Divider()
                                    VStack(spacing: 6) {
                                        ForEach(Array(stats.disks.enumerated()), id: \.element.id) { index, disk in
                                            CompactDiskRow(disk: disk)
                                        }
                                    }
                                }
                            }
                        }
                    } else if !session.isConnected {
                        ContentUnavailableView(
                            "Not Connected",
                            systemImage: "network.slash",
                            description: Text("连接终端后开始监控。")
                        )
                        .frame(minHeight: 180)
                    } else if provider.isLoading {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("加载中...").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                    } else {
                        ContentUnavailableView(
                            "Status Unavailable",
                            systemImage: "chart.bar.xaxis",
                            description: Text("刷新以收集资源信息。")
                        )
                        .frame(minHeight: 180)
                    }

                    StatusFooter(
                        status: provider.status,
                        isLoading: provider.isLoading,
                        hasStats: provider.stats != nil,
                        error: provider.errorMessage
                    )
                    .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .liquidGlassPanel(enabled: appearance.usesLiquidGlassEffects, cornerRadius: 13)
        .onAppear { if isActive && session.isAuthenticated { provider.start() } }
        .onDisappear { provider.stop() }
        .onChange(of: isActive) { _, active in
            active && session.isAuthenticated ? provider.start() : provider.stop()
        }
        .onChange(of: session.isAuthenticated) { _, authenticated in
            isActive && authenticated ? provider.start() : provider.stop()
        }
        .onChange(of: session.isPasswordPrompt) { old, new in
            if old == true && new == false {
                // The user just finished entering their password.
                // Delay briefly to allow the SSH session to fully authenticate,
                // then automatically trigger a refresh to resume polling.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if isActive && provider.isPollingSuspended {
                        provider.refresh(manual: true)
                    }
                }
            }
        }
    }
    
    private func progressColor(_ value: Double) -> Color {
        value >= 90 ? .red : value >= 70 ? .orange : .accentColor
    }
}

private struct CircularMetric: View {
    let title: String
    let percent: Double
    let color: Color
    let detail: String
    let detailIcon: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 1) {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            .frame(width: 64, height: 64)
            
            Label(detail, systemImage: detailIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            content
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .opacity(appearance.usesLiquidGlassEffects ? appearance.translucentResourceCardOpacity : 0.4),
            in: shape
        )
        .conditionalGlassEffect(enabled: appearance.usesLiquidGlassEffects, shape: shape)
    }
}

private struct CompactDiskRow: View {
    let disk: RemoteDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(disk.mountPoint)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(formatShort(disk.usedBytes)) / \(formatShort(disk.totalBytes))")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(disk.percent >= 90 ? Color.red : disk.percent >= 75 ? Color.orange : Color.accentColor)
                            .frame(width: max(0, geo.size.width * (disk.percent / 100)))
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(disk.percent.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}

private struct StatusFooter: View {
    let status: String
    let isLoading: Bool
    let hasStats: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(LocalizedStringKey(status))
            } icon: {
                Image(systemName: statusIcon)
            }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)
            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if hasStats {
                Text("每 2 秒自动刷新")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIcon: String {
        if isLoading { return "arrow.clockwise" }
        return hasStats ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if isLoading { return .secondary }
        return hasStats ? .green : .orange
    }
}

private func formatShort(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(bytes))
}
