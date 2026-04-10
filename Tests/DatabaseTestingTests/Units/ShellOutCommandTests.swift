//
//  ShellOutCommandTests.swift
//
//  Copyright © 2024 Noah Kamara.
//

@testable import DatabaseTestingCore
import ShellOut
import Testing

@Suite("ShellOutCommand Extensions")
struct ShellOutCommandTests {
    @Suite("launchDB")
    struct LaunchDBTests {
        let command = ShellOutCommand.launchDB(
            containerName: "testdb_abc",
            username: "user_xyz",
            password: "secret123",
            database: "test_db",
            image: "postgres:17-alpine"
        )

        @Test("uses docker binary")
        func dockerBinary() {
#if os(macOS)
            #expect(self.command.command == "/usr/local/bin/docker")
#else
            #expect(self.command.command == "docker")
#endif
        }

        @Test("starts with run and container name")
        func runSubcommand() throws {
            #expect(self.command.arguments.first == "run")
            #expect(self.command.arguments.contains("--name"))
            let nameIdx = try #require(self.command.arguments.firstIndex(of: "--name"))
            #expect(self.command.arguments[nameIdx + 1] == "testdb_abc")
        }

        @Test("applies managed label")
        func managedLabel() throws {
            #expect(self.command.arguments.contains("--label"))
            let idx = try #require(self.command.arguments.firstIndex(of: "--label"))
            #expect(self.command.arguments[idx + 1] == "testdb.managed=true")
        }

        @Test("sets POSTGRES_DB env var")
        func postgresDB() {
            #expect(self.command.arguments.contains("POSTGRES_DB=test_db"))
        }

        @Test("sets POSTGRES_USER env var")
        func postgresUser() {
            #expect(self.command.arguments.contains("POSTGRES_USER=user_xyz"))
        }

        @Test("sets POSTGRES_PASSWORD env var")
        func postgresPassword() {
            #expect(self.command.arguments.contains("POSTGRES_PASSWORD=secret123"))
        }

        @Test("sets POSTGRES_HOST_AUTH_METHOD to md5")
        func authMethod() {
            #expect(self.command.arguments.contains("POSTGRES_HOST_AUTH_METHOD=md5"))
        }

        @Test("sets POSTGRES_INITDB_ARGS")
        func initdbArgs() {
            #expect(self.command.arguments.contains("POSTGRES_INITDB_ARGS=--auth-host=md5"))
        }

        @Test("sets PGDATA env var")
        func pgdata() {
            #expect(self.command.arguments.contains("PGDATA=/pgdata"))
        }

        @Test("uses tmpfs mount for speed")
        func tmpfs() throws {
            #expect(self.command.arguments.contains("--tmpfs"))
            let idx = try #require(self.command.arguments.firstIndex(of: "--tmpfs"))
            #expect(self.command.arguments[idx + 1] == "/pgdata:rw,noexec,nosuid,size=1024m")
        }

        @Test("maps ephemeral port to 5432")
        func portMapping() throws {
            #expect(self.command.arguments.contains("-p"))
            let idx = try #require(self.command.arguments.firstIndex(of: "-p"))
            #expect(self.command.arguments[idx + 1] == "0:5432")
        }

        @Test("runs detached")
        func detached() {
            #expect(self.command.arguments.contains("-d"))
        }

        @Test("image is last argument")
        func imageArgument() {
            #expect(self.command.arguments.last == "postgres:17-alpine")
        }

        @Test("works with different images")
        func differentImage() {
            let cmd = ShellOutCommand.launchDB(
                containerName: "testdb_x",
                username: "u",
                password: "p",
                database: "d",
                image: "postgres:16-bookworm"
            )
            #expect(cmd.arguments.last == "postgres:16-bookworm")
        }
    }

    @Suite("removeDB")
    struct RemoveDBTests {
        @Test("constructs docker rm -f command")
        func removesContainer() {
            let cmd = ShellOutCommand.removeDB(containerName: "testdb_abc")
            #expect(cmd.arguments == ["rm", "-f", "testdb_abc"])
        }

        @Test("handles arbitrary container names")
        func arbitraryName() {
            let cmd = ShellOutCommand.removeDB(containerName: "some-container-name-123")
            #expect(cmd.arguments.last == "some-container-name-123")
        }
    }

    @Suite("getContainerPort")
    struct GetContainerPortTests {
        @Test("constructs docker port command")
        func portsCommand() {
            let cmd = ShellOutCommand.getContainerPort(containerName: "testdb_xyz")
            #expect(cmd.arguments == ["port", "testdb_xyz", "5432/tcp"])
        }
    }

    @Suite("inspectContainerEnv")
    struct InspectContainerEnvTests {
        @Test("constructs docker inspect command with JSON env format")
        func inspectCommand() {
            let cmd = ShellOutCommand.inspectContainerEnv(containerName: "testdb_xyz")
            #expect(cmd.arguments == [
                "inspect", "--format", "{{json .Config.Env}}", "testdb_xyz",
            ])
        }
    }

    @Suite("getManagedContainerNames")
    struct GetManagedContainerNamesTests {
        @Test("filters by managed label")
        func managedFilter() throws {
            let cmd = ShellOutCommand.getManagedContainerNames
            #expect(cmd.arguments.contains("--filter"))
            let idx = try #require(cmd.arguments.firstIndex(of: "--filter"))
            #expect(cmd.arguments[idx + 1] == "label=testdb.managed=true")
        }

        @Test("outputs only names")
        func namesFormat() throws {
            let cmd = ShellOutCommand.getManagedContainerNames
            #expect(cmd.arguments.contains("--format"))
            let idx = try #require(cmd.arguments.firstIndex(of: "--format"))
            #expect(cmd.arguments[idx + 1] == "{{.Names}}")
        }
    }

    @Suite("runPSQL")
    struct RunPSQLTests {
        @Test("constructs docker exec with psql")
        func buildsCommand() {
            let cmd = ShellOutCommand.runPSQL(
                containerName: "testdb_1",
                username: "user_1",
                password: "secret",
                database: "postgres",
                sql: "SELECT 1"
            )

            #expect(cmd.arguments == [
                "exec",
                "-e", "PGPASSWORD=secret",
                "testdb_1",
                "psql",
                "-v", "ON_ERROR_STOP=1",
                "-U", "user_1",
                "-d", "postgres",
                "-c", "SELECT 1",
            ])
        }
    }
}
