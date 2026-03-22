import Foundation
import Security

struct GeminiAPIKeyStore {
    private let service = "CareerFuel.Gemini"
    private let account = "api-key"

    func save(_ apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedKey = trimmedKey.replacingOccurrences(of: " ", with: "")
        guard
            !sanitizedKey.isEmpty,
            sanitizedKey.hasPrefix("AIza"),
            sanitizedKey.count >= 24,
            let data = sanitizedKey.data(using: .utf8)
        else {
            throw GeminiAPIKeyStoreError.invalidKey
        }

        let query = baseQuery
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GeminiAPIKeyStoreError.unhandledStatus(status)
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw GeminiAPIKeyStoreError.unhandledStatus(status)
        }

        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw GeminiAPIKeyStoreError.unhandledStatus(status)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum GeminiAPIKeyStoreError: LocalizedError {
    case invalidKey
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Enter a valid Gemini API key. Gemini keys usually start with AIza."
        case let .unhandledStatus(status):
            return "The API key could not be stored securely. Keychain status: \(status)."
        }
    }
}
