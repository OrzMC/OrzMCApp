//
//  RaceWithTimeout.swift
//  OrzMCProtocol
//

import Foundation

/// 「跑一段工作，超过时限就放弃」——**不等**那段工作收尾。
///
/// 为什么不能用 `withThrowingTaskGroup` 竞速：结构化并发要求作用域退出前所有子任务结束，
/// 于是"超时分支先抛错"之后还要等被卡住的那个子任务（实测：2 秒超时被拖到 8 秒）。
/// 这里用「只允许结束一次」的令牌 + 一次性 continuation：
/// 超时就直接 resume，并回调 `onTimeout`（用于关掉 socket，让被卡住的线程尽快退出）。
public enum RaceWithTimeout {

    /// - Parameters:
    ///   - timeout: 时限。
    ///   - onTimeout: 超时瞬间执行（关 socket / 取消底层 IO）。可能和 `work` 并发执行。
    ///   - work: 真正的工作。
    public static func run<T: Sendable>(
        timeout: Duration,
        onTimeout: @escaping @Sendable () -> Void = {},
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = Once()
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let value = try await work()
                    if gate.claim() { continuation.resume(returning: value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            let seconds = Double(timeout.components.seconds)
                + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0, seconds)) {
                guard gate.claim() else { return }
                onTimeout()
                continuation.resume(throwing: MCProbeError.timedOut)
            }
        }
    }

    /// 「只结束一次」的令牌。
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
