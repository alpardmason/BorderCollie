import Foundation

protocol CursorCredentialResolving: Sendable {
    func readCursorCredentials() -> CursorCredentials
}

struct CursorCredentials: Equatable, Sendable {
    let accessToken: String?
    let status: CredentialStatus
    let message: String?
}

struct CursorCredentialResolver: CursorCredentialResolving {
    private static let sqliteTimeoutSeconds = 2.0

    private let stateDatabaseURL: URL
    private let fileExists: @Sendable (String) -> Bool
    private let databaseReader: @Sendable (URL) -> String?

    init(
        stateDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Cursor")
            .appendingPathComponent("User")
            .appendingPathComponent("globalStorage")
            .appendingPathComponent("state.vscdb"),
        fileExists: @escaping @Sendable (String) -> Bool = FileManager.default.fileExists,
        databaseReader: @escaping @Sendable (URL) -> String? = CursorCredentialResolver.readCursorAccessTokenFromStateDatabase
    ) {
        self.stateDatabaseURL = stateDatabaseURL
        self.fileExists = fileExists
        self.databaseReader = databaseReader
    }

    nonisolated func readCursorCredentials() -> CursorCredentials {
        guard fileExists(stateDatabaseURL.path) else {
            return CursorCredentials(
                accessToken: nil,
                status: .notFound,
                message: nil
            )
        }

        guard let token = databaseReader(stateDatabaseURL)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return CursorCredentials(
                accessToken: nil,
                status: .parseError,
                message: "Failed to read Cursor auth state"
            )
        }

        guard !token.isEmpty else {
            return CursorCredentials(
                accessToken: nil,
                status: .notFound,
                message: nil
            )
        }

        return CursorCredentials(
            accessToken: token,
            status: .valid,
            message: nil
        )
    }

    private nonisolated static func readCursorAccessTokenFromStateDatabase(_ databaseURL: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            databaseURL.path,
            "select value from ItemTable where key='cursorAuth/accessToken' limit 1;",
        ]

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

        guard finished.wait(timeout: .now() + sqliteTimeoutSeconds) == .success else {
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
