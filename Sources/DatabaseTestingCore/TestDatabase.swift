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

    package enum BaselineError: Error, LocalizedError {
        case missingIndex(String)

        package var errorDescription: String? {
            switch self {
            case .missingIndex(let name):
                "Missing database index for container '\(name)'"
            }
        }
    }

    static func launch(
        configuration: DatabasePool.Configuration,
        index: Int,
        maxAttempts: Int = 3
    ) async throws -> TestDatabase {
        let containerName = Self.containerName(for: index)
        let username = Self.username(for: index)
        let password = Self.randomPassword()
        let databaseName = Self.databaseName(for: index)

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

    package var index: Int? {
        Self.index(fromContainerName: self.containerName)
    }

    package static func containerName(for index: Int) -> String {
        "testdb_\(index)"
    }

    package static func username(for index: Int) -> String {
        "user_\(index)"
    }

    package static func databaseName(for index: Int) -> String {
        "test_\(index)"
    }

    package static func baselineName(for index: Int) -> String {
        "test_\(index)_baseline"
    }

    package static func index(fromContainerName name: String) -> Int? {
        guard name.hasPrefix("testdb_"),
              let suffix = name.split(separator: "_").last,
              let index = Int(suffix)
        else {
            return nil
        }

        return index
    }

    package static func shortID() -> String {
        UUID().uuidString.prefix(8).lowercased()
    }

    package static func randomPassword(length: Int = 16) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    package var baselineName: String {
        get throws {
            guard let index else {
                throw BaselineError.missingIndex(self.containerName)
            }
            return Self.baselineName(for: index)
        }
    }

    package func initializeBaseline() async throws {
        try await self.recreateDatabase(
            named: self.databaseName,
            fromTemplate: nil
        )
        try await self.replaceBaseline()
    }

    package func restoreBaseline() async throws {
        try await self.recreateDatabase(
            named: self.databaseName,
            fromTemplate: self.baselineName
        )
    }

    private func replaceBaseline() async throws {
        let baselineName = try self.baselineName
        try await self.dropDatabase(named: baselineName)
        try await self.createDatabase(
            named: baselineName,
            fromTemplate: self.databaseName
        )
    }

    private func recreateDatabase(
        named databaseName: String,
        fromTemplate templateName: String?
    ) async throws {
        try await self.dropDatabase(named: databaseName)
        try await self.createDatabase(
            named: databaseName,
            fromTemplate: templateName
        )
    }

    private func dropDatabase(named name: String) async throws {
        try await self.runAdminSQL(
            "DROP DATABASE IF EXISTS \(Self.quoteIdentifier(name)) WITH (FORCE)"
        )
    }

    private func createDatabase(
        named name: String,
        fromTemplate templateName: String?
    ) async throws {
        var sql = "CREATE DATABASE \(Self.quoteIdentifier(name))"
        if let templateName {
            sql += " TEMPLATE \(Self.quoteIdentifier(templateName)) STRATEGY = file_copy"
        }
        try await self.runAdminSQL(sql)
    }

    private func runAdminSQL(_ sql: String) async throws {
        try await ShellOut.shellOut(
            to: .runPSQL(
                containerName: self.containerName,
                username: self.username,
                password: self.password,
                database: "postgres",
                sql: sql
            )
        )
    }

    private static func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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
