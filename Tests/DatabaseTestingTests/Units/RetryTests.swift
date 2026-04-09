//
//  RetryTests.swift
//
//  Copyright © 2024 Noah Kamara.
//

@testable import DatabaseTestingCore
import Testing

@Suite("Retry")
struct RetryTests {
    @Test("succeeds on first attempt")
    func immediateSuccess() async throws {
        var attempts = 0
        let result = try await withRetry(maxAttempts: 3) { _ in
            attempts += 1
            return 42
        }
        #expect(result == 42)
        #expect(attempts == 1)
    }

    @Test("retries until success")
    func retriesUntilSuccess() async throws {
        var attempts = 0
        let result: Int = try await withRetry(maxAttempts: 3, backoff: .milliseconds(10)) { _ in
            attempts += 1
            if attempts < 3 {
                throw TestError.intentional
            }
            return 99
        }

        #expect(result == 99)
        #expect(attempts == 3)
    }

    @Test("maxAttempts = 0 throws immediately without running operation")
    func zeroAttempts() async {
        var attempts = 0
        await #expect(throws: InvalidArgumentError.self) {
            try await withRetry(maxAttempts: 0) { (_: Int) in
                attempts += 1
            }
        }
        #expect(attempts == 0)
    }

    @Test("stops after max attempts reached", arguments: [1, 2, 99])
    func stopsAfter(maxAttempts: Int) async {
        var attempts = 0
        await #expect(throws: MaxAttemptsExceededError.self) {
            try await withRetry(maxAttempts: maxAttempts, backoff: .milliseconds(1)) { _ in
                attempts += 1
                throw TestError.intentional
            }
        }
        #expect(attempts == maxAttempts)
    }

    @Test("error logger is called for each failure")
    func errorLoggerCalled() async {
        var loggedErrors: [any Error] = []
        _ = try? await withRetry(maxAttempts: 3, backoff: .milliseconds(1)) { (_: Int) in
            throw TestError.intentional
        } onError: { error in
            loggedErrors.append(error)
        }

        #expect(loggedErrors.count == 3)
    }
}

private enum TestError: Error {
    case intentional
}
