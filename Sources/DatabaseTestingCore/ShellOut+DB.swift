//
//  ShellOut+DB.swift
//
//  Copyright © 2024 Noah Kamara.
//

import ShellOut

extension ShellOutCommand {
    static func launchDB(
        containerName: String,
        username: String,
        password: String,
        database: String,
        image: String
    ) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "run", "--name", containerName,
            "--label", "testdb.managed=true",
            "-e", "POSTGRES_DB=\(database)",
            "-e", "POSTGRES_USER=\(username)",
            "-e", "POSTGRES_PASSWORD=\(password)",
            "-e", "POSTGRES_HOST_AUTH_METHOD=md5",
            "-e", "POSTGRES_INITDB_ARGS=--auth-host=md5",
            "-e", "PGDATA=/pgdata",
            "--tmpfs", "/pgdata:rw,noexec,nosuid,size=1024m",
            "-p", "0:5432",
            "-d",
            image,
        ])
    }

    static func removeDB(containerName: String) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "rm", "-f", containerName,
        ])
    }

    static func getContainerPort(containerName: String) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "port", containerName, "5432/tcp",
        ])
    }

    static func inspectContainerEnv(containerName: String) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "inspect", "--format", "{{json .Config.Env}}", containerName,
        ])
    }

    static var getManagedContainerNames: ShellOutCommand {
        .init(command: .docker, arguments: [
            "ps", "--filter", "label=testdb.managed=true", "--format", "{{.Names}}",
        ])
    }
}

private extension String {
    static var docker: Self {
#if os(macOS)
        "/usr/local/bin/docker"
#else
        "docker"
#endif
    }
}
