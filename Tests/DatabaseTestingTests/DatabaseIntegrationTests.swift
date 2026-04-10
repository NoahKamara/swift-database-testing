//
//  DatabaseIntegrationTests.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTesting
@testable import DatabaseTestingCore
import Foundation
import ShellOut
import Testing

private enum IntegrationTestSupport {
    static func dockerBinary() -> String {
#if os(macOS)
        "/usr/local/bin/docker"
#else
        "docker"
#endif
    }

    static func dockerAvailable() async -> Bool {
        do {
            _ = try await ShellOut.shellOut(
                to: ShellOutCommand(command: self.dockerBinary(), arguments: ["version"])
            )
            return true
        } catch {
            return false
        }
    }

    static func configureSingleDatabasePool() {
        setenv("TEST_DB_CAPACITY", "1", 1)
    }

    static func execute(
        on database: TestDatabase,
        sql: String,
        tuplesOnly: Bool = false
    ) async throws -> String {
        var arguments = [
            "exec",
            "-e", "PGPASSWORD=\(database.password)",
            database.containerName,
            "psql",
            "-v", "ON_ERROR_STOP=1",
            "-U", database.username,
            "-d", database.databaseName,
        ]
        if tuplesOnly {
            arguments.append("-tA")
        }
        arguments.append(contentsOf: ["-c", sql])

        let output = try await ShellOut.shellOut(
            to: ShellOutCommand(command: self.dockerBinary(), arguments: arguments)
        ).stdout
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Suite("Docker Integration", .serialized)
struct DatabaseIntegrationTests {
    @Test("pool restores the baseline on each retain")
    func poolRestoresBaselineOnEachRetain() async throws {
        guard await IntegrationTestSupport.dockerAvailable() else { return }
        IntegrationTestSupport.configureSingleDatabasePool()
        try? await DatabasePool.destroy()
        do {
            let first = try await DatabasePool.retain()
            _ = try await IntegrationTestSupport.execute(
                on: first,
                sql: """
                CREATE TABLE widgets (id INT PRIMARY KEY);
                INSERT INTO widgets VALUES (1);
                """
            )
            await DatabasePool.release(first)

            let second = try await DatabasePool.retain()
            #expect(second == first)
            _ = try await IntegrationTestSupport.execute(
                on: second,
                sql: """
                CREATE TABLE widgets (id INT PRIMARY KEY);
                INSERT INTO widgets VALUES (1);
                """
            )
            let count = try await IntegrationTestSupport.execute(
                on: second,
                sql: "SELECT COUNT(*) FROM widgets;",
                tuplesOnly: true
            )
            #expect(count == "1")
            await DatabasePool.release(second)
        } catch {
            try? await DatabasePool.destroy()
            throw error
        }
        try? await DatabasePool.destroy()
    }

    @Suite(
        "Trait Integration",
        .database(prepare: { db in
            guard await IntegrationTestSupport.dockerAvailable() else { return }
            IntegrationTestSupport.configureSingleDatabasePool()
            _ = try await IntegrationTestSupport.execute(
                on: db,
                sql: "CREATE TABLE entries (value INT PRIMARY KEY);"
            )
        }),
        .database(prepare: { db in
            guard await IntegrationTestSupport.dockerAvailable() else { return }
            _ = try await IntegrationTestSupport.execute(
                on: db,
                sql: "INSERT INTO entries VALUES (1);"
            )
        }),
        .serialized
    )
    struct TraitIntegrationTests {
        @Test("applies the prepare stack on top of a clean retained database")
        func appliesPrepareStackAndCachesCurrentDatabase() async throws {
            guard await IntegrationTestSupport.dockerAvailable() else { return }
            IntegrationTestSupport.configureSingleDatabasePool()

            let database = try await TestDatabase.current()
            let count = try await IntegrationTestSupport.execute(
                on: database,
                sql: "SELECT COUNT(*) FROM entries;",
                tuplesOnly: true
            )
            #expect(count == "1")
            #expect(try await TestDatabase.current() == database)
        }
    }
}
