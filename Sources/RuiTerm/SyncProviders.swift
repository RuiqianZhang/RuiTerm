import Foundation
import CryptoKit

protocol SyncProvider {
    func save(filename: String, data: Data) async throws
    func load(filename: String) async throws -> Data?
}

final class LocalSyncProvider: SyncProvider {
    private let defaultDirectory: URL
    
    init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.defaultDirectory = supportDirectory.appendingPathComponent("RuiTerm", isDirectory: true)
        try? fileManager.createDirectory(at: self.defaultDirectory, withIntermediateDirectories: true)
    }
    
    private func directoryURL() -> URL {
        let customPath = SyncSettings.shared.localDirectoryPath
        if !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return defaultDirectory
    }
    
    func save(filename: String, data: Data) async throws {
        let url = directoryURL().appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
    }
    
    func load(filename: String) async throws -> Data? {
        let url = directoryURL().appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}

final class S3SyncProvider: SyncProvider {
    
    enum S3Error: Error {
        case invalidEndpoint
        case missingCredentials
        case badResponse(Int)
        case dataLoadFailed
    }
    
    func save(filename: String, data: Data) async throws {
        let request = try makeRequest(method: "PUT", filename: filename, payload: data)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            print("S3 PUT Error: \(String(data: responseData, encoding: .utf8) ?? "")")
            throw S3Error.badResponse(httpResponse.statusCode)
        }
    }
    
    func load(filename: String) async throws -> Data? {
        let request = try makeRequest(method: "GET", filename: filename, payload: Data())
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 {
                return nil
            }
            if !(200...299).contains(httpResponse.statusCode) {
                print("S3 GET Error: \(String(data: responseData, encoding: .utf8) ?? "")")
                throw S3Error.badResponse(httpResponse.statusCode)
            }
        }
        return responseData
    }
    
    // AWS Signature V4 Implementation
    private func makeRequest(method: String, filename: String, payload: Data) throws -> URLRequest {
        let settings = SyncSettings.shared
        
        guard !settings.s3Endpoint.isEmpty,
              !settings.s3AccessKey.isEmpty,
              !settings.s3SecretKey.isEmpty,
              !settings.s3Bucket.isEmpty else {
            throw S3Error.missingCredentials
        }
        
        var endpoint = settings.s3Endpoint
        if !endpoint.hasPrefix("http") {
            endpoint = "https://" + endpoint
        }
        
        let urlString = "\(endpoint)/\(settings.s3Bucket)/\(filename)"
        guard let url = URL(string: urlString), let host = url.host else {
            throw S3Error.invalidEndpoint
        }
        
        let region = settings.s3Region
        let service = "s3"
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)
        
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)
        
        let payloadHash = SHA256.hash(data: payload).compactMap { String(format: "%02x", $0) }.joined()
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        
        if method == "PUT" {
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // 1. Create a canonical request
        let canonicalURI = "/\(settings.s3Bucket)/\(filename)"
        let canonicalQueryString = ""
        var headersToSign = [
            ("host", host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate)
        ]
        if method == "PUT" {
            headersToSign.append(("content-type", "application/json"))
        }
        headersToSign.sort { $0.0 < $1.0 }
        
        let canonicalHeaders = headersToSign.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headersToSign.map { $0.0 }.joined(separator: ";")
        
        let canonicalRequest = """
        \(method)
        \(canonicalURI)
        \(canonicalQueryString)
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHash)
        """
        
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        
        // 2. Create the string to sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = """
        AWS4-HMAC-SHA256
        \(amzDate)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        // 3. Calculate the signature
        let kSecret = "AWS4" + settings.s3SecretKey
        let kDate = hmac(key: Data(kSecret.utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = hmac(key: kService, data: Data("aws4_request".utf8))
        
        let signatureData = hmac(key: kSigning, data: Data(stringToSign.utf8))
        let signature = signatureData.compactMap { String(format: "%02x", $0) }.joined()
        
        // 4. Add signature to request
        let authorizationHeader = "AWS4-HMAC-SHA256 Credential=\(settings.s3AccessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    private func hmac(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }
}

final class SyncManager {
    static let shared = SyncManager()
    
    private lazy var localProvider = LocalSyncProvider()
    private lazy var s3Provider = S3SyncProvider()
    
    private var currentProvider: SyncProvider {
        switch SyncSettings.shared.provider {
        case .local: return localProvider
        case .s3: return s3Provider
        }
    }
    
    func save(filename: String, data: Data) async throws {
        try await currentProvider.save(filename: filename, data: data)
    }
    
    func load(filename: String) async throws -> Data? {
        return try await currentProvider.load(filename: filename)
    }
}
