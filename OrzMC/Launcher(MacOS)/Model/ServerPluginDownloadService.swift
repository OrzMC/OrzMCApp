//
//  ServerPluginDownloadService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Foundation
import Game
import JokerKits

struct ServerPluginDownloadService {
    func downloadAllPaperPlugins(
        versionId: String,
        progressHandler: @escaping ServerPluginDownloadProgressHandler
    ) async throws {
        let updateDirPath = GamePlan.serverPluginUpdateDir(
            version: versionId,
            type: .paper
        )
        try updateDirPath.makeDirIfNeed()

        let outputDirFileURL = URL(fileURLWithPath: updateDirPath)
        await progressHandler(
            ServerPluginDownloadProgress(
                title: "",
                fraction: Float.leastNonzeroMagnitude
            )
        )

        let paperPlugin = PaperPlugin()
        let allPlugins = try await paperPlugin.allPlugin()
        let totalCount = allPlugins.count

        for (index, plugin) in allPlugins.enumerated() {
            let downloadedCount = index + 1
            guard let downloadItem = try await plugin.downloadItem(
                outputFileDirURL: outputDirFileURL,
                version: nil
            ),
                  let pluginName = plugin.name
            else {
                continue
            }

            await progressHandler(
                ServerPluginDownloadProgress(
                    title: "\(pluginName)(\(downloadedCount)/\(totalCount))",
                    fraction: Float(downloadedCount) / Float(totalCount)
                )
            )
            try await Downloader.download(downloadItem)
        }

        await Shell.runCommand(with: ["open", outputDirFileURL.path])
        await progressHandler(
            ServerPluginDownloadProgress(
                title: "",
                fraction: 0
            )
        )
    }
}
