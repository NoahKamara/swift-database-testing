//
//  PoolRegistryTests.swift
//
//  Copyright © 2024 Noah Kamara.
//

@testable import DatabaseTestingCore
import Testing

private func makeDB(
    port: Int = 5432,
    name: String = "testdb_a"
) -> TestDatabase {
    TestDatabase(
        host: "localhost",
        port: port,
        databaseName: "test_\(name)",
        username: "user_\(name)",
        password: "pass_\(name)",
        containerName: name
    )
}

@Suite("PoolRegistry")
struct PoolRegistryTests {
    @Suite("State Machine")
    struct StateMachineTests {
        @Test("starts in unconfigured state")
        func initialState() async {
            let registry = PoolRegistry()
            let state = await registry.state
            #expect(state == .unconfigured)
        }

        @Test("configureForTesting transitions to active")
        func configureToActive() async {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init())
            let state = await registry.state
            #expect(state == .active)
        }

        @Test("reset transitions back to unconfigured")
        func resetToUnconfigured() async {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init())
            await registry.reset()
            let state = await registry.state
            #expect(state == .unconfigured)
        }

        @Test("reset clears all databases")
        func resetClearsAll() async {
            let registry = PoolRegistry()
            let dbs: Set<TestDatabase> = [makeDB(port: 1), makeDB(port: 2)]
            await registry.configureForTesting(.init(capacity: 4), databases: dbs)
            await registry.reset()

            #expect(await registry.availableDatabases.isEmpty)
            #expect(await registry.inUseDatabases.isEmpty)
            #expect(await registry.launchingCount == 0)
            #expect(await registry.configuration == nil)
        }

        @Test("activate reclaims existing databases")
        func activateReclaimsExisting() async throws {
            let db = makeDB(port: 2, name: "testdb_2")
            let registry = PoolRegistry(existingDatabasesLoader: { maxCount in
                #expect(maxCount == 3)
                return [db]
            })

            try await registry.activate(.init(capacity: 3))

            #expect(await registry.state == .active)
            #expect(await registry.configuration == .init(capacity: 3))
            #expect(await registry.availableDatabases == [db])
        }
    }

    @Suite("Retain")
    struct RetainTests {
        @Test("returns an available database")
        func retainAvailable() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 4), databases: [db])

            let retained = try await registry.retain()
            #expect(retained == db)
        }

        @Test("moves database from available to in-use")
        func movesToInUse() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 4), databases: [db])

            _ = try await registry.retain()
            #expect(await registry.availableDatabases.isEmpty)
            #expect(await registry.inUseDatabases.contains(db))
        }

        @Test("returns nil when all databases in use and at capacity")
        func nilAtCapacity() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 1), databases: [db])

            _ = try await registry.retain()
            let second = try await registry.retain()
            #expect(second == nil)
        }

        @Test("after destroy, state is unconfigured (not permanently destroyed)")
        func stateAfterDestroy() async throws {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init(capacity: 1))

            try await registry.destroy()

            #expect(await registry.state == .unconfigured)
        }

        @Test("returns different databases from pool")
        func returnsDifferent() async throws {
            let registry = PoolRegistry()
            let db1 = makeDB(port: 1, name: "testdb_1")
            let db2 = makeDB(port: 2, name: "testdb_2")
            await registry.configureForTesting(.init(capacity: 2), databases: [db1, db2])

            let first = try await registry.retain()
            let second = try await registry.retain()
            #expect(first != nil)
            #expect(second != nil)
            #expect(first != second)
        }

        @Test("totalCount reflects available + inUse")
        func totalCount() async throws {
            let registry = PoolRegistry()
            let db1 = makeDB(port: 1, name: "testdb_1")
            let db2 = makeDB(port: 2, name: "testdb_2")
            await registry.configureForTesting(.init(capacity: 4), databases: [db1, db2])
            #expect(await registry.totalCount == 2)

            _ = try await registry.retain()
            #expect(await registry.totalCount == 2)
        }
    }

    @Suite("Release")
    struct ReleaseTests {
        @Test("moves database back to available")
        func releaseToAvailable() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 4), databases: [db])

            let retained = try try await #require(registry.retain())
            await registry.release(retained)

            #expect(await registry.availableDatabases.contains(db))
            #expect(await registry.inUseDatabases.isEmpty)
        }

        @Test("released database can be retained again")
        func retainAfterRelease() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 1), databases: [db])

            let first = try try await #require(registry.retain())
            await registry.release(first)

            let second = try await registry.retain()
            #expect(second == db)
        }

        @Test("releasing a database not in the in-use set is safe")
        func releaseUnknown() async {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init())
            let db = makeDB()
            await registry.release(db)
            #expect(await registry.availableDatabases.contains(db))
        }
    }

    @Suite("Destroy")
    struct DestroyTests {
        @Test("clears all sets on empty pool")
        func destroyEmpty() async throws {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init())
            try await registry.destroy()

            #expect(await registry.availableDatabases.isEmpty)
            #expect(await registry.inUseDatabases.isEmpty)
            #expect(await registry.launchingCount == 0)
        }

        @Test("is idempotent from unconfigured state")
        func destroyUnconfigured() async throws {
            let registry = PoolRegistry()
            try await registry.destroy()
            #expect(await registry.state == .unconfigured)
        }

        @Test("transitions to unconfigured after destroy")
        func stateAfterDestroy() async throws {
            let registry = PoolRegistry()
            await registry.configureForTesting(.init())
            try await registry.destroy()
            #expect(await registry.state == .unconfigured)
        }

        @Test("destroy with databases throws but still resets state")
        func destroyWithDatabasesResetsState() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 2), databases: [db])

            do {
                try await registry.destroy()
            } catch {
                // Expected: Docker commands will fail
            }

            #expect(await registry.state == .unconfigured)
            #expect(await registry.availableDatabases.isEmpty)
            #expect(await registry.inUseDatabases.isEmpty)
        }
    }

    @Suite("Capacity")
    struct CapacityTests {
        @Test("respects capacity limit")
        func respectsLimit() async throws {
            let registry = PoolRegistry()
            let db1 = makeDB(port: 1, name: "testdb_1")
            let db2 = makeDB(port: 2, name: "testdb_2")
            let db3 = makeDB(port: 3, name: "testdb_3")
            await registry.configureForTesting(
                .init(capacity: 3), databases: [db1, db2, db3]
            )

            _ = try await registry.retain()
            _ = try await registry.retain()
            _ = try await registry.retain()

            let overflow = try await registry.retain()
            #expect(overflow == nil)
        }

        @Test("capacity 1 limits to single database")
        func singleCapacity() async throws {
            let registry = PoolRegistry()
            let db = makeDB()
            await registry.configureForTesting(.init(capacity: 1), databases: [db])

            _ = try await registry.retain()
            #expect(try await registry.retain() == nil)
        }
    }

    @Suite("Configuration")
    struct ConfigurationTests {
        @Test("stores provided configuration")
        func storesConfig() async {
            let registry = PoolRegistry()
            let config = DatabasePool.Configuration(capacity: 5, image: "postgres:16")
            await registry.configureForTesting(config)

            let stored = await registry.configuration
            #expect(stored == config)
        }

        @Test("configureForTesting replaces previous state")
        func replacesState() async throws {
            let registry = PoolRegistry()
            let db1 = makeDB(port: 1, name: "testdb_1")
            await registry.configureForTesting(.init(capacity: 2), databases: [db1])
            _ = try await registry.retain()

            let db2 = makeDB(port: 2, name: "testdb_2")
            await registry.configureForTesting(.init(capacity: 4), databases: [db2])

            #expect(await registry.availableDatabases == [db2])
            #expect(await registry.inUseDatabases.isEmpty)
            #expect(await registry.configuration?.capacity == 4)
        }
    }
}
