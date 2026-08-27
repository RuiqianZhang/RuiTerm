import Foundation

struct RemoteStats: Equatable {
    var cpuPercent: Double
    var physicalCores: Int
    var logicalCores: Int
    var load1: Double
    var load5: Double
    var load15: Double
    var networkReceiveBytesPerSecond: Double
    var networkSendBytesPerSecond: Double
    var diskReadBytesPerSecond: Double
    var diskWriteBytesPerSecond: Double
    var memoryPercent: Double
    var memoryUsedBytes: Double
    var memoryTotalBytes: Double
    var cpuTemperature: Double?
    var disks: [RemoteDisk]
}

struct RemoteDisk: Equatable, Identifiable {
    var id: String { mountPoint }
    var mountPoint: String
    var usedBytes: Double
    var totalBytes: Double
    var percent: Double
}

enum RemoteStatsCollectionMode {
    case full
    case toolbar
}

@MainActor
final class RemoteStatsProvider: ObservableObject {
    @Published private(set) var stats: RemoteStats?
    @Published private(set) var isLoading = false
    @Published private(set) var status = "Waiting"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPollingSuspended = false

    private let host: SSHHost
    private let pollingInterval: TimeInterval
    private let controlPath: String?
    private let collectionMode: RemoteStatsCollectionMode
    private var timer: Timer?
    private var process: Process?
    private var refreshTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var initialRefreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var timedOut = false

    init(
        host: SSHHost,
        pollingInterval: TimeInterval = 2,
        controlPath: String? = nil,
        collectionMode: RemoteStatsCollectionMode = .full
    ) {
        self.host = host
        self.pollingInterval = pollingInterval
        self.controlPath = controlPath
        self.collectionMode = collectionMode
    }

    func start() {
        guard timer == nil, !isPollingSuspended else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPollingSuspended {
                    self.refresh()
                }
            }
        }
        timer.tolerance = min(0.5, pollingInterval * 0.2)
        self.timer = timer

        // Wait briefly before the first refresh to allow the main SSH session to establish
        initialRefreshTask?.cancel()
        initialRefreshTask = Task { [weak self] in
            let delay: Duration = self?.collectionMode == .toolbar ? .milliseconds(50) : .milliseconds(300)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.initialRefreshTask = nil
            if !self.isPollingSuspended {
                self.refresh()
            }
        }
    }
    
    func suspendPolling() {
        isPollingSuspended = true
        timer?.invalidate()
        timer = nil
    }

    func resumePolling() {
        if isPollingSuspended {
            isPollingSuspended = false
            start()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeRefreshID = nil
        let runningProcess = process
        process = nil
        runningProcess?.terminate()
        refreshTask?.cancel()
        refreshTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
        isLoading = false
        timedOut = false
    }

    func refresh(manual: Bool = false) {
        if manual {
            resumePolling()
            if timer == nil { start() }
        }
        guard process == nil, refreshTask == nil, activeRefreshID == nil else { return }
        // Keep automatic refreshes quiet once data is visible. Publishing the
        // loading state for every poll needlessly redraws the glass panel.
        if manual || stats == nil {
            isLoading = true
            status = "Loading"
            errorMessage = nil
        }
        timedOut = false
        refreshTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else {
                isLoading = false
                refreshTask = nil
                return
            }
            refreshTask = nil
            launchRefresh()
        }
    }

    private func launchRefresh() {
        let refreshID = UUID()
        activeRefreshID = refreshID
        let task = Process()
        let output = Pipe()
        let error = Pipe()
        let command = commandForCollectionMode
        if host.isLocal {
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-lc", command]
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            task.arguments = sshArguments(command: command)
        }
        task.standardOutput = output
        task.standardError = error
        task.standardInput = FileHandle.nullDevice
        task.terminationHandler = { [weak self] task in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            Task { @MainActor in
                guard let self, self.activeRefreshID == refreshID else { return }
                self.activeRefreshID = nil
                self.process = nil
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.isLoading = false
                if let parsed = Self.parse(text) {
                    self.stats = parsed
                    self.status = task.terminationStatus == 0 ? "Updated now" : "Updated with partial disk data"
                    self.errorMessage = task.terminationStatus == 0
                        ? nil
                        : "One or more mounted filesystems did not respond."
                } else {
                    self.status = "Unable to load"
                    if !self.timedOut {
                        self.errorMessage = Self.readableError(errorText, output: text)
                        // Only explicit authentication failures should stop
                        // polling. A cancelled refresh, transient socket race,
                        // or empty response should be retried on the next tick.
                        if Self.isAuthenticationError(errorText) {
                            self.suspendPolling()
                            self.errorMessage = "Authentication failed. Connect first, then refresh manually."
                        }
                    }
                    if let data = "OUTPUT:\n\(text)\nERROR:\n\(errorText)".data(using: .utf8) {
                        try? data.write(to: URL(fileURLWithPath: "/tmp/ruiterm_debug.log"))
                    }
                }
            }
        }

        do {
            try task.run()
            if activeRefreshID == refreshID, task.isRunning {
                process = task
            }
            timeoutTask = Task { [weak self, weak task] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled,
                      let self,
                      self.activeRefreshID == refreshID,
                      let task,
                      task.isRunning else {
                    return
                }
                self.timedOut = true
                task.terminate()
                self.status = "Unable to load"
                self.errorMessage = "Status collection timed out. A mounted filesystem may be unresponsive."
            }
        } catch {
            guard activeRefreshID == refreshID else { return }
            activeRefreshID = nil
            isLoading = false
            process = nil
            status = "Unable to load"
            errorMessage = error.localizedDescription
        }
    }

    private var commandForCollectionMode: String {
        switch collectionMode {
        case .full:
            return Self.statsCommand
        case .toolbar:
            return Self.toolbarStatsCommand
        }
    }

    private func sshArguments(command: String) -> [String] {
        var arguments = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath ?? "/tmp/ruiterm-%C")",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1",
            "-o", "NumberOfPasswordPrompts=1",
            "-T",
            "-p", String(host.port)
        ]
        arguments += ["-o", "BatchMode=yes"]
        if !host.identityFile.isEmpty {
            arguments += ["-i", NSString(string: host.identityFile).expandingTildeInPath]
        }
        if !host.proxyJump.isEmpty {
            arguments += ["-J", host.proxyJump]
        }
        arguments += [host.destination, command]
        return arguments
    }

    private static let toolbarStatsCommand = """
    export LC_ALL=C; \
    if [ -r /proc/stat ] && [ -r /proc/meminfo ]; then \
      read _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat; \
      t1=$((u1+n1+s1+i1+w1+q1+sq1+st1)); idle1=$((i1+w1)); \
      sleep 0.25; \
      read _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat; \
      t2=$((u2+n2+s2+i2+w2+q2+sq2+st2)); idle2=$((i2+w2)); \
      cpu=$(awk -v t1="$t1" -v t2="$t2" -v i1="$idle1" -v i2="$idle2" 'BEGIN{d=t2-t1;if(d>0)printf "%.1f",(d-(i2-i1))*100/d;else print 0}'); \
      logical=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1); \
      physical=$(lscpu -p=socket,core 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' '); \
      [ -n "$physical" ] && [ "$physical" -gt 0 ] 2>/dev/null || physical="$logical"; \
      mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0)printf "%.0f|%.0f|%.0f",(t-a)*100/t,(t-a),t;else print "0|0|0"}' /proc/meminfo 2>/dev/null); \
      printf "LIGHTSSH|%.1f|%s|%s|%s|0|0|0|0|0|0|0|\\n" "$cpu" "$physical" "$logical" "$mem"; \
      df -Pk / 2>/dev/null | awk 'NR==2 && $2 ~ /^[0-9]+$/ {gsub("%","",$5); printf "DISK|/|%s|%s|%s\\n",$3,$2,$5}'; \
    elif [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then \
      logical=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1); \
      physical=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "$logical"); \
      cpu=$(iostat -c 2 -w 1 2>/dev/null | awk 'NF >= 6 && $1 ~ /^[0-9.]+$/ {idle=$(NF-3)} END{if(idle=="")print "0.0";else printf "%.1f",100-idle}'); \
      total=$(sysctl -n hw.memsize 2>/dev/null || echo 0); \
      memory=$(memory_pressure -Q 2>/dev/null | awk '/System-wide memory free percentage:/{gsub("%","",$5);printf "%.0f",100-$5}'); \
      [ -n "$memory" ] || memory=0; \
      used=$(awk -v t="$total" -v p="$memory" 'BEGIN{printf "%.0f",t*p/100/1024}'); \
      total_kb=$(awk -v t="$total" 'BEGIN{printf "%.0f",t/1024}'); \
      printf "LIGHTSSH|%.1f|%s|%s|%s|%s|%s|0|0|0|0|0|\\n" "$cpu" "$physical" "$logical" "$memory" "$used" "$total_kb"; \
      disk_info=$(diskutil info -plist / 2>/dev/null); \
      container_total=$(printf "%s" "$disk_info" | plutil -extract APFSContainerSize raw -o - - 2>/dev/null); \
      container_free=$(printf "%s" "$disk_info" | plutil -extract APFSContainerFree raw -o - - 2>/dev/null); \
      if [ -n "$container_total" ] && [ "$container_total" -gt 0 ] 2>/dev/null && [ -n "$container_free" ]; then \
        awk -v t="$container_total" -v f="$container_free" 'BEGIN{u=t-f;printf "DISK|/|%.0f|%.0f|%.1f\\n",u/1024,t/1024,u*100/t}'; \
      else \
        df -Pk / 2>/dev/null | awk 'NR==2 && $2 ~ /^[0-9]+$/ {gsub("%","",$5); printf "DISK|/|%s|%s|%s\\n",$3,$2,$5}'; \
      fi; \
    else \
      echo "LIGHTSSH_UNSUPPORTED"; \
    fi
    """

    private static let statsCommand = """
    export LC_ALL=C; \
    if [ -r /proc/stat ] && [ -r /proc/meminfo ]; then \
      read _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat; \
      t1=$((u1+n1+s1+i1+w1+q1+sq1+st1)); idle1=$((i1+w1)); \
      iface=$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}'); \
      net1=$(awk -F'[: ]+' -v iface="$iface" '$2==iface{printf "%.0f|%.0f",$3,$11}' /proc/net/dev); \
      [ -n "$net1" ] || net1=$(awk -F'[: ]+' '$2!="lo"{rx+=$3;tx+=$11}END{printf "%.0f|%.0f",rx,tx}' /proc/net/dev); \
      disk1=$(awk '$3 !~ /^(loop|ram)/ {r+=$6;w+=$10}END{printf "%.0f|%.0f",r*512,w*512}' /proc/diskstats 2>/dev/null); \
      sleep 1; \
      read _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat; \
      t2=$((u2+n2+s2+i2+w2+q2+sq2+st2)); idle2=$((i2+w2)); \
      cpu=$(awk -v t1="$t1" -v t2="$t2" -v i1="$idle1" -v i2="$idle2" 'BEGIN{d=t2-t1;if(d>0)printf "%.1f",(d-(i2-i1))*100/d;else print 0}'); \
      net2=$(awk -F'[: ]+' -v iface="$iface" '$2==iface{printf "%.0f|%.0f",$3,$11}' /proc/net/dev); \
      [ -n "$net2" ] || net2=$(awk -F'[: ]+' '$2!="lo"{rx+=$3;tx+=$11}END{printf "%.0f|%.0f",rx,tx}' /proc/net/dev); \
      disk2=$(awk '$3 !~ /^(loop|ram)/ {r+=$6;w+=$10}END{printf "%.0f|%.0f",r*512,w*512}' /proc/diskstats 2>/dev/null); \
      load=$(cat /proc/loadavg 2>/dev/null); \
      temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo ""); \
      logical=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1); \
      physical=$(lscpu -p=socket,core 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' '); \
      [ -n "$physical" ] && [ "$physical" -gt 0 ] 2>/dev/null || physical="$logical"; \
      mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0)printf "%.0f|%.0f|%.0f",(t-a)*100/t,(t-a),t;else print "0|0|0"}' /proc/meminfo 2>/dev/null); \
      awk -v temp="$temp" -v cpu="$cpu" -v p="$physical" -v c="$logical" -v m="$mem" -v lavg="$load" -v n1="$net1" -v n2="$net2" -v io1="$disk1" -v io2="$disk2" 'BEGIN{split(lavg,a," ");split(n1,b,"|");split(n2,d,"|");split(io1,e,"|");split(io2,f,"|");if(temp != "") temp=temp/1000; printf "LIGHTSSH|%.1f|%s|%s|%s|%.2f|%.2f|%.2f|%.0f|%.0f|%.0f|%.0f|%s\\n",cpu,p,c,m,a[1],a[2],a[3],d[1]-b[1],d[2]-b[2],f[1]-e[1],f[2]-e[2],temp}'; \
      awk '$1 !~ /^(tmpfs|devtmpfs|overlay|shm|none|sunrpc|mqueue|debugfs|securityfs|pstore|bpf|cgroup|hugetlbfs|fuse|sysfs|proc|devpts|binfmt_misc|configfs|tracefs|rpc_pipefs|lxcfs|nsfs|squashfs|loop)/ && !seen[$2]++ {print $2}' /proc/mounts 2>/dev/null | while IFS= read -r mount; do \
        timeout 1 df -Pk "$mount" 2>/dev/null | awk 'NR==2 && $2 ~ /^[0-9]+$/ {gsub("%","",$5); printf "DISK|%s|%s|%s|%s\\n",$6,$3,$2,$5}'; \
      done; \
    elif [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then \
      logical=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1); \
      physical=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "$logical"); \
      iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2;exit}'); \
      net1=$(netstat -bI "$iface" 2>/dev/null | awk 'NR==2{printf "%.0f|%.0f",$7,$10;exit}'); \
      cpu=$(iostat -c 2 -w 1 2>/dev/null | awk 'NF >= 6 && $1 ~ /^[0-9.]+$/ {idle=$(NF-3)} END{if(idle=="")print "0.0";else printf "%.1f",100-idle}'); \
      net2=$(netstat -bI "$iface" 2>/dev/null | awk 'NR==2{printf "%.0f|%.0f",$7,$10;exit}'); \
      total=$(sysctl -n hw.memsize 2>/dev/null || echo 0); \
      memory=$(memory_pressure -Q 2>/dev/null | awk '/System-wide memory free percentage:/{gsub("%","",$5);printf "%.0f",100-$5}'); \
      [ -n "$memory" ] || memory=0; \
      used=$(awk -v t="$total" -v p="$memory" 'BEGIN{printf "%.0f",t*p/100/1024}'); \
      total_kb=$(awk -v t="$total" 'BEGIN{printf "%.0f",t/1024}'); \
      load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}'); \
      awk -v cpu="$cpu" -v p="$physical" -v c="$logical" -v m="$memory|$used|$total_kb" -v load="$load" -v n1="$net1" -v n2="$net2" 'BEGIN{split(load,a," ");split(n1,b,"|");split(n2,d,"|");printf "LIGHTSSH|%.1f|%s|%s|%s|%.2f|%.2f|%.2f|%.0f|%.0f|0|0|\\n",cpu,p,c,m,a[1],a[2],a[3],d[1]-b[1],d[2]-b[2]}'; \
      disk_info=$(diskutil info -plist / 2>/dev/null); \
      container_total=$(printf "%s" "$disk_info" | plutil -extract APFSContainerSize raw -o - - 2>/dev/null); \
      container_free=$(printf "%s" "$disk_info" | plutil -extract APFSContainerFree raw -o - - 2>/dev/null); \
      if [ -n "$container_total" ] && [ "$container_total" -gt 0 ] 2>/dev/null && [ -n "$container_free" ]; then \
        awk -v t="$container_total" -v f="$container_free" 'BEGIN{u=t-f;printf "DISK|/|%.0f|%.0f|%.1f\\n",u/1024,t/1024,u*100/t}'; \
      else \
        df -Pk / 2>/dev/null | awk 'NR==2 && $2 ~ /^[0-9]+$/ {gsub("%","",$5); printf "DISK|/|%s|%s|%s\\n",$3,$2,$5}'; \
      fi; \
      df -Pk 2>/dev/null | awk 'NR>1 && $6 != "/" && $6 !~ "^/System/Volumes/" && $1 !~ /^(map |devfs|tmpfs|overlay)/ && !seen[$6]++ {gsub("%","",$5);printf "DISK|%s|%s|%s|%s\\n",$6,$3,$2,$5}'; \
    else \
      echo "LIGHTSSH_UNSUPPORTED"; \
    fi
    """

    static func parse(_ text: String) -> RemoteStats? {
        let normalized = text.replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalized.split(whereSeparator: \.isNewline)
        guard let line = lines.first(where: { $0.hasPrefix("LIGHTSSH|") }) else {
            return nil
        }
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 12,
              let cpu = Double(parts[1]),
              let physical = Int(parts[2]),
              let logical = Int(parts[3]),
              let memory = Double(parts[4]),
              let memoryUsed = Double(parts[5]),
              let memoryTotal = Double(parts[6]),
              let load1 = Double(parts[7]),
              let load5 = Double(parts[8]),
              let load15 = Double(parts[9]),
              let receiveRate = Double(parts[10]),
              let sendRate = Double(parts[11])
        else {
            return nil
        }
        let cpuTemp: Double?
        if parts.count >= 15 {
            cpuTemp = Double(parts[14])
        } else if parts.count == 13 {
            cpuTemp = Double(parts[12])
        } else {
            cpuTemp = nil
        }
        let disks = lines.compactMap { line -> RemoteDisk? in
            guard line.hasPrefix("DISK|") else { return nil }
            let values = line.split(separator: "|", omittingEmptySubsequences: false)
            guard values.count == 5,
                  let used = Double(values[2]),
                  let total = Double(values[3]),
                  let percent = Double(values[4])
            else {
                return nil
            }
            return RemoteDisk(
                mountPoint: String(values[1]),
                usedBytes: used * 1_024,
                totalBytes: total * 1_024,
                percent: percent
            )
        }
        return RemoteStats(
            cpuPercent: min(100, max(0, cpu)),
            physicalCores: physical,
            logicalCores: logical,
            load1: load1,
            load5: load5,
            load15: load15,
            networkReceiveBytesPerSecond: max(0, receiveRate),
            networkSendBytesPerSecond: max(0, sendRate),
            diskReadBytesPerSecond: parts.count >= 14 ? max(0, Double(parts[12]) ?? 0) : 0,
            diskWriteBytesPerSecond: parts.count >= 14 ? max(0, Double(parts[13]) ?? 0) : 0,
            memoryPercent: min(100, max(0, memory)),
            memoryUsedBytes: memoryUsed * 1_024,
            memoryTotalBytes: memoryTotal * 1_024,
            cpuTemperature: cpuTemp,
            disks: disks
        )
    }

    private static func readableError(_ error: String, output: String) -> String {
        let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.localizedCaseInsensitiveContains("no route to host") {
            return "No route to host. Check that the Mac and server are on the same network."
        }
        if message.localizedCaseInsensitiveContains("permission denied") {
            return "Authentication failed. Check the saved password or SSH key."
        }
        if message.localizedCaseInsensitiveContains("connection refused") {
            return "Connection refused. Check the SSH port."
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "Connection timed out."
        }
        if output.contains("LIGHTSSH_UNSUPPORTED") {
            return "Host status currently supports Linux and macOS servers."
        }
        if !message.isEmpty {
            return String(message.prefix(240))
        }
        let fallback = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "The server did not return supported resource data." : String(fallback.prefix(240))
    }

    private static func isAuthenticationError(_ error: String) -> Bool {
        let message = error.lowercased()
        return message.contains("permission denied")
            || message.contains("authentication failed")
            || message.contains("too many authentication failures")
    }
}
