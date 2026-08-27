import Foundation

@main
enum RemoteStatsSmoke {
    static func main() {
        let output = """
        LIGHTSSH|34.5|4|8|62|6500000|10485760|1.25|1.10|0.95|2048|1024|4096|8192
        DISK|/|204800|1024000|20
        DISK|/data|819200|1024000|80
        """

        guard let stats = RemoteStatsProvider.parse(output) else {
            fatalError("Unable to parse valid host status output.")
        }
        precondition(stats.cpuPercent == 34.5)
        precondition(stats.physicalCores == 4)
        precondition(stats.logicalCores == 8)
        precondition(stats.memoryPercent == 62)
        precondition(stats.diskReadBytesPerSecond == 4096)
        precondition(stats.diskWriteBytesPerSecond == 8192)
        precondition(stats.disks.count == 2)
        precondition(stats.disks[1].mountPoint == "/data")
        precondition(RemoteStatsProvider.parse("LIGHTSSH_UNSUPPORTED") == nil)
    }
}
