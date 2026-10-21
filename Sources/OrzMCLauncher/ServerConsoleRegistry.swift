import Foundation
import Observation

/// 一个实例的标识（`版本#核心`），与应用里进程登记表用同一套键。
///
/// 例：`1.21.5#Paper`。**控制台按实例隔离**——四种核心、多个版本可以同时跑，
/// 日志与命令必须各归各位，不能"全局一个控制台"。
public struct ConsoleInstanceKey: Hashable, Sendable, CustomStringConvertible {
    public let versionId: String
    public let softwareId: String

    public init(versionId: String, softwareId: String) {
        self.versionId = versionId
        self.softwareId = softwareId
    }

    /// 与 `ManagedServerKey` 的 `rawValue` 同构（`版本#核心`），便于两个登记表对齐。
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        self.versionId = String(parts[0])
        self.softwareId = String(parts[1])
    }

    public var rawValue: String { "\(versionId)#\(softwareId)" }
    public var description: String { rawValue }
}

/// 控制台集合：**每个实例一个** `ServerConsoleModel`（按需创建、保留历史）。
///
/// 为什么要注册表而不是一个全局模型：
/// - 服务端支持 4 种核心（Paper/Vanilla/Fabric/Forge）× 多个版本，可以同时运行；
/// - 每个实例的日志/命令历史/进程句柄必须独立，否则 `stop` 会打到别的实例、
///   `say` 会进错服务器；
/// - 解绑（进程退出）只清自己的句柄，**不清日志**——用户还想看崩溃原因。
@MainActor
@Observable
public final class ServerConsoleRegistry {

    private var models: [ConsoleInstanceKey: ServerConsoleModel] = [:]

    public init() {}

    /// 已有控制台的实例（按启动顺序无关；UI 用它在列表里显示入口）。
    public var activeKeys: [ConsoleInstanceKey] { Array(models.keys) }

    public func hasConsole(for key: ConsoleInstanceKey) -> Bool {
        models[key] != nil
    }

    /// 取（必要时创建）某实例的控制台。视图 `@Bindable` 它。
    public func model(for key: ConsoleInstanceKey) -> ServerConsoleModel {
        if let existing = models[key] { return existing }
        let created = ServerConsoleModel()
        created.attachedLabel = key.description
        models[key] = created
        return created
    }

    /// 挂上实例的进程（启动成功后调用）。
    public func attach(_ process: any ServerConsoleProcess, to key: ConsoleInstanceKey, label: String? = nil) {
        model(for: key).attach(process, label: label ?? key.description)
    }

    /// 进程退出 / 被停：只解绑，本实例日志保留（便于事后排查）。
    public func detach(_ key: ConsoleInstanceKey, reason: String? = nil) {
        models[key]?.detach(reason: reason)
    }

    /// 卸载实例（删除文件后清空日志与历史）。
    public func remove(_ key: ConsoleInstanceKey) {
        models[key]?.detach()
        models[key] = nil
    }

    public func isAttached(_ key: ConsoleInstanceKey) -> Bool {
        models[key]?.isAttached ?? false
    }
}
