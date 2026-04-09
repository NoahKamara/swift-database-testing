//
//  DatabaseTrait.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTestingCore
import Testing

public struct DatabaseTrait: TestTrait, SuiteTrait, TestScoping {
    @TaskLocal private static var isPoolScoped: Bool = false

    let configuration: DatabaseConfiguration?

    public var isRecursive: Bool {
        true
    }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        if test.isSuite, testCase == nil {
            if !Self.isPoolScoped {
                try await Self.$isPoolScoped.withValue(true) {
                    do {
                        try await self.runWithConfig(function)
                        try await DatabasePool.destroy()
                    } catch {
                        try? await DatabasePool.destroy()
                        throw error
                    }
                }
            } else {
                try await self.runWithConfig(function)
            }
        } else {
            let box = DatabaseContext.Box()
            try await DatabaseContext.$box.withValue(box) {
                try await self.runWithConfig(function)
            }
            if let database = box.storage.withLock({ $0 }) {
                await DatabasePool.release(database)
            }
        }
    }

    private func runWithConfig(
        _ function: @Sendable () async throws -> Void
    ) async throws {
        if let configuration {
            try await DatabaseContext.$configurationStack.withValue(
                DatabaseContext.configurationStack + [configuration]
            ) { try await function() }
        } else {
            try await function()
        }
    }
}

public extension Trait where Self == DatabaseTrait {
    static func database(
        prepare: (@Sendable (TestDatabase) async throws -> Void)? = nil
    ) -> Self {
        .init(configuration: prepare.map { DatabaseConfiguration(prepare: $0) })
    }
}
