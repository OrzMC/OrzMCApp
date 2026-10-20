//
//  PluginDownloadModel.swift
//  OrzMC
//

import Foundation
import Observation
import OrzMCLauncher

/// Paper 插件批量下载（进度 + 标题）。
@MainActor
@Observable
final class PluginDownloadModel {

    private(set) var progress: Float = 0
    private(set) var title = ""

    private let service = ServerPluginDownloadService()

    var isDownloading: Bool { progress > 0 }

    func downloadAll(versionId: String) async throws {
        guard !isDownloading else { return }
        defer {
            progress = 0
            title = ""
        }
        try await service.downloadAllPaperPlugins(
            versionId: versionId,
            progressHandler: { [weak self] event in
                await MainActor.run {
                    self?.title = event.title
                    self?.progress = event.fraction
                }
            }
        )
    }
}
