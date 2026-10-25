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
            case .unauthorized:
                return unauthorizedText
            case .server(let status):
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
        String(localized: "The panel returned an error (HTTP \(status)). Try again later.")
    }
}
