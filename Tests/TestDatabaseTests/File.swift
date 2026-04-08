import Testing
import TestDatabase
import TestDatabaseTesting

@Suite(
    .databasePool(capacity: 8),
    .database(prepare: { db in })
)
struct ExampleSuite {
    @Test
    func defaultTest() async throws {
        let db = try await TestDatabase.current()
        _ = db
    }

    @Test(.database(prepare: { db in
        // per method customization of the database
    }))
    func customTest() async throws {
        let db = try await TestDatabase.current()
        _ = db
    }
}
