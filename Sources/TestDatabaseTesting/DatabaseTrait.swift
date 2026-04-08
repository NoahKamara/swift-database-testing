import Testing
import TestDatabase

public struct DatabaseTrait: TestTrait, SuiteTrait, TestScoping {
    let configuration: DatabaseConfiguration

    public var isRecursive: Bool { true }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await DatabaseContext.$configurationStack.withValue(
            DatabaseContext.configurationStack + [configuration]
        ) {
            try await function()
        }
    }
}

extension Trait where Self == DatabaseTrait {
    public static func database(
        prepare: @escaping @Sendable (TestDatabase) async throws -> Void
    ) -> Self {
        .init(configuration: .init(prepare: prepare))
    }
}
