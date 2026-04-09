//
//  TestDatabase+Current.swift
//
//  Copyright © 2024 Noah Kamara.
//

import DatabaseTestingCore

public extension TestDatabase {
    /// Returns the test database for the current scope, lazily acquiring one
    /// from the pool and running all stacked preparations on first access.
    static func current() async throws -> TestDatabase {
        guard let box = DatabaseContext.box else {
            preconditionFailure(
                "TestDatabase.current() called outside of a .database() trait scope"
            )
        }

        if let existing = box.storage.withLock({ $0 }) {
            return existing
        }

        let database = try await DatabasePool.retain()

        for configuration in DatabaseContext.configurationStack {
            try await configuration.prepare(database)
        }

        box.storage.withLock { $0 = database }
        return database
    }
}
