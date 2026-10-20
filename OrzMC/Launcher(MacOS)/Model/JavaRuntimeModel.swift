//
//  JavaRuntimeModel.swift
//  OrzMC
//

import Foundation
import Game
import Observation
import OrzMCLauncher

/// 托管 JRE 的界面状态（唯一事实源仍是引擎 `<root>/java/<major>`）。
@MainActor
@Observable
final class JavaRuntimeModel {

    private(set) var installedMajors: [Int] = []
    /// 当前版本需要的 major（来自 gameInfo，由根模型在选中变化时更新）。
    var requiredMajor: Int?

    private let service = JavaRuntimeService()
    private let policy = JavaRuntimePolicy()

    var status: JavaRuntimeStatus {
        policy.status(
            for: JavaRuntimeRequirement(
                installedMajorVersions: installedMajors,
                requiredMajorVersion: requiredMajor
            )
        )
    }

    /// 是否该显示 Java 区块（有明确要求才显示）。
    var isVisible: Bool { requiredMajor != nil }

    var installedText: String {
        installedMajors.isEmpty ? "None" : installedMajors.map(String.init).joined(separator: ", ")
    }

    /// 游戏根目录（与设置一致；多实例下 JRE 也在该根下）。
    var rootDir: String = GamePlan.defaultRoot

    func refresh() {
        installedMajors = service.installedMajorVersions(root: rootDir)
    }
}
