//
//  MCSManagerErrorText.swift
//  OrzMC
//
//  MCSManager 相关的错误 → **一句能读懂的话**（复用 `RemoteHostingErrorText` 的分类逻辑）。
//
//  与 exaroton 的区别：面板 403 的含义不一样 —— exaroton 是"Token 失效"，
//  MCSM 常见的是"面板没打开 API Key 功能"或 key 与账号不匹配，提示要把这两件事都说清。
//

import Foundation

enum MCSManagerErrorText {

    /// 用户可见的一句话；`nil` = 不用提示（取消类）。
    static func describe(_ error: Error) -> String? {
        if let modelError = error as? MCSManagerModelError {
            switch modelError {
            case .unauthorized(let panelMessage):
                // 面板自己会说「密钥不正确」/「API Key功能已关闭」/「权限不足」——
                // 直接转述，比我们统一猜一句准得多。
                if let panelMessage {
                    return String(localized: "The panel rejected this API key: \(panelMessage)")
                }
                return unauthorizedText
            case .server(let status, let panelMessage):
                if let panelMessage {
                    return String(localized: "The panel returned an error (HTTP \(status)): \(panelMessage)")
                }
                return serverText(status)
            }
        }

        switch RemoteHostingErrorText.kind(of: error) {
        case .cancelled:
            return nil
        case .offline:
            return String(localized: "Can't reach the MCSManager panel. Check the address and your connection.")
        case .unauthorized:
            return unauthorizedText
        case .server(let status):
            return serverText(status)
        case .unknown:
            return String(localized: "The panel did not answer as expected. Try again later.")
        }
    }

    private static var unauthorizedText: String {
        String(
            localized: "The panel rejected this API key. Check that the key is valid and that API Key access is enabled in the panel settings."
        )
    }

    private static func serverText(_ status: Int) -> String {
        // 2xx 还走到这里 = 响应体解不出来（面板版本差异），别对用户说"返回了错误（HTTP 200）"。
        if (200..<300).contains(status) {
            return String(localized: "The panel replied in a format this app does not understand yet (HTTP 200). Please report the panel version.")
        }
        return String(localized: "The panel returned an error (HTTP \(status)). Try again later.")
    }
}
