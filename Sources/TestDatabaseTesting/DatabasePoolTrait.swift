import Testing
import TestDatabase

public struct DatabasePoolTrait: TestTrait, SuiteTrait, TestScoping {
    @TaskLocal private static var isPoolConfigured: Bool = false

    let configuration: DatabasePool.Configuration

    public var isRecursive: Bool { true }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        if testCase != nil {
            let box = DatabaseBox()
            try await TestDatabaseStorage.$box.withValue(box) {
                try await function()
            }
            if let database = box.storage.withLock({ $0 }) {
                await DatabasePool.release(database)
            }
        } else if !Self.isPoolConfigured {
            try await DatabasePool.configure(configuration)
            do {
                try await Self.$isPoolConfigured.withValue(true) {
                    try await function()
                }
                try await DatabasePool.destroy()
            } catch {
                try? await DatabasePool.destroy()
                throw error
            }
        } else {
            try await function()
        }
    }
}

extension Trait where Self == DatabasePoolTrait {
    public static func databasePool(
        capacity: Int = 8,
        containerPrefix: String = "testdb",
        username: String = "test",
        password: String = "test",
        databaseName: String = "test",
        startPort: Int = 15432,
        dockerImage: String = "postgres:16-alpine",
        host: String = "localhost"
    ) -> Self {
        .init(configuration: .init(
            containerPrefix: containerPrefix,
            username: username,
            password: password,
            databaseName: databaseName,
            startPort: startPort,
            poolSize: capacity,
            dockerImage: dockerImage,
            host: host
        ))
    }
}
