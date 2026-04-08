import ShellOut

public struct TestDatabase: Hashable, Sendable {
    public let index: Int
    public let host: String
    public let port: Int
    public let containerName: String

    public var name: String { "test-database-\(index)" }

    init(index: Int, host: String, port: Int, containerName: String) {
        self.index = index
        self.host = host
        self.port = port
        self.containerName = containerName
    }

    static func launch(
        index: Int,
        configuration: DatabasePool.Configuration,
        maxAttempts: Int = 3
    ) async throws -> TestDatabase {
        let port = configuration.startPort + index
        let containerName = "\(configuration.containerPrefix)_\(port)"
        _ = try? await ShellOut.shellOut(to: .removeDB(containerName: containerName))
        try await run(maxAttempts: maxAttempts) { _ in
            try await ShellOut.shellOut(to: .launchDB(
                containerName: containerName,
                port: port,
                username: configuration.username,
                password: configuration.password,
                database: configuration.databaseName,
                image: configuration.dockerImage
            ))
        }
        return TestDatabase(
            index: index,
            host: configuration.host,
            port: port,
            containerName: containerName
        )
    }

    func destroy(maxAttempts: Int = 3) async throws {
        try await run(maxAttempts: maxAttempts) { _ in
            try await ShellOut.shellOut(to: .removeDB(containerName: self.containerName))
        }
    }
}
