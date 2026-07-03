import Foundation

protocol CodexCredentialResolving: Sendable {
    func readCodexCredentials() -> CodexCredentials
}

struct CodexCredentialResolver: CodexCredentialResolving {
    private static let keychainTimeoutSeconds = 2.0

    private let authFileURL: URL
    private let now: @Sendable () -> Date
    private let keychainReader: @Sendable () -> String?

    init(
        authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json"),
        now: @escaping @Sendable () -> Date = Date.init,
        keychainReader: @escaping @Sendable () -> String? = CodexCredentialResolver.readCodexCredentialsFromKeychain
    ) {
        self.authFileURL = authFileURL
        self.now = now
        self.keychainReader = keychainReader
    }

    nonisolated func readCodexCredentials() -> CodexCredentials {
        if let keychainJSON = keychainReader()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainJSON.isEmpty {
            return Self.parseCodexCredentialsJSON(keychainJSON, now: now())
        }

        return readCodexCredentialsFromFile()
    }

    private nonisolated func readCodexCredentialsFromFile() -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .notFound,
                message: nil
            )
        }

        do {
            let content = try String(contentsOf: authFileURL, encoding: .utf8)
            return Self.parseCodexCredentialsJSON(content, now: now())
        } catch {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .parseError,
                message: "Failed to read Codex auth JSON: \(error.localizedDescription)"
            )
        }
    }

    nonisolated static func parseCodexCredentialsJSON(_ content: String, now: Date = Date()) -> CodexCredentials {
        let auth: CodexAuthJSON
        do {
            auth = try JSONDecoder().decode(CodexAuthJSON.self, from: Data(content.utf8))
        } catch {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .parseError,
                message: "Failed to parse Codex auth JSON: \(error.localizedDescription)"
            )
        }

        guard auth.authMode == "chatgpt" else {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .notFound,
                message: "Codex is not using OAuth mode"
            )
        }

        guard let tokens = auth.tokens else {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .parseError,
                message: "No tokens in Codex auth"
            )
        }

        guard let accessToken = tokens.accessToken, !accessToken.isEmpty else {
            return CodexCredentials(
                accessToken: nil,
                accountID: nil,
                status: .parseError,
                message: "access_token is empty or missing"
            )
        }

        if let lastRefresh = auth.lastRefresh,
           Self.isCodexTokenStale(lastRefresh, now: now) {
            return CodexCredentials(
                accessToken: accessToken,
                accountID: tokens.accountID,
                status: .expired,
                message: "Codex token may be stale (>8 days since last refresh)"
            )
        }

        return CodexCredentials(
            accessToken: accessToken,
            accountID: tokens.accountID,
            status: .valid,
            message: nil
        )
    }

    nonisolated static func isCodexTokenStale(_ lastRefresh: String, now: Date = Date()) -> Bool {
        guard let refreshedAt = ISO8601DateFormatter.codex.dateAllowingCodexFormats(from: lastRefresh) else {
            return false
        }

        return now.timeIntervalSince(refreshedAt) > 8 * 24 * 3_600
    }

    private nonisolated static func readCodexCredentialsFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Codex Auth", "-w"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard finished.wait(timeout: .now() + keychainTimeoutSeconds) == .success else {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: output, encoding: .utf8)
    }
}

private struct CodexAuthJSON: Decodable {
    let authMode: String?
    let tokens: CodexTokensJSON?
    let lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

private struct CodexTokensJSON: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}
