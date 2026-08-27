import Foundation

@main
enum LocalStatsSmoke {
    @MainActor
    static func main() async {
        let provider = RemoteStatsProvider(host: .localTerminal)
        provider.start()
        try? await Task.sleep(for: .seconds(5))
        provider.stop()

        guard let stats = provider.stats else {
            fatalError(provider.errorMessage ?? "Local host status did not load.")
        }
        precondition(stats.physicalCores > 0)
        precondition(stats.logicalCores >= stats.physicalCores)
        precondition(stats.memoryTotalBytes > 0)
        precondition(!stats.disks.isEmpty)
    }
}
