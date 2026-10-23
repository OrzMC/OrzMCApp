import SwiftUI

/// 详情页里的**高危操作**：删除实例文件、停止服务端。
///
/// 为什么统一成一个枚举：这些操作不可撤销或会打断玩家，必须**二次确认**，
/// 且确认文案要讲清"会发生什么、能不能恢复"。集中在一处，避免某个按钮漏掉确认。
enum RiskyAction: Identifiable {
    /// 删除某服务端实例的文件（不可恢复）。
    case deleteServer(versionId: String, software: SettingsModel.ServerSoftware, path: String)
    /// 删除**某个类型**的客户端文件（不可恢复）。
    case deleteClient(versionId: String, kind: SettingsModel.ClientKind, path: String)
    /// 删除该版本下**所有已存在的实例**目录（不可恢复）。
    case deleteAllInstances(versionId: String, paths: [String])
    /// 优雅停止正在运行的服务端（送 `stop`，让服务端自己存档退出）。
    case stopServer(versionId: String, software: SettingsModel.ServerSoftware)
    /// 重启服务端（先停后起；玩家会掉线再连）。
    case restartServer(versionId: String, software: SettingsModel.ServerSoftware)
    /// 终止服务端进程（`SIGTERM`→`SIGKILL`，可能丢存档）。
    case terminateServer(versionId: String, software: SettingsModel.ServerSoftware)

    var id: String {
        switch self {
        case let .deleteServer(versionId, software, _):
            return "delete-server-\(versionId)-\(software.rawValue)"
        case let .deleteClient(versionId, kind, _):
            return "delete-client-\(versionId)-\(kind.rawValue)"
        case let .deleteAllInstances(versionId, _):
            return "delete-all-\(versionId)"
        case let .stopServer(versionId, software):
            return "stop-server-\(versionId)-\(software.rawValue)"
        case let .restartServer(versionId, software):
            return "restart-server-\(versionId)-\(software.rawValue)"
        case let .terminateServer(versionId, software):
            return "terminate-server-\(versionId)-\(software.rawValue)"
        }
    }

    /// 被操作实例的 id（用于"该实例操作中"的忙碌标记）。
    var instanceId: String {
        switch self {
        case let .deleteServer(versionId, software, _):
            return "\(versionId)#\(software.rawValue)"
        case let .deleteClient(versionId, kind, _):
            return "\(versionId)#Client-\(kind.rawValue)"
        case let .deleteAllInstances(versionId, _):
            return "\(versionId)#All"
        case let .stopServer(versionId, software):
            return "\(versionId)#\(software.rawValue)"
        case let .restartServer(versionId, software):
            return "\(versionId)#\(software.rawValue)"
        case let .terminateServer(versionId, software):
            return "\(versionId)#\(software.rawValue)"
        }
    }

    var confirmTitle: String {
        switch self {
        case let .deleteAllInstances(_, paths):
            return String(localized: "Delete all \(paths.count) instance folders?")
        case let .deleteServer(_, software, _):
            return String(localized: "Delete \(software.rawValue) Server Files?")
        case let .deleteClient(_, kind, _):
            return String(localized: "Delete \(kind.rawValue) Client Files?")
        case let .stopServer(_, software):
            return String(localized: "Stop \(software.rawValue) Server?")
        case let .restartServer(_, software):
            return String(localized: "Restart \(software.rawValue) Server?")
        case let .terminateServer(_, software):
            return String(localized: "Terminate \(software.rawValue) Server Process?")
        }
    }

    /// 一句话讲清后果：**一行**，只说"会发生什么、能不能恢复"。
    ///
    /// 标题已经说明"要删/要停哪个"，正文不再重复动词，只补后果；
    /// 目录绝对路径不放进弹窗（卡片的「目录」行能看到）。
    func message(selectedVersionId: String?) -> String {
        let version = selectedVersionId ?? String(localized: "this version")
        switch self {
        case let .deleteServer(_, software, _):
            return String(localized: "The \(software.rawValue) server folder (\(version)) is deleted for good, including worlds, configs and plugins.")
        case let .deleteClient(_, kind, _):
            return String(localized: "The \(kind.rawValue) client folder (\(version)) is deleted for good, including assets, mods and options.")
        case let .deleteAllInstances(_, paths):
            return String(localized: "All \(paths.count) instance folders (\(version)) are deleted for good, including worlds, configs, plugins and assets.")
        case let .stopServer(_, software):
            return String(localized: "The \(software.rawValue) server saves the world, then shuts down; connected players are disconnected.")
        case let .restartServer(_, software):
            return String(localized: "The \(software.rawValue) server restarts; players are disconnected during the restart.")
        case let .terminateServer(_, software):
            return String(localized: "The \(software.rawValue) server is killed immediately and cannot finish saving; recent changes may be lost.")
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .deleteServer, .deleteClient, .deleteAllInstances: return String(localized: "Delete")
        case .stopServer: return String(localized: "Stop")
        case .restartServer: return String(localized: "Restart")
        case .terminateServer: return String(localized: "Terminate")
        }
    }

    /// 只有真正"破坏性"的动作才用红色按钮（停止是橙色/普通破坏性）。
    var isDestructive: Bool {
        switch self {
        case .deleteServer, .deleteClient, .deleteAllInstances: return true
        case .stopServer: return true
        case .restartServer: return false
        case .terminateServer: return true
        }
    }
}
