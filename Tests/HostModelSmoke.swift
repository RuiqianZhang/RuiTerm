import Foundation

@main
enum HostModelSmoke {
    static func main() throws {
        let oldJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "hostname": "legacy.example",
          "username": "root",
          "port": 22,
          "identityFile": "",
          "proxyJump": "",
          "savesPassword": false
        }
        """
        let host = try JSONDecoder().decode(SSHHost.self, from: Data(oldJSON.utf8))
        precondition(host.groupID == nil)
        precondition(host.isFavorite == false)
        precondition(host.isLocal == false)
        precondition(host.colorTag == .none)

        var grouped = host
        grouped.groupID = UUID()
        grouped.isFavorite = true
        grouped.colorTag = .blue
        let roundTrip = try JSONDecoder().decode(SSHHost.self, from: JSONEncoder().encode(grouped))
        precondition(roundTrip.groupID == grouped.groupID)
        precondition(roundTrip.isFavorite)
        precondition(roundTrip.colorTag == .blue)
        precondition(SSHHost.localTerminal.isLocal)

        let oldGroupJSON = #"{"name":"Legacy Group"}"#
        let oldGroup = try JSONDecoder().decode(SSHGroup.self, from: Data(oldGroupJSON.utf8))
        precondition(oldGroup.colorTag == .none)
    }
}
