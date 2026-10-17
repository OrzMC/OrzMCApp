//
//  JavaRuntimeService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Foundation
import Game
import OrzMCLauncher

/// 托管 JRE 的**唯一事实源**是引擎（`Game.JavaRuntime` / `GamePlan.java/<major>`）。
///
/// 此前 GUI 用 `OracleJava.currentJDK()` 看系统 JDK，并引导用户手动下载安装包，
/// 与引擎「按需自动装到 `<root>/java/<major>`」的判断不一致（设置页说没 Java、
/// 启动却能跑）。现在只读引擎托管目录。
struct JavaRuntimeService {
    typealias Status = JavaRuntimeStatus

    private let policy = JavaRuntimePolicy()

    /// `<root>/java/` 下已就位的托管运行时 major（升序）。
    func installedMajorVersions(root: String = GamePlan.defaultRoot) -> [Int] {
        let fileManager = FileManager.default
        let javaDir = GamePlan.layout(root: root, version: "").javaDir
        guard let entries = try? fileManager.contentsOfDirectory(atPath: javaDir) else {
            return []
        }
        return entries
            .compactMap { Int($0) }
            .filter { major in
                guard let executable = JavaRuntime.managedExecutable(root: root, major: major)
                else {
                    return false
                }
                return fileManager.fileExists(atPath: executable)
            }
            .sorted()
    }

    func status(installedMajorVersions: [Int], requiredMajorVersion: Int?) -> Status {
        policy.status(
            for: JavaRuntimeRequirement(
                installedMajorVersions: installedMajorVersions,
                requiredMajorVersion: requiredMajorVersion
            )
        )
    }
}
