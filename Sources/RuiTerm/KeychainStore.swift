import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    private static let legacyService = "com.ruiterm.host"
    private static let protectedService = "com.ruiterm.host.protected"

    /// Checks if a password is saved for the given host ID.
    static func containsPassword(for hostID: UUID) -> Bool {
        (supportsProtectedKeychain
            && SecItemCopyMatching(protectedQuery(for: hostID, returnAttributes: true) as CFDictionary, nil) == errSecSuccess)
            || SecItemCopyMatching(legacyQuery(for: hostID, returnAttributes: true) as CFDictionary, nil) == errSecSuccess
    }

    /// Retrieves the password after macOS verifies user presence.
    static func password(for hostID: UUID) -> String? {
        let context = LAContext()
        context.localizedReason = "Authenticate to connect to your SSH host"
        context.localizedFallbackTitle = "Use Mac Password"

        var item: CFTypeRef?
        if supportsProtectedKeychain {
            var query = protectedQuery(for: hostID)
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationContext as String] = context

            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess,
               let data = item as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        } else if !authenticateUser(reason: context.localizedReason) {
            return nil
        }

        // Legacy file-keychain entries may show the traditional Keychain
        // authorization dialog once. After that read, migrate to the Data
        // Protection keychain so future access uses Touch ID / Mac password.
        var legacy = legacyQuery(for: hostID)
        legacy[kSecReturnData as String] = true
        item = nil
        guard SecItemCopyMatching(legacy as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        if save(password, for: hostID) == nil, supportsProtectedKeychain {
            SecItemDelete(legacyQuery(for: hostID, matchOne: false) as CFDictionary)
        }
        return password
    }

    private static func protectedQuery(
        for hostID: UUID,
        returnAttributes: Bool = false,
        matchOne: Bool = true
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: protectedService,
            kSecAttrAccount as String: hostID.uuidString,
            kSecUseDataProtectionKeychain as String: true
        ]
        if matchOne {
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        if returnAttributes {
            query[kSecReturnAttributes as String] = true
        }
        return query
    }

    private static func legacyQuery(
        for hostID: UUID,
        returnAttributes: Bool = false,
        matchOne: Bool = true
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: hostID.uuidString
        ]
        if matchOne {
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        if returnAttributes {
            query[kSecReturnAttributes as String] = true
        }
        return query
    }

    /// Saves the password with Touch ID / Mac password user-presence protection.
    static func save(_ password: String, for hostID: UUID) -> String? {
        guard let data = password.data(using: .utf8) else {
            return "Invalid password format"
        }

        guard supportsProtectedKeychain else {
            return saveLegacy(data, for: hostID)
        }

        var error: Unmanaged<CFError>?
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        )
        
        guard let accessControl else {
            return error?.takeRetainedValue().localizedDescription
                ?? "Unable to protect password with user authentication"
        }

        // Re-add instead of updating so passwords saved by older versions gain
        // the new user-presence access control.
        let query = protectedQuery(for: hostID, matchOne: false)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            return "Failed to replace password in Keychain (Status: \(deleteStatus))"
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessControl as String] = accessControl
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            return "Failed to save password to Keychain (Status: \(addStatus))"
        }
        
        return nil
    }

    private static var supportsProtectedKeychain: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "keychain-access-groups" as CFString,
                nil
              ) else {
            return false
        }
        return (value as? [String])?.isEmpty == false
    }

    private static func saveLegacy(_ data: Data, for hostID: UUID) -> String? {
        let query = legacyQuery(for: hostID, matchOne: false)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            return "Failed to replace password in Keychain (Status: \(deleteStatus))"
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let result = SecItemAdd(item as CFDictionary, nil)
        return result == errSecSuccess ? nil : "Failed to save password in Keychain (Status: \(result))"
    }

    private static func authenticateUser(reason: String) -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Mac Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }

        let semaphore = DispatchSemaphore(value: 0)
        var authenticated = false
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            authenticated = success
            semaphore.signal()
        }
        semaphore.wait()
        return authenticated
    }
    
    /// Deletes the password from Keychain.
    static func delete(for hostID: UUID) {
        if supportsProtectedKeychain {
            SecItemDelete(protectedQuery(for: hostID, matchOne: false) as CFDictionary)
        }
        SecItemDelete(legacyQuery(for: hostID, matchOne: false) as CFDictionary)
    }
}
