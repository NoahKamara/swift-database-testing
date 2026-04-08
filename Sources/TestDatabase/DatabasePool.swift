import PostgresNIO
import Foundation
import ShellOut

private let logger: Logger? = nil

public enum DatabasePool {
    public struct Configuration: Sendable, Hashable {
        public var containerPrefix: String
        public var username: String
        public var password: String
        public var databaseName: String
        public var startPort: Int
        public var poolSize: Int
        public var dockerImage: String
        public var host: String

        public init(
            containerPrefix: String = "testdb",
            username: String = "test",
            password: String = "test",
            databaseName: String = "test",
            startPort: Int = 15432,
            poolSize: Int = 8,
            dockerImage: String = "postgres:16-alpine",
            host: String = "localhost"
        ) {
            self.containerPrefix = containerPrefix
            self.username = username
            self.password = password
            self.databaseName = databaseName
            self.startPort = startPort
            self.poolSize = poolSize
            self.dockerImage = dockerImage
            self.host = host
        }
    }

    package static let registry = PoolRegistry.shared

    /// Must be called once before any `withDatabase` call.
    /// Discovers already-running containers so they can be reused.
    public static func configure(_ configuration: Configuration) async throws {
        try await registry.configure(configuration)
    }

    public static func withDatabase<T: Sendable>(
        _ operation: @Sendable (TestDatabase) async throws -> T
    ) async throws -> T {
        let database = try await retain()
        logger?.info("Acquired database on port \(database.port)")

        do {
            let result = try await operation(database)
            await self.registry.release(database)
            logger?.info("Released database on port \(database.port)")
            return result
        } catch {
            await self.registry.release(database)
            logger?.info("Released database on port \(database.port) after error")
            throw error
        }
    }

    public static func destroy() async throws {
        try await registry.destroy()
    }

    package static func release(_ database: TestDatabase) async {
        await registry.release(database)
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
    case notConfigured
    case alreadyConfigured
    case destroyed

    package var errorDescription: String? {
        switch self {
        case .timeoutWaitingForDatabase:
            "Timeout waiting for available database from pool"
        case .notConfigured:
            "DatabasePool.configure(_:) must be called before using the pool"
        case .alreadyConfigured:
            "DatabasePool.configure(_:) cannot be called after the pool is already configured"
        case .destroyed:
            "DatabasePool has been destroyed and cannot be used"
        }
    }
}

@globalActor
package actor PoolRegistry {
    package static let shared = PoolRegistry()

    enum State: Sendable {
        case unconfigured
        case active
        case destroying
    }

    private(set) var state: State = .unconfigured
    private var configuration: DatabasePool.Configuration?
    private var availableDatabases: Set<TestDatabase> = []
    private var inUseDatabases: Set<TestDatabase> = []
    /// Indices currently being launched, tracked to prevent concurrent launches
    /// from picking the same index due to actor re-entrancy.
    private var launchingIndices: Set<Int> = []

    private var totalCount: Int {
        availableDatabases.count + inUseDatabases.count + launchingIndices.count
    }

    func configure(_ configuration: DatabasePool.Configuration) async throws {
        guard state == .unconfigured else {
            throw DatabasePoolError.alreadyConfigured
        }
        self.configuration = configuration

        let existing = try await findExistingDatabases(
            configuration: configuration,
            maxCount: configuration.poolSize
        )
        for db in existing {
            availableDatabases.insert(db)
        }
        logger?.info("Discovered \(existing.count) existing databases")

        self.state = .active
    }

    /// Returns an available database, launching a new container on demand if
    /// the pool hasn't reached capacity yet. Returns `nil` when all databases
    /// are currently in use (caller should retry after a short delay).
    func retain() async throws -> TestDatabase? {
        guard let configuration else {
            throw DatabasePoolError.notConfigured
        }
        guard state == .active else {
            throw DatabasePoolError.destroyed
        }

        if let database = availableDatabases.randomElement() {
            availableDatabases.remove(database)
            inUseDatabases.insert(database)
            return database
        }

        guard totalCount < configuration.poolSize else {
            return nil
        }

        let usedIndices = Set(availableDatabases.map(\.index))
            .union(inUseDatabases.map(\.index))
            .union(launchingIndices)
        guard let index = (0..<configuration.poolSize).first(where: { !usedIndices.contains($0) }) else {
            return nil
        }

        launchingIndices.insert(index)
        do {
            let database = try await TestDatabase.launch(
                index: index,
                configuration: configuration
            )
            launchingIndices.remove(index)
            inUseDatabases.insert(database)
            logger?.info("Launched database on demand at index \(index)")
            return database
        } catch {
            launchingIndices.remove(index)
            throw error
        }
    }

    func release(_ database: TestDatabase) {
        inUseDatabases.remove(database)
        availableDatabases.insert(database)
    }

    func destroy() async throws {
        guard state == .active else { return }
        self.state = .destroying

        let allDatabases = availableDatabases.union(inUseDatabases)
        availableDatabases = []
        inUseDatabases = []
        launchingIndices = []

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for database in allDatabases {
                    group.addTask {
                        logger?.info("Destroying database: \(database)")
                        try await database.destroy()
                    }
                }

                var firstError: (any Error)? = nil

                while let result = await group.nextResult() {
                    if case .failure(let error) = result, firstError == nil {
                        firstError = error
                    }
                }

                if let firstError {
                    throw firstError
                }
            }

            self.state = .unconfigured
        } catch {
            self.state = .unconfigured
            throw error
        }
    }

    private func findExistingDatabases(
        configuration: DatabasePool.Configuration,
        maxCount: Int
    ) async throws -> [TestDatabase] {
        let output = try await ShellOut.shellOut(to: .getContainerNames).stdout
        let lines = output.components(separatedBy: .newlines)
        let prefix = "\(configuration.containerPrefix)_"

        var existingDatabases: [TestDatabase] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(prefix) else { continue }

            let portString = trimmed.replacingOccurrences(of: prefix, with: "")
            if let port = Int(portString), port >= configuration.startPort {
                let index = port - configuration.startPort
                if index < maxCount {
                    let db = TestDatabase(
                        index: index,
                        host: configuration.host,
                        port: port,
                        containerName: trimmed
                    )
                    existingDatabases.append(db)
                }
            }
        }

        return Array(existingDatabases.prefix(maxCount))
    }
}
