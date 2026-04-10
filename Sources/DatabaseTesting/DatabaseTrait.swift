//
//  DatabaseTrait.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTestingCore
import Testing

public struct DatabaseTrait: TestTrait, SuiteTrait, TestScoping {
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
            await DatabaseContext.poolLifecycle.enterSuiteScope()
            do {
                try await function()
                if await DatabaseContext.poolLifecycle.exitSuiteScope() {
                    try await DatabasePool.destroy()
                }
            } catch {
                if await DatabaseContext.poolLifecycle.exitSuiteScope() {
                    try? await DatabasePool.destroy()
                }
                throw error
            }
        } else {
            _ = await DatabaseContext.registry.push(
                testID: test.id,
                configuration: self.configuration
            )
            do {
                try await function()
            } catch {
                if let box = await DatabaseContext.registry.pop(
                    testID: test.id,
                    hadConfiguration: self.configuration != nil
                ), let database = box.storage.withLock({ $0 }) {
                    await DatabasePool.release(database)
                }
                throw error
            }
            if let box = await DatabaseContext.registry.pop(
                testID: test.id,
                hadConfiguration: self.configuration != nil
            ), let database = box.storage.withLock({ $0 }) {
                await DatabasePool.release(database)
            }
        }
    }
}

public extension Trait where Self == DatabaseTrait {
    /// Registers a preparation function for the test database
    static func database(
        prepare: (@Sendable (TestDatabase) async throws -> Void)? = nil
    ) -> Self {
        .init(configuration: prepare.map { DatabaseConfiguration(prepare: $0) })
    }

    /// Registers a preparation function for the test database
    /// > This overload is to prevent confusing compile errors when preparation methods return a type
    static func database(
        prepare: @escaping @Sendable (TestDatabase) async throws -> some Any
    ) -> Self {
        .init(
            configuration: DatabaseConfiguration(prepare: { db in try await prepare(db) })
        )
    }
}
