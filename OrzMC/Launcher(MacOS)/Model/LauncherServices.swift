//
//  LauncherServices.swift
//  OrzMC
//
//  Created by Codex on 2026/5/3.
//

import MojangAPI

struct JavaRuntimeService {
    enum Status {
        case unknown
        case valid
        case invalid
    }

    func status(currentMajorVersion: Int?, requiredMajorVersion: Int?) -> Status {
        guard let currentMajorVersion, let requiredMajorVersion else {
            return .unknown
        }
        return currentMajorVersion >= requiredMajorVersion ? .valid : .invalid
    }
}

struct VersionFilterService {
    func filter(
        versions: [Version],
        searchText: String,
        releaseOnly: Bool
    ) -> [Version] {
        var filteredVersions = versions
        if !searchText.isEmpty {
            filteredVersions = filteredVersions.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
        }
        if releaseOnly {
            filteredVersions = filteredVersions.filter { $0.buildType == .release }
        }
        return filteredVersions
    }
}

struct ServerProcessService {
    func key(versionId: String, software: SettingsModel.ServerSoftware) -> String {
        "\(versionId)#\(software.rawValue)"
    }

    func filteredPIDMap(_ pidMap: [String: String], runningPids: Set<String>) -> [String: String] {
        pidMap.filter { runningPids.contains($0.value) }
    }
}
