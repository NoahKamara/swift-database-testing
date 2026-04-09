# DatabaseTesting

Ephemeral PostgreSQL databases for Swift Testing. Spins up Docker containers on demand, pools them for concurrent test execution, and tears them down when the suite finishes.

## Requirements

- Swift 6.3+ / swift-tools-version 6.3
- macOS 26+
- Docker (accessible at `/usr/local/bin/docker`)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/noahkamara/swift-database-testing", from: "0.1.0"),
]
```

Then add the module you need to your test target:

```swift
.testTarget(
    name: "MyTests",
    dependencies: [
        .product(name: "DatabaseTesting", package: "swift-database-testing"),
    ]
)
```

## Usage

Apply the `.database()` trait to a suite or test. The trait manages the pool lifecycle automatically -- containers are created as needed and destroyed when the outermost suite finishes.

```swift
import Testing
import DatabaseTesting

@Suite(.database())
struct MyDatabaseTests {
    @Test func insertAndQuery() async throws {
        let db = try TestDatabase.current()

        // db.host, db.port, db.username, db.password, db.databaseName
        // are all available to connect your client of choice.
    }
}
```

### Preparing the database

Pass a `prepare` closure to run setup (migrations, seed data, etc.) against each database before tests use it:

```swift
@Suite(.database(prepare: { db in
    // Run migrations, create tables, insert seed data.
}))
struct MigrationTests {
    @Test func readsSeedData() async throws {
        let db = try TestDatabase.current()
        // ...
    }
}
```

## Modules

| Module | Purpose |
|---|---|
| `DatabaseTestingCore` | Docker container lifecycle, `TestDatabase`, `DatabasePool`, retry helpers. No dependency on Swift Testing. |
| `DatabaseTesting` | Swift Testing integration: `DatabaseTrait`, `TaskLocal` context, `.database()` trait API. |

Import `DatabaseTestingCore` directly if you want the pool and container management without the Swift Testing trait (e.g., for XCTest or custom harnesses).

## Configuration

The pool reads its configuration from environment variables at first use:

| Variable | Default | Description |
|---|---|---|
| `TEST_DB_CAPACITY` | `8` | Maximum number of concurrent database containers. |
| `TEST_DB_IMAGE` | `postgres:17-alpine` | Docker image to use for PostgreSQL. |

## How it works

1. The first time a test needs a database, `PoolRegistry` initializes. It looks for existing containers labeled `testdb.managed=true` and reclaims them (so a crashed previous run doesn't leak containers).
2. When a test retains a database and none are available, a new container is launched up to the configured capacity. If the pool is full, the test waits (with a 10-second timeout).
3. Containers use tmpfs-backed `PGDATA` for faster writes and ephemeral storage.
4. Each container gets a random name (`testdb_<id>`), user, password, and database name. The host port is dynamically assigned (`-p 0:5432`).
5. When the outermost `DatabaseTrait`-scoped suite finishes, all containers are destroyed in parallel.

## License

See [LICENSE](LICENSE) for details.
