import CryptoKit
import Foundation
import Security

nonisolated enum GitLabOAuthPKCEError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case randomGenerationFailed
    case invalidRandomData
    case invalidState
    case invalidCodeVerifier

    var description: String {
        switch self {
        case .randomGenerationFailed:
            "Glab could not create secure OAuth values."
        case .invalidRandomData:
            "The OAuth random data had an invalid length."
        case .invalidState:
            "The OAuth state value is invalid."
        case .invalidCodeVerifier:
            "The OAuth PKCE verifier is invalid."
        }
    }
}

nonisolated struct GitLabOAuthPKCE:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let state: String
    let codeVerifier: String
    let codeChallenge: String

    init(
        state: String,
        codeVerifier: String
    ) throws(GitLabOAuthPKCEError) {
        guard
            !state.isEmpty,
            state.unicodeScalars.allSatisfy(Self.allowedCharacters.contains)
        else {
            throw .invalidState
        }
        guard
            (43...128).contains(codeVerifier.count),
            codeVerifier.unicodeScalars.allSatisfy(Self.allowedCharacters.contains)
        else {
            throw .invalidCodeVerifier
        }

        self.state = state
        self.codeVerifier = codeVerifier
        codeChallenge = Self.challenge(for: codeVerifier)
    }

    static func challenge(for codeVerifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
    }

    var description: String {
        "GitLabOAuthPKCE(state: <redacted>, "
            + "codeVerifier: <redacted>, "
            + "codeChallenge: <redacted>)"
    }

    var debugDescription: String {
        description
    }

    fileprivate static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

nonisolated protocol GitLabOAuthRandomBytesProviding: Sendable {
    func randomBytes(count: Int) throws(GitLabOAuthPKCEError) -> Data
}

nonisolated struct SystemGitLabOAuthRandomBytesProvider:
    GitLabOAuthRandomBytesProviding,
    Sendable
{
    func randomBytes(
        count: Int
    ) throws(GitLabOAuthPKCEError) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }

            return SecRandomCopyBytes(
                kSecRandomDefault,
                count,
                baseAddress
            )
        }

        guard status == errSecSuccess else {
            throw .randomGenerationFailed
        }
        return data
    }
}

nonisolated struct GitLabOAuthPKCEGenerator<RandomBytesProvider>: Sendable
where RandomBytesProvider: GitLabOAuthRandomBytesProviding {
    private let randomBytesProvider: RandomBytesProvider

    init(randomBytesProvider: RandomBytesProvider) {
        self.randomBytesProvider = randomBytesProvider
    }

    func generate() throws(GitLabOAuthPKCEError) -> GitLabOAuthPKCE {
        let randomData = try randomBytesProvider.randomBytes(count: 96)
        guard randomData.count == 96 else {
            throw .invalidRandomData
        }

        let stateData = randomData.prefix(32)
        let verifierData = randomData.suffix(64)

        return try GitLabOAuthPKCE(
            state: GitLabOAuthPKCE.base64URLEncoded(Data(stateData)),
            codeVerifier: GitLabOAuthPKCE.base64URLEncoded(Data(verifierData))
        )
    }
}
