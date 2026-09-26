import AppKit
import SwiftUI

@MainActor
final class SmileRuntime: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var message: String?
    private lazy var hardware = RemoteHardwareService()
    override init() {
        super.init()
        SmileDataManager.shared.prepareForLaunch()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SmileDataManager.shared.start()
        AudioSettingsStore.shared.start()
        hardware.start { [weak self] action in self?.perform(action) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SmileDataManager.shared.busy || SmileDataManager.shared.hardwareOperationInProgress {
            message = "数据或键盘操作正在进行，请等待完成后再退出。"
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        SmileDataManager.shared.save()
        hardware.stop()
        AudioSettingsStore.shared.stopInputMonitor()
        AudioSettingsStore.shared.stopMix()
    }
    func perform(_ action: HardwareAction) {
        switch action {
        case .unconfigured: break
        case let .keyboardShortcut(binding):
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: binding.keyCode, keyDown: down)
                event?.flags = binding.modifiers.cgEventFlags
                event?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
                event?.post(tap: .cghidEventTap)
            }
        case let .application(path), let .systemApplication(path), let .folder(path):
            guard !path.isEmpty, NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                message = "无法打开路径，请检查配置。"; return
            }
        case let .website(value):
            guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), NSWorkspace.shared.open(url) else {
                message = "网址无效，请填写完整的 http 或 https 地址。"; return
            }
        case let .pasteText(text):
            let units = Array(text.utf16)
            for start in stride(from: 0, to: units.count, by: 20) {
                let chunk = Array(units[start..<min(start + 20, units.count)])
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                    chunk.withUnsafeBufferPointer { event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                    event?.setIntegerValueField(.eventSourceUserData, value: ShortcutEventMarker.codexAutomation)
                    event?.post(tap: .cghidEventTap)
                }
            }
        case let .shortcut(name):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { message = "请先填写快捷指令名称。"; return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] task in
                if task.terminationStatus != 0 { Task { @MainActor in self?.message = "快捷指令运行失败，请检查名称和权限。" } }
            }
            do { try process.run() } catch { message = error.localizedDescription }
        }
    }
}

@main
struct SmileToolApp: App {
    @NSApplicationDelegateAdaptor(SmileRuntime.self) private var runtime
    var body: some Scene {
        Window("SmileTool", id: "main") {
            SmileWorkspace(runtime: runtime)
                .frame(minWidth: 1060, minHeight: 760)
                .tint(Color(red: 0.22, green: 0.39, blue: 0.94))
        }
        .defaultSize(width: 1240, height: 860)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("SmileTool", systemImage: "face.smiling") {
            SmileMenu()
            Divider()
            Button("退出 SmileTool") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

private struct SmileMenu: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("打开设备工作台") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct SmileWorkspace: View {
    @ObservedObject var runtime: SmileRuntime
    @ObservedObject private var storage = SmileDataManager.shared
    @ObservedObject private var hardware = RemoteMappingStore.shared
    @State private var page = 0
    private let titles = ["设备工作台", "音频与语音", "数据管理", "系统权限"]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "face.smiling.fill").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SmileTool").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("让每一次按下，都恰到好处。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(0..<4) { index in
                    Button { page = index } label: {
                        Label(titles[index], systemImage: ["square.grid.2x2", "waveform", "externaldrive", "checkmark.shield"][index])
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(page == index ? Color.accentColor.opacity(0.12) : .clear, in: Capsule())
                            .foregroundStyle(page == index ? Color.accentColor : .secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 26).padding(.top, 30).padding(.bottom, 18)
            Divider()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(titles[page]).font(.system(size: 27, weight: .bold))
                    Text(["连接你的设备，定义顺手的操作。", "输入、输出与遥控器语音，在同一处管理。", "本地保存，完整备份，随时可恢复。", "按需授权，让设备与 Mac 顺畅协作。"][page])
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if page == 0 {
                    Label("\(hardware.connected.count) 个按键通道已连接", systemImage: "cable.connector")
                        .font(.caption).padding(10).background(.quaternary, in: Capsule())
                }
            }.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 6)
            Group {
                switch page {
                case 1: AudioSettingsView()
                case 2: DataSettingsView()
                case 3:
                    VStack(alignment: .leading, spacing: 24) {
                        SystemPermissionsView()
                        Divider()
                        Label("独立配置 · 本地保存", systemImage: "internaldrive").font(.headline)
                        Text("SmileTool 使用独立的应用标识与键盘备份目录。设备映射默认关闭，开启后才会接管对应按键。")
                            .foregroundStyle(.secondary)
                        Text("使用同一设备时，请关闭其他软件中对应的按键映射，以免重复触发。")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(28)
                default: HardwareSettingsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(storage.busy || storage.restartRequired)
            if storage.busy {
                HStack { ProgressView().controlSize(.small); Text("正在处理本地数据，请勿退出应用…") }.padding(10)
            }
            if let problem = storage.problem {
                HStack {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("数据管理") { page = 2 }
                    Button("重试保存") { storage.retry() }
                }.padding(12)
            }
            if storage.restartRequired {
                HStack {
                    Label("数据已更新，请退出后重新打开 SmileTool；重启前暂停配置编辑。", systemImage: "arrow.clockwise")
                    Spacer()
                    Button("退出 SmileTool") { NSApp.terminate(nil) }
                }.font(.callout).padding(12).background(Color.accentColor.opacity(0.08))
            }
            Divider()
            HStack {
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("本地设备服务")
                Spacer()
                Text("SmileTool 1.1.1  ·  macOS")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: storage.restartRequired) { _, needed in
            if needed {
                RemoteMappingStore.shared.editing = true
                AudioSettingsStore.shared.stopInputMonitor()
                AudioSettingsStore.shared.stopMix()
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { runtime.message != nil }, set: { if !$0 { runtime.message = nil } })) {
            Button("知道了") { runtime.message = nil }
        } message: { Text(runtime.message ?? "") }
    }
}
