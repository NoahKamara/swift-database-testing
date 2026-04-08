import Testing
@testable import TestDatabase

// MARK: - Configuration Tests

@Suite("Configuration")
struct ConfigurationTests {
    @Test("default values")
    func defaults() {
        let config = DatabasePool.Configuration()
        #expect(config.containerPrefix == "testdb")
        #expect(config.username == "test")
        #expect(config.password == "test")
        #expect(config.databaseName == "test")
        #expect(config.startPort == 15432)
        #expect(config.poolSize == 8)
        #expect(config.dockerImage == "postgres:16-alpine")
        #expect(config.host == "localhost")
    }

    @Test("custom values")
    func customValues() {
        let config = DatabasePool.Configuration(
            containerPrefix: "myapp",
            username: "admin",
            password: "secret",
            databaseName: "mydb",
            startPort: 20000,
            poolSize: 4,
            dockerImage: "postgres:17-alpine",
            host: "127.0.0.1"
        )
        #expect(config.containerPrefix == "myapp")
        #expect(config.username == "admin")
        #expect(config.password == "secret")
        #expect(config.databaseName == "mydb")
        #expect(config.startPort == 20000)
        #expect(config.poolSize == 4)
        #expect(config.dockerImage == "postgres:17-alpine")
        #expect(config.host == "127.0.0.1")
    }

    @Test("equality")
    func equality() {
        let a = DatabasePool.Configuration()
        let b = DatabasePool.Configuration()
        #expect(a == b)

        let c = DatabasePool.Configuration(containerPrefix: "other")
        #expect(a != c)
    }

    @Test("hashable")
    func hashable() {
        let a = DatabasePool.Configuration()
        let b = DatabasePool.Configuration()
        #expect(a.hashValue == b.hashValue)

        var set: Set<DatabasePool.Configuration> = [a]
        set.insert(b)
        #expect(set.count == 1)

        let c = DatabasePool.Configuration(poolSize: 2)
        set.insert(c)
        #expect(set.count == 2)
    }
}

// MARK: - TestDatabase Tests

@Suite("TestDatabase")
struct TestDatabaseTests {
    @Test("computed name uses index")
    func computedName() {
        let db = TestDatabase(index: 0, host: "localhost", port: 15432, containerName: "testdb_15432")
        #expect(db.name == "test-database-0")

        let db5 = TestDatabase(index: 5, host: "localhost", port: 15437, containerName: "testdb_15437")
        #expect(db5.name == "test-database-5")
    }

    @Test("stores properties")
    func storedProperties() {
        let db = TestDatabase(index: 3, host: "192.168.1.1", port: 20003, containerName: "myprefix_20003")
        #expect(db.index == 3)
        #expect(db.host == "192.168.1.1")
        #expect(db.port == 20003)
        #expect(db.containerName == "myprefix_20003")
    }

    @Test("equality based on all stored properties")
    func equality() {
        let a = TestDatabase(index: 0, host: "localhost", port: 15432, containerName: "testdb_15432")
        let b = TestDatabase(index: 0, host: "localhost", port: 15432, containerName: "testdb_15432")
        #expect(a == b)

        let c = TestDatabase(index: 1, host: "localhost", port: 15433, containerName: "testdb_15433")
        #expect(a != c)
    }

    @Test("usable in a Set")
    func setUsage() {
        let a = TestDatabase(index: 0, host: "localhost", port: 15432, containerName: "testdb_15432")
        let b = TestDatabase(index: 0, host: "localhost", port: 15432, containerName: "testdb_15432")
        let c = TestDatabase(index: 1, host: "localhost", port: 15433, containerName: "testdb_15433")

        let set: Set<TestDatabase> = [a, b, c]
        #expect(set.count == 2)
    }
}

// MARK: - Retry Tests

@Suite("Retry")
struct RetryTests {
    @Test("succeeds on first attempt")
    func immediateSuccess() async throws {
        var attempts = 0
        let result = try await run(maxAttempts: 3) { _ in
            attempts += 1
            return 42
        }
        #expect(result == 42)
        #expect(attempts == 1)
    }

    @Test("retries until success")
    func retriesUntilSuccess() async throws {
        var attempts = 0
        let result: Int = try await run(
            maxAttempts: 3,
            backoff: .constant(.milliseconds(10)),
            operation: { _ in
                attempts += 1
                if attempts < 3 {
                    throw TestError.intentional
                }
                return 99
            },
            errorLogger: { _ in }
        )
        #expect(result == 99)
        #expect(attempts == 3)
    }

    @Test("throws after max attempts exceeded")
    func maxAttemptsExceeded() async {
        var attempts = 0
        await #expect(throws: Retry.Error.self) {
            try await run(
                maxAttempts: 2,
                backoff: .constant(.milliseconds(10)),
                operation: { (_: Int) -> Void in
                    attempts += 1
                    throw TestError.intentional
                },
                errorLogger: { _ in }
            )
        }
        #expect(attempts == 2)
    }

    @Test("timeout version completes within deadline")
    func timeoutSuccess() async throws {
        let result = try await run(timeout: .seconds(5)) {
            return "done"
        }
        #expect(result == "done")
    }

    @Test("timeout version throws on expiry")
    func timeoutExpiry() async {
        await #expect(throws: Retry.Error.self) {
            try await run(timeout: .milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
                return "should not reach"
            }
        }
    }
}

private enum TestError: Error {
    case intentional
}
