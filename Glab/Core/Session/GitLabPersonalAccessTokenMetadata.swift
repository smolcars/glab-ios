import Foundation

nonisolated enum GitLabAPIAccess: String, Codable, Equatable, Sendable {
    case readOnly
    case readWrite

    var canWrite: Bool {
        self == .readWrite
    }
}

nonisolated struct GitLabPersonalAccessTokenMetadata:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey {
        case scopes
        case expiresOn
    }

    let scopes: [String]
    let expiresOn: String?

    var apiAccess: GitLabAPIAccess {
        scopes.contains("api") ? .readWrite : .readOnly
    }

    var supportsGlabAPI: Bool {
        scopes.contains("api") || scopes.contains("read_api")
    }

    init(scopes: [String], expiresOn: String?) {
        let normalizedScopes = Set(
            scopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        self.scopes = normalizedScopes.sorted()
        self.expiresOn = expiresOn?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scopes: try container.decode([String].self, forKey: .scopes),
            expiresOn: try container.decodeIfPresent(String.self, forKey: .expiresOn)
        )
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
