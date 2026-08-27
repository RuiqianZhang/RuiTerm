import Darwin
import Foundation

@main
struct KeychainStoreSmoke {
    @MainActor
    static func main() async {
        let hostID = UUID()
        if let error = KeychainStore.save("ruiterm-keychain-smoke-test", for: hostID) {
            print(error)
            exit(1)
        }
        if let error = KeychainStore.save("ruiterm-keychain-updated-smoke-test", for: hostID) {
            print("Update failed: \(error)")
            exit(1)
        }
        guard KeychainStore.containsPassword(for: hostID) else {
            print("Saved password was not found.")
            exit(1)
        }
        guard await KeychainStore.password(for: hostID) == "ruiterm-keychain-updated-smoke-test" else {
            print("Saved password could not be read directly.")
            exit(1)
        }
        KeychainStore.delete(for: hostID)
        print("Keychain save, lookup, and delete passed.")
    }
}
