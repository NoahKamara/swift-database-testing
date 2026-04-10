//
//  ParsingTests.swift
//
//  Copyright © 2024 Noah Kamara.
//

@testable import DatabaseTestingCore
import Foundation
import Testing

@Suite("Parsing")
struct ParsingTests {
    @Suite("Port Parsing")
    struct PortParsingTests {
        @Test("parses standard IPv4 docker port output")
        func ipv4() throws {
            let port = try Parsing.port(from: "0.0.0.0:55432")
            #expect(port == 55432)
        }

        @Test("parses IPv6 docker port output")
        func ipv6() throws {
            let port = try Parsing.port(from: "[::]:55432")
            #expect(port == 55432)
        }

        @Test("handles trailing newline")
        func trailingNewline() throws {
            let port = try Parsing.port(from: "0.0.0.0:12345\n")
            #expect(port == 12345)
        }

        @Test("handles leading/trailing whitespace")
        func whitespace() throws {
            let port = try Parsing.port(from: "  0.0.0.0:9999  \n")
            #expect(port == 9999)
        }

        @Test("handles port 1 (minimum)")
        func minPort() throws {
            let port = try Parsing.port(from: "0.0.0.0:1")
            #expect(port == 1)
        }

        @Test("handles port 65535 (maximum)")
        func maxPort() throws {
            let port = try Parsing.port(from: "0.0.0.0:65535")
            #expect(port == 65535)
        }

        @Test("throws on empty string")
        func emptyString() {
            #expect(throws: TestDatabaseError.self) {
                try Parsing.port(from: "")
            }
        }

        @Test("throws on whitespace-only string")
        func whitespaceOnly() {
            #expect(throws: TestDatabaseError.self) {
                try Parsing.port(from: "   \n  ")
            }
        }

        @Test("bare number without colon parses successfully")
        func bareNumber() throws {
            let port = try Parsing.port(from: "55432")
            #expect(port == 55432)
        }

        @Test("throws on non-numeric port")
        func nonNumeric() {
            #expect(throws: TestDatabaseError.self) {
                try Parsing.port(from: "0.0.0.0:abc")
            }
        }

        @Test("throws on trailing colon with no port")
        func trailingColon() {
            #expect(throws: TestDatabaseError.self) {
                try Parsing.port(from: "0.0.0.0:")
            }
        }
    }

    @Suite("Env Parsing")
    struct EnvParsingTests {
        @Test("parses standard docker inspect env output")
        func standard() {
            let env = Parsing.env(
                from: #"["POSTGRES_DB=testdb","POSTGRES_USER=user","POSTGRES_PASSWORD=secret"]"#
            )
            #expect(env["POSTGRES_DB"] == "testdb")
            #expect(env["POSTGRES_USER"] == "user")
            #expect(env["POSTGRES_PASSWORD"] == "secret")
            #expect(env.count == 3)
        }

        @Test("handles values containing equals signs")
        func equalsInValue() {
            let env = Parsing.env(from: #"["KEY=value=with=equals"]"#)
            #expect(env["KEY"] == "value=with=equals")
        }

        @Test("skips entries without equals sign")
        func noEquals() {
            let env = Parsing.env(from: #"["VALID=yes","NOEQUALS","ALSO_VALID=true"]"#)
            #expect(env["VALID"] == "yes")
            #expect(env["ALSO_VALID"] == "true")
            #expect(env.count == 2)
        }

        @Test("returns empty dict for empty JSON array")
        func emptyArray() {
            let env = Parsing.env(from: "[]")
            #expect(env.isEmpty)
        }

        @Test("returns empty dict for invalid JSON")
        func invalidJSON() {
            let env = Parsing.env(from: "not json at all")
            #expect(env.isEmpty)
        }

        @Test("returns empty dict for empty string")
        func emptyString() {
            let env = Parsing.env(from: "")
            #expect(env.isEmpty)
        }

        @Test("returns empty dict for JSON object instead of array")
        func jsonObject() {
            let env = Parsing.env(from: #"{"key": "value"}"#)
            #expect(env.isEmpty)
        }

        @Test("handles whitespace around JSON")
        func whitespace() {
            let env = Parsing.env(from: #"  ["A=1"]  "#)
            #expect(env["A"] == "1")
        }

        @Test("handles trailing newlines")
        func newlines() {
            let env = Parsing.env(from: #"["X=Y"]"# + "\n")
            #expect(env["X"] == "Y")
        }

        @Test("skips entries with empty values (trailing =)")
        func emptyValue() {
            let env = Parsing.env(from: #"["KEY="]"#)
            #expect(env["KEY"] == nil, "split omits empty trailing subsequences")
            #expect(env.isEmpty)
        }

        @Test("handles many environment variables")
        func manyVars() {
            let entries = (0..<50).map { "VAR\($0)=val\($0)" }
            let json = "[" + entries.map { #""\#($0)""# }.joined(separator: ",") + "]"
            let env = Parsing.env(from: json)
            #expect(env.count == 50)
            #expect(env["VAR0"] == "val0")
            #expect(env["VAR49"] == "val49")
        }
    }

    @Suite("shortID")
    struct ShortIDTests {
        @Test("has length 8")
        func length() {
            let id = TestDatabase.shortID()
            #expect(id.count == 8)
        }

        @Test("is lowercase")
        func lowercase() {
            let id = TestDatabase.shortID()
            #expect(id == id.lowercased())
        }

        @Test("contains only hex characters")
        func hexCharacters() {
            let id = TestDatabase.shortID()
            let validChars = CharacterSet(charactersIn: "0123456789abcdef-")
            for scalar in id.unicodeScalars {
                #expect(validChars.contains(scalar), "Unexpected character: \(scalar)")
            }
        }

        @Test("generates unique values")
        func unique() {
            let ids = (0..<100).map { _ in TestDatabase.shortID() }
            let unique = Set(ids)
            #expect(unique.count == ids.count)
        }
    }

    @Suite("Indexed Names")
    struct IndexedNamesTests {
        @Test("derives stable container identity from index")
        func derivesStableIdentity() {
            #expect(TestDatabase.containerName(for: 4) == "testdb_4")
            #expect(TestDatabase.username(for: 4) == "user_4")
            #expect(TestDatabase.databaseName(for: 4) == "test_4")
            #expect(TestDatabase.baselineName(for: 4) == "test_4_baseline")
        }

        @Test("extracts index from indexed container names")
        func extractsIndex() {
            #expect(TestDatabase.index(fromContainerName: "testdb_0") == 0)
            #expect(TestDatabase.index(fromContainerName: "testdb_17") == 17)
        }

        @Test("ignores non-indexed container names")
        func ignoresNonIndexedNames() {
            #expect(TestDatabase.index(fromContainerName: "testdb_abc") == nil)
            #expect(TestDatabase.index(fromContainerName: "postgres") == nil)
        }
    }

    @Suite("randomPassword")
    struct RandomPasswordTests {
        @Test("default length is 16")
        func defaultLength() {
            let password = TestDatabase.randomPassword()
            #expect(password.count == 16)
        }

        @Test("respects custom length")
        func customLength() {
            #expect(TestDatabase.randomPassword(length: 8).count == 8)
            #expect(TestDatabase.randomPassword(length: 32).count == 32)
            #expect(TestDatabase.randomPassword(length: 1).count == 1)
        }

        @Test("zero length returns empty string")
        func zeroLength() {
            #expect(TestDatabase.randomPassword(length: 0) == "")
        }

        @Test("contains only alphanumeric characters")
        func alphanumeric() {
            let password = TestDatabase.randomPassword(length: 200)
            let validChars = CharacterSet.alphanumerics
            for scalar in password.unicodeScalars {
                #expect(validChars.contains(scalar), "Unexpected character: \(scalar)")
            }
        }

        @Test("generates unique values")
        func unique() {
            let passwords = (0..<50).map { _ in TestDatabase.randomPassword() }
            let uniqueSet = Set(passwords)
            #expect(uniqueSet.count == passwords.count)
        }
    }
}
