//
//  DatabaseContext.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTestingCore
import Synchronization
import Testing

public struct DatabaseConfiguration: Sendable {
    public let prepare: @Sendable (TestDatabase) async throws -> Void

    public init(prepare: @escaping @Sendable (TestDatabase) async throws -> Void) {
        self.prepare = prepare
    }
}

public enum DatabaseContext {
    public final class Box: Sendable {
        let storage: Mutex<TestDatabase?> = .init(nil)
    }

    actor ScopeRegistry {
        struct ScopeState: Sendable {
            var configurationStack: [DatabaseConfiguration]
            let box: Box
            var depth: Int
        }

        private var scopes: [Test.ID: ScopeState] = [:]

        func push(
            testID: Test.ID,
            configuration: DatabaseConfiguration?
        ) -> Box {
            var state = self.scopes[testID] ?? ScopeState(
                configurationStack: [],
                box: Box(),
                depth: 0
            )
            state.depth += 1
            if let configuration {
                state.configurationStack.append(configuration)
            }
            self.scopes[testID] = state
            return state.box
        }

        func currentScope(for testID: Test.ID) -> ScopeState? {
            self.scopes[testID]
        }

        func pop(
            testID: Test.ID,
            hadConfiguration: Bool
        ) -> Box? {
            guard var state = self.scopes[testID] else {
                return nil
            }

            if hadConfiguration {
                _ = state.configurationStack.popLast()
            }

            state.depth -= 1
            if state.depth == 0 {
                self.scopes.removeValue(forKey: testID)
                return state.box
            }

            self.scopes[testID] = state
            return nil
        }
    }

    actor PoolLifecycle {
        private var activeSuiteScopes = 0

        func enterSuiteScope() {
            self.activeSuiteScopes += 1
        }

        func exitSuiteScope() -> Bool {
            self.activeSuiteScopes -= 1
            return self.activeSuiteScopes == 0
        }
    }

    static let registry = ScopeRegistry()
    static let poolLifecycle = PoolLifecycle()
}
