//
//  DatabasePool.swift
//
//  Copyright © 2024 Noah Kamara.
//

import Foundation
import ShellOut

public enum DatabasePool {
    public struct Configuration: Sendable, Hashable {
        public var capacity: Int
        public var image: String

        public init(
            capacity: Int = 8,
            image: String = "postgres:17-alpine"
        ) {
            self.capacity = capacity
            self.image = image
        }
    }

    package static let registry = PoolRegistry.shared

    public static func destroy() async throws {
        try await self.registry.destroy()
    }

    package static func release(_ database: TestDatabase) async {
        await self.registry.release(database)
    }

    package static func retain() async throws -> TestDatabase {
        let maxWaitTime: Duration = .seconds(10)
        let startTime = ContinuousClock.now

        while true {
            if let database = try await registry.retain() {
                return database
            }

            if ContinuousClock.now - startTime > maxWaitTime {
                throw DatabasePoolError.timeoutWaitingForDatabase
            }

            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

package enum DatabasePoolError: Error, LocalizedError {
    case timeoutWaitingForDatabase
    case destroyed

    package var errorDescription: String? {
        switch self {
        case .timeoutWaitingForDatabase:
            "Timeout waiting for available database from pool"
        case .destroyed:
            "DatabasePool has been destroyed and cannot be used"
        }
    }
}

package actor PoolRegistry {
    package static let shared = PoolRegistry()

    package enum State: Sendable {
        case unconfigured
        case active
    }

    package private(set) var state: State = .unconfigured
    package private(set) var configuration: DatabasePool.Configuration?
    package private(set) var availableDatabases: Set<TestDatabase> = []
    package private(set) var inUseDatabases: Set<TestDatabase> = []
    package private(set) var launchingCount: Int = 0
    private let existingDatabasesLoader: @Sendable (Int) async throws -> [TestDatabase]

    package var totalCount: Int {
        self.availableDatabases.count + self.inUseDatabases.count + self.launchingCount
    }

    package init(
        existingDatabasesLoader: @escaping @Sendable (Int) async throws -> [TestDatabase] = PoolRegistry
            .findExistingDatabases
    ) {
        self.existingDatabasesLoader = existingDatabasesLoader
    }

    /// Pre-configure the registry with databases for testing (bypasses Docker).
    package func configureForTesting(
        _ configuration: DatabasePool.Configuration,
        databases: Set<TestDatabase> = []
    ) {
        self.state = .active
        self.configuration = configuration
        self.availableDatabases = databases
        self.inUseDatabases = []
        self.launchingCount = 0
    }

    /// Reset the registry to its initial state (for test cleanup).
    package func reset() {
        self.state = .unconfigured
        self.configuration = nil
        self.availableDatabases = []
        self.inUseDatabases = []
        self.launchingCount = 0
    }

    package func activate(_ configuration: DatabasePool.Configuration) async throws {
        try await self.configure(configuration)
    }

    private func configure(_ configuration: DatabasePool.Configuration) async throws {
        guard self.state == .unconfigured else { return }
        self.configuration = configuration
        self.availableDatabases = try await Set(
            self.existingDatabasesLoader(configuration.capacity)
        )
        self.state = .active
    }

    private func resolveConfiguration() -> DatabasePool.Configuration {
        let env = ProcessInfo.processInfo.environment
        return .init(
            capacity: env["TEST_DB_CAPACITY"].flatMap(Int.init) ?? 8,
            image: env["TEST_DB_IMAGE"] ?? "postgres:17-alpine"
        )
    }

    /// Returns an available database, launching a new container on demand if
    /// the pool hasn't reached capacity yet. Returns `nil` when all databases
    /// are currently in use (caller should retry after a short delay).
    func retain() async throws -> TestDatabase? {
        if self.state == .unconfigured {
            try await self.configure(self.resolveConfiguration())
        }
        guard self.state == .active else {
            throw DatabasePoolError.destroyed
        }
        guard let configuration else {
            throw DatabasePoolError.destroyed
        }

        if let database = availableDatabases.randomElement() {
            self.availableDatabases.remove(database)
            self.inUseDatabases.insert(database)
            return database
        }

        guard self.totalCount < configuration.capacity else {
            return nil
        }

        guard let nextIndex = self.nextAvailableIndex(capacity: configuration.capacity) else {
            return nil
        }

        self.launchingCount += 1
        do {
            let database = try await TestDatabase.launch(
                configuration: configuration,
                index: nextIndex
            )
            self.launchingCount -= 1
            self.inUseDatabases.insert(database)
            return database
        } catch {
            self.launchingCount -= 1
            throw error
        }
    }

    func release(_ database: TestDatabase) {
        self.inUseDatabases.remove(database)
        self.availableDatabases.insert(database)
    }

    func destroy() async throws {
        guard self.state == .active else { return }

        let allDatabases = self.availableDatabases.union(self.inUseDatabases)
        self.availableDatabases = []
        self.inUseDatabases = []
        self.launchingCount = 0
        self.state = .unconfigured

        try await withThrowingTaskGroup(of: Void.self) { group in
            for database in allDatabases {
                group.addTask {
                    try await database.destroy()
                }
            }

            var firstError: (any Error)?

            while let result = await group.nextResult() {
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
            }

            if let firstError {
                throw firstError
            }
        }
    }

    private func nextAvailableIndex(capacity: Int) -> Int? {
        let usedIndices = Set(
            self.availableDatabases
                .union(self.inUseDatabases)
                .compactMap(\.index)
        )

        for index in 0..<capacity where !usedIndices.contains(index) {
            return index
        }

        return nil
    }

    private static func findExistingDatabases(maxCount: Int) async throws -> [TestDatabase] {
        let output = try await ShellOut.shellOut(to: .getManagedContainerNames).stdout
        let names = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.hasPrefix("testdb_") }
            .sorted { lhs, rhs in
                let lhsIndex = TestDatabase.index(fromContainerName: lhs) ?? .max
                let rhsIndex = TestDatabase.index(fromContainerName: rhs) ?? .max
                if lhsIndex == rhsIndex {
                    return lhs < rhs
                }
                return lhsIndex < rhsIndex
            }

        var databases: [TestDatabase] = []
        for name in names.prefix(maxCount) {
            do {
                let db = try await TestDatabase.fromExistingContainer(name: name)
                databases.append(db)
            } catch {
                continue
            }
        }
        return databases
    }
}
