import TestDatabase

extension TestDatabase {
    /// Returns the test database for the current scope, lazily acquiring one
    /// from the pool and running all stacked preparations on first access.
    public static func current() async throws -> TestDatabase {
        guard let box = TestDatabaseStorage.box else {
            preconditionFailure(
                "TestDatabase.current() called outside of a .databasePool() trait scope"
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
