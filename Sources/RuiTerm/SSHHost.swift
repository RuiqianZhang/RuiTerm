import Foundation

enum SSHColorTag: String, Codable, CaseIterable, Identifiable {
    case none
    case gray
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

struct SSHHost: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var hostname = ""
    var username = ""
    var port = 22
    var identityFile = ""
    var proxyJump = ""
    var savesPassword = false
    var groupID: UUID?
    var isFavorite = false
    var isLocal = false
    var colorTag: SSHColorTag = .none
    var hasPromptedOptimization = false

    var destination: String {
        username.isEmpty ? hostname : "\(username)@\(hostname)"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, hostname, username, port, identityFile, proxyJump, savesPassword, groupID, isFavorite, isLocal, colorTag, hasPromptedOptimization
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        hostname: String = "",
        username: String = "",
        port: Int = 22,
        identityFile: String = "",
        proxyJump: String = "",
        savesPassword: Bool = false,
        groupID: UUID? = nil,
        isFavorite: Bool = false,
        isLocal: Bool = false,
        colorTag: SSHColorTag = .none,
        hasPromptedOptimization: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.username = username
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.savesPassword = savesPassword
        self.groupID = groupID
        self.isFavorite = isFavorite
        self.isLocal = isLocal
        self.colorTag = colorTag
        self.hasPromptedOptimization = hasPromptedOptimization
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        hostname = try values.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? 22
        identityFile = try values.decodeIfPresent(String.self, forKey: .identityFile) ?? ""
        proxyJump = try values.decodeIfPresent(String.self, forKey: .proxyJump) ?? ""
        savesPassword = try values.decodeIfPresent(Bool.self, forKey: .savesPassword) ?? false
        groupID = try values.decodeIfPresent(UUID.self, forKey: .groupID)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isLocal = try values.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        colorTag = try values.decodeIfPresent(SSHColorTag.self, forKey: .colorTag) ?? .none
        hasPromptedOptimization = try values.decodeIfPresent(Bool.self, forKey: .hasPromptedOptimization) ?? false
    }

    static var localTerminal: SSHHost {
        SSHHost(name: "Local Terminal", hostname: "localhost", isLocal: true)
    }
}

struct SSHGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var colorTag: SSHColorTag = .none

    enum CodingKeys: String, CodingKey {
        case id, name, colorTag
    }

    init(id: UUID = UUID(), name: String, colorTag: SSHColorTag = .none) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        colorTag = try values.decodeIfPresent(SSHColorTag.self, forKey: .colorTag) ?? .none
    }
}
