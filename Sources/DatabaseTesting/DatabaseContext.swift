//
//  DatabaseContext.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTestingCore
import Synchronization

public struct DatabaseConfiguration: Sendable {
    public let prepare: @Sendable (TestDatabase) async throws -> Void

    public init(prepare: @escaping @Sendable (TestDatabase) async throws -> Void) {
        self.prepare = prepare
    }
}

public enum DatabaseContext {
    @TaskLocal public static var configurationStack: [DatabaseConfiguration] = []
    @TaskLocal public static var box: Box?

    public final class Box: Sendable {
        let storage: Mutex<TestDatabase?> = .init(nil)
    }
}
