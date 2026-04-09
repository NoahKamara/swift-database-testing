//
//  Retry.swift
//
//  Copyright © 2024 Noah Kamara.
//

struct MaxAttemptsExceededError: Error {
    let underlyingError: Error
}

struct InvalidArgumentError: Error, CustomStringConvertible {
    let message: String
    var description: String {
        "InvalidArgumentError: \(self.message)"
    }

    init(_ message: String) {
        self.message = message
    }
}

@discardableResult
public func withRetry<T>(
    maxAttempts: Int = 3,
    backoff: Duration = .milliseconds(100),
    perform operation: (_ attempt: Int) async throws -> T,
    onError logError: ((any Swift.Error) -> Void) = { _ in }
) async throws -> T {
    guard maxAttempts > 0 else {
        throw InvalidArgumentError("maxAttempts must be greater than 0")
    }

    var attemptsLeft = maxAttempts
    var lastError: Error? = nil

    while attemptsLeft > 0 {
        let attempt = maxAttempts - attemptsLeft + 1

        do {
            return try await operation(attempt)
        } catch {
            lastError = error
            logError(error)
            attemptsLeft -= 1
            if attemptsLeft > 0 {
                try? await Task.sleep(for: backoff)
            }
        }
    }

    throw MaxAttemptsExceededError(underlyingError: lastError!)
}

public struct TimeoutError: Error {}
