//
//  ServerStatusNotifications.swift
//  OrzMC
//

import Foundation
import OrzMCLauncher
import OrzMCProtocol
import UserNotifications

/// 自建服务器的状态变化事件（当前只关心在线↔离线）。
///
/// 为什么不报"玩家 X 上线"：Minecraft 的 SLP/RCON 都没有可靠的事件流，只能靠轮询，
/// 20 秒一次轮询下"谁上线了"会漏、会重复；而"掉线了"是用户真正想立刻知道的。
enum ServerStatusEvent: Equatable {
    case wentOnline
    case wentOffline

    var title: String {
        switch self {
        case .wentOnline: return String(localized: "Server is back online")
        case .wentOffline: return String(localized: "Server went offline")
        }
    }
}

/// 纯逻辑：**只在状态真的翻转时**给出事件（第一次观察到不算翻转）。
enum ServerStatusChangeDetector {

    /// - Parameters:
    ///   - isKnown: 是否已经有过一次观测（第一次拉到状态/第一次失败都不该弹通知）。
    ///   - wasOnline: 上一次观测到的在线状态。
    ///   - isOnline: 这一次的在线状态。
    static func event(isKnown: Bool, wasOnline: Bool, isOnline: Bool) -> ServerStatusEvent? {
        guard isKnown, wasOnline != isOnline else { return nil }
        return isOnline ? .wentOnline : .wentOffline
    }
}

/// 状态通知的开关与投递。
///
/// 只在用户打开开关时才申请系统通知权限（不在启动时打扰）；同一台服务器 60 秒内最多弹一条，
/// 避免网络抖动导致连续刷屏。
@MainActor
@Observable
final class ServerStatusNotifier {

    static let enabledKey = "orzmc.selfHosted.notifyStatus"

    /// 用户是否开启「状态变化通知」。
    private(set) var isEnabled: Bool

    /// 每台服务器最近一次通知时间（节流）。
    private var lastNotifiedAt: [UUID: Date] = [:]
    /// 每台服务器最近一次**已知**的在线状态（`nil` = 还没观测过）。
    private var lastOnline: [UUID: Bool] = [:]

    /// 节流窗口。
    private let minimumInterval: TimeInterval = 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// 打开/关闭。打开时申请权限（被拒绝则自动关回去，避免开关看起来是开着的却什么都不做）。
    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            return
        }
        let granted = await requestAuthorizationIfNeeded()
        isEnabled = granted
        defaults.set(granted, forKey: Self.enabledKey)
    }

    /// 观测到一次状态（成功或失败都调用）。
    func observe(_ profile: SelfHostedServerProfile, isOnline: Bool, now: Date = .now) {
        let id = profile.id
        let known = lastOnline[id]
        let event = ServerStatusChangeDetector.event(
            isKnown: known != nil,
            wasOnline: known ?? false,
            isOnline: isOnline
        )
        lastOnline[id] = isOnline

        guard isEnabled, let event else { return }
        if let last = lastNotifiedAt[id], now.timeIntervalSince(last) < minimumInterval { return }
        lastNotifiedAt[id] = now
        post(event, profile: profile)
    }

    /// 忘记一台服务器的历史（删除服务器时调用）。
    func forget(_ id: UUID) {
        lastOnline[id] = nil
        lastNotifiedAt[id] = nil
    }

    // MARK: - 系统通知

    private func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    private func post(_ event: ServerStatusEvent, profile: SelfHostedServerProfile) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = profile.displayName
        content.sound = event == .wentOffline ? .default : nil
        let request = UNNotificationRequest(
            identifier: "orzmc.selfhosted.\(profile.id.uuidString).\(UUID().uuidString)",
            content: content,
            trigger: nil                     // 立即投递
        )
        UNUserNotificationCenter.current().add(request)
    }
}
