import AppKit
import Foundation

@MainActor
final class HostStore: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var groups: [SSHGroup] = []
    @Published var isPresentingNewHost = false
    @Published var notice: String?

    init() {
        Task { await load() }
    }

    func add(_ host: SSHHost) {
        hosts.append(host)
        sortAndSave()
    }

    func update(_ host: SSHHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index] = host
        sortAndSave()
    }

    func addGroup(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        groups.append(SSHGroup(name: trimmed))
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveGroups()
    }

    func deleteGroup(_ group: SSHGroup) {
        groups.removeAll { $0.id == group.id }
        for index in hosts.indices where hosts[index].groupID == group.id {
            hosts[index].groupID = nil
        }
        saveGroups()
        save()
    }

    func renameGroup(_ group: SSHGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !groups.contains(where: {
                  $0.id != group.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }),
              let index = groups.firstIndex(where: { $0.id == group.id })
        else { return }
        groups[index].name = trimmed
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveGroups()
    }

    func toggleFavorite(_ host: SSHHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].isFavorite.toggle()
        save()
    }

    func move(_ host: SSHHost, to groupID: UUID?) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].groupID = groupID
        save()
    }

    func setColorTag(_ colorTag: SSHColorTag, for host: SSHHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].colorTag = colorTag
        save()
    }

    func setColorTag(_ colorTag: SSHColorTag, for group: SSHGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].colorTag = colorTag
        saveGroups()
    }

    func delete(_ host: SSHHost) {
        KeychainStore.delete(for: host.id)
        hosts.removeAll { $0.id == host.id }
        save()
    }

    func importDefaultSSHConfig() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            notice = "No readable ~/.ssh/config file was found."
            return
        }

        let imported = SSHConfigParser.parse(contents)
        var added = 0
        for host in imported where !hosts.contains(where: { $0.name == host.name }) {
            hosts.append(host)
            added += 1
        }
        sortAndSave()
        notice = "Imported \(added) host\(added == 1 ? "" : "s") from ~/.ssh/config."
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select a RuiTerm hosts backup."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url) else {
            notice = "The selected file is not a valid RuiTerm backup."
            return
        }
        let decoder = JSONDecoder()
        let backup = (try? decoder.decode(HostBackup.self, from: data))
        let imported = backup?.hosts ?? (try? decoder.decode([SSHHost].self, from: data)) ?? []
        guard !imported.isEmpty else {
            notice = "The selected file is not a valid RuiTerm backup."
            return
        }

        var added = 0
        for host in imported where !hosts.contains(where: { $0.name == host.name }) {
            hosts.append(host)
            added += 1
        }
        for group in backup?.groups ?? [] where !groups.contains(where: { $0.id == group.id }) {
            groups.append(group)
        }
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveGroups()
        sortAndSave()
        notice = "Imported \(added) host\(added == 1 ? "" : "s") from the backup."
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RuiTerm-hosts.json"
        panel.message = "Save this file in a synced folder to share host settings."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? JSONEncoder.prettyPrinted.encode(HostBackup(hosts: hosts, groups: groups)) else {
            notice = "Unable to encode the host backup."
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            notice = "Exported \(hosts.count) host\(hosts.count == 1 ? "" : "s")."
        } catch {
            notice = "Unable to save the backup: \(error.localizedDescription)"
        }
    }

    private func sortAndSave() {
        hosts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func load() async {
        do {
            if let data = try await SyncManager.shared.load(filename: "hosts.json"),
               let savedHosts = try? JSONDecoder().decode([SSHHost].self, from: data) {
                self.hosts = savedHosts
            } else {
                save()
            }
            if let groupData = try await SyncManager.shared.load(filename: "groups.json"),
               let savedGroups = try? JSONDecoder().decode([SSHGroup].self, from: groupData) {
                self.groups = savedGroups
            } else {
                saveGroups()
            }
            self.notice = nil
        } catch {
            self.notice = "Sync Load Error: \(error.localizedDescription)"
        }
    }

    private func save() {
        let hostsToSave = hosts
        Task {
            do {
                let data = try JSONEncoder.prettyPrinted.encode(hostsToSave)
                try await SyncManager.shared.save(filename: "hosts.json", data: data)
            } catch {
                await MainActor.run { self.notice = "Sync Save Error: \(error.localizedDescription)" }
            }
        }
    }

    private func saveGroups() {
        let groupsToSave = groups
        Task {
            do {
                let data = try JSONEncoder.prettyPrinted.encode(groupsToSave)
                try await SyncManager.shared.save(filename: "groups.json", data: data)
            } catch {
                await MainActor.run { self.notice = "Sync Save Error: \(error.localizedDescription)" }
            }
        }
    }
}

private struct HostBackup: Codable {
    let hosts: [SSHHost]
    let groups: [SSHGroup]
}

private enum SSHConfigParser {
    static func parse(_ contents: String) -> [SSHHost] {
        var hosts: [SSHHost] = []
        var current: SSHHost?

        func finishCurrent() {
            guard let host = current, !host.name.isEmpty, !host.hostname.isEmpty else { return }
            hosts.append(host)
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                finishCurrent()
                guard !value.contains("*"), !value.contains("?"), !value.contains(" ") else {
                    current = nil
                    continue
                }
                current = SSHHost(name: value, hostname: value)
                continue
            }

            guard current != nil else { continue }
            switch key {
            case "hostname": current?.hostname = value
            case "user": current?.username = value
            case "port": current?.port = Int(value) ?? 22
            case "identityfile": current?.identityFile = value
            case "proxyjump": current?.proxyJump = value
            default: break
            }
        }
        finishCurrent()
        return hosts
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
