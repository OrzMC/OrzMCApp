import SwiftUI

/// 详情页里的**高危操作**：删除实例文件、停止服务端。
///
/// 为什么统一成一个枚举：这些操作不可撤销或会打断玩家，必须**二次确认**，
/// 且确认文案要讲清"会发生什么、能不能恢复"。集中在一处，避免某个按钮漏掉确认。
enum RiskyAction: Identifiable {
    /// 删除某服务端实例的文件（不可恢复）。
    case deleteServer(versionId: String, software: SettingsModel.ServerSoftware, path: String)
    /// 删除客户端文件（不可恢复）。
    case deleteClient(versionId: String, path: String)
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
        case let .deleteClient(versionId, _):
            return "delete-client-\(versionId)"
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
        case let .deleteClient(versionId, _):
            return "\(versionId)#Client"
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
        case let .deleteServer(_, software, _):
            return "Delete \(software.rawValue) Server Files?"
        case .deleteClient:
            return "Delete Client Files?"
        case let .stopServer(_, software):
            return "Stop \(software.rawValue) Server?"
        case let .restartServer(_, software):
            return "Restart \(software.rawValue) Server?"
        case let .terminateServer(_, software):
            return "Terminate \(software.rawValue) Server Process?"
        }
    }

    /// 一句话讲清后果（删除要强调不可恢复；停止要强调玩家会掉线）。
    func message(selectedVersionId: String?) -> String {
        switch self {
        case let .deleteServer(_, software, path):
            return """
            This permanently deletes the \(software.rawValue) server folder for \
            \(selectedVersionId ?? "this version"):

            \(path)

            Worlds, configs and plugins inside it are gone. This cannot be undone.
            """
        case let .deleteClient(_, path):
            return """
            This permanently deletes the client folder for \
            \(selectedVersionId ?? "this version"):

            \(path)

            Downloaded assets, mods and options inside it are gone. This cannot be undone.
            """
        case let .stopServer(_, software):
            return """
            `stop` is sent to the \(software.rawValue) server console: it saves the world \
            and shuts down normally. Players connected to it will be disconnected.
            """
        case let .restartServer(_, software):
            return """
            The \(software.rawValue) server stops gracefully, then starts again with the \
            current settings. Players are disconnected during the restart (usually 10-60s).
            """
        case let .terminateServer(_, software):
            return """
            The \(software.rawValue) server process is terminated right away \
            (SIGTERM, then SIGKILL if it doesn't exit). Unlike `stop`, the server has no \
            chance to finish saving — recent world changes may be lost.
            """
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .deleteServer, .deleteClient: return "Delete"
        case .stopServer: return "Stop"
        case .restartServer: return "Restart"
        case .terminateServer: return "Terminate"
        }
    }

    /// 只有真正"破坏性"的动作才用红色按钮（停止是橙色/普通破坏性）。
    var isDestructive: Bool {
        switch self {
        case .deleteServer, .deleteClient: return true
        case .stopServer: return true
        case .restartServer: return false
        case .terminateServer: return true
        }
    }
}
