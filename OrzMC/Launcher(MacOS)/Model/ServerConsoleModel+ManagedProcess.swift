//
//  ServerConsoleModel+ManagedProcess.swift
//  OrzMC
//

import JokerKits
import OrzMCLauncher

/// 把引擎的受管进程接到控制台（`send` / `isRunning` / `processIdentifier` 已由 `ManagedProcess` 提供）。
///
/// 这一行 `extension` 就是共用目标与具体进程实现之间**唯一**的耦合点。
extension ManagedProcess: @retroactive ServerConsoleProcess {}
