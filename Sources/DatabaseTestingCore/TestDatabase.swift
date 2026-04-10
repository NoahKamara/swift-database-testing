//
//  TestDatabase.swift
//
//  Copyright © 2024 Noah Kamara.
//

import Foundation
import ShellOut

public struct TestDatabase: Hashable, Sendable {
    public let host: String
    public let port: Int
    public let databaseName: String
    public let username: String
    public let password: String

    let containerName: String

    static func launch(
        configuration: DatabasePool.Configuration,
        maxAttempts: Int = 3
    ) async throws -> TestDatabase {
        let containerName = "testdb_\(Self.shortID())"
        let username = "user_\(Self.shortID())"
        let password = Self.randomPassword()
        let databaseName = "test_\(Self.shortID())"

        _ = try? await ShellOut.shellOut(to: .removeDB(containerName: containerName))
        try await withRetry(maxAttempts: maxAttempts) { _ in
            try await ShellOut.shellOut(to: .launchDB(
                containerName: containerName,
                username: username,
                password: password,
                database: databaseName,
                image: configuration.image
            ))
        }

        let port = try await discoverPort(containerName: containerName)
        try await waitUntilReady(
            containerName: containerName,
            username: username,
            database: databaseName
        )

        return TestDatabase(
            host: "localhost",
            port: port,
            databaseName: databaseName,
            username: username,
            password: password,
            containerName: containerName
        )
    }

    /// Reconstruct a `TestDatabase` from a running Docker container by
    /// inspecting its port mapping and environment variables.
    static func fromExistingContainer(name: String) async throws -> TestDatabase {
        let port = try await discoverPort(containerName: name)
        let env = try await discoverEnv(containerName: name)
        let databaseName = env["POSTGRES_DB"] ?? "test"
        let username = env["POSTGRES_USER"] ?? "test"
        let password = env["POSTGRES_PASSWORD"] ?? "test"

        try await waitUntilReady(
            containerName: name,
            username: username,
            database: databaseName
        )

        return TestDatabase(
            host: "localhost",
            port: port,
            databaseName: databaseName,
            username: username,
            password: password,
            containerName: name
        )
    }

    func destroy(maxAttempts: Int = 3) async throws {
        try await withRetry(maxAttempts: maxAttempts) { _ in
            try await ShellOut.shellOut(to: .removeDB(containerName: self.containerName))
        }
    }

    package static func shortID() -> String {
        UUID().uuidString.prefix(8).lowercased()
    }

    package static func randomPassword(length: Int = 16) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - Parsing

package enum Parsing {
    /// Extract the host port from `docker port` output like `"0.0.0.0:12345"` or `"[::]:12345"`.
    package static func port(from output: String) throws -> Int {
        guard let portString = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .last,
            let port = Int(portString)
        else {
            throw TestDatabaseError.portDiscoveryFailed("unknown")
        }
        return port
    }

    /// Parse a JSON array of `"KEY=VALUE"` strings (from `docker inspect --format '{{json .Config.Env}}'`)
    /// into a dictionary.
    package static func env(from output: String) -> [String: String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let entries = try? JSONDecoder().decode([String].self, from: data)
        else {
            return [:]
        }

        var env: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                env[String(parts[0])] = String(parts[1])
            }
        }
        return env
    }
}

// MARK: - Internal Helpers

private func discoverPort(containerName: String) async throws -> Int {
    let output = try await ShellOut.shellOut(
        to: .getContainerPort(containerName: containerName)
    ).stdout

    do {
        return try Parsing.port(from: output)
    } catch {
        throw TestDatabaseError.portDiscoveryFailed(containerName)
    }
}

private func discoverEnv(containerName: String) async throws -> [String: String] {
    let output = try await ShellOut.shellOut(
        to: .inspectContainerEnv(containerName: containerName)
    ).stdout
    return Parsing.env(from: output)
}

private func waitUntilReady(
    containerName: String,
    username: String,
    database: String
) async throws {
    try await withRetry(
        maxAttempts: 50,
        backoff: .milliseconds(200)
    ) { _ in
        try await ShellOut.shellOut(
            to: .waitUntilDBReady(
                containerName: containerName,
                username: username,
                database: database
            )
        )
    }
}

package enum TestDatabaseError: Error, LocalizedError {
    case portDiscoveryFailed(String)

    package var errorDescription: String? {
        switch self {
        case .portDiscoveryFailed(let name):
            "Failed to discover host port for container '\(name)'"
        }
    }
}
