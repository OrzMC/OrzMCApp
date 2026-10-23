//
//  WindowReader.swift
//  OrzMC
//

import AppKit
import SwiftUI

/// 读到自己所在的 `NSWindow`（用于"只在这个窗口是 key 时响应快捷键"）。
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}
