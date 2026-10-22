//
//  WindowSnapshot.swift
//  OrzMC
//

#if DEBUG && os(macOS)
import AppKit

/// **仅调试构建**的窗口快照：把应用自己的窗口渲染成 PNG，供 UI 复审使用。
///
/// 为什么不用 `screencapture`：那需要给宿主终端授「屏幕录制」权限（TCC）；
/// 而应用渲染**自己的**窗口不需要任何授权，也不影响任何产品路径。
///
/// 两种用法（参数由 `OrzMCApp.init` 解析）：
///
/// 1. **一次性**：`open -n <OrzMC.app> --args --snapshot /tmp/ui --snapshot-size 1200x742`
///    截完自动退出。
/// 2. **常驻监听**（推荐，窗口状态稳定、可反复出图）：
///    `open -n <OrzMC.app> --args --snapshot-watch /tmp/shots`
///    之后每次写入 `/tmp/shots/request.json` 就出一组图，并写 `/tmp/shots/done`：
///    ```json
///    { "prefix": "/tmp/shots/dark-1200", "size": "1200x742", "appearance": "dark", "settings": false }
///    ```
enum WindowSnapshot {
    /// 若命令行要求截图则安排任务；返回 `true` 表示「这是一次性截图，截完应退出」。
    @MainActor
    @discardableResult
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments

        if let raw = value(after: "--test-click", in: args) {
            // `--test-click 370,172`：在窗口内点一下（窗口坐标从左上角数，单位 pt）。
            // 用于验证"点标题折叠/展开"这类只能靠鼠标触发的交互。
            // 支持多次点击："460,172;890,67"（每次间隔 2s）
            let points: [CGPoint] = raw.split(separator: ";").compactMap { chunk in
                let parts = chunk.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(7))
                NSApp.activate(ignoringOtherApps: true)
                for point in points {
                    click(atTopLeft: point)
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        if args.contains("--test-about") {
            // 验证「关于」菜单项弹的是系统标准关于面板（替换 .appInfo 后仍然有效）。
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }
        if args.contains("--dump-menus") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                dumpMenus()
                NSApp.terminate(nil)
            }
            return true
        }
        if args.contains("--test-keys") || args.contains("--test-keys-top") || args.contains("--test-keys-sidebar") {
            postArrowKeys()
        }
        if let directory = value(after: "--snapshot-watch", in: args) {
            startWatching(directory: directory)
            return false
        }
        guard let prefix = value(after: "--snapshot", in: args) else { return false }

        let delay = Double(value(after: "--snapshot-delay", in: args) ?? "") ?? 2.0
        let size = sizeValue(in: value(after: "--snapshot-size", in: args))
        let appearance = value(after: "--snapshot-appearance", in: args)
        let includeSettings = args.contains("--snapshot-settings")
        let settingsTab = value(after: "--snapshot-settings-tab", in: args)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            await prepare(
                size: size,
                appearance: appearance,
                includeSettings: includeSettings,
                settingsTab: settingsTab
            )
            let written = capture(to: prefix)
            log("wrote \(written) file(s)")
            NSApp.terminate(nil)
        }
        return true
    }

    /// 在窗口内容坐标里点一下（`topLeft` 以窗口左上角为原点）。
    @MainActor
    private static func click(atTopLeft topLeft: CGPoint) {
        guard let window = mainWindow() else { return print("click: no window") }
        let point = NSPoint(x: topLeft.x, y: window.frame.height - topLeft.y)
        log("click: at \(point)")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// 打印主菜单结构（标题 / 是否可用 / 快捷键），用于排查菜单项灰掉或未本地化。
    @MainActor
    private static func dumpMenus() {
        guard let main = NSApp.mainMenu else { return print("menu: <nil>") }
        for top in main.items {
            print("menu: [\(top.title)]")
            guard let sub = top.submenu else { continue }
            for item in sub.items {
                let key = item.keyEquivalent.isEmpty ? "" : " \(item.keyEquivalent)/\(item.keyEquivalentModifierMask.rawValue)"
                print("menu:   \(item.isSeparatorItem ? "-----" : item.title)  enabled=\(item.isEnabled) hidden=\(item.isHidden)\(key)")
            }
        }
    }

    /// 自测键盘导航：激活窗口后向本应用事件队列投递 ↓ / ↓ / ⌘↓。
    /// 投递的事件会经过 `nextEvent`，因此本地监听（快捷键）能看到它们。
    @MainActor
    private static func postArrowKeys() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            NSApp.activate(ignoringOtherApps: true)
            mainWindow()?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1.5))

            func post(_ keyCode: UInt16, characters: String, command: Bool, control: Bool = false) {
                var flags: NSEvent.ModifierFlags = []
                if command { flags.insert(.command) }
                if control { flags.insert(.control) }
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: NSApp.keyWindow?.windowNumber ?? 0,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                ) else {
                    FileHandle.standardError.write(Data("test-keys: keyEvent nil\n".utf8))
                    return
                }
                NSApp.postEvent(event, atStart: false)
                FileHandle.standardError.write(Data("test-keys: posted keyCode=\(keyCode) cmd=\(command)\n".utf8))
            }

            if ProcessInfo.processInfo.arguments.contains("--test-keys-sidebar") {
                post(1, characters: "s", command: true, control: true)   // ⌃⌘S → 显示/隐藏侧边栏
            } else if ProcessInfo.processInfo.arguments.contains("--test-keys-top") {
                post(126, characters: "\u{F700}", command: true)   // ⌘↑ → 跳到最新
            } else {
                post(125, characters: "\u{F701}", command: false)  // ↓
                post(125, characters: "\u{F701}", command: false)  // ↓
                post(125, characters: "\u{F701}", command: true)   // ⌘↓ → 跳到最旧
            }
        }
    }

    // MARK: - 监听模式

    @MainActor
    private static func startWatching(directory: String) {
        Task { @MainActor in
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let request = root.appending(path: "request.json")
            log("watching \(root.path)")
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: request),
                   let options = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    try? FileManager.default.removeItem(at: request)
                    let prefix = options["prefix"] as? String ?? root.appending(path: "shot").path
                    await prepare(
                        size: sizeValue(in: options["size"] as? String),
                        appearance: options["appearance"] as? String,
                        includeSettings: options["settings"] as? Bool ?? false,
                        settingsTab: options["settingsTab"] as? String
                    )
                    let written = capture(to: prefix)
                    log("wrote \(written) file(s) to \(prefix)")
                    try? Data("\(written)".utf8).write(to: root.appending(path: "done"))
                }
                try? await Task.sleep(for: .seconds(0.4))
            }
        }
    }

    // MARK: - 准备窗口

    @MainActor
    private static func prepare(
        size: NSSize?,
        appearance: String?,
        includeSettings: Bool,
        settingsTab: String? = nil
    ) async {
        if let appearance {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        // 不激活的话窗口是"非活动"配色（按钮发灰），截图不能反映真实观感。
        NSApp.activate(ignoringOtherApps: true)
        mainWindow()?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(0.4))

        if let size, let window = mainWindow() {
            resize(window, to: size)
            try? await Task.sleep(for: .seconds(0.6))
        }
        if includeSettings {
            // 让「设置」落在指定分页（`@AppStorage("settingsTab")`）。
            if let settingsTab { UserDefaults.standard.set(settingsTab, forKey: "settingsTab") }
            openSettings()
            // Settings 窗口是异步创建 + 首帧渲染，等久一点再抓（否则抓到空白）。
            try? await Task.sleep(for: .seconds(3.0))
        }
    }

    @MainActor
    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title == "OrzMC" } ?? NSApp.windows.first { $0.isVisible }
    }

    @MainActor
    private static func resize(_ window: NSWindow, to size: NSSize) {
        var frame = window.frame
        let deltaHeight = size.height - frame.height
        frame.size = size
        frame.origin.y -= deltaHeight      // 保持标题栏位置，窗口向下长
        window.setFrame(frame, display: true, animate: false)
    }

    @MainActor
    private static func openSettings() {
        // SwiftUI 的 Settings 场景在 App 菜单里注册的是内部 action（`menuAction:`），
        // 不是 `showSettingsWindow:`，所以按标题找「设置…」再发它的 action。
        func findSettingsItem(in menu: NSMenu?) -> NSMenuItem? {
            guard let menu else { return nil }
            for item in menu.items {
                let title = item.title
                if title.localizedCaseInsensitiveContains("设置") || title.localizedCaseInsensitiveContains("settings") {
                    if item.action != nil { return item }
                }
                if let submenu = item.submenu, let found = findSettingsItem(in: submenu) { return found }
            }
            return nil
        }
        guard let item = findSettingsItem(in: NSApp.mainMenu), let action = item.action else {
            log("openSettings: menu item not found")
            return
        }
        log("openSettings via \(item.title)")
        NSApp.sendAction(action, to: item.target, from: item)
    }

    // MARK: - 渲染

    /// 抓本进程所有可见窗口。优先用窗口合成图：SwiftUI 的 List/表格行画在独立图层里，
    /// `cacheDisplay` 抓不到（侧边栏会整片空白）。抓自己的窗口不需要屏幕录制授权。
    @MainActor
    @discardableResult
    private static func capture(to prefix: String) -> Int {
        mainWindow()?.orderFrontRegardless()
        let owned = windowNumbers()
        log("windows=\(NSApp.windows.map { "\($0.title)(\(Int($0.frame.width))x\(Int($0.frame.height)))" }) cg=\(owned)")
        var written = 0
        for (index, number) in owned.enumerated() {
            guard let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, number, [.boundsIgnoreFraming, .bestResolution]
            ) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: URL(fileURLWithPath: "\(prefix)-\(index).png"))
            written += 1
        }
        // 同时用 cacheDisplay 再抓一份：某些窗口（例如设置）合成图可能是空白，
        // 两份对照就能区分「截图方式问题」和「界面真的空白」。
        written += captureByCachingDisplay(to: prefix)
        return written
    }

    @MainActor
    private static func windowNumbers() -> [CGWindowID] {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return infos.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 100,
                  (bounds["Height"] ?? 0) > 100
            else { return nil }
            return number
        }
    }

    /// 兜底：直接渲染窗口的 frame view（拿不到合成图时用）。
    @MainActor
    @discardableResult
    private static func captureByCachingDisplay(to prefix: String) -> Int {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 100 }
        var written = 0
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: URL(fileURLWithPath: "\(prefix)-\(index)-cached.png"))
            written += 1
        }
        return written
    }

    // MARK: - 参数

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("snapshot: \(message)\n".utf8))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else { return nil }
        return args[args.index(after: index)]
    }

    private static func sizeValue(in raw: String?) -> NSSize? {
        guard let raw else { return nil }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return nil }
        return NSSize(width: width, height: height)
    }
}
#endif
