import TestDatabase

public struct DatabaseConfiguration: Sendable {
    public let prepare: @Sendable (TestDatabase) async throws -> Void

    public init(prepare: @escaping @Sendable (TestDatabase) async throws -> Void) {
        self.prepare = prepare
    }
}
