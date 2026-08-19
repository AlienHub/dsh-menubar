import AppKit
import Foundation
import Darwin
import SystemConfiguration
import Sparkle

// Record why the process is going away, so a "flash-quit" can be diagnosed.
private func installCrashHandlers() {
    NSSetUncaughtExceptionHandler { exception in
        Diag.log("UNCAUGHT EXCEPTION: \(exception)")
    }
    for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
        signal(sig) { s in
            let msg = "CRASH SIGNAL \(s)\n"
            msg.withCString { cs in
                let fd = open("(NSHomeDirectory())/Library/Logs/DSHMenuBar-crash.log", O_WRONLY | O_CREAT | O_APPEND, 0o644)
                if fd >= 0 { write(fd, cs, strlen(cs)); close(fd) }
            }
            _exit(s)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = DSHProcessManager()
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var runtimeMenuItem: NSMenuItem!
    private var runtimeUpdateItem: NSMenuItem!
    private var toggleItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem!
    private var timer: Timer?
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Diag.log("launch: policy=accessory")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Diag.log("statusItem created: \(statusItem != nil)")
        statusItem.button?.title = "DSH"
        if let image = Self.deepSeekWhaleImage() {
            statusItem.button?.image = image
            statusItem.button?.title = ""
            Diag.log("icon loaded: yes, size=\(image.size)")
        } else {
            Diag.log("icon loaded: NO (fallback to DSH title)")
        }
        Diag.log("button: title=\(statusItem.button?.title ?? "nil"), image=\(statusItem.button?.image != nil)")

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "正在检查…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        let t = NSMenuItem(title: "启动 Harness", action: #selector(toggle), keyEquivalent: "s")
        t.target = self
        toggleItem = t
        menu.addItem(t)
        add(menu, "打开 Harness", #selector(openHarness), "o")
        menu.addItem(.separator())
        runtimeMenuItem = NSMenuItem(title: "DSH Runtime：正在检查本地版本…", action: nil, keyEquivalent: "")
        runtimeMenuItem.isEnabled = false
        menu.addItem(runtimeMenuItem)
        runtimeUpdateItem = NSMenuItem(title: "检查 DSH Runtime 更新", action: #selector(checkRuntimeUpdate), keyEquivalent: "")
        runtimeUpdateItem.target = self
        menu.addItem(runtimeUpdateItem)
        add(menu, "配置启动命令…", #selector(configureCommand), ",")
        add(menu, "网络代理…", #selector(configureProxy), "")
        add(menu, "检查更新…", #selector(checkForUpdates), "")
        launchAtLoginItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        add(menu, "退出", #selector(quit), "q")
        statusItem.menu = menu
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil { updaterController.startUpdater() }
        manager.inspectRuntime()
        manager.checkRuntimeUpdate()
        if manager.launchAtLogin { manager.start() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private static func deepSeekWhaleImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "deepseek-whale", withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        source.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        image.unlockFocus()
        return image
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggle() {
        if manager.isRunning { manager.stop() } else { manager.start() }
        refresh()
    }
    @objc private func openHarness() { NSWorkspace.shared.open(manager.url) }
    @objc private func configureCommand() {
        let alert = NSAlert()
        alert.messageText = "Harness 启动命令"
        alert.informativeText = "默认会下载并管理 DSH Runtime，再由本机 Node 启动。也可以填写已经安装的 dsh web 命令。"
        let field = NSTextField(string: manager.command)
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        // Status-item apps have no document window to restore focus to. Make
        // the field the modal's explicit first responder so standard ⌘A,
        // Delete and ⌘V reach its field editor instead of the menu bar.
        let window = alert.window
        window.initialFirstResponder = field
        window.makeFirstResponder(field)
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        refresh()
    }
    @objc private func toggleLaunchAtLogin() { manager.launchAtLogin.toggle(); refresh() }
    @objc private func configureProxy() {
        let alert = NSAlert()
        alert.messageText = "Harness 网络代理"
        alert.informativeText = "配置会在下次启动 Harness 时生效。跟随系统会读取 macOS 的 HTTP/HTTPS 代理；自定义代理仅接受 HTTP(S) URL。"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 62))
        let mode = NSPopUpButton(frame: NSRect(x: 0, y: 34, width: 180, height: 26), pullsDown: false)
        mode.addItems(withTitles: ["跟随系统代理", "直连", "自定义 HTTP 代理"])
        mode.selectItem(at: manager.proxyMode.menuIndex)
        let field = NSTextField(string: manager.customProxyURL)
        field.placeholderString = "http://127.0.0.1:7890"
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        container.addSubview(mode)
        container.addSubview(field)
        alert.accessoryView = container
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let window = alert.window
        window.initialFirstResponder = field
        window.makeFirstResponder(field)
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn,
              let selectedMode = ProxyMode(menuIndex: mode.indexOfSelectedItem) else { return }
        let customURL = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedMode == .custom, ProxySettings.normalizedHTTPProxyURL(customURL) == nil {
            let error = NSAlert()
            error.alertStyle = .warning
            error.messageText = "代理地址无效"
            error.informativeText = "请输入类似 http://127.0.0.1:7890 的 HTTP(S) 代理地址。"
            error.runModal()
            return
        }
        manager.proxyMode = selectedMode
        manager.customProxyURL = customURL
        Diag.log("proxy configuration saved: \(manager.proxySummary)")
    }
    @objc private func quit() { manager.stop(); NSApp.terminate(nil) }
    @objc private func checkForUpdates(_ sender: Any?) { updaterController.checkForUpdates(sender) }
    @objc private func checkRuntimeUpdate() { manager.checkRuntimeUpdate() }
    @objc private func updateRuntime() { manager.updateRuntime() }

    private func refresh() {
        manager.refreshStateFromPort()
        statusMenuItem.title = manager.state.label
        runtimeMenuItem.title = manager.runtimeMenuLabel
        runtimeUpdateItem.title = manager.runtimeUpdateActionTitle
        runtimeUpdateItem.isEnabled = manager.canManageRuntime
        runtimeUpdateItem.action = manager.runtimeHasUpdate ? #selector(updateRuntime) : #selector(checkRuntimeUpdate)
        if let toggleItem {
            switch manager.state {
            case .stopped, .failed:
                toggleItem.title = "▶️ 启动 Harness"
                toggleItem.isEnabled = true
            case .installing, .starting:
                toggleItem.title = "⏳ 启动中…"
                toggleItem.isEnabled = false
            case .running:
                toggleItem.title = "⏹ 停止 Harness"
                toggleItem.isEnabled = true
            }
        }
        launchAtLoginItem.state = manager.launchAtLogin ? .on : .off
        statusItem.button?.toolTip = "DeepSeek Harness · \(manager.state.label)"
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        Diag.log("app will terminate")
    }
}

private enum Diag {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DSHMenuBar-diag.log")
    static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

private enum DSHState {
    case stopped, installing, starting, running, failed
    var label: String {
        switch self {
        case .stopped: return "Harness 未运行"
        case .installing: return "正在下载并安装 DSH Runtime…"
        case .starting: return "Harness 启动中…"
        case .running: return "Harness 运行中"
        case .failed: return "Harness 启动失败"
        }
    }
}

private enum ProxyMode: String {
    case system
    case direct
    case custom

    init?(menuIndex: Int) {
        switch menuIndex {
        case 0: self = .system
        case 1: self = .direct
        case 2: self = .custom
        default: return nil
        }
    }

    var menuIndex: Int {
        switch self {
        case .system: return 0
        case .direct: return 1
        case .custom: return 2
        }
    }
}

private enum ProxySettings {
    static let modeKey = "network.proxy.mode"
    static let customURLKey = "network.proxy.customURL"
    private static let proxyKeys = ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]

    static func normalizedHTTPProxyURL(_ value: String) -> String? {
        let candidate = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        return components.url?.absoluteString
    }

    static func applying(mode: ProxyMode, customURL: String, to environment: [String: String]) -> [String: String] {
        var result = environment
        for key in proxyKeys { result.removeValue(forKey: key) }
        switch mode {
        case .direct:
            break
        case .custom:
            apply(proxy: normalizedHTTPProxyURL(customURL), to: &result)
        case .system:
            applySystemProxy(to: &result)
        }
        let loopback = "localhost,127.0.0.1,::1"
        let existing = result["NO_PROXY"] ?? result["no_proxy"]
        result["NO_PROXY"] = existing.map { "\($0),\(loopback)" } ?? loopback
        result.removeValue(forKey: "no_proxy")
        return result
    }

    static func summary(mode: ProxyMode, customURL: String) -> String {
        switch mode {
        case .direct: return "direct"
        case .custom: return "custom \(normalizedHTTPProxyURL(customURL) ?? "invalid")"
        case .system:
            let proxies = systemProxyURLs()
            guard proxies.http != nil || proxies.https != nil else { return "system (no HTTP proxy)" }
            return "system HTTP=\(proxies.http ?? "off") HTTPS=\(proxies.https ?? "off")"
        }
    }

    private static func applySystemProxy(to environment: inout [String: String]) {
        let proxies = systemProxyURLs()
        if let http = proxies.http { environment["HTTP_PROXY"] = http }
        if let https = proxies.https { environment["HTTPS_PROXY"] = https }
    }

    private static func apply(proxy: String?, to environment: inout [String: String]) {
        guard let proxy else { return }
        environment["HTTP_PROXY"] = proxy
        environment["HTTPS_PROXY"] = proxy
    }

    private static func systemProxyURLs() -> (http: String?, https: String?) {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return (nil, nil) }
        return (proxyURL(prefix: "HTTP", enabledKey: kSCPropNetProxiesHTTPEnable as String, settings: settings),
                proxyURL(prefix: "HTTPS", enabledKey: kSCPropNetProxiesHTTPSEnable as String, settings: settings))
    }

    private static func proxyURL(prefix: String, enabledKey: String, settings: [String: Any]) -> String? {
        guard (settings[enabledKey] as? NSNumber)?.boolValue == true,
              let host = settings["\(prefix)Proxy"] as? String,
              let port = settings["\(prefix)Port"] as? NSNumber else { return nil }
        return normalizedHTTPProxyURL("http://\(host):\(port.intValue)")
    }
}

private final class DSHProcessManager {
    private struct LaunchCommand {
        let value: String
        let usesBundledNode: Bool
    }

    let url = URL(string: "http://deepseek.harness.localhost:3080")!
    private let trustedLocalAuthority = "deepseek.harness.localhost:3080"
    private let defaults = UserDefaults.standard
    private var process: Process?
    private(set) var state: DSHState = .stopped
    private var runtimeInstallProcess: Process?
    private var runtimeCheckProcess: Process?
    private var runtimeVersion: String?
    private var availableRuntimeVersion: String?
    private var runtimeError: String?
    var isRunning: Bool { process?.isRunning == true || state == .running }
    var runtimeHasUpdate: Bool {
        guard let current = runtimeVersion, let available = availableRuntimeVersion else { return false }
        return current != available
    }
    var canManageRuntime: Bool { runtimeInstallProcess == nil && runtimeCheckProcess == nil }
    var runtimeMenuLabel: String {
        if runtimeInstallProcess != nil { return "DSH Runtime：正在下载并安装…" }
        if runtimeCheckProcess != nil { return "DSH Runtime：正在检查更新…" }
        if let error = runtimeError { return "DSH Runtime：\(error)" }
        if let current = runtimeVersion {
            if let available = availableRuntimeVersion, available != current {
                return "DSH Runtime：\(current)（可更新至 \(available)）"
            }
            return "DSH Runtime：\(current)（已安装）"
        }
        return "DSH Runtime：尚未安装"
    }
    var runtimeUpdateActionTitle: String {
        if runtimeInstallProcess != nil { return "正在下载 DSH Runtime…" }
        if let available = availableRuntimeVersion, runtimeHasUpdate { return "更新 DSH Runtime 至 \(available)" }
        return "检查 DSH Runtime 更新"
    }

    // Sync state from the actual port when we are not managing a live process,
    // so an instance started by a previous run (or outside the app) is reflected.
    func refreshStateFromPort() {
        guard runtimeInstallProcess == nil else { return }
        guard process?.isRunning != true else { return }
        state = isPortServed() ? .running : .stopped
    }

    var command: String {
        get { configuredCommand?.value ?? defaultLaunchCommand.value }
        set { defaults.set(newValue, forKey: "dsh.command") }
    }

    var proxyMode: ProxyMode {
        get { ProxyMode(rawValue: defaults.string(forKey: ProxySettings.modeKey) ?? "system") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: ProxySettings.modeKey) }
    }

    var customProxyURL: String {
        get { defaults.string(forKey: ProxySettings.customURLKey) ?? "" }
        set { defaults.set(newValue, forKey: ProxySettings.customURLKey) }
    }

    var proxySummary: String { ProxySettings.summary(mode: proxyMode, customURL: customProxyURL) }

    private var configuredCommand: LaunchCommand? {
        guard let value = defaults.string(forKey: "dsh.command"), !value.isEmpty else { return nil }
        // Migrate the command written by earlier app versions. It was the old
        // built-in npx launcher, not an intentional custom runtime choice.
        if value.contains("@deepseek-ai/dsh web") && value.contains("npx") {
            return nil
        }
        return LaunchCommand(value: value, usesBundledNode: false)
    }

    private func makeDefaultLaunchCommand() -> LaunchCommand {
        // DSH protects /api with a Host trust fence. The app intentionally opens
        // this stable loopback hostname, so declare that exact authority through
        // DSH's supported CLI instead of patching its npx cache at runtime.
        let webArguments = "web --trusted-host \(trustedLocalAuthority)"
        if let node = localNodePath(), let dsh = installedRuntimeEntryURL() {
            Diag.log("using local Node with managed DSH runtime: \(node)")
            return LaunchCommand(value: "\(shellQuote(node)) \(shellQuote(dsh.path)) \(webArguments)", usesBundledNode: false)
        }
        if let npx = localNpxPath() {
            Diag.log("bundled DSH unavailable; using local npx: \(npx)")
            return LaunchCommand(value: "\(shellQuote(npx)) --prefer-offline -y @deepseek-ai/dsh \(webArguments)", usesBundledNode: false)
        }
        if let node = Bundle.main.url(forResource: "node", withExtension: nil, subdirectory: "node-runtime/bin"),
           let npx = Bundle.main.url(forResource: "npx-cli", withExtension: "js", subdirectory: "node-runtime/lib/node_modules/npm/bin") {
            Diag.log("local npx unavailable; using bundled Node runtime")
            return LaunchCommand(value: "\(shellQuote(node.path)) \(shellQuote(npx.path)) --prefer-offline -y @deepseek-ai/dsh \(webArguments)", usesBundledNode: true)
        }
        Diag.log("local npx and bundled Node runtime unavailable; using shell npx")
        return LaunchCommand(value: "npx --prefer-offline -y @deepseek-ai/dsh \(webArguments)", usesBundledNode: false)
    }

    private var defaultLaunchCommand: LaunchCommand { makeDefaultLaunchCommand() }

    // A command saved by an earlier app version (or entered as a custom npx
    // command) can otherwise bypass the app's fixed local hostname policy.
    // DSH accepts repeated --trusted-host flags, so appending our own authority
    // preserves an intentional custom trust list while keeping this GUI usable.
    private func withTrustedLocalAuthority(_ launch: LaunchCommand) -> LaunchCommand {
        guard !launch.value.contains("--trusted-host"),
              launch.value.localizedCaseInsensitiveContains("dsh"),
              launch.value.localizedCaseInsensitiveContains("web") else { return launch }
        let value = "\(launch.value) --trusted-host \(trustedLocalAuthority)"
        Diag.log("appended trusted local authority to DSH launch command")
        return LaunchCommand(value: value, usesBundledNode: launch.usesBundledNode)
    }

    // Finder-launched apps do not inherit Homebrew's PATH, so resolve in a login shell.
    private func localNodePath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "node_path=\"$(command -v node)\" && \"$node_path\" --version >/dev/null 2>&1 && print -r -- \"$node_path\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            Diag.log("local Node probe failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func localNpxPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v node >/dev/null 2>&1 && npx_path=\"$(command -v npx)\" && \"$npx_path\" --version >/dev/null 2>&1 && print -r -- \"$npx_path\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            Diag.log("local npx probe failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func localNpmPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "npm_path=\"$(command -v npm)\" && \"$npm_path\" --version >/dev/null 2>&1 && print -r -- \"$npm_path\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            Diag.log("local npm probe failed: \(error.localizedDescription)")
            return nil
        }
    }

    private var runtimeRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DSHMenuBar/runtime", isDirectory: true)
    }

    private var currentRuntimeURL: URL { runtimeRootURL.appendingPathComponent("current", isDirectory: true) }

    private func installedRuntimeEntryURL() -> URL? {
        let entry = currentRuntimeURL.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
        return FileManager.default.fileExists(atPath: entry.path) ? entry : nil
    }

    func inspectRuntime() {
        guard let entry = installedRuntimeEntryURL() else {
            runtimeVersion = nil
            return
        }
        let manifest = entry.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String else {
            runtimeVersion = "已安装"
            return
        }
        runtimeVersion = version
        runtimeError = nil
    }

    func checkRuntimeUpdate() {
        guard runtimeInstallProcess == nil, runtimeCheckProcess == nil else { return }
        guard let npm = localNpmPath() else {
            runtimeError = "需要本机 Node.js/npm"
            return
        }
        runtimeError = nil
        let pipe = Pipe()
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/zsh")
        check.arguments = ["-lc", "exec \(shellQuote(npm)) view @deepseek-ai/dsh version"]
        check.standardOutput = pipe
        check.standardError = Pipe()
        check.environment = ProxySettings.applying(mode: proxyMode, customURL: customProxyURL, to: ProcessInfo.processInfo.environment)
        check.terminationHandler = { [weak self] process in
            let version = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self else { return }
                self.runtimeCheckProcess = nil
                if process.terminationStatus == 0, let version, !version.isEmpty {
                    self.availableRuntimeVersion = version
                    self.runtimeError = nil
                } else {
                    self.runtimeError = "无法检查更新"
                    Diag.log("DSH runtime update check failed: status=\(process.terminationStatus)")
                }
            }
        }
        do {
            try check.run()
            runtimeCheckProcess = check
        } catch {
            runtimeError = "无法检查更新"
            Diag.log("DSH runtime update check launch failed: \(error.localizedDescription)")
        }
    }

    func updateRuntime() {
        guard localNodePath() != nil, localNpmPath() != nil else {
            runtimeError = "需要本机 Node.js/npm"
            return
        }
        let restartAfterInstall = isRunning
        if restartAfterInstall { stop() }
        installRuntime { [weak self] success in
            if success, restartAfterInstall { self?.start() }
        }
    }

    private func installRuntime(completion: @escaping (Bool) -> Void) {
        guard runtimeInstallProcess == nil else { return }
        guard localNodePath() != nil, let npm = localNpmPath() else {
            runtimeError = "需要本机 Node.js/npm"
            state = .failed
            completion(false)
            return
        }
        let fileManager = FileManager.default
        let staging = runtimeRootURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)
        } catch {
            runtimeError = "无法创建运行时目录"
            state = .failed
            completion(false)
            return
        }
        state = .installing
        runtimeError = nil
        let install = Process()
        install.executableURL = URL(fileURLWithPath: "/bin/zsh")
        install.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        install.arguments = ["-lc", "exec \(shellQuote(npm)) install --prefix \(shellQuote(staging.path)) --omit=dev --no-audit --no-fund @deepseek-ai/dsh"]
        install.environment = ProxySettings.applying(mode: proxyMode, customURL: customProxyURL, to: ProcessInfo.processInfo.environment)
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DSHMenuBar-runtime-install.log")
        try? fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            install.standardOutput = handle
            install.standardError = handle
        }
        install.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.runtimeInstallProcess = nil
                let entry = staging.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js")
                guard process.terminationStatus == 0, fileManager.fileExists(atPath: entry.path) else {
                    try? fileManager.removeItem(at: staging)
                    self.runtimeError = "下载或安装失败（查看运行时日志）"
                    self.state = .failed
                    Diag.log("DSH runtime install failed: status=\(process.terminationStatus)")
                    completion(false)
                    return
                }
                let previous = self.runtimeRootURL.appendingPathComponent("previous", isDirectory: true)
                do {
                    try? fileManager.removeItem(at: previous)
                    if fileManager.fileExists(atPath: self.currentRuntimeURL.path) {
                        try fileManager.moveItem(at: self.currentRuntimeURL, to: previous)
                    }
                    try fileManager.moveItem(at: staging, to: self.currentRuntimeURL)
                    try? fileManager.removeItem(at: previous)
                    self.inspectRuntime()
                    self.availableRuntimeVersion = self.runtimeVersion
                    self.state = .stopped
                    Diag.log("DSH runtime installed: \(self.runtimeVersion ?? "unknown")")
                    completion(true)
                } catch {
                    if !fileManager.fileExists(atPath: self.currentRuntimeURL.path), fileManager.fileExists(atPath: previous.path) {
                        try? fileManager.moveItem(at: previous, to: self.currentRuntimeURL)
                    }
                    try? fileManager.removeItem(at: staging)
                    self.runtimeError = "无法启用已下载的版本"
                    self.state = .failed
                    Diag.log("DSH runtime promotion failed: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
        do {
            try install.run()
            runtimeInstallProcess = install
            Diag.log("DSH runtime install started")
        } catch {
            runtimeError = "无法启动下载"
            state = .failed
            Diag.log("DSH runtime installer launch failed: \(error.localizedDescription)")
            completion(false)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    private func commandOutput(_ executable: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
    }

    // A 404 from an intentionally unknown /api endpoint means the Host fence
    // accepted the hostname. A 403 means a stale DSH has not been launched
    // with the authority the app opens in the browser.
    private func trustedHostProbeStatus() -> Int? {
        let output = commandOutput("/usr/bin/curl", [
            "--silent", "--max-time", "1", "--output", "/dev/null", "--write-out", "%{http_code}",
            "-H", "Host: \(trustedLocalAuthority)",
            "http://127.0.0.1:3080/api/__dsh_menubar_trust_probe"
        ])
        return output.flatMap(Int.init)
    }

    private func isLikelyDSHPortOwner() -> Bool {
        guard let ownerOutput = commandOutput("/usr/sbin/lsof", ["-nP", "-tiTCP:3080", "-sTCP:LISTEN"]),
              let pid = ownerOutput.split(whereSeparator: \.isWhitespace).first.map(String.init),
              let command = commandOutput("/bin/ps", ["-p", pid, "-o", "command="])?.lowercased() else { return false }
        return command.contains("deepseek-ai/dsh") || command.contains("dsh/lib/bin")
    }

    // Directory of the bundled node bin, so the child process finds node on PATH.
    private var bundledNodeBinDir: String? {
        guard let node = Bundle.main.url(forResource: "node", withExtension: nil, subdirectory: "node-runtime/bin") else { return nil }
        return node.deletingLastPathComponent().path
    }
    var launchAtLogin: Bool {
        get { LaunchAgent.isInstalled }
        set { newValue ? LaunchAgent.install() : LaunchAgent.remove() }
    }

    func start() {
        guard process?.isRunning != true else { return }
        if isPortServed() {
            if trustedHostProbeStatus() == 403 {
                if isLikelyDSHPortOwner() {
                    Diag.log("replacing stale DSH on 3080: it rejects \(trustedLocalAuthority)")
                    killPortOwner()
                    state = .starting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start() }
                    return
                }
                state = .failed
                Diag.log("port 3080 is owned by a server that rejects \(trustedLocalAuthority); not terminating unknown process")
                return
            }
            // An instance is already answering on 3080: reuse it instead of starting a duplicate.
            state = .running
            Diag.log("port 3080 already served, reusing existing instance")
            startReadyPolling()
            return
        }
        // The managed runtime is downloaded once into Application Support. Do
        // this before launching so normal starts never wait for npx to fetch.
        if configuredCommand == nil, installedRuntimeEntryURL() == nil {
            installRuntime { [weak self] success in
                if success { self?.start() }
            }
            return
        }
        state = .starting
        let launch = withTrustedLocalAuthority(configuredCommand ?? defaultLaunchCommand)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.arguments = ["-lc", "exec \(launch.value)"]
        var env = ProxySettings.applying(mode: proxyMode, customURL: customProxyURL, to: ProcessInfo.processInfo.environment)
        env["DSH_HOST"] = "127.0.0.1"
        env["DSH_PORT"] = "3080"
        if launch.usesBundledNode, let binDir = bundledNodeBinDir {
            env["PATH"] = binDir + ":" + (env["PATH"] ?? "")
        }
        p.environment = env
        let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DSHMenuBar.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = handle
            p.standardError = handle
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopReadyPolling()
                self?.state = .stopped
                self?.process = nil
            }
        }
        do {
            try p.run()
            process = p
            state = .running
            startReadyPolling()
            Diag.log("started: pid=\(p.processIdentifier) url=\(url.absoluteString)")
            Diag.log("command: \(launch.value)")
            Diag.log("proxy: \(proxySummary)")
        } catch {
            state = .failed
            Diag.log("start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopReadyPolling()
        if let p = process, p.isRunning {
            killTree(pid: p.processIdentifier)
        } else if isPortServed() {
            // We did not spawn it (e.g. stale instance survived a force-quit): kill the port owner.
            killPortOwner()
        }
        process = nil
        state = .stopped
        Diag.log("stopped")
    }

    // Fast loopback probe: does something answer on 127.0.0.1:3080?
    private func isPortServed() -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(3080).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return ok
    }

    // Kill whatever process is listening on 3080 (it is the DSH-only port).
    private func killPortOwner() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "lsof -ti tcp:3080 | xargs -r kill -TERM 2>/dev/null; true"]
        try? p.run()
        p.waitUntilExit()
    }

    // Recursively terminate the whole process tree (npx -> node), so the port is released.
    private func killTree(pid: Int32) {
        for child in children(of: pid) { killTree(pid: child) }
        kill(pid, SIGTERM)
    }

    private func children(of parent: Int32) -> [Int32] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "pid=", "--ppid", String(parent)]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int32($0) } ?? []
    }

    // Poll until the harness responds, then open the local URL in the browser.
    private var readyTimer: Timer?
    private var readyAttempts = 0

    private func startReadyPolling() {
        stopReadyPolling()
        readyAttempts = 0
        Diag.log("ready polling started")
        readyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollReady()
        }
    }

    private func stopReadyPolling() {
        readyTimer?.invalidate()
        readyTimer = nil
    }

    private func pollReady() {
        readyAttempts += 1
        if readyAttempts > 60 { stopReadyPolling(); Diag.log("ready polling timed out"); return }
        let probe = URL(string: "http://127.0.0.1:3080")!
        URLSession.shared.dataTask(with: probe) { [weak self] _, response, _ in
            guard let self = self else { return }
            if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                DispatchQueue.main.async {
                    self.stopReadyPolling()
                    self.state = .running
                    NSWorkspace.shared.open(self.url)
                    Diag.log("ready, opened browser: \(self.url.absoluteString)")
                }
            }
        }.resume()
    }
}

private enum LaunchAgent {
    static let label = "ai.deepseek.harness.menubar"
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func install() {
        guard let executable = Bundle.main.executablePath else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "StandardOutPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DSHMenuBar-launchd.log").path,
            "StandardErrorPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DSHMenuBar-launchd.log").path
        ]
        (plist as NSDictionary).write(to: url, atomically: true)
    }

    static func remove() {
        launchctl(["bootout", "gui/\(getuid())", url.path])
        try? FileManager.default.removeItem(at: url)
    }

    private static func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}

// Explicit main entry: wire the delegate before starting the run loop.
@main
struct Main {
    static func main() {
        installCrashHandlers()
        // Move off any TCC-protected cwd (e.g. Documents) so child processes don't trigger permission prompts.
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())
        // Single-instance guard: if another copy is already running, activate it and exit quietly.
        let me = getpid()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ai.deepseek.harness.menubar"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            others.first?.activate()
            Diag.log("single-instance guard: another copy (pid \(others.first?.processIdentifier ?? -1)) is running, exiting")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
