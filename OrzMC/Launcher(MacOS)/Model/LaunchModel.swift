//
//  LaunchModel.swift
//  OrzMC
//

import Foundation
import Game
import MojangAPI
import Observation
import OrzMCLauncher

/// 启动：只负责「按设置启动客户端/服务端」+ 进度。
///
/// 进度是**一个** `LaunchProgressState`（不是 6 个散字段），文案格式化在
/// `Sources/OrzMCLauncher/LaunchProgressState.swift` 里单测过。
@MainActor
@Observable
final class LaunchModel {

    private(set) var isLaunching = false
    private(set) var progress = LaunchProgressState.idle

    private let service = GameLaunchService()

    func resetProgress() {
        progress = .idle
    }

    func startClient(
        version: Version,
        username: String,
        clientType: SettingsModel.ClientKind,
        rootDir: String,
        minMem: String,
        maxMem: String
    ) async throws {
        try await service.startClient(
            version: version,
            username: username,
            clientType: clientType,
            rootDir: rootDir,
            minMem: minMem,
            maxMem: maxMem,
            progressHandler: progressHandler
        )
    }

    func startServer(
        version: Version,
        software: SettingsModel.ServerSoftware,
        rootDir: String,
        minMem: String,
        maxMem: String,
        enableJVMDebugger: Bool,
        jvmDebuggerArgs: String,
        onServerLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> LaunchedServerSession? {
        try await service.startServer(
            version: version,
            software: software,
            rootDir: rootDir,
            minMem: minMem,
            maxMem: maxMem,
            enableJVMDebugger: enableJVMDebugger,
            jvmDebuggerArgs: jvmDebuggerArgs,
            progressHandler: progressHandler,
            onServerLog: onServerLog
        )
    }

    /// 引擎的结构化进度 → 单一状态。
    func update(_ event: LaunchProgress) {
        progress = LaunchProgressState(
            label: event.label ?? progress.label,
            completed: event.completed,
            total: event.total,
            unit: event.kind == .bytes ? .bytes : .items,
            fraction: event.fraction
        )
    }

    var progressHandler: LaunchProgressHandler {
        { [weak self] event in
            await MainActor.run { self?.update(event) }
        }
    }

    /// 供根模型包一层"启动中"标记，避免各调用点重复写。
    func withLaunching<T>(_ body: () async throws -> T) async rethrows -> T {
        isLaunching = true
        defer { isLaunching = false }
        return try await body()
    }
}
