//
//  File.swift
//  TestDatabase
//
//  Created by Noah Kamara on 09.04.2026.
//

import Foundation

/// A `DatabaseFactory` manages a database container lifecycle
protocol ContainerBacking {
    associatedtype Reference

    /// Create a new database instance
    /// - Parameters:
    ///   - image: the image used to create the container
    func create(
        image: String
    ) async throws -> String

    func destroy(_ containerName: String) async throws

    func list() async throws -> [String]
}

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

