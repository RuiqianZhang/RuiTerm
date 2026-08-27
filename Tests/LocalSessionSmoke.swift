import Foundation

@main
enum LocalSessionSmoke {
    @MainActor
    static func main() async {
        let session = SSHSession(host: .localTerminal)
        session.connect(columns: 100, rows: 30)
        try? await Task.sleep(for: .milliseconds(500))
        session.send(Data("printf 'LIGHTSSH_LOCAL_OK\\n'\r".utf8))
        try? await Task.sleep(for: .milliseconds(500))
        precondition(session.isConnected)
        precondition(session.output.contains("LIGHTSSH_LOCAL_OK"))
        session.disconnect()
    }
}
