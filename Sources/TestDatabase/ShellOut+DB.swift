import ShellOut

extension ShellOutCommand {
    static func launchDB(
        containerName: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        image: String
    ) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "run", "--name", containerName,
            "-e", "POSTGRES_DB=\(database)",
            "-e", "POSTGRES_USER=\(username)",
            "-e", "POSTGRES_PASSWORD=\(password)",
            "-e", "POSTGRES_HOST_AUTH_METHOD=md5",
            "-e", "POSTGRES_INITDB_ARGS=--auth-host=md5",
            "-e", "PGDATA=/pgdata",
            "--tmpfs", "/pgdata:rw,noexec,nosuid,size=1024m",
            "-p", "\(port):5432",
            "-d",
            image,
        ])
    }

    static func removeDB(containerName: String) -> ShellOutCommand {
        .init(command: .docker, arguments: [
            "rm", "-f", containerName,
        ])
    }

    static var getContainerNames: ShellOutCommand {
        .init(command: .docker, arguments: [
            "ps", "--format", "{{.Names}}",
        ])
    }
}

private extension String {
    static var docker: Self {
#if os(macOS)
        // Starting from macOS 15.4.1 Xcode does not have `/usr/local/bin` in its path anymore.
        "/usr/local/bin/docker"
#else
        "docker"
#endif
    }
}
