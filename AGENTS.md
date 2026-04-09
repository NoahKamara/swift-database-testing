# DatabaseTesting

Swift package that spins up ephemeral PostgreSQL containers (Docker) for tests, pools them for concurrent test execution, and integrates with Swift Testing via suite/test traits.

## Modules

| Module | Purpose |
|--------|---------|
| `DatabaseTestingCore` | Docker container lifecycle (`ShellOut+DB`), `TestDatabase`, `DatabasePool` (enum facade over `PoolRegistry` actor), retry helpers. Depends on ShellOut. |
| `DatabaseTesting` | Swift Testing integration: `DatabaseTrait`, `DatabaseConfiguration`, `DatabaseContext` (`@TaskLocal` stacks), `TestDatabase.current()`. |

## Conventions

- Swift 6 language mode, swift-tools-version 6.3, macOS 26+
- Nested `@TaskLocal` stacks (`configurationStack`, `box`) to separate suite vs test lifecycle
- Visibility: `public` for consumer API, `package` for pool internals / registry
- Docker containers: named `testdb_*`, label `testdb.managed=true`, tmpfs for speed
- Docker path: `/usr/local/bin/docker` on macOS, `docker` on Linux
- Env overrides: `TEST_DB_CAPACITY`, `TEST_DB_IMAGE`

## Testing

- Swift Testing framework (`@Suite`, `@Test`, `#expect`)
- `@testable import DatabaseTestingCore` for unit tests without Docker
- Integration tests use `.database(prepare:)` trait + `TestDatabase.current()`

## Agent Guidance

- This package is experimental. Never introduce backward compatibility. Change existing parts if they do not fit a new approach.
- Always validate using `swift test`
