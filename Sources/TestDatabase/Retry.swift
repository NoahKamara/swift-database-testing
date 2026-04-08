//
//  Retry.swift
//  TestDatabase
//
//  Created by Noah Kamara on 09.04.2026.
//


public enum Retry {
    public enum Error: Swift.Error {
        case maxAttemptsExceeded
    }

    public enum BackoffStrategy {
        case constant(Duration)

        func delay(attempt _: Int) async throws {
            switch self {
            case .constant(let duration):
                try await Task.sleep(for: duration)
            }
        }
    }
}

@discardableResult
public func run<T>(
    maxAttempts: Int = 3,
    backoff: Retry.BackoffStrategy = .constant(.milliseconds(100)),
    operation: (_ attempt: Int) async throws -> T,
    errorLogger logError: ((any Error) -> Void) = { print("\($0)") }
) async throws -> T {
    var attemptsLeft = maxAttempts
    while attemptsLeft > 0 {
        let attempt = maxAttempts - attemptsLeft + 1
        do {
            return try await operation(attempt)
        } catch {
            logError(error)
            if attemptsLeft != maxAttempts {
                try? await backoff.delay(attempt: attempt)
            }
            attemptsLeft -= 1
        }
    }
    throw Retry.Error.maxAttemptsExceeded
}

@discardableResult
public func run<T: Sendable>(
    timeout: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: timeout)
            throw Retry.Error.maxAttemptsExceeded
        }

        guard let result = try await group.next() else {
            throw Retry.Error.maxAttemptsExceeded
        }

        group.cancelAll()
        return result
    }
}
