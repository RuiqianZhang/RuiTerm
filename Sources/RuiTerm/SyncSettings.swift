import Foundation
import SwiftUI
import CryptoKit

enum SyncProviderType: String, CaseIterable, Identifiable {
    case local = "Local Directory (Drive/Dropbox/iCloud)"
    case s3 = "Amazon S3 / Compatible API"
    
    var id: String { rawValue }
}

final class SyncSettings: ObservableObject {
    @AppStorage("syncProvider") var provider: SyncProviderType = .local
    @AppStorage("syncLocalDirectoryPath") var localDirectoryPath: String = ""
    
    // S3 Settings
    @AppStorage("s3Endpoint") var s3Endpoint: String = ""
    @AppStorage("s3Region") var s3Region: String = "us-east-1"
    @AppStorage("s3Bucket") var s3Bucket: String = ""
    @AppStorage("s3AccessKey") var s3AccessKey: String = ""
    @AppStorage("s3SecretKey") var s3SecretKey: String = ""
    
    static let shared = SyncSettings()
}
