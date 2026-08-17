import AppKit
import Foundation
import Darwin

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
    private var toggleItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem!
    private var timer: Timer?

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
        add(menu, "配置启动命令…", #selector(configureCommand), ",")
        launchAtLoginItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        add(menu, "退出", #selector(quit), "q")
        statusItem.menu = menu
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
        alert.informativeText = "默认优先使用本机的 node/npx；不可用时使用内置运行时。也可以填写已经安装的 dsh web。"
        let field = NSTextField(string: manager.command)
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        refresh()
    }
    @objc private func toggleLaunchAtLogin() { manager.launchAtLogin.toggle(); refresh() }
    @objc private func quit() { manager.stop(); NSApp.terminate(nil) }

    private func refresh() {
        manager.refreshStateFromPort()
        statusMenuItem.title = manager.state.label
        if let toggleItem {
            switch manager.state {
            case .stopped, .failed:
                toggleItem.title = "▶️ 启动 Harness"
                toggleItem.isEnabled = true
            case .starting:
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
    case stopped, starting, running, failed
    var label: String {
        switch self {
        case .stopped: return "Harness 未运行"
        case .starting: return "Harness 启动中…"
        case .running: return "Harness 运行中"
        case .failed: return "Harness 启动失败"
        }
    }
}

private final class DSHProcessManager {
    private struct LaunchCommand {
        let value: String
        let usesBundledNode: Bool
    }

    let url = URL(string: "http://deepseek.harness.localhost:3080")!
    private let defaults = UserDefaults.standard
    private var process: Process?
    private(set) var state: DSHState = .stopped
    var isRunning: Bool { process?.isRunning == true || state == .running }

    // Sync state from the actual port when we are not managing a live process,
    // so an instance started by a previous run (or outside the app) is reflected.
    func refreshStateFromPort() {
        guard process?.isRunning != true else { return }
        state = isPortServed() ? .running : .stopped
    }

    var command: String {
        get { configuredCommand?.value ?? defaultLaunchCommand.value }
        set { defaults.set(newValue, forKey: "dsh.command") }
    }

    private var configuredCommand: LaunchCommand? {
        guard let value = defaults.string(forKey: "dsh.command"), !value.isEmpty else { return nil }
        return LaunchCommand(value: value, usesBundledNode: false)
    }

    private lazy var defaultLaunchCommand: LaunchCommand = makeDefaultLaunchCommand()

    private func makeDefaultLaunchCommand() -> LaunchCommand {
        if let npx = localNpxPath() {
            Diag.log("using local npx: \(npx)")
            return LaunchCommand(value: "\(shellQuote(npx)) -y @deepseek-ai/dsh web", usesBundledNode: false)
        }
        if let node = Bundle.main.url(forResource: "node", withExtension: nil, subdirectory: "node-runtime/bin"),
           let npx = Bundle.main.url(forResource: "npx-cli", withExtension: "js", subdirectory: "node-runtime/lib/node_modules/npm/bin") {
            Diag.log("local npx unavailable; using bundled Node runtime")
            return LaunchCommand(value: "\(shellQuote(node.path)) \(shellQuote(npx.path)) -y @deepseek-ai/dsh web", usesBundledNode: true)
        }
        Diag.log("local npx and bundled Node runtime unavailable; using shell npx")
        return LaunchCommand(value: "npx -y @deepseek-ai/dsh web", usesBundledNode: false)
    }

    // Finder-launched apps do not inherit Homebrew's PATH, so resolve in a login shell.
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

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
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
            // An instance is already answering on 3080: reuse it instead of starting a duplicate.
            state = .running
            Diag.log("port 3080 already served, reusing existing instance")
            startReadyPolling()
            return
        }
        state = .starting
        runTrustPatch()
        let launch = configuredCommand ?? defaultLaunchCommand
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.arguments = ["-lc", "exec \(launch.value)"]
        var env = ProcessInfo.processInfo.environment
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

    // Idempotent: extend DSH trust fence so *.localhost Host is accepted (RFC 6761).
    private func runTrustPatch() {
        guard let url = Bundle.main.url(forResource: "patch-trust", withExtension: "sh") else {
            Diag.log("trust patch: script missing in bundle")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [url.path]
        do {
            try p.run()
            p.waitUntilExit()
            Diag.log("trust patch exit: \(p.terminationStatus)")
        } catch {
            Diag.log("trust patch failed: \(error.localizedDescription)")
        }
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
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "ai.deepseek.harness.menubar")
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
