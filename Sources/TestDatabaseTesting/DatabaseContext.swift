import Synchronization
import TestDatabase

public enum DatabaseContext {
    @TaskLocal public static var configurationStack: [DatabaseConfiguration] = []
}

public final class DatabaseBox: Sendable {
    let storage: Mutex<TestDatabase?> = .init(nil)
}

public enum TestDatabaseStorage {
    @TaskLocal public static var box: DatabaseBox?
}
